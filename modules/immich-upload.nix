# modules/immich-upload.nix
#
# The darktable end of the ILCE pipeline (M22): a watched folder on a laptop
# whose finished exports are pushed to Immich on ernst.
#
#     Sony ILCE  ->  ARW on disk  ->  darktable  ->  JPEG export into
#     ~/Pictures/immich-inbox  ->  this timer  ->  photos.goclan.org
#
# Imported fleet-wide by `commonHeadful` and INERT until enabled, the same
# shape as modules/hardware/convertible.nix.  Consumers: miralda and jens.
#
# ── JPEG EXPORTS ONLY.  THE RAWS DO NOT GO TO IMMICH ────────────────────────
#
#   lgo's decision, and the reason it is worth stating in the module rather
#   than only in the roadmap: it is the one thing about this pipeline that a
#   later reader is most likely to "fix".
#
#   The ~6.1k DNGs already on the old server ARE imported, because they are the
#   only copy of those shots (see machines/ernst/containers/immich.nix).  The
#   ILCE's new ARWs are not, because they are working files with a finished
#   export beside them, and Immich is a library rather than a raw archive.  The
#   distinction is between an ARCHIVE and a WORKFLOW, and this module is the
#   workflow end.
#
#   Which is why `extensions` below lists no raw format.  Adding `.arw` here
#   would reverse that decision silently, in a module nobody reads, for a
#   library that then doubles in size.
#
# ── WHY A TIMER AND NOT `immich upload --watch` ─────────────────────────────
#
#   The CLI has a `--watch` mode and it is the obvious choice.  It is not used:
#
#     * it is a long-running process holding an API key, restarted by nothing
#       if it dies, for a job whose latency requirement is "before I next look
#       at my phone";
#     * inotify on a directory reports a file the moment it APPEARS, which for
#       a darktable export is while it is still being written.  A partial JPEG
#       uploads perfectly happily and is then a corrupt asset in the library
#       with a valid checksum, so the retry-on-next-run safety net does not
#       catch it either.
#
#   The timer below waits for QUIESCENCE instead — a file is only considered
#   when it has not been modified for a minute.  That is what makes this safe,
#   and it is the reason the unit is a oneshot rather than a daemon.
#
# ── THE KEY IS A CLAN VAR HERE, AND IS NOT ONE ON ernst ─────────────────────
#
#   The opposite answer to the one machines/ernst/photo-import.sh gives, for a
#   reason that is about the JOB rather than about the secret:
#
#     `photo-import` is run by a human at a terminal, a handful of times, and
#     the key selects WHICH ACCOUNT the import lands in — so it is exported for
#     the run and nothing stores it.
#     THIS is an unattended timer that must work when nobody is present.  There
#     is no "the moment it runs" to hand it a credential at, so the credential
#     has to be at rest, which is what invariant #8 means by a clan var.
#
#   THIS OPTION DEFAULTS TO OFF AND MUST BE ENABLED IN A SECOND STEP.  That is
#   not caution, it is the only arrangement that works, and the first attempt
#   at M22 got it wrong — measured on ernst, 2026-09-11.
#
#   The obvious design is the traefik-acme one: declare the generator, and tell
#   the operator to GENERATE BEFORE YOU DEPLOY.  That rule works for the
#   Cloudflare token because the token exists INDEPENDENTLY OF THIS FLEET — you
#   can go and mint one at any time.  An Immich API key cannot: it is issued by
#   a web UI served by a container that does not exist until ernst has been
#   deployed.
#
#   And `clan machines update` RUNS THE GENERATORS FOR EVERY MACHINE IN THE
#   FLAKE, not just the one being updated:
#
#       all_machines = list(flake.list_machines_full().values())
#       run_generators(all_machines, full_closure=False)
#           — clan_cli/machines/update.py
#
#   So a pending prompt on a LAPTOP blocks the ERNST deploy that would make the
#   key obtainable.  Not an ordering hazard — a deadlock, and one that also
#   takes out every unrelated deploy in the fleet until it is broken.  It is
#   recorded as standing note SN5 in docs/roadmap.md, because the next person
#   to add a prompted var will not be reading this file.
#
#   The sequence that does work: deploy ernst -> create the accounts -> mint a
#   key -> set `enable = true` -> `clan vars generate <machine> --generator
#   immich-api-key` -> deploy the laptop.
#
#   Once it IS enabled and the var exists, the old warning still applies to a
#   REGENERATION: clan-core cannot know a sops secret's path until the secret
#   exists, so `files.<n>.path` is the literal "/no-such-path" until then and
#   that is what gets baked into the unit.  The failure is at least loud and
#   fail-closed — EnvironmentFile= on a missing path fails the unit, so it
#   appears in `systemctl --failed` rather than uploading nothing quietly.
#
#   ROOT READS IT, NOT ${cfg.user}.  systemd opens EnvironmentFile= as PID 1,
#   before it drops to User=, so the clan var stays 0400 root:root and the
#   user this runs as never needs to be able to read the key — the same
#   argument containers/traefik.nix makes for its ACME token.
{ config, lib, pkgs, ... }:

let
  cfg = config.clanarchy.immich.upload;
  gen = config.clan.core.vars.generators.immich-api-key;
in
{
  options.clanarchy.immich.upload = {
    enable = lib.mkEnableOption "pushing darktable exports to Immich on a timer";

    user = lib.mkOption {
      type = lib.types.str;
      default = "lgo";
      description = ''
        The account whose inbox is watched, and the user the upload runs as.

        NOT the Immich account — that is decided by the API key, which belongs
        to whoever minted it. The two happen to both be lgo today; they are
        different things and a future second consumer would have to set both.
      '';
    };

    server = lib.mkOption {
      type = lib.types.str;
      default = "https://photos.goclan.org";
      description = ''
        The Immich server, as a plain origin.

        No `/api` suffix: immich-cli 2.7.5 fetches `.well-known/immich` from
        this URL and takes the API endpoint from the answer, falling back to
        the URL as given. Verified by reading the shipped CLI, because the
        older `https://host/api` form is what most documentation still shows
        and both appear to work until the day the fallback is the one running.
      '';
    };

    inboxDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.user}/Pictures/immich-inbox";
      defaultText = lib.literalExpression ''"/home/''${config.clanarchy.immich.upload.user}/Pictures/immich-inbox"'';
      description = ''
        Where darktable exports to. Set this as the export module's target
        directory once; nothing else about darktable has to change.

        It is an ordinary directory rather than anything clever precisely so
        that dropping a file into it by hand does the same thing.
      '';
    };

    uploadedDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.user}/Pictures/immich-uploaded";
      defaultText = lib.literalExpression ''"/home/''${config.clanarchy.immich.upload.user}/Pictures/immich-uploaded"'';
      description = ''
        Where files go after a successful upload, in dated subdirectories.

        MOVED ASIDE RATHER THAN DELETED, deliberately, even though immich-cli
        has a `--delete` flag. The server is the copy that matters, but a
        local copy that survives the week costs nothing and is the only thing
        standing between a misconfigured run and a lost export.

        Pruning this is a human decision and there is no timer for it.
      '';
    };

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "jpg" "jpeg" "png" "tif" "tiff" ];
      description = ''
        Extensions considered for upload, case-insensitively.

        NO RAW FORMATS, and that is a decision rather than an oversight: this
        is the finished-export path, so the ILCE's ARWs stay in darktable's own
        archive. (The ~6.1k DNGs already on the old server ARE imported, by
        `photo-import` on ernst, because they are the only copy of those shots.
        The distinction is between an archive and a workflow.) Adding `.arw`
        here would reverse that silently.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = ''
        `OnUnitActiveSec` for the timer. Latency, not throughput: an export
        session produces a batch, and fifteen minutes later it is on the
        server. A shorter interval would mostly wake a laptop up to find an
        empty directory.
      '';
    };

    settleMinutes = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = ''
        How long a file must have been unmodified before it is eligible.

        This is the whole reason the pipeline is a timer rather than
        `immich upload --watch`: a darktable export that is still being
        written will upload as a truncated image with a perfectly valid
        checksum, which no retry can detect afterwards.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    ##########################################################################
    # The API key.
    #
    # PROMPTED, NOT GENERATED, because it is issued by a server outside this
    # clan — the same category as the Cloudflare token and RomM's metadata
    # keys. Mint it in Immich under Account Settings -> API Keys.
    #
    # A BLANK ANSWER IS NOT A VALID ANSWER HERE, unlike romm-metadata-keys
    # where blank means "source disabled". Blank stores nothing, `.path`
    # becomes /no-such-path, the unit below fails on EnvironmentFile=, and
    # every later deploy re-prompts — which is fatal without a TTY. If the key
    # does not exist yet, leave `enable = false` until it does.
    #
    # PER MACHINE, not fleet-wide, and that is what `clan.core.vars.generators`
    # gives for free: miralda's key and jens's key are separate credentials, so
    # revoking one laptop's access does not touch the other's. immich-cli sends
    # no device identity of its own, so the key is the only thing that
    # distinguishes them server-side.
    #
    # SCOPE IT WHEN YOU MINT IT. Immich API keys carry a permission set and the
    # CLI checks it (`requirePermissions` in the shipped binary), so an
    # upload-only key is enough for this and is not the default offered.
    ##########################################################################
    clan.core.vars.generators.immich-api-key = {
      files."immich.env".secret = true;

      prompts."api-key" = {
        description = "Immich API key for ${cfg.user} on ${cfg.server} (Account Settings -> API Keys) — must NOT be blank";
        type = "hidden";
      };

      runtimeInputs = [ pkgs.coreutils ];

      # Emitted in KEY=value form because systemd's EnvironmentFile= is what
      # consumes it — the same shape containers/traefik.nix uses for its ACME
      # token, and for the same reason: the value never has to pass through a
      # shell that could mangle it.
      #
      # `tr -d '\n'` on the value and a single trailing newline on the line:
      # a stray newline inside the value would make systemd read a malformed
      # assignment, and a key with a newline in it fails authentication with a
      # 401 that looks exactly like a wrong key.
      script = ''
        printf 'IMMICH_API_KEY=%s\n' \
          "$(tr -d '\n' < "$prompts/api-key")" > "$out/immich.env"
      '';
    };

    systemd.services.immich-upload = {
      description = "Upload finished darktable exports to Immich";

      # Wants, not Requires: a laptop that is off the network should skip a
      # run, not fail one. The script exits 0 on an empty inbox and the upload
      # itself is what fails if there is genuinely no server.
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      path = [ pkgs.immich-cli pkgs.coreutils pkgs.findutils ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;

        # Read by PID 1 before the drop to User=, so the var stays root-only.
        EnvironmentFile = gen.files."immich.env".path;

        # immich-cli would otherwise write auth.yml into the user's
        # ~/.config/immich. It has no reason to: with IMMICH_INSTANCE_URL and
        # IMMICH_API_KEY both set the CLI never reads or writes an auth file
        # (verified against the shipped 2.7.5 binary), so pointing its config
        # directory at a per-run RuntimeDirectory makes that a property rather
        # than an observation.
        RuntimeDirectory = "immich-upload";
        Environment = [
          "IMMICH_INSTANCE_URL=${cfg.server}"
          "IMMICH_CONFIG_DIR=%t/immich-upload"
        ];

        # Modest hardening. ProtectHome is NOT set and cannot be: the whole job
        # is reading one directory under $HOME and writing another.
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.inboxDir cfg.uploadedDir ];
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
      };

      script =
        let
          # -iname '*.jpg' -o -iname '*.jpeg' -o … , as one parenthesised group.
          extTest = lib.concatStringsSep " -o " (map (e: "-iname '*.${e}'") cfg.extensions);
        in
        ''
          set -euo pipefail

          inbox=${lib.escapeShellArg cfg.inboxDir}
          staging="$inbox/.staging"
          uploaded=${lib.escapeShellArg cfg.uploadedDir}

          mkdir -p "$inbox" "$staging" "$uploaded"

          # Claim every file that has settled, by MOVING it into staging.
          #
          # The move is the claim, and it is what makes this safe to run
          # concurrently with an export: a file being written is not yet
          # eligible, and a file already claimed is no longer in the inbox for
          # the next run to pick up.
          #
          # -maxdepth 1: the inbox is flat by design. A subdirectory here would
          # otherwise be walked, and .staging is inside the inbox.
          find "$inbox" -maxdepth 1 -type f \
            -mmin +${toString cfg.settleMinutes} \
            \( ${extTest} \) \
            -exec mv -n -t "$staging" {} +

          # Anything left in staging from a previous FAILED run is retried
          # here, which is the whole reason staging is a directory on disk and
          # not a variable.
          if [ -z "$(ls -A "$staging")" ]; then
            echo "immich-upload: nothing to do"
            exit 0
          fi

          count=$(find "$staging" -type f | wc -l)
          echo "immich-upload: $count file(s) -> ${cfg.server}"

          # No --delete and no --album.
          #
          #   --delete would remove the local file on success, which is the
          #   thing the uploadedDir option exists to avoid.
          #   --album/-a names albums after the containing FOLDER, which here
          #   is ".staging". Organising the library is done in Immich, by lgo,
          #   which is also what he asked for.
          immich upload --recursive "$staging"

          # Only reached if immich exited 0, because of `set -e`. A partial
          # upload therefore leaves everything in staging to be retried, rather
          # than filing half a batch as done.
          day=$(date +%Y-%m-%d)
          mkdir -p "$uploaded/$day"
          find "$staging" -maxdepth 1 -type f -exec mv -t "$uploaded/$day" {} +
          echo "immich-upload: moved $count file(s) to $uploaded/$day"
        '';
    };

    systemd.timers.immich-upload = {
      description = "Periodically upload darktable exports to Immich";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # A first run shortly after boot, then on the interval. Persistent so a
        # laptop that was asleep over the scheduled time catches up once on
        # wake rather than waiting a full interval.
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
        Unit = "immich-upload.service";
      };
    };

    # The inbox has to exist before anyone can export into it, and it has to
    # survive a rollback: /home is impermanent on every machine that enables
    # this, so ~/Pictures is a persisted path and these two directories live
    # under it (see modules/users/lgo.nix for that persist set).
    systemd.tmpfiles.rules = [
      "d ${cfg.inboxDir}    0700 ${cfg.user} users -"
      "d ${cfg.uploadedDir} 0700 ${cfg.user} users -"
    ];
  };
}
