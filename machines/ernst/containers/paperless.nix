##############################################################################
# Paperless-ngx — the household document store.                        (M32)
#
# WHAT IT IS FOR, stated before anything technical.  lgo and Sabine scan paper
# with their phones and have nowhere to put it.  Three requirements, from lgo:
#
#   | it gets in from a phone      | FairScan has no cloud of its own — it
#   |                              | shares a PDF to another app, or saves into
#   |                              | a folder a storage app provides.  BOTH of
#   |                              | those doors are wired: the Paperless
#   |                              | Mobile app straight to the API, and a
#   |                              | Nextcloud folder that IS the consumption
#   |                              | directory (see the inbox section below).
#   | everything is searchable     | OCR in German and English, then Whoosh
#   |                              | full-text over the extracted text.  Office
#   |                              | files too, via Tika + Gotenberg.
#   | the local AI can answer      | NOT in this file.  M32b gives mneme
#   | questions about it           | `document_search` / `document_read` over
#   |                              | this container's REST API on the `doc0`
#   |                              | leg declared here.
#
# ── WHY THIS TIER ─────────────────────────────────────────────────────────────
#
# nspawn, and the test is the one containers/nextcloud.nix and romm.nix both
# state: `services.paperless` is a first-class NixOS module, and the podman tier
# is for upstreams that ship only an image.  Invariant #1 — a service moves up a
# tier when it starts talking to the internet on its own behalf, not for being
# reachable from it.  This one answers; it does not dial out.
#
# ── THE INGRESS POSTURE ───────────────────────────────────────────────────────
#
# `docs.goclan.org` is in `appApiHosts`, so it carries NO forward-auth, and the
# one test in containers/ingress-policy.nix is why: Paperless Mobile
# authenticates against /api/token/ and then sends a DRF token header on every
# request.  It cannot render a login page and it cannot follow a 302.
#
# This is therefore CWA's and Nextcloud's arrangement — OIDC INSTEAD OF the
# middleware.  A browser gets Authelia and two-factor; the app protocol reaches
# the application directly and is bounded by the application's own accounts.
# Attaching the `authelia` middleware to this router is a build failure, by
# check (e) of `withWan` in containers/traefik.nix.
#
# Unlike `cloud`, it DOES get a `wanLoginPaths` entry, and the distinction is
# the point rather than an inconsistency — see that block in traefik.nix.
#
# ── WHAT IS DELIBERATELY NOT HERE ─────────────────────────────────────────────
#
# * A PROMETHEUS SCRAPE TARGET.  Paperless exposes no OpenMetrics endpoint, so
#   a job could only ever be `up == 0`.  That is M13's Ollama lesson and
#   standing note SN3 — a broken instrument is indistinguishable from a bad
#   result — and it is the same call containers/nextcloud.nix and karakeep.nix
#   made.  What it gets instead is `ContainerSystemdUnitFailed` for free: the
#   `clanarchy-container-units` collector walks `machinectl list` on a
#   one-minute timer, so any failed unit in here becomes a host-side metric.
#
# * PAPERLESS'S OWN AI.  The LLM title/tag suggestions and the in-app document
#   chat merged against upstream's v3.0.0 milestone; ernst's stable pin carries
#   2.20.15.  Taking them would mean a cross-channel module AND package import
#   onto a stable machine, plus an embedding model llama-swap does not have and
#   that M20 refused on the grounds that the only offer was an unpinned runtime
#   HuggingFace download.  Recorded as a decision in docs/roadmap.md, deferred
#   until 26.11 ships 3.x in-tree.  What 2.20.15 DOES have and what this relies
#   on instead is the scikit-learn classifier, which learns tags, correspondents
#   and document types from the household's own corrections.
#
# * A HOMEPAGE WIDGET.  A plain link tile ships instead.  The widget needs an
#   API token, and adding a prompt to the `homepage-tokens` generator does not
#   re-run it — clan treats a generator as satisfied once every *file* it
#   declares exists — so it would need `--regenerate`, which re-asks all six
#   existing prompts.  Not worth that for a dashboard number.
#
# * AN IMAP CONSUMPTION PATH and a laptop watch folder.  Both were offered and
#   both were declined.  The SANE/hplip scanner is on miralda and jens, so
#   modules/immich-upload.nix's quiescence-timer shape is the route if flatbed
#   scanning ever becomes a habit.
#
# * AN OFF-BOX BACKUP, because there is none anywhere in this fleet and this
#   file is not the place to invent one.  ZFS snapshots live on the same pool as
#   the data and `zdata/backup` is reserved and deliberately uncreated.  This
#   milestone makes that gap matter MORE, since scanned paper gets thrown away —
#   `exporter.enable` below is a mitigation and is not a fix.
##############################################################################
{
  config,
  pkgs,
  lib,
  ...
}:

let
  ##############################################################################
  # Identity.
  ##############################################################################

  # ── NOT FROM THE 3000 BLOCK, AND THAT IS NOT AN OVERSIGHT ──────────────────
  #
  # `ids.uids.paperless` is 315, a well-known NixOS static id, and the nixpkgs
  # module assigns it unconditionally:
  #
  #     users = lib.optionalAttrs (cfg.user == defaultUser) {
  #       users.${cfg.user} = { uid = config.ids.uids.paperless; … };
  #
  # So pinning a 3000-block number on top of it is not a choice this file gets
  # to make — it is the `hass` = 286 option conflict, verbatim:
  #
  #     The option `containers.paperless.users.users.paperless.uid' has
  #     conflicting definition values: 315 / 3042
  #
  # It fails at EVALUATION, which is the good case.  The alternative — setting
  # `services.paperless.user` to something other than the default so the
  # module's own `users` block is skipped, then declaring the account by hand —
  # buys a 3000-block number and costs a hand-rolled user for no benefit.
  #
  # So 315 it is, recorded in machines/ernst/networking.nix's OUT-OF-BLOCK
  # sub-table beside `hass` 286, `postgres` 71 and M31's four mail daemons, with
  # the same sentence they carry: the 3000-block convention does not apply to it
  # and it must not be renumbered into the block.  NEXT FREE in the 3000 block
  # does not advance for it.
  #
  # It still lands on zdata unmapped like every other container id here, which
  # is why it is in that table at all.
  paperlessUid = 315;
  paperlessGid = 315;

  # Not ours to choose either: `ids.uids.postgres`.  Appears on
  # /srv/state/{immich,nextcloud,miniflux,paperless}/postgresql.
  postgresUid = 71;
  postgresGid = 71;

  # ── THE SHARED INGEST GROUP ────────────────────────────────────────────────
  #
  # A group-only allocation from the 3000 block, the way gid 3000 `media` is,
  # and the ONE id this milestone takes from there (M31 took 3041 for
  # `virtualMail`; NEXT FREE is now 3043).
  #
  # It exists because /srv/docs/inbox has TWO principals: Nextcloud (uid 3037)
  # writes a scan into it over WebDAV, and paperless (uid 315) consumes and
  # then UNLINKS it.  Neither is in the other's private group, so without a
  # third group shared between them paperless would be reading Nextcloud's
  # files on the `other` bits by luck — which is exactly the sentence
  # containers/cwa.nix:509-535 wrote about its own ingest directory.
  #
  # Declared in BOTH container configs, because each `containers.<n>.config` is
  # its own NixOS evaluation with no access to the host option tree.  That is
  # the same reason nextcloud.nix restates `mediaGid = 3000`.
  docsinGid = 3042;

  # The Nextcloud uid, restated here for the same reason, because this file
  # creates the directory that both of them use.
  nextcloudUid = 3037;

  ##############################################################################
  # Peers, ports and paths.
  ##############################################################################

  # The one VLAN-90 peer allowed to reach this service.  Every human client —
  # a browser, the Paperless Mobile app on either phone — arrives through it.
  # M5's backend-bypass hardening, mechanism (a).
  traefikAddr = "10.0.90.12";

  # ── THE SECOND PEER, AND IT IS NOT ON VLAN 90 ──────────────────────────────
  #
  # mneme is a HOST service and has to reach this container.  It cannot do that
  # over 10.0.90.32: the host's route to the services VLAN is `via 10.0.50.1`,
  # measured, so every call would hairpin out to the UDM-Pro and back.  M29b
  # hit this exact wall reaching SearXNG and the answer was a point-to-point
  # /128 leg — `web0` — so this is `web0`'s shape and not `ai*`'s.
  #
  # THE DIRECTION IS THE SECURITY PROPERTY.  The host end dials IN; nothing
  # accepts on the way back.  There is no `mkBridges` call and no host-side
  # `ip6tables` accept for `fdca:fe95::2` anywhere in this repository — ernst's
  # `nixos-fw` drops unmatched input, so a compromised paperless is exactly as
  # boxed in as it was.  The only accept is INSIDE the container, below, and it
  # names one source address.
  docVeth = "doc0";
  docHost = "fdca:fe95::1";
  docCont = "fdca:fe95::2";

  # Granian, the module's own server.  Not 80: unlike Nextcloud there is no
  # nginx in front of it inside the container, so this is the application port
  # and the module's default.
  paperlessPort = 28981;

  baseDomain = "goclan.org";
  hostName   = "docs.${baseDomain}";

  # Authelia's portal as the OIDC issuer.  Restated rather than shared, as in
  # traefik.nix, authelia.nix and nextcloud.nix.
  autheliaIssuer = "https://auth.${baseDomain}";

  # ── TWO DATASETS, THE SAME SPLIT IMMICH AND NEXTCLOUD MAKE ─────────────────
  #
  # zdata/docs carries recordsize=1M: a scanned PDF is written whole and is
  # never partially rewritten in place, which is the access pattern that would
  # make 1M wrong.  recordsize is a MAXIMUM and not a quantum, so the small
  # files cost nothing there.
  #
  # The index, the classifier model and the logs do NOT go there — they are
  # small random writes and belong at /srv/state's 128K default.  That is why
  # `dataDir` and `mediaDir` are set apart rather than left at the module's
  # default, which nests media inside data.
  docsRoot   = "/srv/docs";
  mediaDir   = "${docsRoot}/media";
  exportDir  = "${docsRoot}/export";
  stateRoot  = "/srv/state/paperless";
  dataDir    = "${stateRoot}/data";

  # ── THE INGEST DIRECTORY, AND WHY IT IS NOT UNDER /srv/docs ────────────────
  #
  # It MUST be outside `mediaDir`: the consumer walks its own directory and
  # deletes what it has taken, so pointed inside the archive it would
  # re-consume paperless's own output forever.  That part is obvious.
  #
  # WHAT IS NOT OBVIOUS is why it is on /srv/state rather than one directory
  # along at /srv/docs/inbox, which is where it started.  This directory is
  # bind-mounted into TWO containers — paperless consumes from it, Nextcloud
  # writes into it — and a bind mount whose host path does not exist is a
  # container that does not start.  On /srv/docs that would mean A MISSING
  # zdata/docs TAKES NEXTCLOUD DOWN WITH IT: the household's file sync, its
  # calendars and its contacts, stopped by a dataset belonging to a service it
  # has nothing to do with.
  #
  # That is precisely the coupling containers/arr.nix refuses when it orders
  # only `before` on /srv/audiobooks — "Sonarr must not go down because an
  # unrelated library is missing" — and the answer here is the same in spirit:
  # the shared path lives where BOTH users already depend on it.  Nextcloud's
  # own `nextcloud-dirs` already requires `srv-state.mount`, so putting the
  # inbox under /srv/state adds no dependency it did not have.
  #
  # It costs nothing to put it here, because THIS IS A QUEUE AND NOT A LIBRARY.
  # Nothing lives in it longer than one `PAPERLESS_CONSUMER_POLLING` interval,
  # so /srv/docs's 1M recordsize would buy it nothing, and the archive — the
  # part that must be snapshotted and must be on 1M — is untouched by this.
  #
  # The one honest cost: /srv/state carries `exec=on`, because services there
  # drop and invoke helper scripts, where /srv/docs is `exec=off`.  Nothing
  # executes anything in here — paperless reads PDFs — but it is a weaker
  # property than the archive's and is stated rather than glossed.
  consumeDir = "${stateRoot}/inbox";

  ##############################################################################
  # Secrets staging.
  #
  # NOT a bind of /run/secrets itself: that path is a symlink to a
  # per-generation directory which is REPLACED on every deploy, so an nspawn
  # bind established at container start would keep exposing a deleted
  # generation.  containers/traefik.nix carries the long form.
  ##############################################################################
  secretsDir    = "/run/paperless-secrets";
  adminPassFile = "${secretsDir}/admin-pass";
  mnemeTokenDst = "${secretsDir}/mneme-token";

  # ── ONE EnvironmentFile, AND WHY IT IS NOT `settings` ──────────────────────
  #
  # Two of paperless's settings cannot go in `settings` below, because that
  # attrset is rendered into the Nix store:
  #
  #   PAPERLESS_SECRET_KEY                — Django's signing key.
  #   PAPERLESS_SOCIALACCOUNT_PROVIDERS   — embeds the OIDC client secret.
  #
  # Both are written by paperless-secrets.service into this file instead.
  #
  # ── THIS FILE HAS TWO READERS WITH DIFFERENT PARSERS, AND EVERY VALUE IN ──
  #    IT IS THEREFORE SINGLE-QUOTED
  #
  # An earlier version of this comment said systemd's `EnvironmentFile` keeps
  # quotes as part of the value and wrote the JSON bare.  THAT IS WRONG, and it
  # cost `paperless-provision` its first deploy (2026-10-05):
  #
  #     json.decoder.JSONDecodeError: Expecting property name enclosed in
  #     double quotes: line 1 column 2 (char 1)
  #
  # The confusing part is that the SERVICES were fine.  Two readers:
  #
  #   systemd `EnvironmentFile=`   paperless-web and friends.  Reads the file
  #                               itself; strips matching quotes.
  #   bash `source`               `paperless-manage`, which does
  #                               `set -o allexport; source <file>` — and
  #                               therefore applies BRACE EXPANSION and word
  #                               splitting to an unquoted value.
  #
  # Measured on ernst with a two-arm control, the only way to tell these apart:
  #
  #     bare   + bash source  ->  {openid_connect:{OAUTH_PKCE_ENABLED:true,…}}
  #     bare   + systemd      ->  {"openid_connect":{"OAUTH_PKCE_ENABLED":true,…}}
  #     quoted + bash source  ->  {"openid_connect":{"OAUTH_PKCE_ENABLED":true,…}}
  #     quoted + systemd      ->  {"openid_connect":{"OAUTH_PKCE_ENABLED":true,…}}
  #
  # So bash silently ate every double quote in the JSON, and only the one
  # consumer that goes through the wrapper noticed.  Single quotes satisfy both
  # readers, and they are safe here because the JSON contains double quotes
  # only.
  #
  # containers/homepage.nix:300-312 says NOT to quote, and that is not a
  # contradiction to reconcile — that file's values are read by homepage's own
  # Go template engine, not by systemd or by bash.  Check the reader, not the
  # convention.
  envFile = "${secretsDir}/env";

  adminGen = config.clan.core.vars.generators.paperless-admin;
  secretGen = config.clan.core.vars.generators.paperless-secret;
  mnemeGen = config.clan.core.vars.generators.paperless-mneme-token;

  # Declared in containers/authelia.nix beside the other relying parties — ONE
  # GENERATOR PER RELYING PARTY is that file's rule, and it is why this reaches
  # across rather than declaring its own.  Authelia takes the DIGEST; this
  # container takes the PLAINTEXT half of the same pair.
  oidcGen = config.clan.core.vars.generators.authelia-oidc-paperless;

  ##############################################################################
  # mneme's account, as a file rather than a heredoc.
  #
  # A `<<'PYEOF'` heredoc inside a Nix `''` string works only as long as the
  # indentation Nix strips happens to leave the terminator in column 0 — which
  # depends on the least-indented line ANYWHERE in that string.  Add one
  # shallower line later and the heredoc silently never terminates.  A store
  # file has no such coupling, and `paperless-manage shell` reads a script from
  # stdin, so this costs nothing.
  ##############################################################################
  provisionScript = pkgs.writeText "paperless-provision.py" ''
    # Provision mneme's read-only account and its API token.  Run by
    # paperless-provision.service, inside the container, as the paperless user.
    #
    # BOTH WRITES ARE UPSERTS, so this is idempotent across deploys by
    # construction rather than by a stamp file.  A stamp file would be worse
    # than nothing: it would claim the account exists after somebody deleted it
    # in the admin UI.
    from django.contrib.auth.models import Permission, User
    from rest_framework.authtoken.models import Token

    TOKEN_FILE = "${mnemeTokenDst}"

    # FOUR VIEW PERMISSIONS AND NOTHING ELSE.  An agent with a tool is a thing
    # that can be talked into something, so this is scoped rather than
    # convenient: a tool that can only read cannot be talked into deleting the
    # household's records.
    PERMS = [
        "view_document",
        "view_tag",
        "view_correspondent",
        "view_documenttype",
    ]

    # Read from the staged file, not from argv.  nextcloud-provision has to put
    # its OIDC secret on a command line because `occ` offers no file form; this
    # one does not have to, so it does not — the token never appears in
    # /proc/<pid>/cmdline.
    with open(TOKEN_FILE) as fh:
        key = fh.read().strip()

    user, _ = User.objects.update_or_create(
        username="mneme",
        defaults={
            "is_active": True,
            "is_staff": False,
            "is_superuser": False,
            "first_name": "mneme",
            "last_name": "(agent, read-only)",
        },
    )

    # No usable password: this account exists to hold a token, so anything
    # arriving at the login form as `mneme` must fail.
    user.set_unusable_password()
    user.save()

    user.user_permissions.set(Permission.objects.filter(codename__in=PERMS))

    # Keyed on the USER, so re-running with a rotated token replaces the key
    # rather than colliding on rest_framework's one-to-one.
    Token.objects.update_or_create(user=user, defaults={"key": key})

    print(f"mneme: token set, {user.user_permissions.count()} permissions")
  '';
in
{
  ##############################################################################
  # Host side — the datasets, the directories, the secrets and the veth.
  ##############################################################################

  # ── THIS FILE DECLARES NO tmpfiles RULES, AND containers/immich.nix IS WHY ─
  #
  # That file records the measured failure: its host-side directories shipped as
  # `systemd.tmpfiles.rules` and the container died five times into its start
  # limit with
  #
  #     systemd-nspawn: Failed to clone /srv/state/immich/ml-cache:
  #                     No such file or directory
  #
  # because activating a new configuration does not re-run
  # systemd-tmpfiles-setup.service in time for a container the same activation
  # starts.  Every host-side directory this container binds therefore belongs to
  # the ordered unit below, and none of them is ALSO declared as a tmpfiles rule
  # here — two declarations for one path is the M3 defect.
  #
  # ── ONE PATH IS THE EXCEPTION AND IT IS UPSTREAM'S, NOT OURS ───────────────
  #
  # `services.paperless` ships its own rule for the exporter's directory:
  #
  #     d '${exportDir}' - paperless paperless - -
  #
  # It runs INSIDE the container, through the bind, against the inode created
  # below — so ${exportDir} settles at tmpfiles' default 0755 rather than the
  # 0700 asked for here.  It is NOT forced back, for Nextcloud's two reasons:
  # competing with a rule the module already declares IS the M3 defect, and the
  # mode is not an exposure here.  The check is specific rather than
  # reassuring: ${docsRoot} itself is 0700 and is owned by uid 315, and it is
  # NOT bind-mounted into the container — only its children are — so nothing in
  # here can re-mode it.  `go`, the couch account that autologins on the
  # television without a password, cannot traverse into it at all, and an
  # unreachable 0755 grants nobody anything.
  #
  # If ${docsRoot} is ever bound in whole, or its mode ever changes, re-read
  # this paragraph rather than trusting it.
  systemd.services.paperless-dirs = {
    description = "Verify Paperless's datasets are mounted and create its directories";
    wantedBy   = [ "multi-user.target" ];
    after      = [ "srv-docs.mount" "srv-state.mount" "paperless-inbox.service" ];
    requires   = [ "srv-docs.mount" "srv-state.mount" "paperless-inbox.service" ];
    before     = [ "container@paperless.service" ];
    requiredBy = [ "container@paperless.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.util-linux pkgs.coreutils ];

    # BLOCKING (`requires` + `requiredBy`), not advisory, and the argument is
    # Immich's and Nextcloud's rather than arr.nix's.  A paperless that starts
    # without its dataset is not a degraded paperless — it is a NEW, EMPTY one
    # on zroot, which will accept a phone's scans, report success to the app,
    # and lose them at the next boot.  The paper original is in the recycling by
    # then, which is the part that makes this worse than the sync case.
    #
    # It FAILS rather than repairing itself: a unit that silently fixes storage
    # layout hides the fact that the layout was wrong.
    script = ''
      set -eu

      # findmnt, not `mountpoint`: this has to check WHAT is mounted, not just
      # that something is.  /srv/docs carries `nofail`
      # (machines/ernst/disko.nix), so the mount unit can fail while /srv/docs
      # still exists as an ordinary directory on zroot — precisely the case a
      # bare mountpoint test passes.
      src=$(findmnt --noheadings --output SOURCE --target ${docsRoot} || true)
      fstype=$(findmnt --noheadings --output FSTYPE --target ${docsRoot} || true)

      if [ "$src" != "zdata/docs" ] || [ "$fstype" != "zfs" ]; then
        echo "paperless-dirs: ${docsRoot} is NOT zdata/docs." >&2
        echo "  found: source='$src' fstype='$fstype'" >&2
        echo "" >&2
        echo "  Refusing to create it, because doing so would put the" >&2
        echo "  household's document archive on zroot, which rolls back on" >&2
        echo "  every boot — while the phones report every upload as a" >&2
        echo "  success and the paper gets thrown away." >&2
        echo "" >&2
        echo "  The dataset must exist AND carry mountpoint=legacy — a ZFS" >&2
        echo "  dataset without it cannot be mounted by mount(8) at all:" >&2
        echo "" >&2
        echo "    zfs create -o mountpoint=legacy -o recordsize=1M \\" >&2
        echo "      -o exec=off -o setuid=off -o devices=off -o atime=off \\" >&2
        echo "      -o com.sun:auto-snapshot=true zdata/docs" >&2
        echo "" >&2
        echo "  If it exists already:  zfs set mountpoint=legacy zdata/docs" >&2
        echo "  Then:                  systemctl start srv-docs.mount" >&2
        echo "  See docs/guides/ernst-zdata-datasets.md." >&2
        exit 1
      fi

      # THE TARGET IS THE PARENT, NOT ${stateRoot}.  `findmnt --target` on a
      # path that does not exist yet returns nothing — it does not walk up to
      # the nearest existing ancestor — so checking ${stateRoot} here would fail
      # on every first run, before this unit has created it.  immich-dirs
      # refused its own first deploy that way on 2026-09-11.
      ssrc=$(findmnt --noheadings --output SOURCE --target /srv/state || true)
      if [ "$ssrc" != "zdata/state" ]; then
        echo "paperless-dirs: /srv/state is not zdata/state (found '$ssrc')." >&2
        echo "  Refusing to create Paperless's index and database directories," >&2
        echo "  because they would land on zroot and be rolled back." >&2
        exit 1
      fi

      # NUMERIC ids on purpose: `paperless` and `postgres` are CONTAINER users
      # and the host has no matching passwd entries.
      install -d -o ${toString paperlessUid} -g ${toString paperlessGid} -m 0700 ${docsRoot}
      install -d -o ${toString paperlessUid} -g ${toString paperlessGid} -m 0700 ${mediaDir}
      install -d -o ${toString paperlessUid} -g ${toString paperlessGid} -m 0700 ${exportDir}
      # ${stateRoot} ITSELF IS NOT CREATED HERE — `paperless-inbox` below owns
      # it, and this unit is ordered after that one.  Two units running
      # `install -d` on one path is the M3 defect even when they agree about
      # the mode today, because the next edit only changes one of them.
      install -d -o ${toString paperlessUid} -g ${toString paperlessGid} -m 0700 ${dataDir}
      install -d -o ${toString postgresUid}  -g ${toString postgresGid}  -m 0700 ${stateRoot}/postgresql
    '';
  };

  # ── THE SHARED INBOX GETS ITS OWN UNIT, AND THE SPLIT IS THE WHOLE POINT ───
  #
  # This directory is bind-mounted into TWO containers, so its guard must carry
  # only the dependencies BOTH of them have.  `paperless-dirs` above requires
  # `srv-docs.mount`; if Nextcloud were ordered against that unit, a missing
  # zdata/docs would stop the household's file sync, calendars and contacts
  # along with an unrelated document archive.  This unit requires
  # `srv-state.mount` and nothing else — which `nextcloud-dirs` already
  # requires — so it adds Nextcloud no dependency it did not already have.
  #
  # One directory, one declaring unit: the alternative, creating it from both
  # containers' own dirs units, is two declarations for one path and therefore
  # the M3 defect even when the two agree today.
  systemd.services.paperless-inbox = {
    description = "Create the shared scan-ingest directory for paperless and Nextcloud";
    wantedBy   = [ "multi-user.target" ];
    after      = [ "srv-state.mount" ];
    requires   = [ "srv-state.mount" ];
    before     = [ "container@paperless.service" "container@nextcloud.service" ];
    requiredBy = [ "container@paperless.service" "container@nextcloud.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.util-linux pkgs.coreutils ];
    script = ''
      set -eu

      # Same parent check as paperless-dirs, and for the same reason: a scan
      # queued onto zroot is a scan that disappears at the next boot, after the
      # phone reported the upload as a success.
      ssrc=$(findmnt --noheadings --output SOURCE --target /srv/state || true)
      if [ "$ssrc" != "zdata/state" ]; then
        echo "paperless-inbox: /srv/state is not zdata/state (found '$ssrc')." >&2
        echo "  Refusing to create the scan inbox on zroot." >&2
        exit 1
      fi

      install -d -o ${toString paperlessUid} -g ${toString paperlessGid} -m 0700 ${stateRoot}

      # ── EVERY BIT OF THIS MODE IS LOAD-BEARING ────────────────────────────
      #
      #   owner  315   paperless, which CONSUMES AND UNLINKS.  Unlinking needs
      #                write on the DIRECTORY, not on the file, which is what
      #                owning it provides.
      #   group  3042  docsin, which Nextcloud's uid is a member of, so the
      #                WebDAV write lands here at all.
      #   2770         setgid, so a file written by Nextcloud keeps group
      #                `docsin` instead of group `nextcloud` — otherwise
      #                paperless, in neither group, would be reading it on the
      #                `other` bits by luck.  cwa.nix:509-535, verbatim.
      #
      # ── THIS LINE IS AN OPENING BID AND NOT THE LAST WORD.  MEASURED. ─────
      #
      # An earlier version of this comment said `services.paperless` declares
      # no tmpfiles rule for a consumption directory it did not create.  THAT
      # WAS WRONG, and the first deploy (2026-10-05) proved it: the directory
      # came out `drwxrws--- 315:315` and Nextcloud's uid could not write to
      # it, so the second ingest door was dead while every unit read active.
      #
      # The module ships (paperless.nix:461-472):
      #
      #     defaultRule = { user = cfg.user; group = <cfg.user's group>; };
      #     "<cfg.consumptionDir>".d = defaultRule;
      #
      # (angle brackets rather than Nix interpolation syntax on purpose, and
      # the attribute name spelled out rather than quoted: this comment lives
      # inside a Nix indented-string literal, so a literal dollar-brace gets
      # interpolated and a doubled apostrophe ENDS THE STRING.  Both were
      # tried here, in that order.  A shell comment is not a comment to Nix.)
      #
      # `defaultRule` carries NO mode, which is exactly why the symptom was
      # confusing: systemd-tmpfiles left 2770 alone and changed only the
      # group, so the setgid bit survived and pointed at the wrong group.
      #
      # It runs INSIDE the container, through the bind, on every start — the
      # Immich `StateDirectoryMode` finding and nextcloud.nix's 0700-becomes-
      # 0750 finding in a third costume.  Upstream re-asserts after we set
      # ours, and upstream wins.
      #
      # So this line still has to exist, because the bind mount needs the path
      # to be there before EITHER container starts — and the in-container rule
      # is amended to agree with it rather than fought (see the
      # `systemd.tmpfiles.settings` override in the container config below).
      # The two declarations are kept deliberately identical; that is the M3
      # defect's shape, and the reason it is accepted here is that neither one
      # can be removed.
      #
      # containers/cwa.nix needs a whole `cwa-ingest-perms` unit to re-apply
      # this after every container start.  THIS FILE STILL DOES NOT, and the
      # difference is real: that unit exists because the path is bound into an
      # OPAQUE PODMAN IMAGE with no declarative handle on its tmpfiles. Here
      # there is one, so the fix is a two-line override rather than a polling
      # health-check loop.
      install -d -o ${toString paperlessUid} -g ${toString docsinGid} -m 2770 ${consumeDir}
    '';
  };

  # ── Stage the secrets where the container can see them ────────────────────
  #
  # ROTATING ANY OF THEM needs a restart, not just a deploy: this unit's script
  # embeds the sops PATH and not the contents, so systemd sees an unchanged unit
  # and does not re-run it.  Every generator therefore carries `restartUnits`.
  # By hand it is:
  #     systemctl restart paperless-secrets container@paperless
  systemd.services.paperless-secrets = {
    description = "Stage Paperless's secret key, admin password, OIDC secret and mneme token";
    after       = [ "local-fs.target" ];
    before      = [ "container@paperless.service" ];
    requiredBy  = [ "container@paperless.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      set -euo pipefail

      # 0711: traversable by anyone, listable by nobody.  The files inside are
      # read by the PAPERLESS uid, unprivileged, so it must be able to walk in;
      # 0700 root:root here produces EACCES with a message that names the file
      # rather than the directory.  See PR #84, which shipped that inversion
      # once.
      install -d -m 0711 -o root -g root ${secretsDir}

      install -m 0400 -o ${toString paperlessUid} -g ${toString paperlessGid} \
        ${adminGen.files."admin-pass".path} ${adminPassFile}

      install -m 0400 -o ${toString paperlessUid} -g ${toString paperlessGid} \
        ${mnemeGen.files."token".path} ${mnemeTokenDst}

      # ── The EnvironmentFile ───────────────────────────────────────────────
      #
      # Written under a tightened umask rather than chmod'ed afterwards: a
      # chmod leaves a window in which the file exists world-readable, which is
      # the finding machines/ernst/photo-import.sh records about its own
      # credential file.
      (
        umask 077
        {
          printf "PAPERLESS_SECRET_KEY='%s'\n" "$(cat ${secretGen.files."secret-key".path})"

          # ── OIDC, as ONE single-quoted JSON line ──────────────────────────
          #
          # `openid_connect` with an explicit `redirect_uri`, because
          # django-allauth otherwise derives one from the request it sees — and
          # what it sees is Traefik's plain-HTTP forward to 10.0.90.32, not
          # https://docs.goclan.org.  That is the same class of failure
          # `overwriteprotocol` fixes for Nextcloud, and it fails CLOSED at
          # Authelia as `invalid_redirect_uri`.
          #
          # SINGLE QUOTES, and the let block above has the measurement: bash's
          # `source` in the `paperless-manage` wrapper brace-expands an
          # unquoted value and silently eats every double quote in the JSON,
          # while systemd's EnvironmentFile reader strips the single quotes and
          # is happy either way.  Safe because the JSON contains no apostrophe.
          printf "PAPERLESS_SOCIALACCOUNT_PROVIDERS='%s'\n" \
            "{\"openid_connect\":{\"OAUTH_PKCE_ENABLED\":true,\"APPS\":[{\"provider_id\":\"authelia\",\"name\":\"Authelia\",\"client_id\":\"paperless\",\"secret\":\"$(cat ${oidcGen.files."paperless-client-secret".path})\",\"settings\":{\"server_url\":\"${autheliaIssuer}\",\"redirect_uri\":\"https://${hostName}/accounts/oidc/authelia/login/callback/\"}}]}}"
        } > ${envFile}
      )

      chown ${toString paperlessUid}:${toString paperlessGid} ${envFile}
    '';
  };

  ##############################################################################
  # Generators.  ALL THREE ARE GENERATED AND NONE IS PROMPTED.
  #
  # Standing note SN5 is the reason and it is not a style preference: `clan
  # machines update` runs generators for EVERY machine in the fleet, so one
  # pending prompt blocks every deploy — and a prompt left BLANK stores nothing,
  # makes `files.<n>.path` evaluate to the literal `/no-such-path`, kills any
  # consumer running under `set -eu`, and re-prompts on every later deploy,
  # which is fatal without a TTY.  That sequence took RomM down on 2026-09-07.
  ##############################################################################

  # Django's signing key.  2.x REQUIRES it and the 26.05 module does not
  # generate one — the runtime-generated `paperless-secret-key.service` is an
  # addition the v3 module carries, and ernst is not on that module.  Without
  # this the container runs on upstream's published default key, which is
  # equivalent to having none.
  clan.core.vars.generators.paperless-secret = {
    files."secret-key".secret = true;
    files."secret-key".restartUnits = [
      "paperless-secrets.service"
      "container@paperless.service"
    ];
    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
    script = ''
      openssl rand -base64 64 | tr -d '\n=+/' | cut -c1-64 > "$out/secret-key"
    '';
  };

  # The local superuser, and the RECOVERY PATH — the login that still works
  # when Authelia, the client registration or Traefik is what is broken.  Read
  # it when it is needed:
  #
  #     clan vars get ernst paperless-admin/admin-pass
  #
  # Generated and not prompted precisely BECAUSE it is the recovery path: it
  # should be long and it should not be memorable.  `tr -d '=+/'` because this
  # gets typed into a login form and pasted into shell one-liners, where the
  # base64 punctuation buys nothing and costs quoting mistakes.
  clan.core.vars.generators.paperless-admin = {
    files."admin-pass".secret = true;
    files."admin-pass".restartUnits = [
      "paperless-secrets.service"
      "container@paperless.service"
    ];
    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
    script = ''
      openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-48 > "$out/admin-pass"
    '';
  };

  # ── mneme's API token ──────────────────────────────────────────────────────
  #
  # Consumed by M32b.  It is generated HERE rather than read out of paperless
  # after the fact, because the alternative is a prompt — and a DRF token is
  # exactly the kind of runtime credential that would otherwise have to be
  # copied out of a UI by hand and pasted into a prompt that then blocks the
  # fleet.  `paperless-provision` below writes this value INTO the database, so
  # the generator is the source of truth in both directions.
  #
  # 40 lowercase hex characters, which is the shape rest_framework's
  # `Token.generate_key` produces (`binascii.hexlify(os.urandom(20))`).  It is
  # not validated anywhere, but matching the shape means a token in a log looks
  # like what it is.
  clan.core.vars.generators.paperless-mneme-token = {
    files."token".secret = true;
    files."token".restartUnits = [
      "paperless-secrets.service"
      "container@paperless.service"
      # mneme is a HOST service and reads this file directly, so rotating the
      # token has to bounce it too.  Harmless while M32b is unbuilt — a
      # restartUnit naming a unit that does not exist yet is not an error.
      "mneme.service"
    ];
    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
    script = ''
      openssl rand -hex 20 | tr -d '\n' > "$out/token"
    '';
  };

  ##############################################################################
  # Host side of the veths.
  ##############################################################################

  # The VLAN-90 leg — a bridge port on br0.  Identical rationale to
  # vb-nextcloud / vb-immich / vb-jellyfin; containers/traefik.nix carries the
  # long form of KeepMaster-not-Bridge and why a bridge port holds no address.
  systemd.network.networks."60-vb-paperless" = {
    matchConfig.Name = "vb-paperless";
    networkConfig = {
      KeepMaster          = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = 90; PVID = 90; EgressUntagged = 90; } ];
    linkConfig.RequiredForOnline = "enslaved";
  };

  # ── THERE IS DELIBERATELY NO HOST-SIDE NETWORK FOR `doc0` ─────────────────
  #
  # MEASURED, and it cost this container four restarts on its first deploy
  # (2026-10-05).  An earlier draft declared
  #
  #     systemd.network.networks."60-doc0" = {
  #       matchConfig.Name = docVeth;
  #       address = [ "${docHost}/128" ];
  #       routes  = [ { Destination = "${docCont}/128"; Scope = "link"; } ];
  #       ...
  #
  # on the reasoning that a leg needs configuring at both ends.  It does not:
  # `containers.<n>.extraVeths.<v>.hostAddress6` is what nspawn's
  # `--network-veth-extra` consumes, and the nixos-containers module assigns
  # the HOST end from it directly.  Declaring it again in networkd means two
  # things racing to own one address, and the loser is the container:
  #
  #     Error: ipv6: address already assigned.
  #     container@paperless.service: Control process exited,
  #                                  code=exited, status=2/INVALIDARGUMENT
  #
  # — a restart loop whose message names neither the veth nor this file.  The
  # container booted far enough each time to start paperless, Tika and
  # Gotenberg, so the only outward symptom was a 90-second stop job.
  #
  # The check that would have caught it is `grep -rn '60-mon0\|60-ai1\|60-web0'`
  # over the repo: NONE of the four existing ULA legs has a host-side network,
  # and that absence is the pattern rather than an omission.  The CONTAINER
  # side does get one — `20-doc0` below, which matches `20-ai1` and `20-web0`
  # exactly — because the container's networkd has no `extraVeths` to read.
  #
  # Only VLAN legs (`vb-*`, `iot0`, `iot1`) take a `60-*` network, and that is
  # what the `Bridge`-versus-`KeepMaster` note in
  # machines/ernst/networking.nix is about.  It does not apply here.

  # Same VLAN race, same idempotent backstop, same "-" prefix as every other
  # nspawn container on br0: networkd applies [BridgeVLAN] only once it observes
  # the link's master, and nspawn sets that master out of band.  With
  # DefaultPVID = "none" on br0 a miss is fail-CLOSED.
  # `bridge vlan show dev vb-paperless` is the check.
  systemd.services."container@paperless".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev vb-paperless vid 90 pvid untagged"
  ];

  ##############################################################################
  # The container.
  ##############################################################################
  containers.paperless = {
    autoStart = true;
    ephemeral = false;

    # MAC from the allocation table in machines/ernst/networking.nix; the DHCP
    # reservation 10.0.90.32 on the UDM-Pro keys on it (manual step).  Sequence
    # 18, and the last octet is 8 + seq as everywhere else on this bridge.
    #
    # The name is `paperless` and not something longer for the reason `hass` and
    # `mass` are what they are: nspawn names the host side `vb-<container>` and
    # a Linux interface name caps at 15 characters.  `vb-paperless` is 12.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = "02:00:00:90:00:18";

    # Declared here so the veth and its row in networking.nix's assertion land
    # together.  The host end is configured above; the container end is below.
    extraVeths.${docVeth} = {
      hostAddress6  = docHost;
      localAddress6 = docCont;
    };

    bindMounts = {
      # The archive and the originals.
      "${mediaDir}" = {
        hostPath   = mediaDir;
        isReadOnly = false;
      };

      # The consumption directory, shared with Nextcloud and created by
      # `paperless-inbox` rather than by `paperless-dirs`.
      "${consumeDir}" = {
        hostPath   = consumeDir;
        isReadOnly = false;
      };

      # The exporter's output.  Inside /srv/docs on purpose, so it is covered by
      # the same `com.sun:auto-snapshot=true` as the archive it protects.
      "${exportDir}" = {
        hostPath   = exportDir;
        isReadOnly = false;
      };

      # The index, the classifier model and the logs.
      "${dataDir}" = {
        hostPath   = dataDir;
        isReadOnly = false;
      };

      # The database.  The PARENT is bound, not the version subdirectory, so a
      # future PostgreSQL major bump lands beside the old one on zdata instead
      # of on the container's rootfs.
      "/var/lib/postgresql" = {
        hostPath   = "${stateRoot}/postgresql";
        isReadOnly = false;
      };

      "${secretsDir}" = {
        hostPath   = secretsDir;
        isReadOnly = true;
      };
    };

    config = { config, pkgs, lib, ... }: {
      # Pins the PostgreSQL major through `services.postgresql.package`'s
      # stateVersion-derived default, which is the thing that must not move
      # under a running database.
      system.stateVersion = "26.05";

      ##########################################################################
      # Networking — two legs.
      ##########################################################################
      networking.useHostResolvConf = false;
      networking.useNetworkd = true;
      services.resolved.enable = true;

      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          DNS          = "10.0.5.3";
          Domains      = "~. skynet.lan";
          IPv6AcceptRA = false;
          # SN2: v4 only on this leg.  M18 measured that IPv6AcceptRA alone
          # blocks an RA but NOT link-local assignment; this is the line that
          # actually makes `ip -6 addr show dev eth0` empty.
          LinkLocalAddressing = "no";
        };
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      # The `doc0` end.  A single /128 with a link-scope route back to the host
      # end and nothing else — no RA, no default route, no DNS.
      systemd.network.networks."20-${docVeth}" = {
        matchConfig.Name = docVeth;
        address = [ "${docCont}/128" ];
        routes  = [ { Destination = "${docHost}/128"; Scope = "link"; } ];
        networkConfig.IPv6AcceptRA = false;
        # No carrier until the host end exists.
        linkConfig.RequiredForOnline = "no";
      };

      # Same 20 s cap as every sibling: a DHCP failure must leave a RUNNING
      # container with one failed unit, not a host-side restart loop.
      systemd.network.wait-online.timeout = 20;

      # ── The container firewall — the only enforcement point for br0-local
      #    traffic, since those frames are one L2 hop and the UDM-Pro never
      #    sees them.
      #
      #   28981/tcp from Traefik, over v4.  Every human client arrives through
      #             the proxy.
      #   28981/tcp from fdca:fe95::1, over v6.  That is mneme, on the host,
      #             and it is the ONLY thing that reaches this service without
      #             going through Traefik.
      #
      # extraCommands, not extraInputRules: the latter is declared
      # unconditionally but consumed only under networking.nftables, so here it
      # would produce no rule and no warning.
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands = ''
        iptables  -A nixos-fw -p tcp -s ${traefikAddr}/32 --dport ${toString paperlessPort} -j nixos-fw-accept
        ip6tables -A nixos-fw -p tcp -s ${docHost}/128     --dport ${toString paperlessPort} -j nixos-fw-accept
      '';

      ##########################################################################
      # The service.
      ##########################################################################
      services.paperless = {
        enable = true;

        # ── `::` AND NOT `0.0.0.0`, AND THE DIFFERENCE IS A REAL BUG ────────
        #
        # This becomes GRANIAN_HOST.  Traefik arrives over IPv4 on eth0 and
        # mneme arrives over IPv6 on `doc0`, so a `0.0.0.0` bind would serve
        # the browser and give the agent ECONNREFUSED on a leg that looks
        # correctly configured from both ends — the `ai0` class of failure,
        # where the socket is up and the only symptom is silence.
        #
        # MEASURED, not reasoned, against the granian 2.7.4 in this very pin
        # (`granian --interface asgi --host :: --port 28991`):
        #
        #     ss -ltn          ->  LISTEN  *:28991  *:*
        #     curl 127.0.0.1   ->  HTTP 200
        #     curl [::1]       ->  HTTP 200
        #
        # So one listener covers both families: granian does not set
        # IPV6_V6ONLY, and `net.ipv6.bindv6only` is 0 on Linux with NixOS not
        # changing it.  If a future granian starts setting V6ONLY the symptom
        # is Traefik getting a 502 while mneme keeps working, and the fix is
        # two listeners rather than one.
        address = "::";
        port    = paperlessPort;

        inherit dataDir mediaDir;
        consumptionDir = consumeDir;

        # Local PostgreSQL over the unix socket.
        #
        # THIS FILE THEREFORE DECLARES NO DATABASE PASSWORD, the same call
        # containers/immich.nix and nextcloud.nix make: socket connections use
        # peer authentication, and a credential that is never checked is a
        # credential that should not exist.
        database.createLocally = true;

        # ── OFFICE FILES, which is one of the three requirements ───────────
        #
        # Brings up Tika (content extraction) and Gotenberg (LibreOffice ->
        # PDF), both of which the module wires by their own endpoint options.
        # NEITHER TAKES A uid AND NEITHER IS EXPOSED: `services.tika` defaults
        # to listenAddress 127.0.0.1 and `services.gotenberg` to bindIP
        # 127.0.0.1, both inside this container, and both run `DynamicUser`
        # with nothing on zdata — reason (c) in networking.nix's "takes no uid"
        # list.  It costs a Chromium and a LibreOffice in the closure.
        configureTika = true;

        passwordFile = adminPassFile;
        environmentFile = envFile;

        # ── The exporter, which is the only non-ZFS protection here ─────────
        #
        # Writes the originals plus a metadata JSON that restores WITHOUT
        # paperless, which is what distinguishes it from a snapshot of the
        # database.
        #
        # ⚠ IT STOPS THE PAPERLESS SERVICES WHILE IT RUNS (the unit lists them
        # in `Conflicts`), so the hour is chosen rather than defaulted: 02:30
        # is after the household is asleep and clear of the 01:30 default,
        # which exists to collide with nothing in particular.
        exporter = {
          enable = true;
          directory = exportDir;
          onCalendar = "02:30:00";
        };

        settings = {
          # ALLOWED_HOSTS and CSRF_TRUSTED_ORIGINS are both derived from this.
          # Without it the login POST is refused as a CSRF failure, which
          # presents as a form that silently does nothing.
          PAPERLESS_URL = "https://${hostName}";

          # Traefik terminates TLS and forwards plain HTTP, so Django has to be
          # told how to recognise that the original request was https.  The
          # OIDC redirect depends on it, and so does every absolute URL
          # paperless generates.  Rendered as a JSON array by the module, which
          # JSON-encodes any list or attrset in `settings`.
          PAPERLESS_PROXY_SSL_HEADER = [ "HTTP_X_FORWARDED_PROTO" "https" ];

          # German first: the household's paper is German, and tesseract tries
          # the languages in the order given.  No package override is needed —
          # the default `tesseract5` carries every language, and the
          # `tesseract5 may be overwritten` comment in the paperless package is
          # about SHRINKING that closure, not about adding to it.
          PAPERLESS_OCR_LANGUAGE = "deu+eng";

          # `skip` leaves a PDF that already has a text layer alone instead of
          # rasterising and re-OCRing it.  For a household that mixes phone
          # scans with downloaded invoices this is most of the corpus.
          PAPERLESS_OCR_MODE = "skip";

          # ── POLLING, NOT inotify, AND THIS IS THE ONE SETTING MOST LIKELY
          #    TO BE "TIDIED UP" LATER ──────────────────────────────────────
          #
          # The inbox is a host directory, bind-mounted in, written by a
          # DIFFERENT PRINCIPAL (Nextcloud, over WebDAV).
          # modules/immich-upload.nix:29-44 is this fleet's own argument
          # against inotify on an ingest directory: it reports a file the
          # moment it APPEARS, which for an upload in flight is while it is
          # still being written — and a partial PDF consumes perfectly
          # happily into a corrupt document with a valid checksum, so the
          # retry-on-next-run safety net never catches it either.
          #
          # Polling re-stats until the size stops changing.  60 s is the
          # latency the household sees between sharing a scan and it
          # appearing, which is well inside "smooth".
          PAPERLESS_CONSUMER_POLLING = 60;

          PAPERLESS_TIME_ZONE = "Europe/Berlin";

          # A human-navigable archive tree, which matters here more than it
          # looks: ZFS snapshots are the backup, and a snapshot is only as
          # useful as the layout inside it.  `{created_year}/{correspondent}`
          # means a recovery can be done with `cp` and without paperless.
          PAPERLESS_FILENAME_FORMAT = "{created_year}/{correspondent}/{title}";

          # Loads django-allauth's OIDC provider.  The provider CONFIG, which
          # carries the client secret, is in the EnvironmentFile instead.
          PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";

          # ── THE THREE SIGNUP SWITCHES, WHICH ARE INDEPENDENT ───────────────
          #
          # Read out of src/paperless/settings.py:507-526 at this exact
          # version rather than from the docs, because the two that matter
          # pull in opposite directions and `__get_boolean` defaults to "NO"
          # for all but one of them:
          #
          #   ACCOUNT_ALLOW_SIGNUPS        default NO   self-registration form
          #   SOCIALACCOUNT_ALLOW_SIGNUPS  default YES  account creation via OIDC
          #   SOCIALACCOUNT_AUTO_SIGNUP    default NO   skip the intermediate form
          #
          # So an Authelia identity materialises as a paperless account on
          # first login — which is how Sabine gets one without a row in this
          # repo, the same effect as Nextcloud's `--unique-uid=0` mapping —
          # while the public self-registration form stays shut.  Turning the
          # first one off does NOT turn the second one off; they are separate
          # settings and conflating them would lock her out.
          PAPERLESS_SOCIAL_AUTO_SIGNUP = true;

          # Already the default.  Pinned anyway, because "nobody can register
          # themselves on a WAN-exposed hostname" is a property worth being
          # able to grep for rather than infer from an absence.
          PAPERLESS_ACCOUNT_ALLOW_SIGNUPS = false;

          # ── THE LOCAL LOGIN FORM STAYS ─────────────────────────────────────
          #
          # `PAPERLESS_DISABLE_REGULAR_LOGIN` is deliberately NOT set, and its
          # default is NO.  Keeping the password form is what makes the
          # generated admin above an actual recovery path rather than a
          # decoration — Nextcloud's `allow_multiple_user_backends` argument,
          # applied here.  Same for `PAPERLESS_REDIRECT_LOGIN_TO_SSO`: a login
          # page that redirects straight to a portal is useless on the day the
          # portal is what is broken.

          # OCR is CPU-bound and this machine is shared — llama-server has the
          # dGPU, Jellyfin transcodes on the iGPU, and both compete for memory
          # bandwidth with whatever is scanning.  Two workers is Karakeep's
          # `INFERENCE_NUM_WORKERS = 1` reasoning in CPU form: a 40-page scan
          # should not pin the box.
          PAPERLESS_TASK_WORKERS = 2;
        };
      };

      # ── Pin the ids ───────────────────────────────────────────────────────
      #
      # The uid/gid are NOT set here, and the let block says why at length:
      # the module assigns `ids.uids.paperless` = 315 itself, and a second
      # definition is an evaluation conflict rather than an override.  What
      # this block does is the group membership that the shared inbox needs.
      users.groups.docsin.gid = docsinGid;
      users.users.paperless.extraGroups = [ "docsin" ];

      # ── AND THE RULE THAT WOULD OTHERWISE UNDO THE INBOX'S GROUP ──────────
      #
      # `services.paperless` declares the consumption directory in its own
      # `systemd.tmpfiles.settings."10-paperless"` with
      # `group = <paperless's own group>` and no mode.  That runs on every
      # container start, through the bind, and chowns the shared inbox back to
      # `paperless:paperless` — which leaves the setgid bit pointing at a group
      # Nextcloud is not in, so the WebDAV write fails with EACCES and the
      # Nextcloud ingest door silently stops working.
      #
      # Measured on the first deploy; `install -d` on the host had already set
      # 315:3042 and the live directory was still 315:315.
      #
      # THIS AMENDS UPSTREAM'S RULE RATHER THAN ADDING A SECOND ONE, which is
      # the distinction that keeps it out of M3-defect territory: there is
      # still exactly one tmpfiles entry for this path, and `mkForce` changes
      # the group it names.  A competing `systemd.tmpfiles.rules` line would be
      # two rules for one path taking turns winning, one per deploy.
      #
      # The mode is set here too, even though upstream's rule omits it, so the
      # in-container declaration is complete on its own instead of depending on
      # the host-side `install -d` having run first and left 2770 behind.
      systemd.tmpfiles.settings."10-paperless".${consumeDir}.d = {
        group = lib.mkForce "docsin";
        mode  = "2770";
      };

      ##########################################################################
      # ── Provisioning that only the Django layer can express ────────────────
      #
      # One thing paperless keeps in its DATABASE rather than in a setting, so
      # it is unreachable from `settings` above: mneme's API token, and the
      # read-only account it belongs to.
      #
      # It is an UPSERT — `update_or_create` both times — so this unit is
      # idempotent across deploys by construction rather than by a stamp file.
      # A stamp file would be worse than nothing: it would claim the account
      # exists after somebody deleted it in the admin UI.
      ##########################################################################
      systemd.services.paperless-provision = {
        description = "Provision mneme's read-only paperless account and API token";
        wantedBy = [ "multi-user.target" ];
        after    = [ "paperless-web.service" "paperless-scheduler.service" ];
        requires = [ "paperless-scheduler.service" ];

        # It retries because the migrations it depends on run in
        # paperless-scheduler's own start, and losing that race on a cold boot
        # is the expected case rather than the exceptional one.  It gives up
        # after ten tries over ten minutes and STAYS FAILED, which is
        # deliberate: `ContainerSystemdUnitFailed` sees failed units inside
        # nspawn containers within a minute, so a genuine misconfiguration
        # alerts instead of being retried forever in silence.
        #
        # The visible symptom of this unit never succeeding is `document_search`
        # returning HTTP 401 once M32b is built.  Nothing a human uses breaks.
        startLimitIntervalSec = 600;
        startLimitBurst = 10;

        serviceConfig = {
          Type            = "oneshot";
          RemainAfterExit = true;
          Restart         = "on-failure";
          RestartSec      = "60s";
          User  = "paperless";
          Group = "paperless";
        };
        path = [ config.services.paperless.manage pkgs.coreutils ];
        script = ''
          set -euo pipefail
          paperless-manage shell < ${provisionScript}
        '';
      };

      # `curl` is the test plan's instrument for proving this backend is
      # reachable from Traefik and from mneme, and from nowhere else.
      environment.systemPackages = with pkgs; [ curl ];
      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
