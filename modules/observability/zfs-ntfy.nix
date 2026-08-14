# Fleet ZFS pool-health alerting via ZED → ntfy.sh.
#
# ZED (the ZFS Event Daemon) fires zedlets for pool/vdev events.  NixOS
# installs the stock zedlets under /etc/zfs/zed.d/ and ZED walks that
# directory, so any extra script we drop into it (via environment.etc)
# runs alongside the shipped ones.  This module installs a single
# statechange zedlet that POSTs to an ntfy.sh topic URL.
#
# Enable per machine:
#   clanarchy.zfs.ntfy.url = "https://ntfy.sh/<hard-to-guess-topic>";
#
# The URL is null by default — the zedlet is only written when set,
# so the module is a no-op on machines that don't opt in.  Topic
# strings are unauthenticated on the public ntfy.sh server, so pick
# one that isn't guessable (`openssl rand -hex 12` is a fine source)
# and don't commit it to a public repo — use a clan-var, sops secret,
# or NixOS-level `imports = [ /path/to/local/secret.nix ]` if the
# repository is public.
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.zfs.ntfy;
in
{
  options.clanarchy.zfs.ntfy = {
    url = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      example     = "https://ntfy.sh/my-secret-topic-abc123";
      description = ''
        ntfy.sh topic URL to POST ZFS pool state-change events to.
        Set to null (default) to disable the zedlet entirely.
      '';
    };

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

  config = lib.mkIf (cfg.url != null) {
    environment.etc."zfs/zed.d/statechange-ntfy.sh" = {
      mode = "0755";
      text = ''
        #!/bin/sh
        # ZED zedlet: POST pool/vdev state changes to ntfy.sh.
        # Fired by ZED for the "statechange" zevent.  Managed by
        # modules/observability/zfs-ntfy.nix; do not edit in place.

        NTFY_URL='${cfg.url}'
        PRIORITY='${cfg.priority}'
        BASE_TAGS='${lib.concatStringsSep "," cfg.extraTags}'

        # Only fire on transitions away from ONLINE — ONLINE events fire
        # on resilver completion / pool import too and would spam.
        case "$ZEVENT_POOL_STATE_STR" in
          ONLINE|"") exit 0 ;;
        esac

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
