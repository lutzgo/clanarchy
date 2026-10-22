# machines/ernst/containers/arr/video.nix
#
# The film-and-television half of the `arr` container: Sonarr, Radarr, Bazarr,
# Jellyseerr and Recyclarr, plus the hardening overrides for the three whose
# upstream units need them.
#
# ── THIS FILE CO-DEFINES containers.arr ─────────────────────────────────────
#
# It creates no container. `containers.<name>.config` is a module option, so
# every file in this directory merges into the one ./common.nix declares —
# the same mechanism containers/crowdsec.nix uses to put a daemon inside
# Traefik's namespace, and the one containers/homepage.nix already used to add
# a service to THIS container.
#
# The split is by media domain rather than by mechanism because that is how
# these services were added and how they are reasoned about: a change to the
# film pipeline touches Sonarr, Radarr and Bazarr together and nothing else.
{
  config,
  lib,
  pkgs,
  ...
}: let
  ids = import ./ids.nix;

  # The old flat names, so the service definitions below are UNCHANGED from
  # the 6,218-line file they came out of. A split that also renamed every
  # reference would be unreviewable; this way the move is a move.
  arrSyscallFilter = ids.syscallFilter;
  arrSecretsDir = ids.secretsDirs.arrApiKeys;
  sonarrPort = ids.ports.sonarr;
  radarrPort = ids.ports.radarr;
  bazarrPort = ids.ports.bazarr;
  jellyseerrPort = ids.ports.jellyseerr;
in {
  # ── Inside the container ──────────────────────────────────────────────────
  containers.arr.config = {
    config,
    pkgs,
    lib,
    ...
  }: {
    # Sonarr.  dataDir left at its default so the module keeps
    # StateDirectory=sonarr; /var/lib/sonarr is the bind mount.
    services.sonarr = {
      enable = true;
      user = "sonarr";
      group = "media"; # PRIMARY group — PrivateUsers=true, see header
      openFirewall = false; # explicit list above
      settings.server.port = sonarrPort;
    };

    services.radarr = {
      enable = true;
      user = "radarr";
      group = "media";
      openFirewall = false;
      settings.server.port = radarrPort;
    };

    ##########################################################################
    # M12 (c) — BAZARR.  Subtitles, both directions.
    #
    # The only one of M12's additions with an upstream module, and the module
    # is a thin one: it writes an ExecStart, a tmpfiles rule and a user, and
    # sets NO hardening directives at all.  Not a reduced set — none.  So the
    # `systemd.services.bazarr.serviceConfig` block further down is not a
    # tightening of upstream's choices, it is the whole of them, and its
    # before/after score is the largest movement in this milestone.
    #
    # `media` as the PRIMARY group is the one thing that must not be
    # "simplified" later: Bazarr writes .srt sidecars INTO the library, next
    # to the video files, in directories that are 2770 root:media.
    #
    # LANGUAGE PROFILES ARE A MANUAL STEP, and deliberately so.  M12 asks for
    # German and English "both directions" — German subtitles on English
    # content and English subtitles on German content — which is two profiles
    # plus per-series/per-movie assignment plus provider credentials.  All of
    # that lives in Bazarr's own database, and the argument the root folders
    # lost applies here unchanged: faking it from Nix would create a second
    # source of truth for state the application owns.  The PR body carries
    # the steps.
    services.bazarr = {
      enable = true;
      listenPort = bazarrPort;
      user = "bazarr";
      group = "media"; # PRIMARY group — see the header
      openFirewall = false; # explicit list above
    };

    ##########################################################################
    # M12 (e) — UNPACKERR IS NOT HERE, and that is a measured decision.
    #
    # M12 makes it conditional on there actually being archive-delivered
    # releases to unpack.  Measured on ernst, 2026-08-26:
    #
    #   sonarr, last 50 grabs      50/50 protocol=torrent, client qBittorrent
    #   radarr, all 30 in history  30/30 protocol=torrent, client qBittorrent
    #   download clients configured   ONE, qBittorrent.  No usenet client
    #                                 exists in either application.
    #   archives under /srv/media/torrents
    #                              0, out of 986 files
    #                              (*.rar, *.r0[0-9], *.zip, *.zipx, *.7z)
    #   archives under /srv/media/library
    #                              0
    #
    # There is nothing for it to do.  SKIPPED, recorded in docs/history.md so
    # it is not re-litigated in six months, and uid 3013 stays reserved and
    # unused.
    #
    # THE TRIGGER TO REVISIT IS A USENET DOWNLOAD CLIENT, not a hunch: the
    # whole reason this stack sees no archives is that it has no usenet path.
    # Note pkgs.unpackerr exists (0.15.2) and needs a unit, not a derivation.

    ##########################################################################
    # M13 — JELLYSEERR.  The request side of the loop.
    #
    # ── THE MODULE WAS RENAMED, AND THE OPTION YOU WANT IS `services.seerr` ─
    #
    # docs/history.md's M13 prompt says "jellyseerr HAS a module", surveyed
    # 2026-08-25.  It still does, but in ernst's own pin it is reached under a
    # different name: nixos/modules/services/misc/seerr.nix declares
    # `services.seerr` and imports
    #
    #   (lib.mkRenamedOptionModule [ "services" "jellyseerr" ] [ "services" "seerr" ])
    #
    # so `services.jellyseerr` still evaluates — it just emits a rename
    # warning and sets something else.  The package attribute moved too:
    # `seerr`, version 3.2.0.  This file uses the new names for both, so the
    # build produces no rename warnings and a reader grepping for "seerr"
    # finds everything.
    #
    # The 26.05 rename also moved the STATE PATH.  That is handled at the
    # bind mount, where the two candidate paths are written out.
    #
    # ── INTERNAL SCOPE ONLY.  THE EXTERNAL HALF IS M16 ─────────────────────
    #
    # lgo has decided Jellyseerr must eventually be reachable FROM THE
    # INTERNET.  THAT IS M16 AND IS DELIBERATELY NOT IMPLEMENTED HERE.
    # Nothing in this file, in containers/traefik.nix, or in the UDM-Pro
    # policy changed to admit a WAN source; M13's router rides the existing
    # permanent "Allow Traefik" rule (LAN + IoT → traefik:443) and no new
    # gateway rule was created.
    #
    # The split is the same reasoning that gave M2b its own milestone: the
    # household proves the request workflow first, and the ingress boundary
    # then gets reviewed AS an ingress change rather than as one line in a
    # library-cleanup milestone.
    #
    # ── IT DOES NOT GO BEHIND AUTHELIA, AND THAT IS DELIBERATE ─────────────
    #
    # Authelia exists (M7) and every other browser-facing service in this
    # container sits behind it.  Jellyseerr does not, for two reasons:
    #
    #   1. M16 decides the external auth posture.  Putting it behind
    #      forward-auth now and reworking it there is two changes to one
    #      router.
    #   2. IT IS NOT AN ADMIN SERVICE.  The others in this container are
    #      operator tools; this is the thing the household opens to ask for a
    #      film.  Its posture is its OWN Jellyfin-account login — the
    #      credential everyone here already has — which is also what makes
    #      "who requested this" meaningful inside Jellyseerr rather than
    #      collapsing to one Authelia identity.
    #
    # This is the same call containers/traefik.nix makes for Jellyfin itself,
    # and its header states the general form of the argument.
    services.seerr = {
      enable = true;
      port = jellyseerrPort;

      # Explicit list above, as everywhere in this file.  The module's
      # openFirewall would set allowedTCPPorts, which is the unconditional
      # mechanism M5 emptied on purpose.
      openFirewall = false;
    };

    ##########################################################################
    # Recyclarr — TRaSH-Guides quality definitions, synced on a timer.
    #
    # SCOPE NOTE: M4's prompt says "recyclarr is explicitly OUT of scope; it
    # is a backlog item to evaluate after this settles."  It is here because
    # lgo asked for it during the milestone, not because the boundary drifted.
    # Recorded so the prompt and the tree do not silently disagree.
    #
    # It is a good fit for this repo: the NixOS module takes the entire
    # recyclarr config as a Nix attrset, so "which quality definitions apply"
    # becomes a reviewable diff instead of UI state nobody can reconstruct.
    # That is the same argument the root folders lost — those only exist in
    # the UI, so they stay a documented manual step; this one does not have
    # to.
    ##########################################################################

    # THE API KEYS, and why they are not a clan var.
    #
    # Recyclarr authenticates to Sonarr and Radarr with their API keys.  Those
    # keys are not ours to choose: each app generates one on first run and
    # writes it into its own config.xml on zdata.  There are two ways to get
    # them to recyclarr and only one of them stays true.
    #
    #   A clan-vars prompt would work today and rot tomorrow.  It would mean
    #   pasting a value that already exists elsewhere, creating a second copy
    #   with no link to the first — and the day an API key is regenerated in
    #   the UI (Settings → General → API Key, one button), the var still holds
    #   the old one and every sync fails 401 while the repo looks correct.
    #
    #   Reading config.xml keeps ONE source of truth.  The key lives where the
    #   app that owns it put it; rotating it in the UI is picked up on the
    #   next sync with no deploy and no re-prompt.
    #
    # So this oneshot stages both keys into a root-only tmpfs directory, and
    # services.recyclarr's `_secret` mechanism turns them into LoadCredential=
    # entries.  The key is never in the Nix store and never in the repo, so
    # invariant #8 is satisfied without a generator — there is no secret here
    # that this machine did not already hold.
    #
    # THE KEY IS NOT "never on disk", measured on ernst 2026-08-26.  The
    # recyclarr module's ExecStartPre (recyclarr-pre-start) reads each
    # credential and SUBSTITUTES IT INTO /var/lib/recyclarr/config.yml before
    # the sync runs.  On this machine that file is:
    #
    #     -rw-r--r-- 1 recyclarr recyclarr  /var/lib/recyclarr/config.yml
    #     drwxr-xr-x 7 recyclarr recyclarr  /var/lib/recyclarr
    #
    # i.e. both API keys in PLAINTEXT, world-readable, inside the container.
    #
    # It is left alone, deliberately, and the reasoning is worth writing down
    # rather than re-deriving: the exposure is to processes already inside
    # this netns, and every one of them — sonarr, radarr, prowlarr, bazarr,
    # cleanuparr, mediathekarr, umlautadaptarr — either owns one of these keys
    # or is handed it on purpose.  Widening nothing is what the uid boundary
    # already does; the keys' real protection is that the container is not
    # reachable except through Traefik.
    #
    # WHAT WOULD CHANGE THIS: a service landing in this container that is NOT
    # trusted with *arr API access.  There is no such tenant today.  If one
    # arrives, this is the line that has to be revisited, and the fix is
    # upstream's (the module should chmod its rendered config), not a second
    # mechanism here.
    #
    # RuntimeDirectoryPreserve = "yes" with RemainAfterExit = false is the
    # combination that makes this re-run.  Without the preserve, the runtime
    # directory is deleted the instant this oneshot exits — i.e. before
    # recyclarr.service starts and before LoadCredential can read it.  With
    # RemainAfterExit = true instead, the unit would stay active and never run
    # again, so a rotated key would be staged once and then be stale forever.
    # This pair keeps the directory and re-runs the extraction on every sync.
    #
    services.recyclarr = {
      enable = true;

      # Daily, with the module's 5-minute jitter.  Nothing here is urgent —
      # TRaSH guide changes are edits to a git repo, not events.
      schedule = "daily";

      # localhost, because all of this shares one netns.  Same payoff as the
      # Prowlarr→Sonarr/Radarr wiring: no port opened, nothing to firewall.
      #
      # ── The config is INLINED, not `include`d, and that is forced ────────
      #
      # The obvious form is `include: [ { template = "remux-web-2160p"; } ]`,
      # naming one of the ids in the official config-templates repo.  It does
      # not work on v8 and fails with "Unable to find include template with
      # name".  Those templates are STARTER CONFIGS, meant to be copied once
      # via `recyclarr config create` and then edited; the repo ships no
      # include-able fragments at all (its `includes/` directory is for
      # user-authored ones and is empty).  So the template body is transcribed
      # here — the better shape for this repo anyway, since the profile and
      # every custom-format group becomes an explicit reviewable value rather
      # than a remote id whose contents can change under a `git fetch`.
      #
      # Transcribed from config-templates @ 9faf65f
      # ({radarr,sonarr}/templates/remux-web-2160p.yml) and validated with
      # `recyclarr sync --preview` against the live instances before commit.
      #
      # ── INSTANCE NAMES *AND* base_url MUST BE UNIQUE ─────────────────────
      #
      # `movies` and `series`, not `main` and `main`.  Recyclarr treats the
      # instance-name namespace as GLOBAL, not per-service, and enforces it in
      # the worst possible way: with both named `main` it logs "Duplicate
      # instances: [main]" at DEBUG, syncs NOTHING, prints nothing to the
      # console and EXITS 0.  A green timer, forever, doing nothing.  Measured
      # 2026-08-21 — the first version of this file had exactly that bug and
      # only a --preview run caught it.
      #
      # Unique names are necessary and NOT sufficient: recyclarr also groups
      # instances by base_url and treats two names on one server as
      # duplicates, with the identical silent outcome.  ONE INSTANCE PER
      # SERVER, ALWAYS; extra profiles go in `quality_profiles`.
      #
      # ── WHAT THIS CHANGES on the live instances ──────────────────────────
      #
      # Quality definitions (per-quality file size limits) AND a quality
      # profile AND custom-format scoring.  `[Audio] Audio Formats` syncs by
      # default (it is listed under the templates' `skip:` blocks, commented
      # out), and that group is what scores TrueHD Atmos and DTS-X above
      # everything else.
      #
      # THE TWO SERVICES ARE DELIBERATELY ASYMMETRIC:
      #
      #   radarr → Remux + WEB 2160p   films are what you sit down for, and
      #                                TrueHD Atmos lives on Bluray remuxes;
      #                                WEB releases carry only lossy DD+ Atmos
      #   sonarr → WEB-1080p           series are the bulk of the episode
      #                                count, so this is where restraint
      #                                actually saves the pool
      #
      # WHAT "REMUX" MEANS HERE, because the everyday meaning of the word
      # points the wrong way: in TRaSH/*arr terms a Remux release is the video
      # and audio streams lifted UNTOUCHED off the UHD Blu-ray into an MKV.
      # It is the TOP of the quality ladder and the LARGEST file type —
      # roughly 40–80 GB per film — not a re-package for compatibility.  If
      # anything it is *less* compatible: full TrueHD Atmos and dual-layer
      # Dolby Vision are exactly what weak clients cannot direct-play.
      #
      # ── CENSUS, MEASURED 2026-08-26 via each app's /api/v3 ───────────────
      #
      #   SONARR   139 series
      #     id 4  HD-1080p               upgradeAllowed=false    67
      #     id 6  HD - 720p/1080p        upgradeAllowed=false    13
      #     id 7  Remux + WEB 2160p      upgradeAllowed=TRUE     59
      #     id 5  Ultra-HD               upgradeAllowed=false     0  ← empty
      #
      #   RADARR   2432 movies
      #     id 5  Ultra-HD               upgradeAllowed=false  2389
      #     id 7  Remux + WEB 2160p      upgradeAllowed=TRUE     27
      #     id 6  HD - 720p/1080p        upgradeAllowed=false    16
      #
      # So "the big pile on a non-upgrading Ultra-HD profile" is a RADARR fact
      # — 2389 films — and Sonarr's Ultra-HD holds nothing at all.  The
      # bulk-edit hazard is real and mostly on the film side; that library is
      # the 13 TB one and the pool has ~47.6 TB free, so a mass promotion
      # there is still capable of consuming most of it through the VPN.
      #
      # THE OPERATING RULE: promote titles to a new profile INDIVIDUALLY.  The
      # one part that applies fleet-wide regardless is `quality_definition`,
      # which rewrites size limits for every profile including "Ultra-HD".
      #
      # `reset_unmatched_scores` means custom formats NOT named by these
      # groups are set to 0 on the synced profile.  That is what makes the
      # profile reproducible from this file rather than accumulating whatever
      # the UI has been poked into.
      #
      # ── TO PREVIEW BEFORE LETTING THE TIMER RUN ──────────────────────────
      #
      # `recyclarr` IS NOT ON $PATH inside this container — environment.
      # systemPackages is deliberately just `curl`, and the binary only ever
      # exists as an absolute store path in the unit's ExecStart.  A naive
      # invocation fails in a way that reads like a permissions problem
      # (`runuser: failed to execute recyclarr: Permission denied`).  The
      # store path changes with every rebuild, so it must not be pasted
      # literally either — ask systemd where it is:
      #
      #   nixos-container run arr -- systemctl start arr-api-keys
      #   BIN=$(nixos-container run arr -- \
      #           systemctl show recyclarr -p ExecStart --value \
      #         | grep -o '/nix/store/[^ ]*/bin/recyclarr' | head -1)
      #   nixos-container run arr -- runuser -u recyclarr -- \
      #     "$BIN" sync --preview --config /var/lib/recyclarr/config.yml
      #
      # ONE TRAP IN READING THE OUTPUT: /var/lib/recyclarr/config.yml IS
      # REGENERATED BY ExecStartPre, not by the deploy.  Straight after a
      # rebuild it is still the PREVIOUS generation's file, so a preview run
      # faithfully processes the OLD instance list and shows nothing new.
      # That is not a config that failed to apply.  The check that the new
      # instances really are deployed is the unit itself —
      #
      #   nixos-container run arr -- systemctl show recyclarr -p ExecStartPre \
      #     --value | xargs cat | grep -o 'quality_profiles.*' | head -c 400
      #
      # — the pre-start script embeds the whole rendered config as a heredoc,
      # so it shows what the NEXT run will use without running anything.
      # (`grep -c LoadCredential` counts `_secret` references, which is two
      # here — one per INSTANCE, not per profile.)  Run the service once, or
      # wait for the timer, and config.yml catches up.
      configuration = {
        ####################################################################
        # M12 (g) — THREE MORE PROFILES, ON THE TWO EXISTING INSTANCES.
        #
        # ── RECYCLARR DEDUPLICATES ON base_url, NOT ON INSTANCE NAME ──────
        #
        # THIS IS THE CORRECTED VERSION.  The first attempt gave each new
        # profile its own INSTANCE (`sonarr.series-german`, and so on) with a
        # distinct name, on the strength of the "instance names must be
        # unique" warning further up this file.  Unique names are necessary
        # and NOT sufficient.  Measured on ernst 2026-08-26:
        #
        #   [DBG] Split instances: [
        #     {"BaseUrl":"http://localhost:7878",
        #      "InstanceNames":["movies","movies-german"]},
        #     {"BaseUrl":"http://localhost:8989",
        #      "InstanceNames":["series","series-german","series-remux-2160p"]}]
        #
        # …and then it synced NOTHING and EXITED 0.  Two instance names
        # pointing at ONE base_url are duplicates as far as recyclarr is
        # concerned, however differently they are named.  This is the SAME
        # fails-by-succeeding bug the header already warns about, on a
        # dimension the warning did not cover — so the rule is now:
        #
        #   ONE INSTANCE PER SERVER.  ALWAYS.  Additional profiles go in
        #   `quality_profiles`; never in a new instance.
        #
        # It is only visible with `--log debug`.  At the default level the
        # command prints two "Initializing provider" lines and stops, which
        # looks like success.  The check is the ABSENCE of "Processing" and
        # "Completed at" lines, exactly as the note below `systemd.services.
        # recyclarr` says.
        #
        # ── SO HOW ARE THE GROUPS KEPT APART? assign_scores_to ────────────
        #
        # The cross-contamination worry that motivated separate instances is
        # real: `custom_format_groups` is declared per INSTANCE, and a group
        # with no `assign_scores_to` applies to ALL guide-backed profiles in
        # that instance.  Left implicit, the German unwanted-formats set
        # would land on the English profile and vice versa — a config that
        # syncs cleanly and scores nonsense.
        #
        # `assign_scores_to` is the mechanism that solves it properly, and it
        # takes a profile REFERENCE — `trash_id` or `name`.  trash_id is used
        # throughout below: it is what `quality_profiles` already keys on, and
        # a name can be changed in the *arr UI by anyone, silently detaching
        # the scores from the profile.
        #
        # EVERY GROUP HERE CARRIES AN EXPLICIT assign_scores_to, including
        # the ones that go to only one profile.  Relying on the "applies to
        # all" default would mean the correctness of this block changed the
        # next time a profile was added — which is precisely how it broke.
        #
        # The pairings below are NOT invented: each is the group list its own
        # TRaSH template ships with, transcribed whole, from config-templates
        # @ 9faf65f.  Scores and CF combinations are tested together to
        # prevent download loops; a half-transcribed group is not a smaller
        # version of the same thing.
        #
        # NOT ADDED, both recorded so they are not "discovered" later:
        #
        #   AN ANIME PROFILE.  M12 (g) says to ask rather than assume, because
        #   it is a substantial custom-format set for content nobody has said
        #   they watch.  Asked on 2026-08-26; the answer was no.  Reopen it by
        #   adding sonarr/templates/anime-remux-1080p.yml's profile to the
        #   `sonarr.series` quality_profiles list below — NOT as a new
        #   instance, for the reason at the top of this comment.
        #
        #   PROFILARR.  Same job as this block, but it keeps state in ITS OWN
        #   DATABASE.  A Nix attrset is a reviewable diff with recorded
        #   provenance and is strictly better here — the argument the
        #   recyclarr header makes about why this config is inlined rather
        #   than `include`d applies to Profilarr with more force, not less.
        #   REJECTED, deliberately.
        ####################################################################

        radarr.movies = {
          base_url = "http://localhost:${toString radarrPort}";
          api_key._secret = "${arrSecretsDir}/radarr-api-key";

          quality_definition.type = "movie";

          quality_profiles = [
            {
              trash_id = "fd161a61e3ab826d3a22d53f935696dd"; # Remux + WEB 2160p
              reset_unmatched_scores.enabled = true;
            }
            # M12: the German companion, pitched to MATCH the English profile
            # rather than sit below it.  Films are what you sit down for, and
            # a German profile a step down would make "upgrade to German when
            # one appears" a downgrade in everything except language.
            #
            # THE BEHAVIOUR THIS BUYS, which is the actual request in M12 (g):
            # grab the best English release first, then upgrade to German /
            # German-DL when one appears, upgrading until "Upgrade Until
            # Custom Format Score".  That is a property of the TRaSH German
            # profile itself — its German-audio CFs carry positive scores and
            # its cutoff sits above what an English-only release can reach —
            # not something configured here.  It only takes effect for titles
            # ASSIGNED to it; see the promotion rule on the Sonarr side.
            {
              trash_id = "79faa9943cef2f510b997b1f2a9f3ea6"; # [German] Remux + WEB 2160p
              reset_unmatched_scores.enabled = true;
            }
          ];

          # Groups these templates add on top of the three synced by default
          # ([Audio] Audio Formats, [HDR Formats] HDR, [Streaming Services]
          # General).  Those three are not listed anywhere — they are on
          # unless explicitly skipped.
          custom_format_groups.add = [
            # Both templates ship Golden Rule UHD, so it goes to both.
            {
              trash_id = "ff204bbcecdd487d1cefcefdbf0c278d"; # [Optional] Golden Rule UHD
              assign_scores_to = [
                {trash_id = "fd161a61e3ab826d3a22d53f935696dd";}
                {trash_id = "79faa9943cef2f510b997b1f2a9f3ea6";}
              ];
            }
            # English unwanted formats — ENGLISH PROFILE ONLY.
            {
              trash_id = "a3ac6af01d78e4f21fcb75f601ac96df"; # [Unwanted] Unwanted Formats
              assign_scores_to = [{trash_id = "fd161a61e3ab826d3a22d53f935696dd";}];
            }
            # GERMAN unwanted formats — GERMAN PROFILE ONLY.  A different
            # trash_id with different contents, not a translation: it adds
            # German LQ, German LQ (release title) and German Microsized,
            # which are the formats that make a German library unwatchable
            # and which the English group knows nothing about.
            {
              trash_id = "0ca61b4b233178d07113082a7acff72d"; # [Unwanted] Unwanted Formats German
              assign_scores_to = [{trash_id = "79faa9943cef2f510b997b1f2a9f3ea6";}];
            }
          ];
        };

        sonarr.series = {
          base_url = "http://localhost:${toString sonarrPort}";
          api_key._secret = "${arrSecretsDir}/sonarr-api-key";

          quality_definition.type = "series";

          # 1080p for series, deliberately — see the asymmetry note above.
          # Transcribed from sonarr/templates/web-1080p.yml, NOT from the
          # 2160p one: the group list differs by more than the profile id.
          quality_profiles = [
            {
              trash_id = "72dae194fc92bf828f32cde7744e51a1"; # WEB-1080p
              reset_unmatched_scores.enabled = true;
            }
            # M12: German series at HD, matching the English profile's
            # restraint for the reason this file already gives — series are
            # the bulk of the episode count, so this is where restraint
            # actually saves the pool.
            {
              trash_id = "dca7e5e9e99c703bcbdaaa471dd40e98"; # [German] HD Bluray + WEB
              reset_unmatched_scores.enabled = true;
            }
            # M12: Sonarr Remux + WEB 2160p.
            #
            # ── THIS ONE ADOPTS AN EXISTING PROFILE.  IT IS NOT NEW ──────
            #
            # M12 asked for this to be "created ALONGSIDE" the others.  It
            # cannot be, and the deploy is what revealed why: Sonarr ALREADY
            # HAS a profile named exactly `Remux + WEB 2160p` (id 7), with
            # upgradeAllowed = TRUE and 59 OF THE 139 SERIES ON IT.  Syncing
            # the guide's profile under its guide name therefore does not
            # create anything — recyclarr takes the existing profile over and
            # rewrites it, and `reset_unmatched_scores` below zeroes every
            # custom format these groups do not name.
            #
            # ADOPTING IT IS A DELIBERATE CHOICE, made by lgo on 2026-08-26
            # with the consequence stated: those 59 series ride an
            # upgrade-enabled profile, so re-scoring can put their current
            # files below cutoff and queue 2160p upgrade searches.  The
            # alternative — giving the guide-backed profile an explicit
            # `name` so recyclarr builds a separate one and leaves id 7
            # alone — was considered and rejected: bringing the profile
            # actually in use into line with TRaSH is the point, and a
            # second nearly-identical 2160p profile is a thing nobody would
            # keep straight.
            #
            # WATCH THE ACTIVITY QUEUE AFTER THE FIRST REAL SYNC.  If it
            # fills with upgrade grabs for those 59 series, the lever is
            # Sonarr's own "Upgrade Until Custom Format Score" on this
            # profile, not this file.
            #
            # ── THE RULE IS STILL INDIVIDUAL PROMOTION.  DO NOT BULK-EDIT ─
            #
            # Someone will eventually "tidy up" by selecting everything and
            # reassigning the profile in one action.  Re-measured 2026-08-26,
            # and the hazard is mostly on the RADARR side: 2389 of 2432 films
            # sit on a hand-made "Ultra-HD" profile with upgradeAllowed =
            # false, and every TRaSH profile ships upgradeAllowed = true.
            # Mass-promoting those would queue a re-download of most of a
            # 13 TB film library against ~47.6 TB of free space, through the
            # VPN.  (The older form of this note put 133 series on Sonarr's
            # Ultra-HD; Sonarr's Ultra-HD is empty and always was the wrong
            # service to cite — see the census above.)
            #
            # Recyclarr never reassigns a title, so nothing moves on its own.
            # The danger is entirely a human with a multi-select box.
            {
              trash_id = "76a5053bdb2d1e4a8f16a69a37d46c12"; # Remux + WEB 2160p
              reset_unmatched_scores.enabled = true;
            }
          ];

          custom_format_groups.add = [
            # Golden Rule *HD* for the two HD profiles.  It is a different
            # group from the UHD one below — different trash_ids, tuned to
            # different resolutions — and carrying the UHD one onto a 1080p
            # profile would score x265/HDR rules that do not belong there.
            {
              trash_id = "158188097a58d7687dee647e04af0da3"; # [Optional] Golden Rule HD
              assign_scores_to = [
                {trash_id = "72dae194fc92bf828f32cde7744e51a1";}
                {trash_id = "dca7e5e9e99c703bcbdaaa471dd40e98";}
              ];
            }
            # Golden Rule UHD, and note this is SONARR's id — Sonarr and
            # Radarr have different groups with different trash_ids under the
            # same name.  2160p profile only.
            {
              trash_id = "e3f37512790f00d0e89e54fe5e790d1c"; # [Optional] Golden Rule UHD
              assign_scores_to = [{trash_id = "76a5053bdb2d1e4a8f16a69a37d46c12";}];
            }
            # The three the two ENGLISH templates share.  Deliberately NOT on
            # the German profile: its own template ships neither Language
            # Profiles nor the streaming boost, and adding them would be
            # exactly the "mixing groups that were tested together" the TRaSH
            # guidance warns about.
            {
              trash_id = "74aff4168620ed49dcc67e92b2c2a5b4"; # [Optional] Language Profiles
              assign_scores_to = [
                {trash_id = "72dae194fc92bf828f32cde7744e51a1";}
                {trash_id = "76a5053bdb2d1e4a8f16a69a37d46c12";}
              ];
            }
            {
              trash_id = "85fae4a2294965b75710ef2989c850eb"; # [Streaming Services] HD/UHD boost
              assign_scores_to = [
                {trash_id = "72dae194fc92bf828f32cde7744e51a1";}
                {trash_id = "76a5053bdb2d1e4a8f16a69a37d46c12";}
              ];
            }
            {
              trash_id = "59c3af66780d08332fdc64e68297098f"; # [Unwanted] Unwanted Formats
              assign_scores_to = [
                {trash_id = "72dae194fc92bf828f32cde7744e51a1";}
                {trash_id = "76a5053bdb2d1e4a8f16a69a37d46c12";}
              ];
            }
            # GERMAN unwanted formats — German profile only, same argument as
            # on the Radarr side.
            {
              trash_id = "6f0872eebfc95b1f93474b7ac866ced0"; # [Unwanted] Unwanted Formats German
              assign_scores_to = [{trash_id = "dca7e5e9e99c703bcbdaaa471dd40e98";}];
            }
          ];
        };
      };
    };

    # Do not fire while the things being configured are still coming up.
    # `wants`, not `requires`: recyclarr failing is not a reason to consider
    # sonarr degraded, and a sync that runs a minute early simply fails and
    # retries tomorrow.
    systemd.services.recyclarr = {
      after = ["sonarr.service" "radarr.service"];
      wants = ["sonarr.service" "radarr.service"];

      # DO NOT ADD `path = [ pkgs.git ]` HERE.  It was added once, on the
      # strength of an inference, and reverted after measurement.
      #
      # Recyclarr does shell out to a `git` binary to clone and fetch the
      # TRaSH-Guides and config-templates repos, and `command -v git` inside
      # this container correctly reports nothing — which makes "git is
      # missing" a very convincing explanation for a sync that does nothing.
      # It is wrong.  nixpkgs wraps the recyclarr binary with git already on
      # its PATH (`nix-store -q --references` on the package lists
      # git-2.54.0), so it finds one regardless of the unit's environment.
      # Verified on ernst 2026-08-21: with git explicitly filtered OUT of the
      # PATH passed to it, recyclarr still fetched 74 MB of guides and its
      # debug log shows the `git fetch` and `git reset --hard` succeeding.
      #
      # WHAT ACTUALLY CAUSED the silent run that prompted this: the config
      # file was not where recyclarr was told to look.  This container's /tmp
      # is a tmpfs, so a file written to the HOST's
      # /var/lib/nixos-containers/arr/tmp/ is invisible inside — and recyclarr
      # given a --config path that does not exist prints nothing and EXITS 0.
      #
      # Which is the part worth keeping, because it is not specific to that
      # mistake: this service fails by succeeding.  A missing config, a
      # duplicate instance name (see above), a bad template id — all of them
      # exit 0.  A green `systemctl list-timers` therefore proves nothing
      # about whether a sync happened.  The real check is the journal:
      #
      #   journalctl -u recyclarr | grep -E "Processing|Completed at"
      #
      # Their ABSENCE is the failure signal, not a non-zero status.
    };
    systemd.services.sonarr.serviceConfig = {
      ProtectSystem = "strict";
      ReadWritePaths = ["/srv/media" "/var/lib/sonarr"];
      UMask = lib.mkForce "0002";

      # Stops a mode tug-of-war, which is the M3 lesson in a new place.
      #
      # sonarr and prowlarr carry StateDirectory=, whose StateDirectoryMode
      # defaults to 0755 and is RE-APPLIED on every service start.  The host
      # tmpfiles rule above declares 0700 and is re-applied on every
      # `clan machines update`.  So the two took turns: 0700 after a deploy,
      # 0755 after the next restart, neither wrong enough to notice.  First
      # observed on ernst 2026-08-21 — sonarr and prowlarr on disk as 0755
      # while this file said 0700, and radarr (no StateDirectory) correctly
      # at 0700.
      #
      # Pinning it here makes systemd agree with tmpfiles rather than
      # alternate with it.  Radarr needs no equivalent: it has no
      # StateDirectory, so nothing competes.
      StateDirectoryMode = "0700";
    };
    systemd.services.radarr.serviceConfig = {
      ProtectSystem = "strict";
      ReadWritePaths = ["/srv/media" "/var/lib/radarr"];
      UMask = lib.mkForce "0002";
    };

    # BAZARR — the M12 equivalent of the Prowlarr row, and worse to start
    # with.
    #
    # Upstream's module (nixos/modules/services/misc/bazarr.nix) sets Type,
    # User, Group, SyslogIdentifier, ExecStart, Restart, KillSignal and
    # SuccessExitStatus.  That is the complete list.  There is NO hardening
    # of any kind — not a reduced set like prowlarr's, not a partial one:
    # none.  So everything below is ours, and unlike prowlarr there is no
    # "restoring what DynamicUser had been implying" to do, because upstream
    # never had DynamicUser either.
    #
    # The set is deliberately the same one sonarr and radarr get, because
    # Bazarr is the same kind of thing: a Python/.NET-adjacent web service
    # that reads and writes the library as group `media` and talks to
    # subtitle providers over HTTPS.
    #
    # ReadWritePaths is /srv/media AND its state directory, and /srv/media
    # is not narrowable to the library: Bazarr also reads from the download
    # tree when it grabs subtitles for something mid-import, and the "sync
    # subtitles" feature rewrites files in place.
    #
    # NOT PrivateUsers, for the reason cleanuparr's block gives: it would
    # squash a supplementary group, and here `media` is primary anyway — but
    # adding it would buy nothing and would make the primary-group choice
    # load-bearing in a second place.
    #
    # NOT MemoryDenyWriteExecute — Bazarr is Python and its native
    # extensions map writable-then-executable pages, the same rejection this
    # file already records for the three .NET services.
    systemd.services.bazarr.serviceConfig = {
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RemoveIPC = true;
      RestrictSUIDSGID = true;

      ReadWritePaths = ["/srv/media" "/var/lib/bazarr"];

      # Group-writable sidecars.  A .srt that only bazarr can replace is a
      # .srt nothing else can clean up, on a tree whose whole point is that
      # `media` can manage it.  Same argument as sonarr/radarr, and here it
      # applies to the PRIMARY artefact rather than to incidental metadata.
      UMask = "0002";

      CapabilityBoundingSet = "";
      PrivateDevices = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = arrSyscallFilter;
    };

    # `curl` is the test plan's instrument: it is what proves this container
    # can reach the download client's API at 10.0.90.11:8080 over br0 without
    # the UDM-Pro being involved, and what checks each web UI answers on
    # localhost before any firewall is in the picture.
    #
    # `music-stage` is beets with this deployment's config — see the binding
    # in the `let` above.  It belongs HERE rather than in the VPN guest
    # because it is a pure tag/metadata operation on files already on disk:
    # the only network it touches is MusicBrainz over HTTPS, which is an
    # ordinary API call and not something that needs to exit through the
    # tunnel.  Nothing else is added.
    # `beets` itself alongside the wrapper, because `music-stage` only ever
    # runs `import` — deliberately, see its binding — and maintenance needs
    # the other subcommands.  Removing a bad catalogue entry is the case that
    # forced this:
    #
    #   beet -c <config> remove -d '<query>'
    #
    # The config path is printed by `music-stage` in its own command line, or
    # read out of this file.
  };
}
