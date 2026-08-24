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
#
# ── THE VAR HOLDS EITHER FORM, AND THAT IS A FIX, NOT A CONVENIENCE ─────────
#
#   MEASURED ON ernst 2026-08-24: the deployed value is a BARE TOPIC —
#   24 hex characters, exactly what `openssl rand -hex 12` produces and
#   exactly what the prompt's own "`openssl rand -hex 12` is a fine source"
#   invites — with no scheme and no host.  The prompt asks for a URL; what
#   was entered was the thing the same sentence suggests generating.
#
#   The zedlet passed that string to curl verbatim, curl guessed http:// and
#   tried to resolve a hostname made of hex, and the `>/dev/null 2>&1` on the
#   end threw the error away:
#
#     curl: (6) Could not resolve host: <24-hex-topic>
#
#   So ZFS alerting on this machine had NEVER fired, and nothing said so.
#   It was found only because M6's Alertmanager bridge needed the baseurl and
#   the topic as two separate values and refused to start when it could not
#   split one out of the other — i.e. by a consumer that failed LOUDLY on the
#   same input this one had been failing silently on for months.
#
#   Two changes follow from that, and the second matters more than the first:
#
#     1. `splitScript` below accepts both shapes and normalises a bare topic
#        against `baseUrl`.  Deliberately NOT done by re-prompting: the value
#        is correct, only the reader's assumption about it was wrong, and
#        changing the generator would invalidate the var on every machine
#        that holds one.
#     2. THE ZEDLET NO LONGER DISCARDS curl's ERROR.  It still exits 0 — ZED
#        runs zedlets serially and a failing one must not block the queue —
#        but the failure now lands in the journal where `journalctl -u
#        zfs-zed` will show it.  A fire-and-forget notifier that cannot
#        report its own failure is indistinguishable from one that was never
#        needed.
#
# ── OPTIONAL BEARER-TOKEN AUTH ──────────────────────────────────────────────
#
#   `clanarchy.zfs.ntfy.auth.enable = true` adds an Authorization header to
#   every publish, which is what a RESERVED ntfy topic requires.
#
#   WHY IT MATTERS, and it is not theoretical here: on a public instance an
#   unreserved topic is a BEARER SECRET.  Knowing it grants both read and
#   publish, so a single leak — a screenshot, a pasted journal line, a public
#   commit — hands over every pool alert this fleet emits and the ability to
#   forge them.  That happened on 2026-08-24 (see docs/roadmap.md, M6), and
#   rotation was the only available remedy because there was no second factor
#   to revoke.  With a reserved topic set to deny anonymous access, a leaked
#   TOPIC is worth nothing on its own, and a leaked TOKEN is revocable from
#   ntfy's web UI without touching a single machine.
#
#   OFF BY DEFAULT, deliberately.  Turning it on before the account, the
#   reservation and the token exist would leave `clan vars generate` prompting
#   for something nobody has, and — on the machine running M6's Alertmanager
#   bridge — a staging unit that fails and takes the monitoring container with
#   it.  Enablement is a per-machine opt-in once the ntfy side is set up, and
#   THE ORDER MATTERS: account, reserve the topics, deny anonymous access, mint
#   a token per machine, and only then flip the option.  The full sequence,
#   including the negative test that proves the reservation actually took, is
#   in docs/roadmap.md under "Enabling ntfy auth — the order matters".
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.zfs.ntfy;
  urlFile = config.clan.core.vars.generators.zfs-ntfy.files."url".path;

  # A SEPARATE generator, not a second file on `zfs-ntfy`.  Adding a file to
  # an existing generator changes that generator's definition, and clan
  # decides whether a stored var is still current by comparing definitions —
  # so the cheap-looking change would put every machine's ALREADY-CORRECT
  # topic up for regeneration.  A new generator has nothing to invalidate.
  tokenFile =
    if cfg.auth.enable
    then config.clan.core.vars.generators.zfs-ntfy-token.files."token".path
    else null;

  # Normalise the var into "<baseurl> <topic>" on stdout, or fail with a
  # message on stderr.  ONE implementation, shared: the zedlet below uses it,
  # and so does the Alertmanager bridge's staging unit in
  # service-modules/monitoring.nix — which is the whole point, because the two
  # publishers landing on different topics would silently split the alerting
  # path this repo insists is single.
  #
  # POSIX-only: the zedlet is /bin/sh.
  splitScript = pkgs.writeShellScript "zfs-ntfy-split-url" ''
    set -eu
    v=$(${pkgs.coreutils}/bin/tr -d '[:space:]' < "$1")

    case "$v" in
      "")
        echo "zfs-ntfy: $1 is empty" >&2; exit 1 ;;
      http://*|https://*)
        base=''${v%/*}
        topic=''${v##*/}
        ;;
      */*)
        echo "zfs-ntfy: '$v' has a path but no scheme — expected https://host/topic" >&2
        exit 1 ;;
      *)
        # A bare topic.  This is the shape actually on disk; see the header.
        base=${lib.escapeShellArg cfg.baseUrl}
        topic=$v
        ;;
    esac

    # "https://ntfy.sh" with no topic splits into base="https:/", which is
    # non-empty and therefore passes a naive check.  Require the scheme to
    # have survived.
    case "$base" in
      http://?*|https://?*) ;;
      *) echo "zfs-ntfy: cannot split '$v' into a base URL and a topic" >&2; exit 1 ;;
    esac
    [ -n "$topic" ] || { echo "zfs-ntfy: no topic in '$v'" >&2; exit 1; }

    printf '%s %s\n' "$base" "$topic"
  '';
in
{
  options.clanarchy.zfs.ntfy = {
    enable = lib.mkEnableOption "ZFS pool state-change alerts via ntfy.sh (URL prompted via clan-vars)";

    baseUrl = lib.mkOption {
      type        = lib.types.str;
      default     = "https://ntfy.sh";
      description = ''
        ntfy instance to publish to when the clan var holds a BARE TOPIC
        rather than a full URL.  Ignored when the var already carries a
        scheme.  No trailing slash.

        Point this at a self-hosted instance to move every machine's alerts
        off the public one without re-prompting a single var.
      '';
    };

    splitScript = lib.mkOption {
      type        = lib.types.package;
      internal    = true;
      readOnly    = true;
      default     = splitScript;
      description = ''
        Reads the clan var and prints "<baseurl> <topic>".  Exposed so that
        the M6 Alertmanager bridge normalises the value exactly as the zedlet
        does — two publishers on one topic, which is the property
        service-modules/monitoring.nix depends on.
      '';
    };

    auth.enable = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = ''
        Send `Authorization: Bearer <token>` with every publish, from a clan
        var prompted by the `zfs-ntfy-token` generator.

        Required by a RESERVED ntfy topic with anonymous access denied, which
        is the only configuration in which the topic stops being a bearer
        secret in its own right.  See the header for what that buys.

        ENABLE ONLY AFTER the ntfy account, the topic reservation and the token
        exist — otherwise `clan vars generate` prompts for a value nobody has
        yet, and on the machine holding M6's Alertmanager bridge the staging
        unit fails closed and the monitoring container does not start.

        The token must carry WRITE access to this machine's topic.  One ntfy
        account can own every machine's topic and issue one token per machine,
        which keeps revocation per-machine — the same reason each machine has
        its own topic.
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

    # ── clan-vars: ntfy access token (only when auth is enabled) ──────────
    #
    # Validated at prompt time, because every way this can be wrong fails
    # LATE and quietly: a bad token yields HTTP 401 from inside a zedlet that
    # exits 0 by design, i.e. exactly the class of silent failure this module
    # spent M6 learning about.  A human is watching once, here.
    clan.core.vars.generators.zfs-ntfy-token = lib.mkIf cfg.auth.enable {
      files."token" = {
        secret = true;
        # Re-stage the Alertmanager bridge's copy when the token is rotated.
        # The monitoring service module adds its own unit to this list on the
        # machine that has one; see service-modules/monitoring.nix.
        restartUnits = [ ];
      };

      prompts."token" = {
        description = "ntfy access token with write access to this machine's topic (tk_…)";
        type        = "hidden";
      };

      runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];

      script = ''
        set -euo pipefail
        tok=$(tr -d '[:space:]' < "$prompts/token")

        if [ -z "$tok" ]; then
          echo "  ✗ empty token" >&2
          exit 1
        fi

        # ntfy access tokens are documented as `tk_` followed by alphanumerics.
        # Rejecting anything else catches the likely mistake — pasting the
        # ACCOUNT PASSWORD — which would otherwise authenticate nowhere and
        # present as a topic that silently stops receiving.
        if ! printf '%s' "$tok" | grep -qE '^tk_[A-Za-z0-9]{20,}$'; then
          echo "  ✗ that does not look like an ntfy access token." >&2
          echo "    Expected tk_ followed by alphanumerics." >&2
          echo "    Create one at: ntfy web UI → Account → Access tokens → Create." >&2
          echo "    An account PASSWORD is not a token; this module sends a Bearer header." >&2
          exit 1
        fi

        printf '%s' "$tok" > "$out/token"
      '';
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

        # Normalise the var into base + topic.  Accepts a full URL or a bare
        # topic; see the header for why both, and for what a whole year of
        # trusting the first shape cost.  A split failure is REPORTED, not
        # swallowed — ZED's output goes to the journal.
        if ! SPLIT=$(${splitScript} "$URL_FILE"); then
          echo "zfs-ntfy: refusing to notify — cannot read a topic out of $URL_FILE" >&2
          exit 0
        fi
        NTFY_BASE=''${SPLIT%% *}
        NTFY_TOPIC=''${SPLIT##* }
        NTFY_URL="$NTFY_BASE/$NTFY_TOPIC"

        HOSTNAME=$(${pkgs.nettools}/bin/hostname)
        TITLE="ZFS $ZEVENT_POOL_STATE_STR on $HOSTNAME"
        BODY="pool=$ZEVENT_POOL state=$ZEVENT_POOL_STATE_STR"
        [ -n "''${ZEVENT_VDEV_PATH:-}" ] && \
          BODY="$BODY vdev=$ZEVENT_VDEV_PATH"
        [ -n "''${ZEVENT_VDEV_STATE_STR:-}" ] && \
          BODY="$BODY vdev_state=$ZEVENT_VDEV_STATE_STR"

        # Bounded and non-fatal — ZED runs zedlets serially, so this must
        # never hang the queue and must never return non-zero.
        #
        # BUT IT IS NO LONGER SILENT.  The original discarded stdout AND
        # stderr, which is how `curl: (6) Could not resolve host` went
        # unnoticed on ernst from the day this module was written until
        # 2026-08-24.  stdout is still dropped (ntfy echoes the message back
        # as JSON and it is noise); stderr goes to the journal, where
        # `journalctl -u zfs-zed` will show it.  The exit status is still
        # swallowed by design — the `|| echo` keeps `set -e`-less sh from
        # caring while making the failure legible.
        post() {
          ${pkgs.curl}/bin/curl -sSf --max-time 10 "$@" \
            -H "Title: $TITLE" \
            -H "Priority: $PRIORITY" \
            -H "Tags: $BASE_TAGS,$HOSTNAME" \
            -d "$BODY" \
            "$NTFY_URL" >/dev/null
        }

        ${lib.optionalString cfg.auth.enable ''
        # ── Bearer token, and it never touches argv ────────────────────────
        #
        # `-H "Authorization: Bearer $tok"` would be the obvious form and is
        # wrong on this machine: argv is world-readable through /proc, and
        # ernst carries an unprivileged couch account (`go`) that could read
        # the token straight out of `ps` during the request.  Assigning it to
        # a shell variable first is no better — it lands in the environment of
        # anything the zedlet forks.
        #
        # curl's own config format takes a `header = "..."` line, and `-K -`
        # reads that config from STDIN.  The token therefore travels file →
        # pipe → curl and is never an argument, never an env var, and never a
        # temporary file.  `printf` is a shell builtin so the opening literal
        # does not fork either.
        TOKEN_FILE='${tokenFile}'
        if [ -r "$TOKEN_FILE" ]; then
          {
            printf 'header = "Authorization: Bearer '
            ${pkgs.coreutils}/bin/tr -d '[:space:]' < "$TOKEN_FILE"
            printf '"\n'
          } | post -K - \
            || echo "zfs-ntfy: authenticated POST to $NTFY_BASE failed; the alert was NOT delivered" >&2
          exit 0
        fi

        # Auth is enabled but the token has not been deployed yet.  Say so
        # rather than falling back to an anonymous publish: against a reserved
        # topic that gets a 403, and against an unreserved one it would
        # succeed while quietly proving nothing about the auth path.
        echo "zfs-ntfy: auth enabled but $TOKEN_FILE is unreadable — run 'clan vars generate' for this machine" >&2
        exit 0
        ''}

        post || echo "zfs-ntfy: POST to $NTFY_BASE failed; the alert was NOT delivered" >&2

        exit 0
      '';
    };
  };
}
