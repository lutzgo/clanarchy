# Fleet ZFS pool-health alerting via ZED → ntfy.sh.
#
# ZED (the ZFS Event Daemon) fires zedlets for pool/vdev events.  NixOS
# installs the stock zedlets under /etc/zfs/zed.d/ and ZED walks that
# directory, so any extra script we drop into it (via environment.etc)
# runs alongside the shipped ones.  This module installs a single
# statechange zedlet that POSTs to an ntfy.sh topic URL read from a
# clan-vars secret at runtime.
#
# Enable per machine:
#   clanarchy.zfs.ntfy.enable = true;
#
# Then run once per machine:
#   clan vars generate <machine>
#
# The prompt asks for the ntfy.sh topic URL (e.g.
# "https://ntfy.sh/<hard-to-guess-topic>", `openssl rand -hex 12` is a
# fine source).  Each machine has its own generator instance, so pick a
# separate topic per machine — that way one noisy machine can be muted
# on the phone without silencing the others.
#
# The URL is a sops-encrypted clan-vars secret; the plaintext never
# lands in the Nix store.  ZED runs as root and reads the deployed
# secret file (0400 root:root) at zedlet invocation time.
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.zfs.ntfy;
  urlFile = config.clan.core.vars.generators.zfs-ntfy.files."url".path;
in
{
  options.clanarchy.zfs.ntfy = {
    enable = lib.mkEnableOption "ZFS pool state-change alerts via ntfy.sh (URL prompted via clan-vars)";

    priority = lib.mkOption {
      type        = lib.types.enum [ "min" "low" "default" "high" "urgent" ];
      default     = "high";
      description = "ntfy Priority header — controls phone notification behaviour.";
    };

    extraTags = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [ "warning" "zfs" ];
      description = ''
        Additional ntfy tags (emoji shortcodes or arbitrary labels).
        The machine's hostname is always appended automatically.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # ── clan-vars: ntfy.sh topic URL ─────────────────────────────────────
    # sops-install-secrets writes this at /run/secrets/vars/zfs-ntfy/url
    # (or the current clan-vars runtime layout equivalent), 0400 root:root.
    # ZED runs as root, so no extra activation script is needed.
    clan.core.vars.generators.zfs-ntfy = {
      files."url" = { secret = true; };
      prompts."url" = {
        description = "ntfy.sh topic URL for ZFS pool alerts (e.g. https://ntfy.sh/<hex-topic>)";
        type        = "hidden";
      };
      runtimeInputs = [ pkgs.coreutils ];
      script = ''${pkgs.coreutils}/bin/cat "$prompts/url" > "$out/url"'';
    };

    # ── ZED zedlet ────────────────────────────────────────────────────────
    environment.etc."zfs/zed.d/statechange-ntfy.sh" = {
      mode = "0755";
      text = ''
        #!/bin/sh
        # ZED zedlet: POST pool/vdev state changes to ntfy.sh.
        # Fired by ZED for the "statechange" zevent.  Managed by
        # modules/observability/zfs-ntfy.nix; do not edit in place.

        URL_FILE='${urlFile}'
        PRIORITY='${cfg.priority}'
        BASE_TAGS='${lib.concatStringsSep "," cfg.extraTags}'

        # Only fire on transitions away from ONLINE — ONLINE events fire
        # on resilver completion / pool import too and would spam.
        case "$ZEVENT_POOL_STATE_STR" in
          ONLINE|"") exit 0 ;;
        esac

        # Silent no-op if the clan-var hasn't been generated yet (e.g.
        # first switch on a new machine before `clan vars generate`).
        [ -r "$URL_FILE" ] || exit 0
        NTFY_URL=$(${pkgs.coreutils}/bin/cat "$URL_FILE")
        [ -n "$NTFY_URL" ] || exit 0

        HOSTNAME=$(${pkgs.nettools}/bin/hostname)
        TITLE="ZFS $ZEVENT_POOL_STATE_STR on $HOSTNAME"
        BODY="pool=$ZEVENT_POOL state=$ZEVENT_POOL_STATE_STR"
        [ -n "''${ZEVENT_VDEV_PATH:-}" ] && \
          BODY="$BODY vdev=$ZEVENT_VDEV_PATH"
        [ -n "''${ZEVENT_VDEV_STATE_STR:-}" ] && \
          BODY="$BODY vdev_state=$ZEVENT_VDEV_STATE_STR"

        # Fire and forget — never fail the zedlet on a network hiccup,
        # ZED runs zedlets serially and one hung curl blocks the queue.
        ${pkgs.curl}/bin/curl -sSf --max-time 10 \
          -H "Title: $TITLE" \
          -H "Priority: $PRIORITY" \
          -H "Tags: $BASE_TAGS,$HOSTNAME" \
          -d "$BODY" \
          "$NTFY_URL" >/dev/null 2>&1

        exit 0
      '';
    };
  };
}
