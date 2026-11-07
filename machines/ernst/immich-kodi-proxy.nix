# machines/ernst/immich-kodi-proxy.nix
#
# The Immich API key for the TV, held by a loopback proxy rather than by Kodi.
#
# ── WHY, MEASURED 2026-11-07 ────────────────────────────────────────────────
#
#   The Immich add-on (modules/roles/pkgs/immich-kodi.nix) authenticates the
#   only way Kodi lets a plugin attach a header to a URL it hands back: a
#   `|x-api-key=<key>` suffix on every thumbnail, original and video URL.
#   Kodi treats that suffix as part of the path, so the key was written to:
#
#     ~/.kodi/temp/kodi.log         `VideoPlayer::OpenFile: …|x-api-key=…`,
#                                   plus 30 lines a day from the Jellyfin
#                                   add-on, which logs whatever is playing
#     ~/.kodi/userdata/Database/Textures13.db   5,172 thumbnail URLs
#
#   /home/go is 0700, so on this host that is go and root.  The exposure is
#   the COPIES: a log pasted into a bug report or an agent session (it was),
#   the texture DB in every snapshot of /persist, Kodi's own log uploader.
#   A credential that ends up in every debugging artefact is a leaked one.
#
# ── THE SHAPE ───────────────────────────────────────────────────────────────
#
#   Kodi's add-on points at http://127.0.0.1:${port} with an EMPTY api_key.
#   This nginx adds the real header and forwards to https://photos.goclan.org
#   — THROUGH TRAEFIK, for the same reason the add-on always went that way
#   (containers/immich.nix, "THE KODI PATH": the backend accepts only
#   Traefik as a peer).  Every URL Kodi logs or caches is now
#   `http://127.0.0.1:2283/api/assets/<id>/…|x-api-key=`, which grants
#   nothing off this host.
#
#   The key is a clan var, so it is in sops and nowhere else.  Mint it
#   READ-ONLY (asset.read, asset.view, asset.download, album.read,
#   timeline.read — what the add-on calls): the proxy is a capability for
#   whoever can reach it, and that is the limit of what it can be used for.
#
# ── WHO CAN REACH IT ────────────────────────────────────────────────────────
#
#   Loopback only, and on loopback only `go` (the TV session) and root.  An
#   iptables OUTPUT owner match, because nixos-fw is an INPUT chain and
#   accepts `-i lo` before anything else, and an owner match only exists on
#   the sending side.  The containers are in their own network namespaces
#   and cannot see this host's 127.0.0.1 at all.
#
#   CHECK:   iptables -L immich-kodi-out -n -v
#   PROVE:   sudo -u lgo curl -sS http://127.0.0.1:2283/api/server/ping
#            -> connection reset;  as root -> {"res":"pong"}
{
  config,
  pkgs,
  ...
}: let
  port = 2283;
  upstream = "photos.goclan.org";
  runDir = "/run/immich-kodi-proxy";

  nginxConf = pkgs.writeText "immich-kodi-proxy.conf" ''
    daemon off;
    pid ${runDir}/nginx.pid;
    error_log stderr warn;
    worker_processes 1;
    events { worker_connections 256; }
    http {
      # Off: the request line is an asset id, and nothing here needs it.
      access_log off;
      client_body_temp_path ${runDir}/body;
      proxy_temp_path ${runDir}/proxy;
      fastcgi_temp_path ${runDir}/fastcgi;
      uwsgi_temp_path ${runDir}/uwsgi;
      scgi_temp_path ${runDir}/scgi;

      server {
        listen 127.0.0.1:${toString port};

        location / {
          # The add-on reads (GET) and searches (POST /api/search/metadata).
          # Anything else is not something a television should be sending.
          limit_except GET HEAD POST { deny all; }

          proxy_pass https://${upstream};
          proxy_set_header Host ${upstream};
          proxy_ssl_server_name on;
          proxy_ssl_name ${upstream};
          proxy_ssl_verify on;
          proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
          # nginx's default depth is 1, which cannot reach a root through
          # Let's Encrypt's intermediate: every request was a 502 with
          # "unable to get local issuer certificate".  Leaf, intermediate, root.
          proxy_ssl_verify_depth 3;
          proxy_http_version 1.1;

          # Video: stream it, honour Range, do not spool it to disk.
          proxy_buffering off;
          proxy_request_buffering off;

          # `proxy_set_header x-api-key "<key>";`, written at start from the
          # credential.  It REPLACES the empty header the add-on sends.
          include ${runDir}/key.conf;
        }
      }
    }
  '';
in {
  clan.core.vars.generators.immich-kodi-api-key = {
    files."key" = {
      secret = true;
      neededFor = "services";
    };
    prompts."key" = {
      description = "Immich API key for the TV (read-only: asset.read, asset.view, asset.download, album.read, timeline.read)";
      type = "hidden";
    };
    script = ''tr -d '[:space:]' < "$prompts/key" > "$out/key"'';
    runtimeInputs = [pkgs.coreutils];
  };

  systemd.services.immich-kodi-proxy = {
    description = "Loopback proxy that adds the Immich API key for Kodi";
    wantedBy = ["multi-user.target"];
    # nginx resolves the upstream name once, at start.  Technitium lives in a
    # container that may not be answering yet on a cold boot — hence the
    # restart rather than an ordering this host cannot express.
    after = ["network-online.target"];
    wants = ["network-online.target"];
    startLimitIntervalSec = 600;
    startLimitBurst = 20;
    serviceConfig = {
      DynamicUser = true;
      RuntimeDirectory = "immich-kodi-proxy";
      RuntimeDirectoryMode = "0700";
      LoadCredential = ["key:${config.clan.core.vars.generators.immich-kodi-api-key.files."key".path}"];
      ExecStartPre = pkgs.writeShellScript "immich-kodi-proxy-key" ''
        set -eu
        key=$(cat "$CREDENTIALS_DIRECTORY/key")
        # Immich keys are alphanumeric.  Refuse anything that could close the
        # nginx string and add a directive of its own.
        case "$key" in
          "" | *[!A-Za-z0-9_-]*)
            echo "immich-kodi-proxy: the key is empty or has unexpected characters" >&2
            exit 1 ;;
        esac
        umask 077
        printf 'proxy_set_header x-api-key "%s";\n' "$key" > ${runDir}/key.conf
      '';
      # `-e stderr`: nginx opens its compiled-in /var/log/nginx path before it
      # reads the config, and ProtectSystem makes that an alert on every start.
      ExecStart = "${pkgs.nginx}/bin/nginx -e stderr -c ${nginxConf} -p ${runDir}";
      Restart = "on-failure";
      RestartSec = "15s";

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      CapabilityBoundingSet = "";
    };
  };

  # Flushed and rebuilt on every firewall start, so a reload cannot leave a
  # second jump behind.  REJECT with a TCP reset rather than DROP: a refused
  # connection is an answer, a dropped one is a 30-second hang in Kodi.
  networking.firewall.extraCommands = ''
    iptables -N immich-kodi-out 2>/dev/null || iptables -F immich-kodi-out
    iptables -A immich-kodi-out -m owner --uid-owner go -j RETURN
    iptables -A immich-kodi-out -m owner --uid-owner root -j RETURN
    iptables -A immich-kodi-out -p tcp -j REJECT --reject-with tcp-reset
    iptables -D OUTPUT -o lo -p tcp --dport ${toString port} -j immich-kodi-out 2>/dev/null || true
    iptables -A OUTPUT -o lo -p tcp --dport ${toString port} -j immich-kodi-out
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D OUTPUT -o lo -p tcp --dport ${toString port} -j immich-kodi-out 2>/dev/null || true
    iptables -F immich-kodi-out 2>/dev/null || true
    iptables -X immich-kodi-out 2>/dev/null || true
  '';
}
