# machines/ernst/containers/arr/music.nix
#
# The music half of the `arr` container: Lidarr, Soularr (the Soulseek
# bridge), Navidrome, and the beets staging tool the three of them hand files
# between. Their host-side staging units and the two credential generators
# they read live here too.
#
# ── THIS FILE CO-DEFINES containers.arr ─────────────────────────────────────
#
# It creates no container; see ./video.nix for the mechanism and the reason
# the split is by media domain.
#
# `musicStage` is in this file's `environment.systemPackages` rather than
# ./common.nix's: the list merges across definitions, so the container still
# gets curl, musicStage and beets — and the one that is a music concern is
# declared next to the music services, with the beets config it embeds.
{ config, lib, pkgs, ... }:
let
  ids = import ./ids.nix;

  # The old flat names — see ./video.nix.
  arrSyscallFilter    = ids.syscallFilter;
  arrSecretsDir       = ids.secretsDirs.arrApiKeys;
  lidarrPort          = ids.ports.lidarr;
  navidromePort       = ids.ports.navidrome;
  navidromeSecretsDir = ids.secretsDirs.navidrome;
  navidromeEnvFile    = ids.navidromeEnvFile;
  soularrSecretsDir   = ids.secretsDirs.soularr;
  soularrConfigDir    = ids.soularrConfigDir;
  soulseekRoot        = ids.soulseekRoot;
  soulseekDownloadDir = ids.paths.soulseekDownloads;
  slskdAddr           = ids.peers.slskd.addr;
  slskdPort           = ids.peers.slskd.port;
  beetsStagingRoot    = ids.paths.beetsStaging;
  beetsStateDir       = ids.paths.beetsState;

  # Read `config`, so they cannot live in ./ids.nix — that file is plain
  # data. Both tolerate an ungenerated var: a missing credential must
  # degrade one service rather than stop the container.
  slskdCredsGen =
    if config.clan.core.vars.generators ? slskd-credentials
    then config.clan.core.vars.generators.slskd-credentials
    else { files."api-key".path = "/no-such-path"; };
  navidromeMetricsGen =
    if config.clan.core.vars.generators ? navidrome-metrics
    then config.clan.core.vars.generators.navidrome-metrics
    else { files."metrics.env".path = "/no-such-path"; };

  # it has already fetched in a per-playlist `_index.csv` INSIDE its own output
  # tree, and the batch re-runs over the same CSVs for weeks.  Moving files out
  # from under it leaves that bookkeeping describing files that are gone.
  # Copying costs disk — 42 TB free against ~100 GB of music — and costs
  # nothing else.
  #
  # `quiet_fallback: skip` is the important one.  In quiet mode beets takes the
  # best match without asking; on a weak match that silently files a track
  # under the wrong album, which is worse than not filing it at all and is
  # invisible afterwards.  `skip` leaves anything it is not confident about in
  # place, to be run again interactively.
  beetsConfig = pkgs.writeText "beets-config.yaml" ''
    directory: ${beetsStagingRoot}
    library: ${beetsStateDir}/library.db

    # ── `*.incomplete` IS NOT COSMETIC: IT IMPORTS TRUNCATED AUDIO ──────────
    #
    # sldl names an in-flight download `<name>.flac.incomplete` and renames it
    # on completion.  The batch now runs for weeks, so a `music-stage` run
    # ALWAYS overlaps live transfers — and beets does not care about the
    # extension, it cares whether the file has readable tags.  A half-written
    # FLAC usually does, because the tags are at the front.
    #
    # Measured 2026-10-04: a 4.6 MB truncated file landed as
    # `Dover/2/King George 07 (2007 Remastered Version).incomplete`, catalogued
    # as a real track.  Worse than the stray file itself is what it does next —
    # `duplicate_action: skip` means the FINISHED download is then skipped as a
    # duplicate of the broken one, so the good copy never arrives.
    #
    # beets' default ignore list is replaced wholesale when this key is set, so
    # its defaults are restated here rather than merged.
    ignore:
      - '*.incomplete'
      - '.*'
      - '*~'
      - 'System Volume Information'
      - 'lost+found'

    import:
      copy: yes
      move: no
      write: yes
      quiet_fallback: skip
      log: ${beetsStateDir}/import.log
      duplicate_action: skip

    # The singleton line carries the album when the tags have one, because
    # Lidarr is album-oriented and `Artist/Non-Album Tracks/` (beets' usual
    # singleton shape) gives it nothing to match.  Measured: 236 of 239 files
    # DO carry an album tag, so the fallback is the rare path, not the common
    # one.
    paths:
      default: $albumartist/$album%aunique{}/$track $title
      singleton: $artist/%if{$album,$album,Non-Album Tracks}/$title
      comp: Various Artists/$album%aunique{}/$track $title

    # `fromfilename` is the fallback for the handful with no tags at all (2 of
    # 239 measured): it guesses artist/title from the filename rather than
    # dropping them entirely.
    plugins: fromfilename
  '';

  # `beet` with this deployment's config, and the umask that keeps the
  # hardlink property intact — the same half that slskd gets from `UMask=0002`
  # on its unit and that sldl gets from its own wrapper.  A bare `beet` as root
  # writes 0644 and Lidarr can then no longer hardlink out of the staging tree.
  # `-A -s` IS BAKED IN, AND BOTH FLAGS WERE ARRIVED AT BY MEASUREMENT.
  # Running `beet import` without them on this input is not a worse result, it
  # is a WRONG one, so the wrapper does not offer the choice:
  #
  #   WITHOUT -s, beets treats each PLAYLIST DIRECTORY as one album.  sldl's
  #   folders are playlists — unrelated tracks by unrelated artists — so it
  #   picked one file's album tag and filed all three under it.  Measured
  #   2026-10-03: three unrelated singles landed in
  #   `Various Artists/Psychic/`, Psychic being Darkside's album.
  #
  #   WITHOUT -A, beets asks MusicBrainz and `quiet_fallback: skip` then skips
  #   everything it cannot match confidently.  Measured on the same three
  #   files: `Found 0 candidates` and three skips, with MusicBrainz reachable
  #   and answering (HTTP 200 in 0.18 s, checked separately — this is not a
  #   network fault).  The tags are already right; asking a remote database to
  #   second-guess them buys nothing here and loses the files when it fails.
  #
  # With both, the same three files landed as Trettmann/…, Darkside/… and
  # Iriepathie/… — each under its own artist, which is the whole point.
  #
  # Raw beets, for anything this does not cover, is
  # `beet -c ${beetsConfig} …` — the config path is stable in the store.
  musicStage = pkgs.writeShellApplication {
    name = "music-stage";
    runtimeInputs = [ pkgs.beets ];
    text = ''
      umask 0002
      exec beet -c ${beetsConfig} import -q -A -s "''${1:-/srv/media/soulseek/sldl}"
    '';
  };
in
{

  # ── 2026-09-08.  The Navidrome metrics password ───────────────────────────
  #
  # ROTATING IT needs a restart of BOTH containers, not just a deploy — the
  # janitorr-secrets caveat, doubled, because two services share this value:
  #     systemctl restart navidrome-secrets container@arr
  #     systemctl restart monitoring-secrets container@monitoring
  # Restarting only one leaves Prometheus scraping with the old password and
  # the `navidrome` job reporting up=0 with a 401 — which looks like Navidrome
  # being down rather than a half-finished rotation.
  systemd.services.navidrome-secrets = {
    description = "Stage Navidrome's Prometheus password for container@arr";
    after       = [ "local-fs.target" ];
    before      = [ "container@arr.service" ];
    wantedBy    = [ "container@arr.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    # Stage an EMPTY file rather than failing when the var is absent, the
    # soularr-secrets pattern.  systemd treats a MISSING EnvironmentFile as a
    # fatal unit error, so a first deploy before `clan vars generate ernst`
    # would take Navidrome down entirely rather than merely leaving its
    # metrics unauthenticated.  With an empty file the service starts, serves
    # music, and only the scrape fails — which is the right thing to break.
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${navidromeSecretsDir}
      if [ -r ${navidromeMetricsGen.files."metrics.env".path} ]; then
        ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
          ${navidromeMetricsGen.files."metrics.env".path} ${navidromeEnvFile}
      else
        echo "navidrome-secrets: no metrics password at ${navidromeMetricsGen.files."metrics.env".path} — run 'clan vars generate ernst'. Staging an empty file so Navidrome still starts; its /metrics will refuse the scrape." >&2
        ${pkgs.coreutils}/bin/install -m 0400 -o root -g root /dev/null ${navidromeEnvFile}
      fi
    '';
  };

  # The generator itself.  A generated password, NOT a prompt: nothing human
  # ever types this — Prometheus reads it from a file and Navidrome reads it
  # from an environment variable — so prompting for it would only invite a
  # weak one and add a question to every `clan vars generate ernst` run.
  #
  # Two files from one generator, deliberately.  `metrics.env` is the
  # KEY=value form systemd's EnvironmentFile wants; `password` is the bare
  # value, because Prometheus' `basic_auth.password_file` reads the file
  # CONTENTS as the password and would otherwise authenticate as the literal
  # string "ND_PROMETHEUS_PASSWORD=…".  Deriving both here is what keeps the
  # two consumers from disagreeing about format.
  clan.core.vars.generators.navidrome-metrics = {
    files."metrics.env".secret = true;
    files."password".secret    = true;

    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];

    script = ''
      set -euo pipefail

      # 32 bytes base64.  No prompt, no human in the loop, so there is no
      # reason for it to be shorter or memorable.
      pw=$(openssl rand -base64 32 | tr -d '\n')

      printf '%s' "$pw" > "$out/password"

      # No quoting: systemd's EnvironmentFile parser keeps quotes as part of
      # the value, which is the mistake the traefik-acme generator records.
      printf 'ND_PROMETHEUS_PASSWORD=%s\n' "$pw" > "$out/metrics.env"
    '';
  };

  # The same staging, for slskd's API key — see soularrSecretsDir above for why
  # soularr cannot read the clan var's own path from inside the container.
  #
  # ROTATING IT needs a restart and not just a deploy, for the same reason as
  # janitorr-secrets: unchanged unit text means systemd will not re-run this
  # when the underlying sops file changes.  After `clan vars generate ernst`:
  #     systemctl restart soularr-secrets container@arr
  systemd.services.soularr-secrets = {
    description = "Stage slskd's API key for Soularr in container@arr";
    after       = [ "local-fs.target" ];
    before      = [ "container@arr.service" ];
    wantedBy    = [ "container@arr.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    # Stage an EMPTY file rather than failing when the var is absent.
    #
    # LoadCredential is evaluated by PID 1 before ExecStartPre runs, so a
    # missing source file kills soularr at step CREDENTIALS with "No such file
    # or directory" — which names neither the key nor the command that would
    # produce it.  An empty file lets the unit reach its own render script,
    # whose emptiness check already prints the actionable message.  A source
    # that exists but cannot be copied still fails here, loudly, as it should.
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${soularrSecretsDir}
      if [ -r ${slskdCredsGen.files."api-key".path} ]; then
        ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
          ${slskdCredsGen.files."api-key".path} \
          ${soularrSecretsDir}/slskd-api-key
      else
        echo "soularr-secrets: no slskd API key at ${slskdCredsGen.files."api-key".path} — run 'clan vars generate ernst'. Staging an empty file so soularr reports it by name." >&2
        ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
          /dev/null ${soularrSecretsDir}/slskd-api-key
      fi
    '';
  };
  # ── Inside the container ──────────────────────────────────────────────────
  containers.arr.config = { config, pkgs, lib, ... }: let
    soularr = pkgs.callPackage ../pkgs/soularr.nix { };
  in {
    # THE WHOLE LIST LIVES HERE, not in ./common.nix, because its one
    # non-trivial member is defined here — musicStage carries ninety lines of
    # beets configuration, and that belongs with the music services rather
    # than in the file every other domain reads. curl rides along.
    #
    # One literal rather than two merged definitions, deliberately:
    # systemPackages order is PATH precedence, and keeping it identical is
    # what lets this split be verified as a no-op against the derivation hash.
    environment.systemPackages = with pkgs; [ curl musicStage beets ];


  ##########################################################################
  # M14 (a) — LIDARR.  Music, and the consumer end of the second write path.
  #
  # ── ITS UPSTREAM MODULE SHIPS NO HARDENING.  NONE ────────────────────
  #
  # This is the surprise of M14 and it is worth stating plainly, because
  # the sibling modules set the expectation the other way.  nixpkgs'
  # servarr modules are NOT uniform:
  #
  #   sonarr.nix    a full "# Hardening" block — CapabilityBoundingSet,
  #                 NoNewPrivileges, ProtectHome, PrivateUsers, ProtectProc,
  #                 RestrictAddressFamilies, UMask = "0022", …
  #   radarr.nix    the same
  #   lidarr.nix    Type, User, Group, EnvironmentFile, ExecStart, Restart.
  #                 THAT IS THE ENTIRE serviceConfig.
  #
  # Read at ernst's own pin on 2026-08-28, not assumed from the family
  # resemblance.  So Lidarr does not need its UMask overridden the way
  # sonarr's and radarr's do — it needs the whole set supplied, and the
  # `mkForce` those two require would be wrong here (there is no upstream
  # definition to conflict with).
  #
  # This is the Prowlarr trap in a third form.  M4 met it as "DynamicUser →
  # static uid silently drops six directives"; M12 met it as "upstream sets
  # eight of them"; here upstream sets zero and the family suggests
  # otherwise.  The lesson generalises: READ THE UNIT, do not infer it from
  # a sibling.
  #
  # ── dataDir IS NOT /var/lib/lidarr ───────────────────────────────────
  #
  # The module defaults it to `/var/lib/lidarr/.config/Lidarr`, and the
  # unit has no StateDirectory at all, so nothing creates the directory
  # either.  Left alone, that is exactly right for this container: the bind
  # mount is /var/lib/lidarr (the home), the host tmpfiles rule owns it as
  # 3017:3000, and Lidarr creates `.config/Lidarr` inside on first start.
  ##########################################################################
  services.lidarr = {
    enable       = true;
    user         = "lidarr";
    group        = "media";     # PRIMARY group — see the users block
    openFirewall = false;       # explicit list above
    settings.server.port = lidarrPort;
  };

  systemd.services.lidarr.serviceConfig = {
    # THE hardlink line, and the consumer half of the property
    # microvms/wg-qbittorrent.nix's slskd block provides.  slskd writes
    # 0664; Lidarr links and then writes its own artwork and .nfo files
    # next to the media, and at 0022 those would land writable by exactly
    # one uid on a tree whose whole point is that `media` can manage it.
    #
    # NO mkForce, unlike sonarr and radarr: upstream sets no UMask here at
    # all, so this is a new definition rather than a competing one.
    UMask = "0002";

    # The hardening upstream omits.  Same set as sonarr's and radarr's,
    # restated in full rather than referenced, because there is nothing
    # here to inherit from.
    CapabilityBoundingSet = "";
    NoNewPrivileges       = true;
    PrivateDevices        = true;
    PrivateTmp            = true;
    ProtectClock          = true;
    ProtectControlGroups  = true;
    ProtectHostname       = true;
    ProtectKernelLogs     = true;
    ProtectKernelModules  = true;
    ProtectKernelTunables = true;
    ProtectProc           = "invisible";
    RemoveIPC             = true;
    RestrictNamespaces    = true;
    RestrictRealtime      = true;
    RestrictSUIDSGID      = true;
    LockPersonality       = true;
    SystemCallArchitectures = "native";
    SystemCallFilter        = arrSyscallFilter;

    # AF_INET/AF_INET6 for indexers and MusicBrainz, AF_UNIX for logging.
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];

    # NOT ProtectHome = true.  sonarr and radarr carry it and can, because
    # their dataDir is /var/lib/<name>; Lidarr's home IS its state
    # directory and ProtectHome would make /var/lib/lidarr invisible to it.
    # ProtectSystem=strict plus an explicit ReadWritePaths is what does the
    # work instead.
    ProtectSystem  = "strict";
    ReadWritePaths = [ "/srv/media" "/var/lib/lidarr" ];

    # NOT PrivateUsers.  sonarr and radarr carry it — which is why `media`
    # has to be their PRIMARY group — and it is upstream's choice there,
    # not this file's.  Adding it here would buy nothing (Lidarr's access
    # to /srv/media is entirely its group membership, and that group is
    # already primary) and would cost the same footgun for the next person
    # who adds a supplementary group.
    #
    # NOT MemoryDenyWriteExecute: Lidarr is .NET and the JIT maps
    # writable-then-executable pages.  Same rejection as sonarr/radarr and
    # containers/jellyfin.nix, for the same runtime.
  };

  ##########################################################################
  # M14 (b) — SOULARR.  A TIMER, NOT A SERVICE.
  #
  # It reads Lidarr's "wanted" list, searches Soulseek through slskd's REST
  # API, grabs the best match into slskd's download tree, and tells Lidarr
  # to import it.  Lidarr then hardlinks out of that tree, which is the
  # chain M14's proof is about.
  #
  # ── WHY A TIMER ──────────────────────────────────────────────────────
  #
  # soularr.py runs one pass and EXITS.  Upstream's Docker image fakes a
  # daemon with a `SCRIPT_INTERVAL` sleep loop and its README's non-Docker
  # instruction is a cron entry.  A `Restart=always` service would restart-
  # loop by design and log every SUCCESSFUL pass as a service exit.
  #
  # 15 minutes, not upstream's 5.  Every firing is a full pass over Lidarr's
  # wanted list plus live Soulseek searches, each search bounded by
  # `search_timeout`; five minutes is tuned for someone watching a fresh
  # setup fill up, not for steady state.  The lock file makes an overlong
  # pass safe either way — see below.
  #
  # ── THE CONFIG IS RENDERED AT RUN TIME, NOT INTO THE STORE ───────────
  #
  # config.ini carries TWO API keys: Lidarr's (out of Lidarr's own
  # config.xml, via the existing arr-api-keys stager) and slskd's (from the
  # clan var).  Neither may sit in /nix/store, so the file is written into
  # a tmpfs on every firing — the same shape as janitorr's application.yml.
  #
  # ── THE LOCK FILE IS AN INTERLOCK, NOT A LEFTOVER ────────────────────
  #
  # soularr.py writes `.soularr.lock` into --var-dir and refuses to start
  # while it exists, which is what stops a slow pass from being overrun by
  # the next timer firing.  --var-dir therefore points at the PERSISTENT
  # state bind mount, not at the tmpfs holding the config: a lock on a
  # tmpfs would be erased by a reboot mid-pass, and — worse — would not be
  # seen by the next firing at all if the tmpfs were per-invocation.
  #
  # It also means a CRASHED pass leaves the lock behind and Soularr stays
  # stopped until someone removes it.  That is upstream's design and it is
  # the right failure direction here (a stuck downloader is visible; a
  # doubled one corrupts its own import queue), but it is the first thing
  # to check when Soularr "stops working":
  #
  #     rm /srv/state/soularr/.soularr.lock
  #
  # ── THE LOGGING FORMAT TAKES A SINGLE %, AND THIS IS NOT COSMETIC ────
  #
  # Doubling the percent signs in the [Logging] section destroys every log
  # line the service ever writes — in BOTH sinks, the journal and
  # soularr.log:
  #
  #   soularr[1969]: [%(levelname)s|%(module)s|L%(lineno)d] %(asctime)s: %(message)s
  #
  # Doubling is the correct reflex for configparser's DEFAULT
  # BasicInterpolation, where `%(name)s` is a reference to another option
  # and a literal `%` must be escaped.  Soularr does not use it.  It builds
  # its parser with an ExtendedInterpolation subclass (soularr.py:1331),
  # whose reference syntax is `${section:option}` and in which `%` has no
  # special meaning whatsoever — upstream's comment on that line says the
  # point was to make "storing logging formats in the config file much
  # easier".
  #
  # So `%%` is never un-doubled.  It arrives at logging.basicConfig still
  # doubled, and %-style formatting renders `%%` as a literal `%` — which
  # prints the TEMPLATE and discards the message.  soularr.log reached
  # 143 KB without one readable line.
  #
  # This shipped unnoticed because it was unreachable: until 2026-09-06 the
  # unit died at LoadCredential and never ran a pass at all.
  ##########################################################################
  systemd.services.soularr = {
    description = "Soularr — fill Lidarr's wanted list from Soulseek via slskd";

    # Wants, not requires: if Lidarr is down this pass should fail and be
    # retried at the next firing, not block the timer forever.
    after    = [ "lidarr.service" "arr-api-keys.service" ];
    wants    = [ "lidarr.service" ];
    # requires, not wants: without the staged keys this pass can only
    # write a config.ini with an empty API key, which Lidarr answers with
    # a 401 that says nothing about why.
    requires = [ "arr-api-keys.service" ];

    serviceConfig = {
      Type  = "oneshot";
      User  = "soularr";
      Group = "media";

      # Bound the pass.  Without this a hung one runs forever.
      #
      # A Type=oneshot unit is "activating" for as long as its ExecStart
      # runs, and TimeoutStartSec defaults to infinity for oneshots — so a
      # pass that wedges on an unresponsive slskd or a transfer that never
      # completes never ends.  While it sits there the timer cannot fire
      # again (the unit is already active), so Soularr stops running
      # permanently, and the unit shows `activating` rather than `failed`
      # so nothing looks wrong.  Silent, indefinite, and self-concealing:
      # the worst of the three.
      #
      # TimeoutStartSec and NOT RuntimeMaxSec.  systemd.service(5) is
      # explicit that RuntimeMaxSec "does not have any effect on
      # Type=oneshot services ... use TimeoutStartSec= to limit their
      # activation".  Setting the other one looks right and does nothing.
      #
      # Two hours.  A legitimate pass is bounded by the config rendered
      # below: each search by `search_timeout`, and a transfer this pass is
      # waiting on by `stalled_timeout`, which is 3600.  So one stalled
      # download can legitimately hold a pass for an hour; two hours clears
      # that with room and still turns "forever" into a bounded failure.
      #
      # On expiry the unit goes to `failed` with Result=timeout, and the
      # lock file described above is LEFT BEHIND.
      #
      # THAT USED TO BE THE DELIBERATE RESTING PLACE — "Soularr stays
      # stopped until someone runs the `rm`" — on the grounds that
      # `failed` is at least a state something can alert on.  IT IS NO
      # LONGER, and both halves of the reasoning expired: M6 gained
      # ContainerSystemdUnitFailed, so it does now page; and an
      # interrupted pass turned out to be a DEPLOY far more often than a
      # two-hour hang (measured 2026-09-07).  The ExecStartPre below
      # clears the stale lock, so an interruption of any kind costs one
      # skipped pass instead of every pass until a human intervenes.
      TimeoutStartSec = 7200;

      # See the render script: these are read by PID 1 as root and handed
      # to the unit as 0400 copies under $CREDENTIALS_DIRECTORY.  Both are
      # root-owned and unreadable by this unit's user at their real paths.
      LoadCredential = [
        "lidarr-api-key:${arrSecretsDir}/lidarr-api-key"
        # The STAGED copy, not slskdCredsGen's own path: that one is on the
        # host and invisible in here.  See soularrSecretsDir.
        "slskd-api-key:${soularrSecretsDir}/slskd-api-key"
      ];

      # Renders config.ini into a private tmpfs directory immediately
      # before the run.  RuntimeDirectory gives it 0700 ownership by the
      # service user and — importantly — REMOVES IT WHEN THE UNIT STOPS,
      # so the API keys exist only while a pass is running.
      RuntimeDirectory     = "soularr";
      RuntimeDirectoryMode = "0700";

      ExecStartPre = [
        # Clear a stale `.soularr.lock` before every pass.
        #
        # THIS IS THE CAVEAT IN THE TimeoutStartSec BLOCK ABOVE, CASHED IN.
        # That block said the lock is "LEFT BEHIND ... Soularr stays
        # stopped until someone runs the `rm`", and called it acceptable
        # because "nothing watches units inside this container yet". Two
        # things have changed: M6 gained ContainerSystemdUnitFailed, so it
        # now pages; and the interruption that actually happened was not
        # the timeout at all.
        #
        # MEASURED ON ernst 2026-09-07. A `clan machines update` restarted
        # the container mid-pass, soularr took SIGTERM two minutes in
        # (`code=killed, status=15/TERM`), and every run afterwards exited
        # 1 in 260 ms having logged nothing at all — no traceback, no
        # message, just an instant non-zero. The alert fired 15 minutes
        # later and would have kept firing forever. Removing the lock by
        # hand and starting the unit produced a normal pass, which is what
        # confirmed the cause rather than merely fitting it.
        #
        # A DEPLOY IS A FAR MORE COMMON INTERRUPTION THAN A TWO-HOUR HANG,
        # so the failure direction chosen there was tuned for the rarer
        # event. Reboots and OOM kills land the same way.
        #
        # REMOVING IT UNCONDITIONALLY IS SAFE, and specifically it does not
        # give up the overlap interlock the lock was for. systemd will not
        # start a unit that is already active, so a timer firing during a
        # long pass is refused by PID 1 before this script ever runs —
        # meaning that whenever this line executes, no other pass is in
        # flight and any lock present is by definition stale. The lock was
        # only ever a second, weaker copy of a guarantee systemd already
        # makes, and its sole remaining effect was to convert any unclean
        # exit into a permanent stop.
        "${pkgs.writeShellScript "soularr-clear-stale-lock" ''
          set -euo pipefail
          lock=/var/lib/soularr/.soularr.lock
          if [ -e "$lock" ]; then
            echo "soularr: clearing stale $lock left by an interrupted pass" >&2
            rm -f "$lock"
          fi
        ''}"
        "${pkgs.writeShellScript "soularr-render-config" ''
          set -euo pipefail

          # Read into variables FIRST and check them.  A command
          # substitution that fails inside a sed argument does not trip
          # `set -e`, which is how containers/jellyfin.nix's sibling bug
          # shipped an EMPTY password once.  A plain assignment does trip
          # it, and the explicit test covers "file present but empty".
          # $CREDENTIALS_DIRECTORY, NOT the staging directory.
          #
          # The staged keys are 0600 root:root inside a 0700 root directory
          # — deliberately, see the arr-api-keys block — so User=soularr
          # cannot open them and `cat` fails with "Permission denied".
          # That is exactly what shipped: every timer firing failed for a
          # day before anyone looked, because a failed oneshot on a timer
          # is silent unless you go and read its journal.
          #
          # LoadCredential below is what bridges it: PID 1 reads the files
          # as root BEFORE dropping to this unit's user, and places 0400
          # copies here that the service can read.  Scraparr solves the
          # same problem the same way and this file's header already said
          # so.
          lidarr_key=$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/lidarr-api-key")
          slskd_key=$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/slskd-api-key")

          if [ -z "$lidarr_key" ] || [ -z "$slskd_key" ]; then
            echo "soularr: an API key is empty — has arr-api-keys run, and has 'clan vars generate ernst' been run for slskd-credentials?" >&2
            exit 1
          fi

          ${pkgs.coreutils}/bin/install -m 0600 /dev/null ${soularrConfigDir}/config.ini
          ${pkgs.coreutils}/bin/cat > ${soularrConfigDir}/config.ini <<EOF
          [Lidarr]
          api_key = $lidarr_key
          host_url = http://localhost:${toString lidarrPort}
          download_dir = ${soulseekDownloadDir}
          disable_sync = False

          [Slskd]
          api_key = $slskd_key
          host_url = http://${slskdAddr}:${toString slskdPort}
          url_base = /
          download_dir = ${soulseekDownloadDir}
          delete_searches = False
          stalled_timeout = 3600
          remote_queue_timeout = 300

          [Release Settings]
          use_selected_lidarr_release = False
          use_most_common_tracknum = True
          allow_multi_disc = True
          accepted_countries = Europe,Japan,United Kingdom,United States,[Worldwide],Australia,Canada
          skip_region_check = False
          accepted_formats = CD,Digital Media,Vinyl

          [Search Settings]
          search_timeout = 5000
          maximum_peer_queue = 50
          minimum_peer_upload_speed = 0
          minimum_filename_match_ratio = 0.8
          minimum_search_interval = 5
          allowed_filetypes = flac 24/192,flac 16/44.1,flac,mp3 320,mp3
          album_prepend_artist = False
          search_type = incrementing_page
          number_of_albums_to_grab = 10
          search_source = missing
          failed_import_denylist = True

          [Download Settings]
          allow_uploads = False

          # Single %, NOT %% — soularr parses with ExtendedInterpolation.
          # See the block comment above this unit before changing these.
          [Logging]
          level = INFO
          format = [%(levelname)s|%(module)s|L%(lineno)d] %(asctime)s: %(message)s
          datefmt = %Y-%m-%dT%H:%M:%S%z
          EOF
        ''}"
      ];

      # --config-dir and --var-dir are BOTH passed explicitly.  Upstream
      # defaults both to os.getcwd(), which for a systemd unit is `/`, and
      # a downloader that silently reads its configuration out of the root
      # directory is worse than one that fails.
      ExecStart = "${lib.getExe soularr} --config-dir ${soularrConfigDir} --var-dir /var/lib/soularr";

      # Group-writable output — it moves rejected downloads aside inside
      # slskd's tree, which is 2770 root:media.  Same argument as
      # sonarr/radarr/cleanuparr.
      UMask = "0002";

      # Static uid with persistent state — the prowlarr shape, so every
      # directive DynamicUser would have implied is restated explicitly.
      NoNewPrivileges  = true;
      PrivateTmp       = true;
      ProtectSystem    = "strict";
      ProtectHome      = true;
      RemoveIPC        = true;
      RestrictSUIDSGID = true;

      # It reads ID3 tags out of the download tree and moves rejects; it
      # never touches the library, which Lidarr owns.
      ReadWritePaths = [ soulseekRoot "/var/lib/soularr" ];

      CapabilityBoundingSet   = "";
      PrivateDevices          = true;
      ProtectClock            = true;
      ProtectControlGroups    = true;
      ProtectHostname         = true;
      ProtectKernelLogs       = true;
      ProtectKernelModules    = true;
      ProtectKernelTunables   = true;
      ProtectProc             = "invisible";
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces      = true;
      RestrictRealtime        = true;
      LockPersonality         = true;
      SystemCallArchitectures = "native";
      SystemCallFilter        = arrSyscallFilter;
    };
  };

  systemd.timers.soularr = {
    description = "Run Soularr every 15 minutes";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnBootSec      = "10m";
      OnUnitActiveSec = "15m";
      # A missed firing (host down, container restarting) runs once on the
      # next start rather than not at all.  Harmless for an idempotent
      # pass over a wanted list.
      Persistent     = true;
      # Without this every firing lands on the same second across reboots,
      # which for a job that hammers a P2P network is a needless pattern.
      RandomizedDelaySec = "2m";
    };
  };

  systemd.services.komga.serviceConfig = {
    # ── ONE DIRECTIVE, AND IT IS THE ONE THAT MATTERS ──────────────────
    #
    # nixpkgs' komga module is the OPPOSITE of the audiobookshelf and
    # lidarr cases this file is used to: it already ships CapabilityBounding
    # Set="", NoNewPrivileges, PrivateUsers, PrivateDevices, ProtectProc,
    # RestrictNamespaces, a syscall filter and fifteen more — read at
    # ernst's pin.  Restating any of that here would be noise that drifts.
    #
    # WHAT IT GETS WRONG FOR THIS DEPLOYMENT IS `ProtectSystem = "full"`,
    # AND IT IS NOT A DETAIL.  `full` makes /usr, /boot and /etc read-only
    # AND NOTHING ELSE.  /srv is untouched — so under the module's own
    # setting, komga (in group `media`, against a 2770 root:media tree)
    # CAN DELETE THE COMICS LIBRARY from its own UI.  `strict` makes the
    # entire filesystem read-only and `ReadWritePaths` opens back exactly
    # its own state directory.
    #
    # mkForce because the module sets it as a plain definition rather than
    # a mkDefault, so a bare value is a conflict and not an override.  That
    # conflict is how this was found; it is worth the friction, because a
    # silent merge would have left the library writable.
    ProtectSystem  = lib.mkForce "strict";
    ReadWritePaths = [ "/var/lib/komga" ];

    # NOT a SystemCallFilter override.  The module ships
    # [ "@system-service" ]; arrSyscallFilter would MERGE with it (lists
    # concatenate) rather than replace it, and the result would be a
    # filter neither list describes.  Komga needs nothing arrSyscallFilter
    # adds — it writes only into its own StateDirectory and never chowns.
    #
    # NOT MemoryDenyWriteExecute: the JVM JITs.  The module does not set
    # it and must not; fourth runtime in this file with this property,
    # after Mono, .NET and Node.
  };

  ##########################################################################
  # NAVIDROME — the Subsonic / OpenSubsonic server over Lidarr's library.
  #
  # ── THE LIBRARY IS LIDARR'S AND STAYS LIDARR'S ───────────────────────
  #
  # /srv/media/library/music, 55 GB across 6 artists as of today, owned
  # uid 3017 (lidarr) : gid media, 2770.  Navidrome READS it and must never
  # write into it — a scrobble, a rating or a playlist must never become a
  # file in a tree whose contents Lidarr's database claims to know.
  #
  # ENFORCED IN TWO PLACES, ONE OF WHICH IS UPSTREAM'S:
  #
  #   1. The nixpkgs module runs this unit with RootDirectory=/run/navidrome
  #      and bind-mounts `MusicFolder` in through `BindReadOnlyPaths`.  So
  #      the read-only property is structural and comes for free — verified
  #      by reading the module at ernst's pin, not assumed.
  #   2. `ProtectSystem = "strict"` plus a `ReadWritePaths` naming only its
  #      own state, restated here so the guarantee does not silently depend
  #      on an upstream module keeping a sandbox directive it could drop.
  #
  # Again: NOT the group.  navidrome is in `media` because 2770 leaves no
  # other way to read the tree at all.
  #
  # ── TRANSCODING: WHAT IS DECLARATIVE HERE AND WHAT CANNOT BE ─────────
  #
  # `EnableTranscodingConfig` exposes the transcoding editor in the UI.
  # The PROFILES THEMSELVES ARE DATABASE ROWS, NOT CONFIGURATION, and that
  # is a property of Navidrome rather than of this module — verified by
  # inspecting a freshly created 0.63.2 database, which ships four seeded
  # rows (mp3 192, opus 128, aac 256, flac) in a `transcoding` table, and a
  # `player` table whose `transcoding_id` and `max_bit_rate` columns are
  # written when a client first connects.
  #
  # So the Opus ~96 kbps mobile profile ASKED FOR HERE CANNOT BE SET IN
  # NIX.  It is: the seeded `opus audio` profile, plus a per-player
  # assignment made once in the UI after the phone has connected.  The
  # steps are in docs/guides/ernst-app-api-ingress.md.  Writing the row
  # directly into the SQLite file from an activation script was considered
  # and rejected — it is a second writer to a database the application
  # owns, and the failure mode is a corrupted library rather than a wrong
  # bitrate.
  #
  # THE LAN PATH STAYS UNTRANSCODED because no player gets an assignment
  # until someone makes one; the default is raw.  That is the desired
  # behaviour and it is the default, so there is nothing to configure.
  #
  # NOTE FOR WHOEVER DEBUGS A BITRATE COMPLAINT: since 0.61 transcoding is
  # SERVER-MANAGED.  Clients no longer negotiate the format — the server
  # decides from the player row.  A client-side "audio quality" setting
  # that appears to do nothing is not broken; it is this.
  #
  # ffmpeg is ALREADY in the package's runtime path — its startup log
  # prints `Found ffmpeg path=/nix/store/…-ffmpeg-headless-…/bin/ffmpeg`
  # with nothing added.  No `path` entry is needed and adding one would
  # shadow the wrapper.
  ##########################################################################
  services.navidrome = {
    enable = true;
    user   = "navidrome";
    group  = "media";          # for /srv/media/library/music, read-only per above

    # The Prometheus scrape credential.  It is `ND_PROMETHEUS_PASSWORD` in
    # this file rather than `Prometheus.Password` in `settings` below for
    # one reason: `settings` is rendered to a JSON file IN THE NIX STORE,
    # which is world-readable.  The env var is read from a 0400 file
    # staged out of a clan var.  Verified that the override works at
    # 0.63.2 — /metrics answers 401 without it and 200 with it.
    environmentFile = navidromeEnvFile;

    settings = {
      # 0.0.0.0 for the audiobookshelf reason; the module defaults to
      # 127.0.0.1, which Traefik in another netns cannot reach.
      Address = "0.0.0.0";
      Port    = navidromePort;

      MusicFolder = "/srv/media/library/music";

      # DataFolder DELIBERATELY UNSET.  It defaults to the module's
      # WorkingDirectory, /var/lib/navidrome, which the bind mount above
      # puts on zdata.  Setting it explicitly would add a second place the
      # path is written and a second thing to keep in step with the bind.

      # ── Telemetry: OFF, EXPLICITLY ────────────────────────────────────
      #
      # The nixpkgs module already defaults this to false, so this line is
      # redundant TODAY and is here anyway: the upstream BINARY defaults it
      # ON (a bare `navidrome` logs "Starting Insight Collector"), so the
      # safe state depends entirely on a module default that could change.
      # Stated explicitly, it cannot.  Confirmed by the startup log
      # reading "Insight Collector is DISABLED".
      EnableInsightsCollector = false;

      # ── Scanning: a schedule AND a watcher, which are not redundant ───
      #
      # The watcher catches Lidarr's imports within seconds, which is the
      # normal path and the one that matters for "I just downloaded an
      # album and it is not there".  The periodic scan is the backstop for
      # everything inotify structurally misses: a file whose mtime changed
      # without an inotify event this process saw, anything written while
      # the service was down, and tag edits made in bulk outside the
      # library.
      #
      # 12h rather than hourly because a full scan walks 55 GB and reads
      # tags, and the watcher already covers the interactive case — the
      # schedule exists for correctness over days, not for latency.
      #
      # `Scanner.Schedule`, NOT the top-level `ScanSchedule`.  THIS IS A
      # TRAP AND IT IS MEASURED: at 0.63.2 the old key is accepted
      # silently, produces no error and no warning, and the startup log
      # reads "Periodic scan is DISABLED".  A config that looks correct in
      # review and never rescans.  Verified both spellings against the
      # running binary before this was written.
      Scanner = {
        Schedule       = "@every 12h";
        WatcherEnabled = true;
      };

      # ── Transcoding: the UI editor on; profiles are DB rows ───────────
      # See the long note above for why the Opus profile is not here.
      EnableTranscodingConfig = true;

      # ── Prometheus ────────────────────────────────────────────────────
      #
      # Metrics ride the ordinary port; there is no separate listener to
      # bind.  The endpoint demands HTTP Basic as user `navidrome` with
      # the password from the environment file above — measured, not
      # inferred from documentation.
      Prometheus = {
        Enabled     = true;
        MetricsPath = "/metrics";
      };

      # ── SQLite backups ────────────────────────────────────────────────
      #
      # ALONGSIDE ZFS SNAPSHOTS IS THE INTENT, BUT READ THIS: zdata/state
      # currently has NO SNAPSHOTS AT ALL.  `disko.nix` declares
      # com.sun:auto-snapshot=true on it, but disko does not apply
      # properties to datasets on an existing pool, and the live pool has
      # the property unset — measured on ernst 2026-09-08, where only
      # zdata/audiobooks and zdata/roms carry it.
      #
      # So today this backup IS the protection for this database, not a
      # supplement to one.  Turning the snapshots on is one `zfs set` and
      # it is in the deploy checklist; until it is run, do not read the
      # word "alongside" as describing reality.
      #
      # 04:00 daily, keep 14.  Navidrome's backup is a consistent SQLite
      # copy, so it is safe to take live — which a raw file copy of a WAL
      # database is not, and is why this uses the application's own
      # mechanism rather than a tmpfiles/rsync job.
      Backup = {
        Path     = "/var/lib/navidrome/backup";
        Schedule = "0 4 * * *";
        Count    = 14;
      };

      # ── ListenBrainz: PREPARED, NOT ENABLED ───────────────────────────
      #
      # TODO(listenbrainz): point BaseURL at the self-hosted instance when
      # it exists.  IT DOES NOT EXIST YET — that service is out of scope
      # here and is not on the roadmap as built.
      #
      # `Enabled = false` deliberately, and it is the important half: the
      # BaseURL below is upstream's PUBLIC endpoint, which is also the
      # built-in default.  Enabling the scrobbler before the self-hosted
      # instance exists would send the household's complete listening
      # history to listenbrainz.org — which is a reasonable thing to
      # choose and a very unreasonable thing to do by accident while
      # "preparing" for a local one.
      #
      # When the local instance lands: change BaseURL, set Enabled = true,
      # and each user links their own token in Settings — the token is
      # per-user and is not a server credential, so nothing here needs a
      # clan var for it.
      ListenBrainz = {
        Enabled = false;
        BaseURL = "https://api.listenbrainz.org/1/";
      };
    };

    openFirewall = false;      # explicit list above
  };
  };
}
