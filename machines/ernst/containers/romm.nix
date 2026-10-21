# machines/ernst/containers/romm.nix
#
# RomM — a self-hosted ROM library manager.  It scans a directory tree of game
# files, enriches it with metadata and artwork, and serves the result as a web
# UI.  Here it is the AUTHORITATIVE ROM LIBRARY for the fleet; birte's
# RetroDECK reads a Syncthing replica of the same tree.
#
# ── WHY IT IS HERE AND NOT ON THE DECK ─────────────────────────────────────
#
#   The library has to live somewhere that is backed up, has room, and is not
#   rolled back on every boot.  birte is none of those things: it is a handheld
#   whose @home is blanked at boot, whose only large writable area is a single
#   btrfs subvolume, and which is frequently off.  ernst is all three.
#
#   THE DECK STILL GETS A FULL LOCAL COPY, and that is the whole point of the
#   topology chosen in this change.  A network mount would have been simpler —
#   no duplication, saves naturally shared — and it was rejected because a
#   Steam Deck's defining property is that it LEAVES THE HOUSE.  A library
#   reachable only on the home LAN turns the device into a console.  So: ernst
#   masters, Syncthing replicates, birte plays offline.  The cost is a second
#   full copy of the library on birte's NVMe, accepted deliberately.
#
#   The Syncthing wiring is NOT in this file — it is a clan service, declared
#   in clan.nix.  See the note there about `devices`, which is load-bearing.
#
# ── THE TREE IS SHARED WITH RetroDECK BY CONSTRUCTION ──────────────────────
#
#   RomM's recommended layout ("structure A") and RetroDECK's are the same
#   shape — `roms/<platform>/` under one root — which is why birte's
#   /games/retrodeck can be replicated here without translation:
#
#     ernst   /srv/roms/roms/<platform>/      ← this file
#     birte   /games/retrodeck/roms/<system>/ ← machines/birte/deck.nix
#
#   They agree on the common platform names (nes, snes, gba, psx) and diverge
#   on others; RomM absorbs that with a `system.platforms` mapping in its own
#   config.yml rather than anything being renamed on disk.  docs/guides/
#   birte-emulation.md is the single description of the layout.
#
# ── TIER: PODMAN, and this is the tier's THIRD occupant ────────────────────
#
#   Upstream ships a Docker Compose file and a container image and nothing
#   else; there is no non-Docker path at all.  That is the same test M9's
#   TubeSync and M14's Storyteller applied, with the same answer, so this takes
#   the podman tier beside them.
#
#   `virtualisation.oci-containers` INSIDE AN NSPAWN CONTAINER IS REJECTED,
#   restated here as every service on this tier is required to restate it: the
#   value of containers/arr/ is that upstream units and their
#   `systemd-analyze` scores stay legible, and an opaque image inside it is
#   opaque to all three.  The escape hatch is this tier, not that hybrid.
#
#   THE COST, accepted explicitly: two opaque images, a package tree we do not
#   build, and a `systemd-analyze security` score for `podman-romm.service`
#   that measures podman rather than RomM.
#
# ── TWO CONTAINERS, ONE NAMESPACE, AND THE DATABASE IS NOT ON THE VLAN ─────
#
#   RomM requires an external database; upstream's compose runs MariaDB beside
#   it and the docs are explicit that PostgreSQL support is experimental, so
#   MariaDB it is.
#
#   Both containers join the SAME network namespace.  That is not a shortcut —
#   it is what keeps the database off VLAN 90 entirely.  RomM reaches it at
#   127.0.0.1:3306, which is `lo` inside the namespace and therefore matched by
#   the one ACCEPT rule that exists for `lo`; nothing outside the namespace can
#   address it at all, and no firewall rule has to be written to say so.
#
#   The alternative — a podman network between them — would have put the
#   database on an addressable interface and made its exposure a matter of
#   getting rules right.  This way it is structural.
{
  config,
  pkgs,
  lib,
  ...
}: let
  # uid/gid 3029, reserved in machines/ernst/allocations.nix.
  #
  # LITERAL ON zdata, because this container is ROOTFUL AND UNMAPPED — the
  # decision containers/tubesync.nix and containers/storyteller.nix both record
  # at length.  Rootless podman remaps uids through a subuid range, so a number
  # chosen inside the container would not be that number on the pool.
  #
  # ITS OWN GROUP, deliberately NOT `media` (gid 3000).  `media` is the arr
  # suite's shared hardlink domain — one group so that a download, an import
  # and a library file can be the same inode.  A ROM library takes part in none
  # of that: nothing hardlinks into it, no arr writes to it, and Jellyfin does
  # not read it.  Putting ROMs in `media` would widen that group's reach for no
  # benefit.  The one principal that genuinely needs access is Syncthing, and
  # it is added to THIS group rather than the library being moved into that one.
  rommUid = 3029;
  rommGid = 3029;

  # ── L2 / L3 ───────────────────────────────────────────────────────────────
  #
  # Next free sequence in machines/ernst/allocations.nix
  # was 0e (0c went to M14's storyteller, 0d to M16's cloudflared), and the last
  # octet follows that table's 8 + <seq> convention: 10.0.90.22.
  netns = "romm";
  vethHost = "vb-romm";

  # `rm0` — NOT `eth0`, and NOT `st0` either.
  #
  # containers/storyteller.nix diagnosed this the expensive way and left an
  # explicit instruction for the next service on this tier: EVERY podman-tier
  # namespace must use a UNIQUE interface name, because dhcpcd keys its pidfile
  # and control socket on the INTERFACE NAME rather than the network namespace
  # (/run/dhcpcd/<iface>-4.sock), and these units share a mount namespace with
  # the host.  A duplicate name makes the second dhcpcd hand its arguments to
  # the first as a client and exit 0, applying the lease in the wrong namespace
  # — a container that is simply unreachable while every unit reports success.
  #
  # This is that instruction being followed.  A fourth service must not reuse
  # `rm0` either.
  vethNs = "rm0";
  mac = "02:00:00:90:00:0e";
  vlanId = 90;

  # ROMM_PORT's default.  Named rather than left implicit because the firewall
  # rule and traefik.nix both have to agree with it.
  webPort = 8080;

  # Traefik's veth address — the ONLY source permitted to reach the web UI.
  # Same one-hop-on-br0 caveat as every sibling: these frames never reach the
  # UDM-Pro, so the netns firewall below is the only enforcement point.  The
  # adjacency that makes it matter is real — 10.0.90.11 is the qBittorrent and
  # slskd microvm, one layer-2 hop away.
  traefikAddr = "10.0.90.12";

  # M26.  The arr container, because that is where the service index runs —
  # see containers/homepage.nix.  Named for the dashboard rather than for the
  # container so that grepping `dashboardAddr` across machines/ernst finds
  # every widening M26 made, in one pass.
  dashboardAddr = "10.0.90.13";

  # ── Storage: the library and the state are deliberately separate ──────────
  #
  # The LIBRARY is content: large, replaceable only by re-dumping, and the one
  # thing that has to be byte-identical with birte's copy.  It gets its own
  # dataset — see the note on the exec property below.
  #
  # The STATE is RomM's own — its database, its fetched artwork, its config and
  # its redis spool.  It goes on zdata/state.  Keeping them apart is what lets
  # Syncthing be pointed at exactly the library and nothing else: replicating a
  # live MariaDB directory to a Steam Deck would be both useless and unsafe.
  # NOT /srv/games, and containers/arr/ is the reason.  That dataset carries
  # exec ON — deliberately, because Steam and Questarr's PC games are binaries
  # that must run, and arr/ calls giving anything else a foothold there "the
  # worst place in the fleet to do it".  A ROM is data: it is read by an
  # emulator and never executed.  Putting the library on the one dataset in the
  # pool where files are allowed to run would hand that property to thousands
  # of files downloaded from the internet for no reason at all.
  #
  # So zdata/roms, its own dataset, exec=off/setuid=off/devices=off.  See
  # machines/ernst/disko.nix and the runbook in
  # docs/guides/ernst-zdata-datasets.md.
  #
  # The doubled name below (/srv/roms/roms) is RomM's layout, not an accident:
  # the DATASET is the library root, and "structure A" puts the games in a
  # `roms/` directory inside it beside `bios/`.
  libraryDir = "/srv/roms";
  stateDir = "/srv/state/romm";
  secretsDir = "/run/romm-secrets";

  # Images pinned by DIGEST, never by tag.
  #
  # Upstream's own compose file uses `:latest` for both, which is exactly the
  # trap containers/storyteller.nix documents: `latest` moved under it to a
  # major-version beta.  A ROM manager holding the only index of the library is
  # not something to let float.
  #
  # TO BUMP: pick the new tag, then
  #   skopeo inspect --format '{{.Digest}}' docker://<image>:<tag>
  # and update BOTH lines of the pair.  Never point this at a tag.
  #
  # Measured 2026-09-01 with skopeo:
  #   rommapp/romm:5.2.0   sha256:3512f2ca…  created 2026-08-20
  #   rommapp/romm:latest  sha256:3512f2ca…  ← the SAME image, today
  #
  # That second line is why the pin is worth stating rather than assuming.
  # `latest` and the newest stable happen to coincide right now, so following
  # upstream's compose would work — and would keep working right up until it
  # silently didn't, which is exactly how containers/storyteller.nix found a
  # major-version beta in a household service.
  rommTag = "5.2.0";
  rommDigest = "sha256:3512f2ca455782f90247271bed23116e6bc675bc74e379be2c41696e607ab11e";

  # MariaDB 11.4, the current LTS series.  Pinned to the `11.4` tag's digest
  # rather than to `lts`: the two resolve to DIFFERENT images (measured the
  # same day), and a floating alias that moves across major versions under a
  # database is the last place to accept that.
  dbTag = "11.4";
  dbDigest = "sha256:611a2fcc5fa7c6ceb8644c6f74b25ede004ff6c3a6b38c8f8c23d3bbf6c26430";
in {
  ##############################################################################
  # Podman is already enabled by containers/tubesync.nix (M9), the tier's first
  # occupant.  It is NOT re-enabled here — one owner, one place, so that two
  # differing `dockerCompat` definitions can never become a merge conflict that
  # only surfaces when someone edits one of them.
  ##############################################################################

  ##############################################################################
  # Keep RetroDECK's internal symlinks out of the library.
  ##############################################################################
  #
  # RetroDECK's bios/ tree is full of symlinks pointing back into its own data
  # directory — absolute paths under /home/deck/retrodeck/… that mean something
  # on birte and nothing here.  Syncthing replicates the *link*, not its
  # target, so each one lands on ernst dangling:
  #
  #   /srv/roms/bios/dc/textures
  #     -> /home/deck/retrodeck/texture_packs/retroarch-core/Flycast/textures
  #
  # RomM's scanner stats every entry and aborts the whole run on the first one
  # it cannot open — "Scan failed: File not found: /romm/library/bios/dc/
  # textures" — so a handful of broken links from the Deck stop the library
  # scanning at all.  Observed 2026-09-04: twenty of them, across pcsx2,
  # fbneo, Mupen64plus, pico-8, cemu, dc and HdPacks.  Note RetroDECK puts
  # `/pcsx2/bios` in that set — a *symlink* named bios, not the BIOS files
  # themselves, which live beside it and do sync.
  #
  # Ignored rather than deleted, and the order matters: the bios folder is
  # sendreceive, so removing them on ernst would propagate the deletion to
  # birte and take RetroDECK's texture packs with it.  An ignored path is not
  # synced in *either* direction, which makes the local copies safe to remove
  # afterwards.
  #
  # Listed by name rather than solved generically because Syncthing's ignore
  # patterns match paths, not file types — there is no "ignore symlinks".  If
  # RetroDECK grows another one, it shows up as the same scan failure naming
  # the new path, and it goes in this list.
  #
  # ── sendonly, because a list of names is not a rule ─────────────────────
  #
  # The ignore list below is twenty paths that happened to exist on 2026-09-04.
  # RetroDECK will add an emulator, that emulator will get its own symlinks,
  # and the scan will break again naming a path nobody has written down yet.
  # Enumerating symptoms does not stop the cause.
  #
  # The cause is that `bios` is sendreceive between a server that masters the
  # library and a handheld that scribbles emulator state into the same tree.
  # This file's header already calls ernst's copy the authoritative one, so
  # make the sync say that: ernst sends, and simply does not accept what birte
  # has to say about the BIOS folder. RetroDECK can then create whatever
  # internal links it likes and none of them reach the server.
  #
  # The cost, stated plainly: a BIOS file dropped on the Deck no longer
  # propagates up. Adding one now means putting it on ernst — which is where
  # the library is curated anyway, and is the same direction ROMs already
  # flow.
  #
  # `roms` is deliberately left sendreceive. The Deck is a legitimate source
  # of ROMs, and RetroDECK does not litter that tree the way it does bios/.
  #
  # The ignores stay, and are not redundant. Under sendonly a local deletion
  # is *propagated*, so without them removing those twenty stale links from
  # ernst would have pushed the deletion to birte and taken RetroDECK's
  # texture packs with it. Ignored paths are excluded in both directions,
  # which is what made the cleanup safe.
  # mkForce because the clan syncthing service sets `type` for every folder it
  # declares (sendreceive); this is a deliberate per-folder override of that,
  # not a second opinion.
  services.syncthing.settings.folders.bios.type = lib.mkForce "sendonly";

  services.syncthing.settings.folders.bios.ignorePatterns = [
    "/HdPacks"
    "/cemu/usr/save"
    "/dc/textures"
    "/fbneo/blend"
    "/fbneo/cheats"
    "/fbneo/ips"
    "/fbneo/patched"
    "/fbneo/romdata"
    "/Mupen64plus/cache"
    "/Mupen64plus/hires_texture"
    "/pcsx2/bios"
    "/pcsx2/cheats"
    "/pcsx2/cheats_ni"
    "/pcsx2/cheats_ws"
    "/pcsx2/logs"
    "/pcsx2/memcards"
    "/pcsx2/shaders"
    "/pcsx2/textures"
    "/pico-8/carts"
    "/pico-8/cdata"
  ];

  ##############################################################################
  # The group, and the one other principal that gets into it.
  ##############################################################################

  users.groups.romm = {
    gid = rommGid;

    # Membership declared from the GROUP side rather than as
    # `users.users.syncthing.extraGroups`, and that is deliberate.
    #
    # Writing `users.users.syncthing.extraGroups` is a DEFINITION of that
    # user: it instantiates the submodule, so on a machine where the syncthing
    # module has not defined the rest of the account the build fails with
    # assertions about `isSystemUser` and an unset `group` that mention
    # neither RomM nor Syncthing.  Wrapping it in `lib.mkIf` does NOT help —
    # naming the attribute path is enough to instantiate it.  Both were
    # measured, in that order, by removing ernst from the syncthing instance.
    #
    # `members` names a user without defining one, so it is inert when the
    # account does not exist and correct when it does.
    members = ["syncthing"];
  };

  # Syncthing replicates the library to birte, so it needs to read and write
  # inside it.  It is added to `romm` rather than the library being handed to
  # a group Syncthing already had — the narrower of the two changes.
  #
  # The clan syncthing service runs as user/group `syncthing` (see
  # clanServices/syncthing in clan-core); this only adds a supplementary group
  # to that account and does not otherwise touch it.
  #
  # (The membership itself is declared on the group above — see the note there
  # for why it is not `users.users.syncthing.extraGroups`.)

  ##############################################################################
  # The network namespace, its veth, and its firewall.
  ##############################################################################

  ##############################################################################
  # Secrets.
  ##############################################################################

  # All three are GENERATED, not prompted — nobody types them, nothing outside
  # the repo needs to know them, and a prompt would only invite a weak value.
  # The same call M9's Django key and M14's Storyteller key made.

  # Signs sessions.  Upstream's own instruction is `openssl rand -hex 32`.
  # Losing it logs everyone out; leaking it is worse.
  clan.core.vars.generators.romm-auth-secret = {
    files."secret-key".secret = true;
    runtimeInputs = [pkgs.coreutils pkgs.openssl];
    script = ''
      openssl rand -hex 32 | tr -d '\n' > "$out/secret-key"
    '';
  };

  # The application's database password, and MariaDB's root password.
  #
  # Two separate generators rather than one with two files, so that rotating
  # either does not churn the other's sops entry.
  #
  # `tr -d` over a base64 alphabet with the padding stripped: these values are
  # interpolated into an env file that MariaDB's entrypoint parses, and a
  # trailing '=' or a newline in a password has a long history of being read as
  # syntax rather than data.
  clan.core.vars.generators.romm-db-password = {
    files."password".secret = true;
    runtimeInputs = [pkgs.coreutils pkgs.openssl];
    script = ''
      openssl rand -base64 32 | tr -d '\n=' > "$out/password"
    '';
  };

  # ── Metadata provider credentials.  PROMPTED, not generated ─────────────
  #
  # The three above are generated because nobody types them.  These are the
  # opposite: they are credentials for accounts that exist outside this clan,
  # so the only source is the operator.
  #
  # THEY ARE NOT A UI SETTING.  RomM reads every metadata provider's
  # credentials from the ENVIRONMENT at startup and its API only reports which
  # sources came out enabled — `/api/heartbeat` on 5.2.0 answers
  #
  #   "STEAMGRIDDB_API_ENABLED": false, "IGDB_API_ENABLED": false,
  #   "HASHEOUS_API_ENABLED": true
  #
  # so there is no field in the web UI that could set them.  That is why this
  # is a clan var and a container env var rather than a note telling someone to
  # click something.
  #
  # OPTIONAL BY CONSTRUCTION.  An empty answer is a valid answer: RomM treats a
  # missing or empty key as "source disabled" and carries on with Hasheous,
  # which needs no account at all.  So this prompt never blocks a deploy on a
  # credential the operator does not have yet — press enter and revisit it with
  # `clan vars generate ernst --generator romm-metadata-keys --regenerate`.
  #
  # That optionality is NOT free: clan stores no secret for a blank answer, so
  # the var's path becomes `/no-such-path`.  It only holds because romm-secrets
  # reads these through `optional_secret` rather than a bare `cat` — see the
  # comment there before changing either.
  clan.core.vars.generators.romm-metadata-keys = {
    files."steamgriddb-api-key".secret = true;
    files."igdb-client-id".secret = true;
    files."igdb-client-secret".secret = true;

    prompts."steamgriddb-api-key" = {
      description = "SteamGridDB API key for RomM cover art (steamgriddb.com/profile/preferences/api) — blank to leave disabled";
      type = "hidden";
    };
    # IGDB is RomM's primary metadata source and the one that fills in names,
    # release dates and genres; SteamGridDB only supplies artwork.  Prompted
    # together because they are the same errand, and because the same IGDB
    # application already backs Questarr.
    prompts."igdb-client-id" = {
      description = "IGDB (Twitch) client ID for RomM metadata — blank to leave disabled";
      type = "hidden";
    };
    prompts."igdb-client-secret" = {
      description = "IGDB (Twitch) client secret for RomM metadata — blank to leave disabled";
      type = "hidden";
    };

    runtimeInputs = [pkgs.coreutils];
    script = ''
      # `tr -d` strips the trailing newline the prompt adds: these end up in an
      # env file, where a newline would terminate the value early and leave the
      # next line looking like a stray assignment.
      for f in steamgriddb-api-key igdb-client-id igdb-client-secret; do
        tr -d '\n' < "$prompts/$f" > "$out/$f"
      done
    '';
  };

  # ── The second-tier metadata providers ──────────────────────────────────
  #
  # A SEPARATE GENERATOR, DELIBERATELY.  Adding files to
  # `romm-metadata-keys` above would change that generator, and clan re-runs a
  # generator as a unit — so it would re-prompt for the IGDB and SteamGridDB
  # credentials that are already stored and working.  Splitting keeps this an
  # additive errand: answer the new prompts, leave the old ones untouched.
  #
  # WHY BOTHER, given IGDB is already enabled.  Measured on this library
  # (2026-09-07, 37,896 ROMs): IGDB matched 24,301 and 22,860 got a summary —
  # about 64%.  The missing third is not random.  It is ROM hacks, bad dumps
  # and pirate multicarts — `100-in-1 Contra Function 16`, `[hM02]`, `[a1]`,
  # `110-in-1 (Menu)` — which IGDB does not catalogue at all, because IGDB
  # catalogues *published games*.  No amount of retrying IGDB reaches them.
  #
  # ScreenScraper is the one that does: it matches on file hash rather than
  # name, and its corpus is community dumps, which is exactly this population.
  # It needs a personal account *on top of* the dev credentials RomM ships
  # (`SCREENSCRAPER_DEV_ID=zurdi15` is RomM's author, not us) — `ss_handler.py`
  # gates on `bool(SCREENSCRAPER_USER and SCREENSCRAPER_PASSWORD)`, so without
  # a user account the source reports enabled=false however good the dev
  # credentials are.  That is why /api/heartbeat showed
  # `"SS_API_ENABLED": false, "SS_DEV_CREDENTIALS_SET": true`.
  #
  # Same empty-answer contract as the generator above: blank leaves the source
  # disabled and the deploy still succeeds.
  clan.core.vars.generators.romm-metadata-keys-extra = {
    files."screenscraper-user".secret = true;
    files."screenscraper-password".secret = true;
    files."retroachievements-api-key".secret = true;

    prompts."screenscraper-user" = {
      description = "ScreenScraper username (screenscraper.fr) — hash-based matching, best for hacks and multicarts IGDB misses; blank to leave disabled";
      type = "hidden";
    };
    prompts."screenscraper-password" = {
      description = "ScreenScraper password — blank to leave disabled";
      type = "hidden";
    };
    # NO MOBYGAMES PROMPT, DELIBERATELY.  MobyGames' API is a paid tier and
    # there is no key for this clan, so declaring the prompt only ever produces
    # a blank answer — and a blank answer is not a stable state in clan: it
    # stores no secret, so `clan machines update` re-prompts for it on every
    # single deploy and aborts outright when there is no TTY (termios error out
    # of clan_lib/vars/prompt.py).  Add the prompt back at the moment there is
    # a key to type into it, not before.
    prompts."retroachievements-api-key" = {
      description = "RetroAchievements API key (retroachievements.org/controlpanel.php) — blank to leave disabled";
      type = "hidden";
    };

    runtimeInputs = [pkgs.coreutils];
    script = ''
      # Same newline strip as romm-metadata-keys: these land in an env file.
      for f in screenscraper-user screenscraper-password retroachievements-api-key; do
        tr -d '\n' < "$prompts/$f" > "$out/$f"
      done
    '';
  };

  clan.core.vars.generators.romm-db-root-password = {
    files."password".secret = true;
    runtimeInputs = [pkgs.coreutils pkgs.openssl];
    script = ''
      openssl rand -base64 32 | tr -d '\n=' > "$out/password"
    '';
  };

  # Stage them as env files the container units can read.
  #
  # A directory WE own, rather than a bind of /run/secrets — which is a symlink
  # to a per-generation directory REPLACED on every deploy, so a mount
  # established at container start would keep exposing a deleted generation.
  # M5, M9, M13 and M14 all record this.
  #
  # ENV FILES rather than mounted secret files, because RomM's image takes its
  # database credentials only as environment variables (`DB_PASSWD`); there is
  # no `_FILE` variant to prefer.  They are read by podman as root before the
  # container drops to ${toString rommUid}, so 0400 root:root is correct and
  # the values never appear in a world-readable /proc/<pid>/environ of ours.
  #
  # requiredBy, NOT wantedBy: neither container starts usefully without these,
  # so a container that started anyway would just be a restart loop in a
  # different unit's journal.
  systemd.services.romm-secrets = {
    description = "Stage RomM's generated secrets as container env files";
    requiredBy = ["podman-romm.service" "podman-romm-db.service"];
    before = ["podman-romm.service" "podman-romm-db.service"];
    after = ["local-fs.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = let
      authKey = config.clan.core.vars.generators.romm-auth-secret.files."secret-key".path;
      dbPw = config.clan.core.vars.generators.romm-db-password.files."password".path;
      rootPw = config.clan.core.vars.generators.romm-db-root-password.files."password".path;
      meta = config.clan.core.vars.generators.romm-metadata-keys.files;
      sgdbKey = meta."steamgriddb-api-key".path;
      igdbId = meta."igdb-client-id".path;
      igdbSec = meta."igdb-client-secret".path;
      extra = config.clan.core.vars.generators.romm-metadata-keys-extra.files;
      ssUser = extra."screenscraper-user".path;
      ssPass = extra."screenscraper-password".path;
      raKey = extra."retroachievements-api-key".path;
    in ''
      set -eu
      umask 077
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${secretsDir}

      # ── Required secrets: a bare cat, so a genuine absence fails loudly ──
      auth=$(${pkgs.coreutils}/bin/cat ${authKey})
      dbpw=$(${pkgs.coreutils}/bin/cat ${dbPw})
      rootpw=$(${pkgs.coreutils}/bin/cat ${rootPw})

      # ── Optional provider credentials ───────────────────────────────────
      #
      # BLANK IS A VALID ANSWER, AND IT HAS TO BE HANDLED HERE.  Both metadata
      # generators tell the operator they may press enter to leave a source
      # disabled.  That promise was false: clan does not store an empty answer
      # to a prompt — it writes no secret file at all, and the var's `.path`
      # then evaluates to the literal string `/no-such-path`.  Under `set -eu`
      # a bare `cat` on that exits 1, this unit fails, and podman-romm.service
      # and podman-romm-db.service never start because they order after it.
      #
      # That is exactly what happened on 2026-09-07: MobyGames is a paid tier,
      # the prompt was answered blank as the comment invited, and RomM went
      # down on the next deploy.  `ls vars/per-machine/ernst/…/mobygames-api-key`
      # shows `machines users` where the answered ones show `machines secret
      # users` — the missing `secret/` is the whole failure.
      #
      # An unset value is what RomM wants anyway: config/__init__.py reads each
      # key with _get_env and every handler gates on bool(), so empty means
      # "source disabled" rather than "misconfigured".
      optional_secret() {
        if [ -r "$1" ]; then ${pkgs.coreutils}/bin/cat "$1"; fi
      }

      sgdb=$(optional_secret "${sgdbKey}")
      igdbid=$(optional_secret "${igdbId}")
      igdbsec=$(optional_secret "${igdbSec}")
      ssuser=$(optional_secret "${ssUser}")
      sspass=$(optional_secret "${ssPass}")
      rakey=$(optional_secret "${raKey}")

      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root /dev/null ${secretsDir}/romm.env
      ${pkgs.coreutils}/bin/cat > ${secretsDir}/romm.env <<EOF
      ROMM_AUTH_SECRET_KEY=$auth
      DB_PASSWD=$dbpw
      STEAMGRIDDB_API_KEY=$sgdb
      IGDB_CLIENT_ID=$igdbid
      IGDB_CLIENT_SECRET=$igdbsec
      SCREENSCRAPER_USER=$ssuser
      SCREENSCRAPER_PASSWORD=$sspass
      RETROACHIEVEMENTS_API_KEY=$rakey
      EOF

      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root /dev/null ${secretsDir}/romm-db.env
      ${pkgs.coreutils}/bin/cat > ${secretsDir}/romm-db.env <<EOF
      MARIADB_ROOT_PASSWORD=$rootpw
      MARIADB_PASSWORD=$dbpw
      EOF
    '';
  };

  ##############################################################################
  # The container.
  ##############################################################################
  #
  # Declared through modules/containers/podman-netns.nix, which generates the
  # netns unit, the DHCP client, the host-side networkd file, the dirs unit,
  # both oci-containers entries and the ordering between all of them.
  #
  # `romm-secrets` STAYS HAND-WRITTEN: it writes TWO env files for two
  # different images out of five generators, one of which it assembles from a
  # prompt-per-provider. The module's `secrets` option writes one file per
  # named env file out of KEY=value pairs, which is not that shape.
  clanarchy.podmanContainers.romm = {
    enable = true;
    mac = "02:00:00:90:00:0e";
    interface = "rm0";

    # Rootful and unmapped: these ids land on zdata, where a rootless subuid
    # remap would write files the rest of the host cannot name. Applies to
    # both images in the namespace.
    uidgid = "${toString rommUid}:${toString rommGid}";

    # The library is its own dataset; the guard names the MOUNT POINT, since
    # the dirs unit derives a mount unit from this path.
    extraGuardedMounts = [
      {
        path = libraryDir;
        source = "zdata/roms";
        fstype = "zfs";
      }
    ];

    # 2770 root:romm on the library so a human can drop a ROM in; 0750 on the
    # state tree, which only RomM itself touches.
    stateDirs =
      [
        {
          path = libraryDir;
          owner = "root";
          group = rommGid;
          mode = "2770";
        }
        {
          path = "${libraryDir}/roms";
          owner = "root";
          group = rommGid;
          mode = "2770";
        }
        {
          path = "${libraryDir}/bios";
          owner = "root";
          group = rommGid;
          mode = "2770";
        }
        {
          path = stateDir;
          owner = rommUid;
          group = rommGid;
          mode = "0750";
        }
      ]
      ++ map (d: {
        path = "${stateDir}/${d}";
        owner = rommUid;
        group = rommGid;
        mode = "0750";
      })
      ["resources" "assets" "config" "redis" "mysql"];

    allowFrom = [
      {
        peer = traefikAddr;
        port = webPort;
      }
      {
        peer = dashboardAddr;
        port = webPort;
      }
    ];

    images = {
      # THE DATABASE IS BOUND TO LOOPBACK AND SHARES THIS NAMESPACE, which is
      # what makes it unaddressable rather than merely unadvertised: there is
      # no interface in here it could answer on except `lo`, and the single
      # `-i lo` accept in the netns unit covers it.
      romm-db = {
        image = "docker.io/library/mariadb@${dbDigest}";
        environment = {
          TZ = "Europe/Berlin";
          MARIADB_DATABASE = "romm";
          MARIADB_USER = "romm-user";
        };
        environmentFiles = ["${secretsDir}/romm-db.env"];
        volumes = ["${stateDir}/mysql:/var/lib/mysql"];
        ports = [];
        extraOptions = ["--health-cmd=healthcheck.sh --connect --innodb_initialized"];
        cmd = ["--bind-address=127.0.0.1"];
      };

      romm = {
        image = "docker.io/rommapp/romm@${rommDigest}";
        environment = {
          TZ = "Europe/Berlin";
          DB_HOST = "127.0.0.1";
          DB_NAME = "romm";
          DB_USER = "romm-user";
          # DB_PASSWD and ROMM_AUTH_SECRET_KEY arrive via environmentFiles.
          ROMM_PORT = toString webPort;
          HASHEOUS_API_ENABLED = "true";
        };
        environmentFiles = ["${secretsDir}/romm.env"];
        volumes = [
          # The library, read-write: RomM accepts uploads through the web UI,
          # which is the intended way to add a game from a machine that is
          # not birte.
          "${libraryDir}:/romm/library"
          # Fetched artwork and metadata — large and re-fetchable, but
          # re-fetching a whole library's covers is slow enough to persist.
          "${stateDir}/resources:/romm/resources"
          # Saves, states and screenshots RomM manages itself.
          "${stateDir}/assets:/romm/assets"
          "${stateDir}/config:/romm/config"
          "${stateDir}/redis:/redis-data"
        ];
        ports = [];
        # The database first; oci-containers turns this into Requires/After
        # on podman-romm-db.service.
        dependsOn = ["romm-db"];
      };
    };
  };

  # ── SCHEDULING PRIORITY, MERGED ONTO THE GENERATED UNIT ─────────────────────
  #
  # Ordering comes from the module. These two numbers do not: they are a
  # judgement about THIS workload and they differ per service, so they stay
  # next to the reasoning rather than becoming a module passthrough.
  #
  # A library scan hashes every file it has not seen before. On a cold first
  # scan of a large library that is hours of sustained IO and real CPU,
  # competing with a Jellyfin transcode, the HTPC session on the TV, and an
  # interactive Ollama session — the last being the claimant whose degradation
  # is hardest to attribute.
  #
  # Less aggressive than Storyteller's 15/20 because a scan is bounded and
  # occasionally a human IS waiting on it (adding one game and wanting to see
  # it), whereas forced alignment is pure batch.
  systemd.services.podman-romm.serviceConfig = {
    Nice = 10;
    CPUWeight = 40;
  };
}
