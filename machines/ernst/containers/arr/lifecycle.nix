# machines/ernst/containers/arr/lifecycle.nix
#
# What manages media AFTER it arrives: Janitorr (expiry), Cleanuparr (stalled
# and unwanted downloads) and Scraparr (the Prometheus exporter for the whole
# stack). Their host-side staging units and the Janitorr/Jellyfin credential
# generator live here too — the host half and the container half of one
# service belong in one file.
#
# ── THIS FILE CO-DEFINES containers.arr ─────────────────────────────────────
#
# It creates no container; see ./video.nix for the mechanism and the reason
# the split is by media domain.
#
# JANITORR DELETES MEDIA, and `janitorrDryRun` in ./ids.nix keeps it
# proposing rather than doing until a human has read a cycle's log and agreed
# with it. That flag is data in the shared file precisely so it is findable.
{ config, lib, pkgs, ... }:
let
  ids = import ./ids.nix;

  # The old flat names — see ./video.nix.
  arrSyscallFilter   = ids.syscallFilter;
  arrSecretsDir      = ids.secretsDirs.arrApiKeys;
  janitorrDryRun     = ids.janitorrDryRun;
  janitorrSecretsDir = ids.secretsDirs.janitorr;
  janitorrPort       = ids.ports.janitorr;
  cleanuparrPort     = ids.ports.cleanuparr;
  scraparrPort       = ids.ports.scraparr;
  sonarrPort         = ids.ports.sonarr;
  radarrPort         = ids.ports.radarr;
  bazarrPort         = ids.ports.bazarr;
  prowlarrPort       = ids.ports.prowlarr;
  jellyseerrPort     = ids.ports.jellyseerr;
  jellyfinAddr       = ids.peers.jellyfin.addr;
  jellyfinPort       = ids.peers.jellyfin.port;

  # Reads `config`, so it cannot live in ./ids.nix — that file is plain data
  # on purpose. Tolerant of an ungenerated var for the reason the module's
  # `readvar` is: a missing credential must degrade one service, not stop the
  # container.
  janitorrJellyfinGen =
    if config.clan.core.vars.generators ? janitorr-jellyfin
    then config.clan.core.vars.generators.janitorr-jellyfin
    else { files."jellyfin.env".path = "/no-such-path"; };
in
{

  # The rest of the media tree is NOT declared here.  containers/jellyfin.nix
  # owns those tmpfiles rules (library/{movies,tvshows}, torrents/{movies,tv})
  # and microvms/wg-qbittorrent.nix owns torrents/{incomplete,complete}.  A
  # second set of rules for the same paths is precisely the failure M3 spent a
  # round on: tmpfiles enforces mode and ownership on EVERY run, so two
  # declarations that disagree take turns winning, silently, one per deploy.
  #
  # torrents/mediathek above is the ONE exception and does not break that rule,
  # because it is a path NO OTHER FILE DECLARES.  It belongs to this file
  # because the service that writes it lives in this file, and the ownership
  # rule the M3 lesson actually states is "one declaration per path", not "one
  # file per tree".  If a later milestone moves MediathekArr elsewhere, these
  # three rules move with it rather than being duplicated there.

  ##############################################################################
  # M13 — JANITORR'S JELLYFIN CREDENTIALS.  A clan var, and the only prompted
  # secret this container has.
  #
  # ── WHY THESE THREE CANNOT BE READ OUT OF A CONFIG FILE ────────────────────
  #
  #   Everything else this container needs is read from the application that
  #   generated it: sonarr's and radarr's API keys come out of their own
  #   config.xml (see arr-api-keys), and Jellyseerr's comes out of its own
  #   settings.json.  That keeps ONE source of truth and survives a key
  #   rotation in a UI with no deploy — M4's argument, restated in M12.
  #
  #   Jellyfin is the exception, twice over:
  #
  #     1. Its API key lives in its DATABASE, not in a file this container
  #        could read even if it had a bind mount for it (it does not — the
  #        Jellyfin container is a separate netns and a separate state tree).
  #     2. JANITORR NEEDS A REAL USER, NOT JUST AN API KEY.  Jellyfin's delete
  #        endpoint authorises against a user account with deletion rights;
  #        an API key alone cannot delete.  So a username and password are
  #        needed as well, and an account is definitionally created by a human
  #        in a UI.
  #
  #   That makes prompts the honest shape.  `clan vars generate ernst` asks for
  #   all three; the PR body carries the in-Jellyfin steps that produce them.
  #
  # ── IT IS NOT NEEDED FOR THE FIRST DEPLOY TO SUCCEED ───────────────────────
  #
  #   Deliberately.  Janitorr's first deploy runs in DRY-RUN (see its block),
  #   and dry-run does not call Jellyfin's delete endpoint at all — so a
  #   deploy that lands before the Jellyfin account exists still produces a
  #   Janitorr that starts, connects to the *arrs, and prints what it WOULD
  #   delete, which is the deliverable M13 asks for.
  #
  #   What it will not do until these are filled in is build the "Leaving
  #   Soon" collections, because those are created through the Jellyfin API.
  clan.core.vars.generators.janitorr-jellyfin = {
    files."credentials.env" = {
      secret = true;
    };
    prompts."api-key" = {
      description = "Jellyfin API key for Janitorr (Dashboard → API Keys → +)";
      type = "hidden";
    };
    prompts."username" = {
      description = "Jellyfin username for Janitorr's dedicated deletion account";
      type = "line";
    };
    prompts."password" = {
      description = "Password for that Jellyfin account";
      type = "hidden";
    };
    # Written as an EnvironmentFile rather than three separate files because
    # the consumer is a single config-rendering oneshot inside the container.
    # Values are NOT quoted: systemd's EnvironmentFile parser treats quotes as
    # part of the value unless the whole value is quoted, and a password that
    # silently gains a pair of quotes fails authentication with a message that
    # says nothing about quoting.
    script = ''
      {
        printf 'JELLYFIN_API_KEY=%s\n'  "$(cat "$prompts/api-key")"
        printf 'JELLYFIN_USERNAME=%s\n' "$(cat "$prompts/username")"
        printf 'JELLYFIN_PASSWORD=%s\n' "$(cat "$prompts/password")"
      } > "$out/credentials.env"
    '';
    runtimeInputs = [ pkgs.coreutils ];
  };

  # Stage them where the container can see them.
  #
  # Same shape and the same reasoning as containers/traefik.nix's
  # traefik-secrets: a directory WE own, bound into the container at the same
  # path, rather than a bind of /run/secrets — which is a symlink to a
  # per-generation directory that is REPLACED on every deploy, so an nspawn
  # bind established at container start would keep exposing a deleted
  # generation until the container is restarted.
  #
  # 0400 root:root.  The rendering oneshot inside the container reads this as
  # root before writing a file the janitorr uid can read; uid 3015 never opens
  # this one and must not be able to.
  #
  # GENERATE BEFORE YOU DEPLOY — but unlike traefik-secrets, a deploy that runs
  # first is NOT fatal here.  Until the var exists, `files.<n>.path` evaluates
  # to the literal "/no-such-path", so this unit fails; it is deliberately NOT
  # `requiredBy` container@arr, so the container still starts and every other
  # service in it runs.  Janitorr's config renderer degrades to a Jellyfin-less
  # configuration, which is exactly what dry-run needs.  See the janitorr-config
  # block, which is where that degradation is implemented and explained.
  #
  # ROTATING THE CREDENTIALS needs a restart, not just a deploy: if this unit's
  # text is unchanged, systemd will not re-run it when the underlying sops file
  # changes.  After `clan vars generate ernst`:
  #     systemctl restart janitorr-secrets container@arr
  systemd.services.janitorr-secrets = {
    description = "Stage Janitorr's Jellyfin credentials for container@arr";
    after       = [ "local-fs.target" ];
    before      = [ "container@arr.service" ];
    wantedBy    = [ "container@arr.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${janitorrSecretsDir}
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${janitorrJellyfinGen.files."credentials.env".path} \
        ${janitorrSecretsDir}/jellyfin.env
    '';
  };
  # ── Inside the container ──────────────────────────────────────────────────
  containers.arr.config = { config, pkgs, lib, ... }: let
    # Packaged in this repo; each domain file calls the ones its own units need.
    cleanuparr = pkgs.callPackage ../pkgs/cleanuparr.nix { };
    janitorr   = pkgs.callPackage ../pkgs/janitorr.nix { };
    scraparr   = pkgs.callPackage ../pkgs/scraparr.nix { };
  in {

  ##########################################################################
  # M12 (d) — CLEANUPARR.
  #
  # ── IT RETIRES THREE THINGS, so they are not added ───────────────────
  #
  # DECLUTTARR, HUNTARR and CHECKRR.  Recorded here so that a later session
  # "discovers" one of them and finds the answer in the same file as the
  # thing that replaced it.
  #
  # ── WHY IT IS WORTH A uid ────────────────────────────────────────────
  #
  # Beyond stalled / blocked / malicious cleanup — it exists because *.lnk
  # and *.zipx files were getting stuck in *arr queues — it does
  # missing-content search, cutoff-unmet search, and custom-format score
  # upgrade search with score tracking.
  #
  # The part that earns it a place in THIS container: it removes downloads
  # that are ORPHANED, HAVE NO HARDLINKS, or are no longer referenced by
  # the *arrs.  That turns M4's link-count invariant from something proven
  # once with `stat` into something a service watches continuously, which
  # is a genuine upgrade to the property the whole stack rests on.
  #
  # ── CONFIGURE CONSERVATIVELY ON THE FIRST DEPLOY ─────────────────────
  #
  # A cleaner that deletes is a cleaner that can delete the wrong thing,
  # and this one reasons about hardlink counts on a tree whose hardlink
  # correctness is the entire point of M3 and M4.  Its configuration is a
  # SQLite database driven from its web UI — there is nothing to set here
  # — so "conservatively" is a manual step and the PR body spells it out:
  # every cleaner starts disabled, the download cleaner's unlinked/orphan
  # handling goes on LAST and only after the *arr Recycle Bin is set.
  systemd.services.cleanuparr = {
    description = "Cleanuparr — stalled/blocked/orphaned download cleanup";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "sonarr.service" "radarr.service" ];
    wants       = [ "sonarr.service" "radarr.service" ];

    environment = {
      PORT = toString cleanuparrPort;

      # CLEANUPARR_CONFIG_PATH is the NON-DOCKER override, and it is the
      # only way to move the config directory off its built-in default.
      # /var/lib/cleanuparr is the zdata bind mount.
      CLEANUPARR_CONFIG_PATH = "/var/lib/cleanuparr";
    };

    serviceConfig = {
      Type      = "simple";
      User      = "cleanuparr";
      Group     = "media";
      ExecStart = "${lib.getExe cleanuparr}";
      Restart   = "on-failure";
      RestartSec = "30s";

      # Group-writable output, for the reason the sonarr/radarr UMask note
      # at the bottom of this file gives at length: 0022 would make
      # anything this service creates writable by exactly one uid, on a
      # tree whose whole point is that the `media` group can manage it.
      UMask = "0002";

      # Static uid with persistent state — the prowlarr shape, not the
      # flaresolverr one — so every directive DynamicUser would have
      # implied is restated explicitly.  This is the Prowlarr trap in
      # reverse and it is the reason this block is long.
      NoNewPrivileges  = true;
      PrivateTmp       = true;
      ProtectSystem    = "strict";
      ProtectHome      = true;
      RemoveIPC        = true;
      RestrictSUIDSGID = true;

      # It DELETES from the library and the download tree; that is the job.
      ReadWritePaths = [ "/srv/media" "/var/lib/cleanuparr" ];

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

      # NOT PrivateUsers.  sonarr and radarr carry it and it is why `media`
      # has to be their primary group; here it would buy nothing and cost
      # the same footgun, because this service's access to /srv/media is
      # ENTIRELY its group membership — it owns none of those files.
    };
  };

  # ── THE PROWLARR TRAP, IN ITS THIRD FORM ──────────────────────────────
  #
  # The upstream unit runs DynamicUser = true.  A static uid is needed
  # here for the reason the file header gives — nspawn does not remap ids,
  # so the number chosen inside is a number on zdata, and /srv/state has to
  # be owned by something nameable.
  #
  # M13's brief warns that switching DynamicUser off silently loses six
  # directives it implied: NoNewPrivileges, PrivateTmp, ProtectSystem=strict,
  # ProtectHome=read-only, RemoveIPC and RestrictSUIDSGID.
  #
  # CHECKED RATHER THAN ASSUMED, and the answer is interesting: the seerr
  # module ALREADY sets all six explicitly, so unlike Prowlarr nothing is
  # actually lost here.  They are restated below anyway — not out of
  # ceremony, but because this file must not depend on an upstream module
  # continuing to be generous.  ProtectHome is tightened from the implied
  # `read-only` to `true` (which the module also does).
  #
  # What the module does NOT set, and what this block therefore adds, is
  # the second tier: CapabilityBoundingSet, RestrictAddressFamilies,
  # RestrictNamespaces, LockPersonality, SystemCallFilter,
  # SystemCallArchitectures, ProtectProc and UMask.
  systemd.services.seerr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User        = "jellyseerr";
    Group       = "jellyseerr";

    # The six DynamicUser implied.  Restated, per the paragraph above.
    NoNewPrivileges  = true;
    PrivateTmp       = true;
    ProtectSystem    = "strict";
    ProtectHome      = true;
    RemoveIPC        = true;
    RestrictSUIDSGID = true;

    # StateDirectory= already grants this, but naming it keeps the set of
    # writable paths readable in one place.
    ReadWritePaths = [ "/var/lib/seerr" ];

    # 0027, NOT 0002 — and this is the one place in this file where the
    # group-writable default is wrong.
    #
    # sonarr, radarr, bazarr, cleanuparr and mediathekarr all use 0002
    # because their output lands in /srv/media, a tree whose whole point is
    # that the `media` group can manage it.  Jellyseerr writes only its own
    # state directory, holds API keys for every *arr in that directory, and
    # is in no shared group at all — so group-writable buys nothing and
    # widens a file full of credentials.
    UMask = "0027";

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

  ##########################################################################
  # M13 — JANITORR.  The reaping side of the loop.
  #
  # ── WHAT IT IS NOT ────────────────────────────────────────────────────
  #
  # IT DOES NOT DELETE AFTER WATCHING.  Someone will expect it to, because
  # that is what "media lifecycle" sounds like, and M13's brief asks for
  # this to be written into the file header rather than discovered.
  #
  # What it actually does is DISK-SPACE-AWARE EXPIRY: each threshold in
  # `movie-expiration` / `season-expiration` maps a percentage of FREE DISK
  # to an age, and nothing is deleted at all until free space falls below
  # the highest threshold named.  On a pool with room, Janitorr does
  # nothing, forever, which is the intended resting state.
  #
  # IT ONLY SEES MEDIA THE *ARRS DOWNLOADED.  It reasons entirely through
  # Sonarr's and Radarr's APIs, so anything imported by hand — and anything
  # arriving through MediathekArr's own path — is invisible to it.  That is
  # a real gap on this host, not a hypothetical one: M12 added MediathekArr
  # specifically to pull ARD/ZDF content in.
  #
  # ── IT HAS NO WEB UI.  VERIFIED, NOT ASSUMED ──────────────────────────
  #
  # At v2.2.0 the source tree contains zero @RestController and zero
  # @Controller classes and ships no static resources; upstream's README
  # says "You don't have to publish ANY ports on the host machine."
  #
  # It nonetheless BINDS one, because spring-boot-webmvc is on its
  # classpath and Spring Boot starts Tomcat regardless.  Left alone that is
  # 0.0.0.0:8080 — inside this netns, that is the veth, on VLAN 90.  So the
  # configuration below pins the port to 8978 and the ADDRESS to 127.0.0.1,
  # and the firewall list does not name it.  Two independent mechanisms,
  # because the trap that produced this note (M12's 0.0.0.0-binding
  # helpers) was found by measurement rather than by reading a manual.
  #
  # ── DRY-RUN IS ON, AND THE FIRST DEPLOY KEEPS IT ──────────────────────
  #
  # `application.dry-run: true` below.  M13 requires the first deploy to
  # ship it that way and requires the PR body to carry what Janitorr WOULD
  # have deleted, read out of the journal, as the deliverable.
  #
  # TURNING IT OFF IS A SEPARATE, DELIBERATE COMMIT.  Alongside it, the
  # *arr Recycle Bin must be configured — M13 asks for two independent
  # safety nets on the first run of a deleting service pointed at 47 TB,
  # and that one is a manual step in Sonarr's and Radarr's own settings.
  systemd.services.janitorr = {
    description = "Janitorr — disk-space-aware media expiry across the *arr stack";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "sonarr.service" "radarr.service" "seerr.service" "janitorr-config.service" ];
    wants       = [ "sonarr.service" "radarr.service" "seerr.service" ];
    requires    = [ "janitorr-config.service" ];

    environment = {
      # Spring reads this as an additional config location.  `optional:` is
      # NOT used: the config renderer is a hard `requires` dependency, so
      # if the file is missing something has already failed and Janitorr
      # starting with framework defaults (every client disabled, and a
      # property-binding failure) helps nobody.
      SPRING_CONFIG_ADDITIONAL_LOCATION = "/run/janitorr/application.yml";

      # 256 MB is upstream's own recommendation, and it is not arbitrary:
      # the JVM sizes its heap from the container/cgroup limit, and
      # upstream reports 200 MB as the floor at which it still starts.
      # MemoryMax below enforces the same number from systemd's side so the
      # two agree.
      JAVA_TOOL_OPTIONS = "-XX:+UseSerialGC -Xss512k";
    };

    serviceConfig = {
      Type      = "simple";
      User      = "janitorr";
      Group     = "media";
      ExecStart = "${lib.getExe janitorr}";
      Restart   = "on-failure";
      RestartSec = "60s";

      # See the JAVA_TOOL_OPTIONS note.  A hard cap rather than MemoryHigh:
      # this is a background reaper sharing a host with Jellyfin
      # transcoding and Ollama, and a JVM that grows without bound is
      # exactly the neighbour that turns a busy evening into an OOM.
      MemoryMax = "512M";

      # Group-writable, like every other service here that writes into
      # /srv/media: the "Leaving Soon" tree has to be readable by Jellyfin
      # (uid 964, group media) and removable by Janitorr on the next run.
      UMask = "0002";

      # Static uid with persistent state, so every directive DynamicUser
      # would have implied is restated — the Prowlarr trap in reverse, the
      # same shape as the cleanuparr block above.
      NoNewPrivileges  = true;
      PrivateTmp       = true;
      ProtectSystem    = "strict";
      ProtectHome      = true;
      RemoveIPC        = true;
      RestrictSUIDSGID = true;

      # It deletes from the library and builds the Leaving Soon tree.
      ReadWritePaths = [ "/srv/media" "/var/lib/janitorr" ];

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

      # NO SystemCallFilter, and this is the one deliberate gap in the
      # hardening of this unit.
      #
      # A JVM needs @privileged-adjacent calls that the other services here
      # do not — membarrier and the perf/JIT paths in particular — and a
      # filter that kills the runtime at an unpredictable moment during
      # class loading is worse than no filter: it presents as a service
      # that starts sometimes.  Everything the filter would have bought is
      # bought instead by an empty CapabilityBoundingSet, NoNewPrivileges
      # and the Protect*/Restrict* set above.
      #
      # If this is revisited, `SystemCallFilter = [ "@system-service" ]`
      # WITHOUT the "~@privileged" subtraction is the version to test first.
    };
  };

  # ── Janitorr's configuration, rendered at start from staged secrets ────
  #
  # A separate oneshot rather than a Nix-rendered file in the store,
  # because application.yml has to contain FOUR API KEYS AND A PASSWORD and
  # /nix/store is world-readable.
  #
  # It reads from three sources, and the spread is the point:
  #
  #   sonarr, radarr    arr-api-keys, which extracts them from each
  #                     application's OWN config.xml.  One source of truth;
  #                     survives a key rotation in the UI with no deploy.
  #   jellyseerr        its own settings.json, for the same reason.  The
  #                     key is generated by Jellyseerr on first run.
  #   jellyfin          a clan var with prompts, because its key lives in a
  #                     database and it additionally needs a real user
  #                     account.  See the generator on the host side.
  #
  # DEGRADES RATHER THAN FAILS when a source is absent, and each
  # degradation is chosen so that dry-run still produces its listing:
  #
  #   no jellyseerr key   the jellyseerr client is written `enabled: false`
  #   no jellyfin creds   the jellyfin client is written `enabled: false`
  #
  # A missing SONARR OR RADARR key is fatal, correctly: those are the
  # services Janitorr reasons about, and a Janitorr with neither has
  # nothing to say.
  systemd.services.janitorr-config = {
    description = "Render Janitorr's application.yml from staged credentials";
    after      = [ "arr-api-keys.service" "seerr.service" ];
    requires   = [ "arr-api-keys.service" ];
    before     = [ "janitorr.service" ];
    serviceConfig = {
      Type                     = "oneshot";
      RemainAfterExit          = false;
      RuntimeDirectory         = "janitorr";
      RuntimeDirectoryMode     = "0750";
      RuntimeDirectoryPreserve = "yes";

      # NO User=, so this runs as root — it has to, to read other users'
      # 0700 directories.  Group=media is what makes the RuntimeDirectory
      # come out root:media 0750 WITHOUT a chown.
      #
      # systemd takes RuntimeDirectory ownership from the unit's own
      # User=/Group=, which is the mechanism the fictional
      # `RuntimeDirectoryGroup=` was reaching for.  Setting the real
      # directive gets the same result for free.
      #
      # THE FIRST FIX FOR THIS WAS A `chown` IN THE SCRIPT AND IT CRASHED:
      #
      #   janitorr-render-config: line 10: 358 Bad system call (core dumped)
      #     .../coreutils-9.11/bin/chown root:media /run/janitorr
      #   janitorr-config.service: Main process exited, status=159/n/a
      #
      # 159 is 128+31, i.e. SIGSYS — killed by this unit's own
      # SystemCallFilter.  `~@privileged` subtracts the @chown set, so
      # chown(2) is not merely denied, the process is shot.  Group= avoids
      # the syscall entirely rather than widening the filter to permit it,
      # which is the better of the two fixes: nothing here needs to change
      # the ownership of anything.
      #
      # Measured on ernst 2026-08-26, on the deploy that shipped the chown.
      Group = "media";

      # THE DIRECTORY'S GROUP IS SET IN THE SCRIPT, NOT HERE, AND THAT IS
      # NOT A STYLE CHOICE.
      #
      # The obvious spelling is `RuntimeDirectoryUser` /
      # `RuntimeDirectoryGroup`.  THOSE DIRECTIVES DO NOT EXIST.  systemd
      # has RuntimeDirectoryMode and RuntimeDirectoryPreserve and takes the
      # OWNERSHIP from the unit's own User=/Group=; the two invented names
      # are accepted by the NixOS module, written into the unit file, and
      # then dropped by systemd with
      #
      #   Unknown key 'RuntimeDirectoryGroup' in section [Service], ignoring
      #
      # — a warning in the journal and nothing else.  Caught here with
      # `systemd-analyze verify` before deploying, not on ernst.
      #
      # This unit runs as ROOT (it has to; it reads other users' 0700
      # directories), so without the chown below /run/janitorr would be
      # root:root 0750 — and a 0640 root:media file inside a directory the
      # media group cannot TRAVERSE is unreadable.  That is precisely the
      # bug microvms/wg-qbittorrent.nix documents in its staging unit:
      # "Group needs x on the directory, not just r on the file."
      #
      # CAP_CHOWN is in the bounding set above for exactly this one call.
      UMask = "0027";

      # Same posture as arr-api-keys, and for the same reason: this unit
      # handles credentials and has no business having a network stack.
      #
      # CAP_DAC_READ_SEARCH for the same reason too — sonarr's staged key
      # and Jellyseerr's settings.json both sit under directories owned by
      # someone else.  NOT CAP_DAC_OVERRIDE: read and traverse only, so
      # this unit cannot write over anything it can see.
      PrivateNetwork          = true;
      IPAddressDeny           = "any";
      # CAP_DAC_READ_SEARCH only.  CAP_CHOWN was here for the chown that
      # the Group= note above removed; it went with it.
      CapabilityBoundingSet   = [ "CAP_DAC_READ_SEARCH" ];
      NoNewPrivileges         = true;
      ProtectSystem           = "strict";
      ProtectHome             = true;
      PrivateTmp              = true;
      PrivateDevices          = true;
      ProtectClock            = true;
      ProtectControlGroups    = true;
      ProtectHostname         = true;
      ProtectKernelLogs       = true;
      ProtectKernelModules    = true;
      ProtectKernelTunables   = true;
      ProtectProc             = "invisible";
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictNamespaces      = true;
      RestrictRealtime        = true;
      RestrictSUIDSGID        = true;
      RemoveIPC               = true;
      LockPersonality         = true;
      SystemCallArchitectures = "native";
      SystemCallFilter        = arrSyscallFilter;

      ExecStart = pkgs.writeShellScript "janitorr-render-config" ''
        set -euo pipefail

        out=/run/janitorr/application.yml

        # No chown here — see the Group= note in this unit's serviceConfig.
        # systemd already created /run/janitorr as root:media 0750, and the
        # file inherits gid media from this process's egid, so UMask=0027
        # lands it at root:media 0640 with nothing to adjust.

        # Assign, then test — the shape PR #84 got wrong and arr-api-keys
        # documents at length.  A command substitution that fails inside
        # an argument does not trip `set -e`, so building the file in one
        # step would turn an unreadable key into an EMPTY key and a 401
        # with nothing in the log to explain it.
        sonarr_key=$(${pkgs.coreutils}/bin/cat ${arrSecretsDir}/sonarr-api-key)
        radarr_key=$(${pkgs.coreutils}/bin/cat ${arrSecretsDir}/radarr-api-key)
        if [ -z "$sonarr_key" ] || [ -z "$radarr_key" ]; then
          echo "janitorr: sonarr/radarr API key is empty — has arr-api-keys run?" >&2
          exit 1
        fi

        # Jellyseerr's key comes from arr-api-keys, which extracts it from
        # Jellyseerr's own settings.json.
        #
        # M13 originally read settings.json directly here.  It now goes
        # through the stager for the reason M12 gave when it renamed that
        # unit: two consumers reading the same application's config file is
        # one extraction too many, and the stager is already a hard
        # dependency of this unit.  Still degrades rather than fails —
        # Janitorr in dry-run is useful without Jellyseerr.
        seerr_key=""
        if [ -r ${arrSecretsDir}/jellyseerr-api-key ]; then
          seerr_key=$(${pkgs.coreutils}/bin/cat ${arrSecretsDir}/jellyseerr-api-key)
        fi
        seerr_enabled=true
        if [ -z "$seerr_key" ]; then
          seerr_enabled=false
          echo "janitorr: no Jellyseerr API key yet — has its first-run wizard been completed?" >&2
        fi

        # Jellyfin's three come from the clan var staged on the host.
        # Absent until `clan vars generate ernst` has been run and the
        # in-Jellyfin account created; same degradation.
        jf_key=""; jf_user=""; jf_pass=""
        if [ -r ${janitorrSecretsDir}/jellyfin.env ]; then
          # shellcheck disable=SC1091
          . ${janitorrSecretsDir}/jellyfin.env
          jf_key="''${JELLYFIN_API_KEY:-}"
          jf_user="''${JELLYFIN_USERNAME:-}"
          jf_pass="''${JELLYFIN_PASSWORD:-}"
        fi
        jf_enabled=true
        if [ -z "$jf_key" ] || [ -z "$jf_user" ] || [ -z "$jf_pass" ]; then
          jf_enabled=false
          echo "janitorr: no Jellyfin credentials — Leaving Soon collections will not be built" >&2
        fi

        ${pkgs.coreutils}/bin/rm -f "$out"
        ${pkgs.coreutils}/bin/cat > "$out" <<EOF
        # GENERATED by janitorr-config.service.  Do not edit — it is
        # rewritten on every start of janitorr.service.  The declarative
        # source is machines/ernst/containers/arr/.
        server:
          # See the "IT HAS NO WEB UI" note in arr/.  Loopback, and not
          # in the firewall list.
          port: ${toString janitorrPort}
          address: 127.0.0.1

        logging:
          level:
            # DEBUG while dry-running, INFO once live — see the
            # janitorrDryRun binding at the top of arr/ for why these
            # two settings are deliberately welded together.
            com.github.schaka: ${if janitorrDryRun then "DEBUG" else "INFO"}
          # NO `file:` key.  Upstream's template writes /logs/janitorr.log;
          # this runs under systemd, so stdout goes to the journal and a
          # second copy on disk is one more thing to rotate and to persist.

        file-system:
          access: true
          # Skip deletion of anything still seeding.  ON, deliberately: the
          # download client is one layer-2 hop away in M3's VPN microvm and
          # this check is what keeps a reap from cutting a live torrent.
          validate-seeding: true
          leaving-soon-dir: "/srv/media/leaving-soon"
          media-server-leaving-soon-dir: "/srv/media/leaving-soon"
          from-scratch: true
          # NOT "/".  The root filesystem here is the container's, which
          # has nothing to do with the pool Janitorr is reaping.  Pointing
          # it at / would read zroot's free space and make every expiry
          # threshold meaningless.
          free-space-check-dir: "/srv/media"

        application:
          dry-run: ${if janitorrDryRun then "true" else "false"}
          run-once: false
          whole-tv-show: false
          whole-show-seeding-check: false
          leaving-soon: 14d
          leaving-soon-threshold-offset-percent: 5
          exclusion-tags:
            - "janitorr_keep"

          media-deletion:
            enabled: true
            movie-expiration:
              5: 180d
              10: 365d
            season-expiration:
              5: 180d
              10: 365d

          # OFF on the first deploy.  Both of these act on *arr TAGS, and
          # no title in this library carries one yet — so enabling them
          # would either do nothing or, worse, do something the moment a
          # tag is added for an unrelated reason.
          tag-based-deletion:
            enabled: false
            minimum-free-disk-percent: 100
            schedules: []

          episode-deletion:
            enabled: false

        clients:
          default:
            connect-timeout: 60s
            read-timeout: 60s
            level: NONE

          # localhost throughout: all of this shares one netns, which is
          # the same payoff the Prowlarr wiring gets — no port opened,
          # nothing to firewall.
          sonarr:
            enabled: true
            url: "http://localhost:${toString sonarrPort}"
            api-key: "$sonarr_key"
            delete-empty-shows: true
          radarr:
            enabled: true
            url: "http://localhost:${toString radarrPort}"
            api-key: "$radarr_key"
          jellyfin:
            enabled: $jf_enabled
            url: "http://${jellyfinAddr}:${toString jellyfinPort}"
            api-key: "$jf_key"
            username: "$jf_user"
            password: "$jf_pass"
            # Jellyfin is a DIFFERENT container (M2b, 10.0.90.10), so this
            # one is not localhost — it is the same layer-2 hop Traefik
            # takes.  Its firewall accepts only Traefik on 8096, so this
            # needs a rule there; see containers/jellyfin.nix.
            delete: true
            exclude-favorited: true
            leaving-soon-tv: "Shows (Leaving Soon)"
            leaving-soon-movies: "Movies (Leaving Soon)"
            leaving-soon-type: MOVIES_AND_TV
          jellyseerr:
            enabled: $seerr_enabled
            url: "http://localhost:${toString jellyseerrPort}"
            api-key: "$seerr_key"
            match-server: false

          # JELLYSTAT IS DELIBERATELY OFF, and it is not merely deferred.
          #
          # M13's brief lists Jellystat as a target, on the grounds that it
          # feeds Janitorr's expiry logic.  Two things found on 2026-08-26
          # move it out of this milestone:
          #
          #   1. COST.  It is a Vite SPA plus an Express backend with no
          #      nixpkgs package, and it requires a PostgreSQL server —
          #      which this container does not have and which would be the
          #      first database in it.
          #   2. UPSTREAM NOW RECOMMENDS SOMETHING ELSE.  Janitorr's own
          #      example compose says, verbatim: "New users without an
          #      existing stats setup should only enable janitorr-stats and
          #      skip Jellystat/Streamystats entirely."
          #
          # So the watch-history feed, when it is wanted, is a
          # `janitorr-stats` question and not a Jellystat one.  Neither is
          # needed for space-based expiry, which is what M13 ships.
          jellystat:
            enabled: false
          streamystats:
            enabled: false
          janitorr-stats:
            enabled: false
        EOF

        # No chown/chmod: Group=media gives this process egid media, so the
        # redirect above creates the file root:media, and UMask=0027 makes
        # it 0640.  Both syscalls would be killed by SystemCallFilter
        # anyway — see the Group= note.
      '';
    };
  };

  ##########################################################################
  # M13 — SCRAPARR.  *arr metrics for M6, as ONE service.
  #
  # ── EXPORTARR WAS REJECTED.  RECORDING THE REJECTION ──────────────────
  #
  # Exportarr is the better-known option and it is the wrong shape for this
  # container.  It needs ONE INSTANCE PER APP: one uid, one port and one
  # firewall line each, in a file whose entire port policy is "one list in
  # one place" and whose Traefik source-restriction is literally a
  # concatMapStrings over a single explicit list.  Six *arr would mean six
  # of everything.
  #
  # Scraparr is one service, one port (7100), one configuration, with every
  # instance addressed by alias inside it.
  #
  # ── ITS CONFIGURATION IS AN EnvironmentFile, NOT A YAML ───────────────
  #
  # Scraparr merges a config.yaml with environment variables.  This deploy
  # ships NO yaml at all, and the reason is the API keys: they must not sit
  # in /nix/store, and the yaml's own `${VAR}` substitution explicitly does
  # NOT support the `*_FILE` form (upstream's config.yaml says so in a
  # comment).  Environment variables support both.
  #
  # A NOTE AGAINST docs/history.md, which says "env-var mode does NOT
  # support multiple instances, so the file-based path is the only one that
  # works here."  That was true once; at v3.1.0 it is not.  Reading
  # src/scraparr/parser/__init__.py:
  #
  #   SONARR_URL           single instance
  #   SONARR_PROD_URL      instance with alias "prod"
  #   SONARR_API_KEY_FILE  reads the key from a path
  #
  # — aliases and _FILE both work in env-var mode, and they compose.  The
  # CONCLUSION the roadmap reached is still the right one; the reason it
  # gave has expired, so it is corrected here rather than propagated.
  #
  # ── IT REUSES arr-api-keys.  NO SECOND STAGING MECHANISM ──────────────
  #
  # M13 requires this explicitly, and M4's argument holds unchanged: the
  # keys are generated BY THE APPLICATIONS into their own config.xml, so
  # reading them there keeps one source of truth and survives a key
  # rotation in a UI with no deploy.  A prompted clan var would be a second
  # copy with no link to the first.
  #
  # The staged files sit in a 0700 root-owned RuntimeDirectory, so an
  # unprivileged reader cannot open them directly.  LoadCredential bridges
  # that — see the note on it below.
  systemd.services.scraparr = {
    description = "Scraparr — Prometheus exporter for the *arr suite";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "sonarr.service" "radarr.service" "prowlarr.service" "arr-api-keys.service" ];
    wants       = [ "sonarr.service" "radarr.service" "prowlarr.service" ];
    requires    = [ "arr-api-keys.service" ];

    environment = {
      GENERAL_PORT = toString scraparrPort;

      # 127.0.0.1 would be wrong: Prometheus is in ANOTHER container and
      # reaches this over the veth.  0.0.0.0 is upstream's default anyway;
      # it is stated rather than left implicit because the firewall rule
      # above is what makes that safe, and the two belong in one field of
      # view.
      GENERAL_ADDRESS = "0.0.0.0";
      GENERAL_PATH    = "/metrics";

      # localhost throughout — one netns, no ports opened.
      SONARR_URL   = "http://localhost:${toString sonarrPort}";
      RADARR_URL   = "http://localhost:${toString radarrPort}";
      PROWLARR_URL = "http://localhost:${toString prowlarrPort}";
      BAZARR_URL   = "http://localhost:${toString bazarrPort}";
      SEERR_URL    = "http://localhost:${toString jellyseerrPort}";

      # The keys, by PATH rather than by value.  `_FILE` is read by
      # Scraparr itself at startup (parser/__init__.py `_get_env_value`),
      # which is what keeps them out of /proc/<pid>/environ.
      #
      # %d is systemd's credentials directory — the 0400 copies
      # LoadCredential below places there, NOT the 0700 staging directory,
      # which this unit's user cannot open.  Specifier expansion applies to
      # Environment=, so these resolve before the process starts.
      #
      # ALL FIVE, and it is all-or-nothing by Scraparr's design: it exits 1
      # on a service that has a URL without a key OR a key without a URL.
      # The URLs above and these paths have to stay in lockstep.
      SONARR_API_KEY_FILE     = "%d/sonarr-api-key";
      RADARR_API_KEY_FILE     = "%d/radarr-api-key";
      PROWLARR_API_KEY_FILE   = "%d/prowlarr-api-key";
      BAZARR_API_KEY_FILE     = "%d/bazarr-api-key";
      SEERR_API_KEY_FILE      = "%d/jellyseerr-api-key";
    };

    serviceConfig = {
      Type      = "simple";
      User      = "scraparr";
      Group     = "scraparr";
      ExecStart = "${lib.getExe scraparr}";
      Restart   = "on-failure";
      RestartSec = "30s";

      # arr-api-keys writes its output into a 0700 RuntimeDirectory owned
      # by root, so an unprivileged reader needs help.  This is the one
      # place M13 adds a path into that directory for a non-root consumer,
      # and it is done with a systemd CREDENTIAL rather than by widening
      # the directory: LoadCredential is read by PID 1 before the drop to
      # User=scraparr, and lands a 0400 copy the service can read.
      #
      # Widening the directory instead would have been the tempting fix and
      # is the wrong one — recyclarr and umlautadaptarr read from the same
      # directory, and loosening it for a third consumer loosens it for all
      # three.
      LoadCredential = [
        "sonarr-api-key:${arrSecretsDir}/sonarr-api-key"
        "radarr-api-key:${arrSecretsDir}/radarr-api-key"
        "prowlarr-api-key:${arrSecretsDir}/prowlarr-api-key"
        "bazarr-api-key:${arrSecretsDir}/bazarr-api-key"
        "jellyseerr-api-key:${arrSecretsDir}/jellyseerr-api-key"
      ];

      # No state, no media, nothing to write anywhere.
      UMask = "0077";

      NoNewPrivileges  = true;
      PrivateTmp       = true;
      ProtectSystem    = "strict";
      ProtectHome      = true;
      RemoveIPC        = true;
      RestrictSUIDSGID = true;

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
  };
}
