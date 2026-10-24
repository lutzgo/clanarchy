# machines/ernst/containers/nextcloud.nix
#
# Nextcloud — the household file-sync, calendar and contacts server (M23 in
# docs/history.md).  An nspawn container on VLAN 90, serving
# `cloud.goclan.org` through Traefik on BOTH entrypoints, with its own
# accounts, no forward-auth, and Authelia as an OIDC provider for the browser.
#
# ── WHAT THIS REPLACES ──────────────────────────────────────────────────────
#
#   The hosted instance at citizengo.io.  M22b already pulled its PHOTO corpus
#   into Immich (see containers/immich.nix, the `nextcloud` import sets); what
#   is left over there is the file tree the desktop sync clients point at, and
#   the CalDAV endpoint modules/caldav-sync.nix pushes lgo's org VTODOs to.
#   This container is what lets that instance be turned off.
#
#   IT STANDS UP EMPTY.  Nothing here downloads anything from citizengo.io —
#   migrating the remaining file corpus is its own milestone, exactly as M22b
#   was for the photographs, and for the same reason: choosing what comes
#   across is a triage decision and not a script.
#
# ── WHY THE nspawn TIER ─────────────────────────────────────────────────────
#
#   `services.nextcloud` is a first-class NixOS module.  The podman tier here
#   exists for upstreams that ship only an OCI image (storyteller, cwa, romm,
#   tubesync) and Nextcloud is not one of them.  An internet-facing service
#   does not move up a tier for being internet-facing; it moves up for needing
#   its own kernel.  containers/immich.nix argues this at length and this file
#   takes the same side for the same reason.
#
# ── NO forward-auth ON THIS HOSTNAME, AND IT IS NOT A CONVENIENCE ───────────
#
#   `cloud.goclan.org` is in `appApiHosts` (containers/ingress-policy.nix).
#   The test that file states is whether EVERY client of the hostname can
#   render a login page and follow a 302, and here three cannot:
#
#     * the Nextcloud desktop sync client on miralda, jens and biene
#       (modules/desktop/noctalia-hm.nix already installs it), which
#       authenticates with an app password over /remote.php/dav/**;
#     * DAVx5 on the phones, same protocol, no browser at all;
#     * vdirsyncer, run headless from a user timer on miralda.
#
#   So the vhost is answered by Nextcloud, not by Authelia — and the BROWSER
#   path gets its second factor from Authelia's OIDC provider instead.  That is
#   Calibre-Web-Automated's arrangement (containers/cwa.nix), NOT Grafana's or
#   Open WebUI's: those two are behind forward-auth AND take OIDC, because the
#   middleware decides whether the request arrives and OIDC decides whose it
#   is.  Here OIDC is INSTEAD OF the middleware.  Do not merge the two
#   reasonings; containers/authelia.nix says so at the client block.
#
#   The compensating controls `appApiHosts` demands are, in order: Nextcloud's
#   own accounts, `wan-ratelimit` + `wan-inflight`, CrowdSec reading Traefik's
#   access log, and Nextcloud's OWN brute-force throttle — which is real, on by
#   default, and depends entirely on `trusted_proxies` below being right.  See
#   the note there; it is the one line in this file that turns a control into
#   a decoration if it is wrong.
#
# ── WHAT IS DELIBERATELY NOT HERE ───────────────────────────────────────────
#
#   `services.nextcloud.notify_push` — the push daemon that lets desktop
#   clients stop polling.  It is genuinely wanted and it does not work behind
#   this proxy as configured: `notify_push.nextcloudUrl` defaults to
#   `https://${hostName}`, and its `bendDomainToLocalhost` escape points that
#   name at 127.0.0.1 — where nothing listens on 443, because the container's
#   nginx terminates plain HTTP on 80 and TLS is Traefik's job.  Enabling it
#   would need a second local listener whose only purpose is to satisfy a
#   self-test.  Recorded as a decision rather than an oversight; it is a
#   follow-on, not a defect.
#
#   A Prometheus scrape target.  Nextcloud's serverinfo endpoint is
#   token-authenticated JSON, not an OpenMetrics exposition, so a job pointed
#   at it could only ever be `up == 0` — which is M13's Ollama lesson, and
#   service-modules/monitoring.nix is disciplined about not adding targets that
#   cannot work.  What this container DOES get for free, because it is nspawn
#   and `machinectl` can see it, is `ContainerSystemdUnitFailed`: any failed
#   unit inside it is a host-side metric within a minute.  That is the alerting
#   story here, and it is enough for a first deploy.
{
  config,
  pkgs,
  lib,
  ...
}: let
  ##############################################################################
  # Identity.
  ##############################################################################
  # From machines/ernst/allocations.nix.  OWN group, not
  # `media` — `media` is a SECONDARY membership below, for the external storage
  # mount, and making it primary would put the media gid on every file the
  # service writes into its own store.
  #
  # PINNING IT IS LOAD-BEARING, not hygiene, for exactly the reason Immich's
  # row in that table gives: the nixpkgs module creates `nextcloud` with
  # `isSystemUser = true` and no uid, and nspawn passes ids through UNMAPPED,
  # so whatever the container's useradd happens to pick is the number that ends
  # up on every file in /srv/nextcloud.  Adding an unrelated user to this
  # container could otherwise change the owner of the household's file store.
  nextcloudUid = 3037;
  nextcloudGid = 3037;

  # Not ours to choose: a well-known NixOS static id (`ids.uids.postgres`).  It
  # lands on zdata unmapped like every other container uid here.  The
  # 3000-block convention does not apply to it and it must not be renumbered
  # into the block.
  postgresUid = 71;
  postgresGid = 71;

  # The host-side media group from containers/jellyfin.nix, restated here
  # because a container config is its own NixOS evaluation and cannot read the
  # host's option tree.  This is the "group-add, not a chown" that jellyfin.nix
  # anticipated when it created the group.
  mediaGid = 3000;

  ##############################################################################
  # Peers, ports and paths.
  ##############################################################################

  # The one VLAN-90 peer allowed to reach this service.  Every client — the
  # laptops' sync agents, the phones, a browser, vdirsyncer — arrives through
  # it.  This is M5's backend-bypass hardening, mechanism (a).
  traefikAddr = "10.0.90.12";

  # Plain HTTP on 80, terminated by the container's own nginx.  TLS is
  # Traefik's, once, at the edge, with the *.goclan.org wildcard it already
  # holds — nothing here requests a certificate.
  nextcloudPort = 80;

  baseDomain = "goclan.org";
  hostName = "cloud.${baseDomain}";

  # Authelia's portal, as the OIDC issuer.  Restated rather than shared for the
  # same reason baseDomain is restated in traefik.nix and authelia.nix.
  autheliaIssuer = "https://auth.${baseDomain}";

  # THE TWO DATASETS, SPLIT FOR THE REASON IMMICH SPLIT ITS OWN: a 1M
  # recordsize is right for a bulk file store and wrong for PostgreSQL.
  #
  # zdata/nextcloud holds config/, data/ and store-apps/ — the module's whole
  # `home`.  recordsize is a MAXIMUM, not a quantum, so the small files in
  # config/ cost nothing there; what it buys is that a 4 GB upload is not
  # 32,768 records.  Nextcloud writes user files whole over WebDAV and never
  # does an in-place partial rewrite of a large one, which is the access
  # pattern that would make 1M the wrong answer.
  dataRoot = "/srv/nextcloud";
  stateRoot = "/srv/state/nextcloud";

  # The media library, bound in READ-ONLY as external storage.  Read-only at
  # the NSPAWN level rather than as a files_external option, because a mount
  # flag is enforced by the kernel and an app setting is enforced by whatever
  # the app believes about itself.
  mediaRoot = "/srv/media";

  # ── THE SCAN INBOX (M32) ───────────────────────────────────────────────────
  #
  # This is paperless's CONSUMPTION DIRECTORY, mounted here as writable
  # external storage so that "FairScan → Share → Nextcloud" lands a scan where
  # paperless will pick it up.  FairScan has no cloud of its own; it shares a
  # PDF to another app or saves into a folder a storage app provides, and this
  # household already has the Nextcloud app on both phones with an account
  # each.  So the cheapest door is the one that needs no new app and no new
  # login — and upstream is going the same way, having replaced the Nextcloud
  # Android app's own scanner with FairScan in nextcloud/android#17710.
  #
  # UNLIKE mediaRoot THIS ONE IS WRITABLE, which is the whole point, so the
  # kernel-enforced boundary that `isReadOnly` provides there is not available
  # here.  What bounds it instead is the directory's mode: 2770
  # paperless:docsin, with this container's service user a member of `docsin`
  # below.  Nextcloud can write into that one directory and nowhere else,
  # because its parent /srv/state/paperless is 0700 owned by uid 315 and is NOT
  # bound in.
  #
  # ── IT IS ON /srv/state AND NOT ON /srv/docs, FOR THIS CONTAINER'S SAKE ───
  #
  # A bind mount whose host path does not exist is a container that does not
  # start.  Under /srv/docs, a missing zdata/docs would therefore have taken
  # THE HOUSEHOLD'S FILE SYNC, CALENDARS AND CONTACTS down with an unrelated
  # service's dataset.  The shared path lives where both users already depend
  # on it instead: `nextcloud-dirs` below already requires `srv-state.mount`,
  # so this costs this container no dependency it did not have.
  #
  # Created by `paperless-inbox.service` in containers/paperless.nix — a unit
  # deliberately separate from `paperless-dirs` so that it carries only the
  # dependencies BOTH containers share.  That is also why it is not created
  # here: one directory, one declaring unit.
  #
  # FILES VANISH FROM IT, AND THAT IS CORRECT: paperless consumes and unlinks.
  # Making Nextcloud notice is what the `filesystem_check_changes` option in
  # `nextcloud-provision` is for — without it this folder would show scans that
  # no longer exist.
  docsInbox = "/srv/state/paperless/inbox";

  # The shared ingest group from containers/paperless.nix, restated here
  # because a container config is its own NixOS evaluation and cannot read the
  # host's option tree — the same reason `mediaGid` is restated above.
  docsinGid = 3042;

  ##############################################################################
  # Secrets staging.
  #
  # NOT a bind of /run/secrets itself: that path is a symlink to a
  # per-generation directory which is REPLACED on every deploy, so an nspawn
  # bind established at container start would keep exposing a deleted
  # generation.  A directory we own has a stable identity and is rewritten in
  # place.  containers/traefik.nix carries the long form of this.
  ##############################################################################
  secretsDir = "/run/nextcloud-secrets";
  adminPassFile = "${secretsDir}/admin-pass";
  oidcSecretFile = "${secretsDir}/oidc-client-secret";
  smtpSecretFile = "${secretsDir}/smtp.json";

  # noreply@'s password, declared in containers/mail.nix beside the mailbox it
  # belongs to.  Both containers are on ernst, so a per-machine var reaches
  # both — this is the same reach-across every consumer makes for the OIDC
  # pairs in containers/authelia.nix.
  systemSenderGen = config.clan.core.vars.generators.mail-system-sender;

  # The mail server (M31).  Reached BY NAME and not by address, because the
  # certificate is issued for `mail.goclan.org` and Technitium resolves it to
  # 10.0.90.31 from inside this container (verified) — pointed at the bare
  # address, TLS fails on a name mismatch.
  mailHost = "mail.goclan.org";

  adminGen = config.clan.core.vars.generators.nextcloud-admin;

  # Declared in containers/authelia.nix, beside the other relying parties —
  # ONE GENERATOR PER RELYING PARTY is that file's rule, and it is why this
  # reaches across rather than declaring its own.  Authelia takes the DIGEST;
  # this container takes the PLAINTEXT half of the same pair.
  oidcGen = config.clan.core.vars.generators.authelia-oidc-nextcloud;
in {
  ##############################################################################
  # Host side — the datasets, the directories, the secrets and the veth.
  ##############################################################################

  # ── NO tmpfiles RULES IN THIS FILE, AND containers/immich.nix IS WHY ───────
  #
  # That file records the measured failure: three of its four host-side
  # directories shipped as `systemd.tmpfiles.rules` and the container died
  # five times into its start limit with
  #
  #     systemd-nspawn: Failed to clone /srv/state/immich/ml-cache:
  #                     No such file or directory
  #
  # because activating a new configuration does not re-run
  # systemd-tmpfiles-setup.service in time for a container the same activation
  # starts.  Every host-side directory this container binds therefore belongs
  # to the ordered unit below, and NONE of them is also a tmpfiles rule — two
  # declarations for one path is the M3 defect, where two rules that disagree
  # about mode take turns winning, one per deploy.

  # ── Stage the secrets where the container can see them ────────────────────
  #
  # ROTATING EITHER OF THEM needs a restart, not just a deploy: this unit's
  # script embeds the sops PATH and not the contents, so systemd sees an
  # unchanged unit and does not re-run it.  Both generators therefore carry
  # `restartUnits`, which is what makes `clan vars generate ernst` +
  # `clan machines update ernst` sufficient.  By hand it is:
  #     systemctl restart nextcloud-secrets container@nextcloud
  systemd.services.nextcloud-secrets = {
    description = "Stage Nextcloud's admin password and OIDC secret for container@nextcloud";
    after = ["local-fs.target"];
    before = ["container@nextcloud.service"];
    requiredBy = ["container@nextcloud.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.coreutils];
    script = ''
      set -euo pipefail

      # 0711: traversable by anyone, listable by nobody.  The files inside are
      # read by the NEXTCLOUD uid, unprivileged — nextcloud-setup.service runs
      # as `nextcloud`, not as PID 1 — so it must be able to walk in, and
      # 0700 root:root here would produce EACCES on every one of them with a
      # message that names the file rather than the directory.  See PR #84,
      # which shipped that inversion once.
      install -d -m 0711 -o root -g root ${secretsDir}

      install -m 0400 -o ${toString nextcloudUid} -g ${toString nextcloudGid} \
        ${adminGen.files."admin-pass".path} ${adminPassFile}

      install -m 0400 -o ${toString nextcloudUid} -g ${toString nextcloudGid} \
        ${oidcGen.files."nextcloud-client-secret".path} ${oidcSecretFile}

      # ── The SMTP password, as JSON for `services.nextcloud.secretFile` ────
      #
      # NOT as a `settings` entry: that attrset is rendered into config.php
      # through the Nix store, which is world-readable on this host. The
      # module's `secretFile` exists for exactly this — a JSON blob merged
      # into config.php at activation, in the same shape as `settings`.
      #
      # Written through .tmp + mv so a half-written file is never read: unlike
      # the two installs above, this one is BUILT here rather than copied, so
      # there is a window to get wrong.
      umask 077
      printf '{"mail_smtppassword":"%s"}\n' \
        "$(cat ${systemSenderGen.files."noreply.plain".path})" > ${smtpSecretFile}.tmp
      chown ${toString nextcloudUid}:${toString nextcloudGid} ${smtpSecretFile}.tmp
      chmod 0400 ${smtpSecretFile}.tmp
      mv -f ${smtpSecretFile}.tmp ${smtpSecretFile}
    '';
  };

  # ── The admin password ────────────────────────────────────────────────────
  #
  # GENERATED, NOT PROMPTED, and read out of sops when it is needed:
  #
  #     clan vars get ernst nextcloud-admin/admin-pass
  #
  # A prompt here would be a password a human chose for an account that is the
  # RECOVERY PATH — the local login that still works when Authelia, the OIDC
  # client registration, or Traefik is what is broken.  It should be long and
  # it should not be memorable.
  #
  # `tr -d '=+/'` because this string is typed into a login form and pasted
  # into shell one-liners; the base64 punctuation buys nothing here and costs
  # quoting mistakes.  32 bytes of entropy survive it comfortably.
  clan.core.vars.generators.nextcloud-admin = {
    files."admin-pass".secret = true;
    files."admin-pass".restartUnits = [
      "nextcloud-secrets.service"
      "container@nextcloud.service"
    ];
    runtimeInputs = [pkgs.coreutils pkgs.openssl];
    script = ''
      openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-48 > "$out/admin-pass"
    '';
  };

  ##############################################################################
  # The container.
  ##############################################################################
  #
  # modules/containers/nspawn.nix generates the dirs unit (with BOTH mount
  # guards), the host-side veth network, the VLAN backstop, the container
  # preamble, the in-container networking and the firewall.
  #
  # `nextcloud-secrets` above STAYS HAND-WRITTEN, deliberately: it writes JSON
  # for Nextcloud's `secretFile`, not the `KEY=value` env file the module's
  # `secrets` option generates. A second format for one consumer would be
  # generality bought on speculation.
  clanarchy.containers.nextcloud = {
    enable = true;
    mac = "02:00:00:90:00:12";

    uid = nextcloudUid;
    gid = nextcloudGid;
    user = "nextcloud";

    # PINNED, AND LOAD-BEARING: `services.postgresql.package` derives its
    # default from this, so the value is the database's major version. A bump
    # is a deliberate edit plus a dump/restore, never a side effect.
    stateVersion = "26.05";

    # TWO DATASETS, TWO GUARDS. This service owns `zdata/nextcloud` as well as
    # living on `zdata/state`, and the data one checks FSTYPE too.
    extraGuardedMounts = [
      {
        path = dataRoot;
        source = "zdata/nextcloud";
        fstype = "zfs";
      }
    ];

    stateDirs = [
      {
        path = dataRoot;
        owner = nextcloudUid;
        group = nextcloudGid;
      }
      {
        path = stateRoot;
        owner = nextcloudUid;
        group = nextcloudGid;
      }
      # PostgreSQL's own upstream-static id, not one from ernst's 3000 block.
      # The PARENT of the version directory is bound, so a major bump lands
      # beside the old one on zdata rather than needing a new mount.
      {
        path = "${stateRoot}/postgresql";
        owner = postgresUid;
        group = postgresGid;
      }
    ];

    bindMounts = {
      "/var/lib/nextcloud" = {
        hostPath = dataRoot;
        isReadOnly = false;
      };
      "/var/lib/postgresql" = {
        hostPath = "${stateRoot}/postgresql";
        isReadOnly = false;
      };
      # The media tree, read-only: external storage is a view, not a second
      # master. Nextcloud must never be able to write into Jellyfin's library.
      "${mediaRoot}" = {
        hostPath = mediaRoot;
        isReadOnly = true;
      };
      # The shared scan inbox, writable — it IS paperless's consumption
      # directory, which is why it sits on /srv/state and not /srv/docs.
      "${docsInbox}" = {
        hostPath = docsInbox;
        isReadOnly = false;
      };
      # Staged by the hand-written secrets unit above.
      "${secretsDir}" = {
        hostPath = secretsDir;
        isReadOnly = true;
      };
    };

    allowFrom = [
      {
        peer = traefikAddr;
        port = nextcloudPort;
      } # every client arrives through the proxy
    ];

    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      ##########################################################################
      # The service.
      ##########################################################################
      services.nextcloud = {
        enable = true;

        # PINNED EXPLICITLY, AND TO THE stateVersion DEFAULT.  nixpkgs carries
        # 31 through 34 at this pin, and the module derives a default from
        # `system.stateVersion` — 33 for 26.05.
        #
        # An earlier draft took 32, on the reasoning that the oldest supported
        # major makes the first in-place upgrade a deliberate act rather than a
        # side effect of the initial deploy.  THAT ARGUMENT IS FOR AN EXISTING
        # INSTANCE AND THIS ONE STARTS EMPTY: there is nothing to upgrade, so
        # all it bought was the module's legacy-install warning on every single
        # evaluation.  A deploy that always prints a warning is a deploy nobody
        # reads — that is a standing item in docs/history.md's backlog.
        #
        # It is still written out rather than left to the default, because the
        # default moves with `system.stateVersion`, and a Nextcloud major must
        # never move as a side effect of editing an unrelated line.  Bumping it
        # is an edit here, with a `zfs snapshot zdata/nextcloud` first.
        package = pkgs.nextcloud33;

        inherit hostName;

        # Tells the module to emit `fastcgi_param HTTPS on` and the HSTS
        # header.  It does NOT make nginx listen on 443 and does not request a
        # certificate: TLS is terminated once, at Traefik, with the wildcard it
        # already holds.
        https = true;

        # Local PostgreSQL over the unix socket at /run/postgresql.
        #
        # THIS FILE THEREFORE DECLARES NO DATABASE PASSWORD AND NO DATABASE
        # STAGING UNIT, and that is the same argument containers/immich.nix
        # makes: `dbhost` defaults to the socket, socket connections use peer
        # authentication, and a credential that is never checked is a
        # credential that should not exist.  A `nextcloud-db-password`
        # generator would be a generator nothing reads.
        database.createLocally = true;
        config.dbtype = "pgsql";

        # The local account, and the RECOVERY PATH.  It remains a Nextcloud
        # password login after OIDC is registered below, which is the point:
        # when the portal, the client registration or Traefik is what is
        # broken, this is the way back in.  `root` is the module's default and
        # is a confusing name for a Nextcloud user.
        config.adminuser = "ncadmin";
        config.adminpassFile = adminPassFile;

        # ── Outbound mail, via M31's server as noreply@ ────────────────────
        #
        #   Until this landed `mail_smtphost` was Nextcloud's stock
        #   `127.0.0.1` and nothing could send.  That is a SILENT failure in
        #   four places — share-by-mail links, calendar iMIP invitations,
        #   activity notifications and local password resets — and the
        #   calendar one is the trap: inviting an external guest appears to
        #   work and simply never reaches them.
        #
        #   `secretFile` below carries the password; it is NOT in `settings`,
        #   because that attrset is rendered into config.php through the Nix
        #   store and this host's store is world-readable.
        #
        #   AUTHENTICATED SUBMISSION ON 465, not a `mynetworks` exemption for
        #   this container's address.  The exemption was the cheaper option —
        #   no credential, no mailbox, one line — and it was rejected: Postfix
        #   `mynetworks` bypasses relay denial, so a compromised Nextcloud
        #   could relay to any destination as any sender, carrying our DKIM
        #   signature.  A credential scoped to one mailbox is revocable by
        #   regenerating one generator; a trusted /32 is not revocable at all
        #   short of editing the mail server.
        secretFile = smtpSecretFile;

        settings = {
          mail_smtpmode = "smtp";
          mail_smtphost = mailHost;
          mail_smtpport = 465;
          # `ssl`, not `tls`: Nextcloud's `tls` means STARTTLS, and 465 is
          # implicit TLS.  M31 leaves 587 off per RFC 8314, so there is no
          # STARTTLS port to fall back to and getting this wrong is a hang
          # rather than a clear error.
          mail_smtpsecure = "ssl";
          mail_smtpauth = true;
          mail_smtpname = "noreply@${baseDomain}";
          mail_from_address = "noreply";
          mail_domain = baseDomain;
        };

        # Redis for the distributed cache and the file-locking backend, over
        # its unix socket.  APCu stays the local cache (`caching.apcu`, on by
        # default).  Redis lives on the container's own rootfs under
        # /var/lib/nixos-containers/nextcloud, which machines/ernst/configuration.nix
        # persists — it is a cache and has no business on zdata.
        configureRedis = true;

        # Raised from the module's 512M default.  This is a file-sync server;
        # the ceiling people actually hit is a video, and the corresponding
        # ceiling at the proxy is already high enough — traefik.nix sets
        # websecure's readTimeout to 3600s and wan's to 1800s, after a 1.1 GB
        # Immich upload died at exactly 60.000 s on 2026-09-14.
        maxUploadSize = "16G";

        settings = {
          # ── THE LINE THAT MAKES THE BRUTE-FORCE CONTROL REAL ──────────────
          #
          # Without it every request appears to come from 10.0.90.12 and two
          # separate things break in the same direction: Nextcloud's own
          # brute-force throttle keys on the client address, so ONE attacker
          # would lock out the whole household; and the logs an operator reads
          # during an incident would name the proxy instead of the client.
          #
          # `appApiHosts` in containers/ingress-policy.nix names the service's
          # own controls as compensation number 5 for having no forward-auth.
          # This is what turns that from a claim into a fact.
          trusted_proxies = [traefikAddr];

          # Traefik forwards the original Host, so `trusted_domains` (which the
          # module sets to hostName) is enough on its own — but the protocol is
          # NOT forwarded in a form PHP sees, and without this Nextcloud
          # generates http:// URLs for share links, DAV discovery and the OIDC
          # redirect.  The last of those fails closed at Authelia with
          # `invalid_redirect_uri`, which reads as an Authelia fault.
          overwriteprotocol = "https";

          # Silences the admin-panel warning and, more usefully, pins WHEN the
          # heavy background jobs run.  1 = 01:00 UTC.
          maintenance_window_start = 1;

          # Required for the Contacts app's phone-number handling; without it
          # every admin page carries a warning about it.
          default_phone_region = "DE";

          # ── THE LINE WITHOUT WHICH OIDC CANNOT WORK AT ALL, AND THE ──────
          #    SECURITY TRADE IT MAKES
          #
          # MEASURED ON ERNST 2026-09-15, on the first attempt to log in:
          #
          #     OCP\Http\Client\LocalServerException
          #     Host "10.0.90.12" (auth.goclan.org:80) violates local access rules
          #
          # …and Nextcloud rendered it as a plain 404 on
          # /index.php/apps/user_oidc/login/1, which reads as "the app is
          # broken" rather than as a refusal.  The provider row was correct,
          # the discovery endpoint answered 200 to `curl` from inside this very
          # container, and the login still failed — because the block is in
          # Nextcloud's OWN HTTP client (`DnsPinMiddleware`), not in the
          # network.
          #
          # WHAT IT IS: Nextcloud refuses server-side requests to RFC1918
          # addresses as SSRF protection.  `auth.goclan.org` resolves to
          # 10.0.90.12 — Traefik, on VLAN 90 — so both the discovery fetch and
          # the token exchange are refused before a packet leaves.
          #
          # THERE IS NO NARROWER FORM.  Nextcloud offers a boolean and no
          # per-host allowlist, and every path to Authelia is RFC1918: it is
          # reached through Traefik, and Traefik is on the same private VLAN.
          # Pointing the issuer at the public name would need a NAT hairpin on
          # the UDM-Pro for a request that never leaves the box.
          #
          # WHAT IT COSTS, stated plainly because it is a real widening:
          # Nextcloud features that fetch a URL on the server's behalf —
          # federated sharing, "add remote share", link previews — can now
          # reach the LAN, and this vhost is on the `wan` entrypoint with
          # app-level accounts as its only boundary.
          #
          # WHAT BOUNDS IT: this changes what the APPLICATION will refuse, not
          # what the container can reach.  Its firewall is inbound-only — the
          # `curl` above proves egress was never restricted — so a shell in
          # here could always have probed VLAN 90.  What is new is that an
          # AUTHENTICATED Nextcloud user can now aim that at a URL of their
          # choosing.  Accounts here are household members, and that is the
          # whole of the argument; if this vhost ever gains self-registration
          # or a public guest flow, re-read this paragraph first.
          allow_local_remote_servers = true;

          # The module's default is `https://localhost`, which is what
          # `occ config:system:get overwrite.cli.url` returned on the first
          # deploy.  Anything Nextcloud generates OUTSIDE a request — cron,
          # activity emails, share notifications — builds its links from this,
          # so left alone the household would receive mail pointing at
          # localhost.  Not a security property; just wrong.
          "overwrite.cli.url" = "https://${hostName}";
        };

        # ── The apps, from nixpkgs' curated set ───────────────────────────
        #
        # NOT the in-app appstore, which is left at its default (off when
        # `extraApps` is set): an app store that can install code into
        # /var/lib/nextcloud at runtime is a second, unreviewed source of truth
        # for what this container runs, and this repository's whole argument is
        # against those.  Adding an app is a pull request.
        #
        # `files_external` is NOT listed and does not need to be — it ships
        # inside the Nextcloud tarball and is enabled by occ below.
        extraApps = {
          inherit
            (pkgs.nextcloud33Packages.apps)
            calendar # CalDAV, replacing citizengo.io's
            contacts # CardDAV
            tasks # the VTODO surface modules/caldav-sync.nix pushes to
            notes
            user_oidc # the Authelia login button
            mail # webmail against M31's server — see the note below
            integration_paperless # "send to Paperless" in the Files menu (M32)
            ;
        };
        extraAppsEnable = true;
      };

      # ── THE PAPERLESS APP IS A FILE ACTION, NOT A SECOND INBOX (M32) ──────
      #
      #   `integration_paperless` adds one item to the Files action menu:
      #   "Send to Paperless". It is the official Nextcloud app
      #   (nextcloud/integration_paperless), in nixpkgs' curated set, so it
      #   needs no appstore — which is the whole reason it is acceptable here.
      #
      #   IT DOES NOT REPLACE THE SCAN INBOX, and the two are for different
      #   motions. `Scan Inbox` is a drop box: anything that lands there is
      #   consumed and vanishes, which is what a phone wants. This is for a
      #   file that is ALREADY in Nextcloud and should ALSO be in the archive —
      #   a PDF someone mailed you, a contract you edited. The original stays
      #   where it is.
      #
      #   THE UPLOAD IS SERVER-SIDE, so this container has to reach paperless.
      #   Verified from inside it (2026-10-07):
      #
      #     getent hosts docs.goclan.org   -> 10.0.90.12   (Traefik)
      #     curl https://docs.goclan.org/api/   -> 302      (paperless answering)
      #     curl http://10.0.90.32:28981/api/   -> 000      (backend, blocked)
      #
      #   So it is configured with the PUBLIC NAME and needs no new firewall
      #   rule anywhere — and the direct path stays shut. Pointing it at the
      #   backend address would fail anyway: `PAPERLESS_URL` sets Django's
      #   ALLOWED_HOSTS, so a request with `Host: 10.0.90.32` is refused. That
      #   is containers/homepage.nix's Nextcloud-widget situation exactly, one
      #   service along.
      #
      #   PER-USER AND NOT PROVISIONABLE. The app stores its URL and API token
      #   in PERSONAL settings, so each person enters them once under
      #   Settings → Personal → Paperless. A token is minted in paperless under
      #   the user's own account, which is the point: the upload is attributed
      #   to the person who made it, not to a shared credential. The `mneme`
      #   token is read-only and deliberately unsuitable.
      #   docs/guides/document-store.md carries the two fields.

      # ── THE MAIL APP'S ACCOUNTS ARE NOT PROVISIONED, AND CANNOT BE ────────
      #
      #   `mail` is a per-user IMAP client, not a second mail server.  It talks
      #   to M31's Dovecot on 10.0.90.31 — by NAME, `mail.goclan.org`, which
      #   Technitium resolves to that address from inside this container
      #   (verified), so the Let's Encrypt certificate validates.  Reaching it
      #   needs NO accept rule anywhere: containers/mail.nix opens 993/465/4190
      #   to everything, which is the one place that convention-break pays off.
      #
      #   NEXTCLOUD MAIL CAN AUTO-PROVISION ACCOUNTS, AND BOTH OF ITS MODES ARE
      #   UNAVAILABLE HERE.  This is worth writing down, because "just turn on
      #   provisioning" is the obvious next thought and it dead-ends twice:
      #
      #     1. The default mode logs into IMAP with the user's NEXTCLOUD LOGIN
      #        PASSWORD.  Logins here go through Authelia over OIDC (`user_oidc`
      #        above), so Nextcloud never sees a password and has none to reuse.
      #        Provisioning would create accounts that cannot authenticate.
      #
      #     2. The master-password mode exists precisely for SSO deployments —
      #        one credential for every provisioned account — but it needs
      #        Dovecot MASTER USERS, and simple-nixos-mailserver exposes no
      #        option for them (grepped: no `master_user`, no `auth_master`).
      #        Enabling it would mean hand-written Dovecot config underneath a
      #        module that owns that file.
      #
      #   So each person adds their account once, in the Mail app's UI, with
      #   the password from `modules/mail-accounts.nix` — the same one K-9 uses.
      #   docs/guides/mail.md carries the four fields.  That is three mailboxes
      #   typed once each, against a standing source of truth divergence; the
      #   trade is not close.
      #
      #   NO SYSTEM SMTP IS SET HERE EITHER, and that is a separate gap rather
      #   than part of this one: `mail_smtphost` is still Nextcloud's stock
      #   127.0.0.1 default, so `sharebymail` and password-reset mail cannot
      #   send.  Wiring that needs a credential or a Postfix `mynetworks`
      #   exemption, which is its own decision and its own change.

      # ── Pin the ids ───────────────────────────────────────────────────────
      #
      # See the let block: unmapped nspawn ids mean a container-chosen number
      # is a number on the pool.  `media` is SECONDARY, for the read-only
      # external storage mount only.
      # `media` is SECONDARY, for the read-only external storage mount.
      # `docsin` is SECONDARY too, and is what lets a scan shared from a phone
      # be written into paperless's consumption directory (M32).  Neither is
      # primary: making either one primary would put a shared gid on every file
      # Nextcloud writes into its own store.
      users.users.nextcloud.extraGroups = ["media" "docsin"];
      users.groups.media.gid = mediaGid;
      users.groups.docsin.gid = docsinGid;

      ##########################################################################
      # ── Provisioning that only occ can express ──────────────────────────────
      #
      # Two things Nextcloud keeps in its DATABASE rather than in config.php,
      # so neither is reachable from `settings` above: the OIDC provider
      # registration and the external storage mount.
      #
      # `nextcloud-occ user_oidc:provider <name> …` is an UPSERT — it creates
      # on first run and updates on every subsequent one — so this unit is
      # idempotent across deploys by construction rather than by a stamp file.
      # A stamp file would be worse than nothing here: it would claim the
      # provider exists after somebody deleted it in the admin UI.
      ##########################################################################
      systemd.services.nextcloud-provision = {
        description = "Register the Authelia OIDC provider and the external storage mounts";
        wantedBy = ["multi-user.target"];
        after = ["nextcloud-setup.service" "phpfpm-nextcloud.service" "network-online.target"];
        wants = ["network-online.target"];
        requires = ["nextcloud-setup.service"];

        # ── IT RETRIES, AND THE REASON IS NOT GENERAL ROBUSTNESS ─────────────
        #
        # `user_oidc:provider --discoveryuri` FETCHES that URL when it runs, so
        # this unit depends on `auth.goclan.org` resolving through Technitium
        # AND on container@authelia being up behind Traefik — neither of which
        # this container can order against, because they are in a different
        # namespace and on the other side of the host's unit graph.  On a cold
        # boot of ernst, or on the very first deploy, losing that race is the
        # expected case rather than the exceptional one.
        #
        # It gives up after ten tries over ten minutes and STAYS FAILED, which
        # is deliberate: `ContainerSystemdUnitFailed` sees failed units inside
        # nspawn containers within a minute, so a genuine misconfiguration
        # alerts instead of being retried forever in silence.
        #
        # The visible symptom of this unit never succeeding is a Nextcloud
        # login page with only the local password form on it.
        startLimitIntervalSec = 600;
        startLimitBurst = 10;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "60s";
          # As `nextcloud`, like nextcloud-setup.service.  The occ wrapper does
          # NOT drop privileges, so running this as root would leave root-owned
          # files inside a store the service then cannot write.
          User = "nextcloud";
          Group = "nextcloud";

          # ── AND THE CREDENTIALS, WHICH IS THE OTHER HALF OF "LIKE
          #    nextcloud-setup.service" ─────────────────────────────────────
          #
          # Copying that unit's User and Group without its LoadCredential is
          # what broke this service for seventeen days — 2026-10-07 to
          # 2026-10-24, restart counter 1248 — with:
          #
          #   systemd-run[368]: Failed to start transient service unit:
          #                     Access denied
          #
          # `nextcloud-occ` is a wrapper, and when SMTP credentials are
          # configured it takes a branch that runs, in effect:
          #
          #   if requiresRuntimeSystemdCredentials and CREDENTIALS_DIRECTORY
          #      is empty:
          #     exec systemd-run --property=LoadCredential=secret_file:...
          #       --uid=nextcloud ...
          #
          # It EXECs, so the sudo and runuser fallbacks further down that
          # wrapper are never reached — and an unprivileged user cannot create
          # a transient unit, so every occ call died right there.  Loading the
          # credential here sets CREDENTIALS_DIRECTORY, the branch is skipped,
          # and occ runs in process exactly as it does inside nextcloud-setup.
          #
          # The same two entries that unit declares, read with `systemctl cat`
          # against the running container rather than copied out of nixpkgs.
          LoadCredential = [
            "adminpass:${adminPassFile}"
            "secret_file:${smtpSecretFile}"
          ];
        };
        path = [config.services.nextcloud.occ pkgs.coreutils pkgs.gnugrep pkgs.jq];
        script = ''
          set -euo pipefail

          # ── Authelia as an OIDC provider ─────────────────────────────────
          #
          # THE SECRET PASSES THROUGH ARGV, and there is no alternative: the
          # command takes `--clientsecret=<value>` and has no stdin or file
          # form.  The exposure is /proc/<pid>/cmdline, for the life of one occ
          # invocation, inside a container whose only other unprivileged users
          # are nginx and postgres.  Stated rather than smoothed — if upstream
          # grows a file form, this should take it.
          #
          # `--unique-uid=0` maps accounts by the preferred_username claim
          # rather than by Authelia's opaque subject hash, so an OIDC login
          # lands on the SAME Nextcloud account a pre-existing local user
          # already has.  With it set to 1 the first Authelia login would
          # silently create a second, empty account beside the real one.
          nextcloud-occ user_oidc:provider Authelia \
            --clientid="nextcloud" \
            --clientsecret="$(cat ${oidcSecretFile})" \
            --discoveryuri="${autheliaIssuer}/.well-known/openid-configuration" \
            --scope="openid profile email groups" \
            --unique-uid=0 \
            --mapping-uid=preferred_username \
            --mapping-display-name=name \
            --mapping-email=email

          # Keep the local password form on the login page.  This is what makes
          # `ncadmin` above an actual recovery path rather than a decoration.
          nextcloud-occ config:app:set user_oidc allow_multiple_user_backends --value=1

          # ── /srv/media as read-only external storage ─────────────────────
          #
          # files_external ships in the tarball, so this enables rather than
          # installs.
          nextcloud-occ app:enable files_external

          # Idempotency without a stamp file: ask what is already mounted.  PHP
          # escapes forward slashes in JSON output (\/srv\/media), hence the
          # `tr -d`, which is cheaper and less brittle than a JSON parser for a
          # substring test.
          #
          # THE TEST IS DELIBERATELY LOOSE — a bare substring rather than the
          # exact `"datadir":"…"` pair — because the two ways it can be wrong
          # are not symmetric.  Too loose means the mount is never created,
          # which is visible in the UI on the first look.  Too strict means a
          # DUPLICATE MOUNT IS CREATED ON EVERY DEPLOY, silently, forever.
          #
          # NO --user AND NO --group, so this is a SYSTEM mount applicable to
          # every Nextcloud account.  That is the intent — it is the household
          # media library and the bind is read-only — and it is stated here
          # because "applicable to everyone" is a default rather than a flag,
          # and defaults are what nobody re-reads.  Narrow it in Settings →
          # External storage if that stops being true.
          if ! nextcloud-occ files_external:list --output=json | tr -d '\\' | grep -q '${mediaRoot}'; then
            nextcloud-occ files_external:create Media local null::null -c datadir=${mediaRoot}
          fi

          # ── The scan inbox as WRITABLE external storage (M32) ─────────────
          #
          # Same loose-substring idempotency as the Media mount above, for the
          # same asymmetry: too loose creates nothing and is visible on the
          # first look; too strict creates a duplicate mount on every deploy,
          # silently, forever.
          #
          # ⚠ `filesystem_check_changes` IS NOT OPTIONAL HERE, AND THE DEFAULT
          #   IS AGAINST US.
          #
          # Paperless consumes a scan and UNLINKS it.  Nextcloud does not
          # notice a file disappearing from external storage unless it is told
          # to look, so without this option the folder keeps showing scans that
          # no longer exist — and the household's conclusion is that uploading
          # is broken, not that it worked.
          #
          # THE WEB UI SETS THIS AND `files_external:create` DOES NOT.  Mounts
          # made through the GUI are initialised with
          # `filesystem_check_changes = 1`; the non-GUI creation path omits the
          # option entirely and falls back to the GLOBAL default, which is 0
          # (Never).  So this is the one line that makes the inbox behave, and
          # it has to be set explicitly because we are on the path that skips
          # it.  Values: 0 never, 1 once per direct access, 2 always.  `1` is
          # what we want — opening the folder in the Files app rescans that one
          # directory, and nothing scans on a timer.
          #
          # The Media mount above is almost certainly on the global default
          # too.  It is left alone deliberately: it is read-only, nothing
          # deletes from it behind Nextcloud's back, and a rescan-on-access
          # over a multi-terabyte library is a cost with no benefit.
          #
          # `files_external:option <mount_id> <key> <value>` rather than
          # `:config` — read out of
          # apps/files_external/lib/Command/Option.php at this exact Nextcloud
          # version.  `:option` takes mount OPTIONS; `:config` sets BACKEND
          # configuration such as `datadir`.  Three positional arguments, no
          # `set` verb.
          #
          # THE JSON KEYS ARE `mount_id` AND `configuration`, and the comment
          # that used to sit here asserted the opposite — `id` and
          # `backendOptions`, "read out of Lib/StorageConfig.php::jsonSerialize
          # rather than guessed".  Whatever that reading was, the running
          # server disagrees.  Measured against this deployment:
          #
          #   files_external:list --output=json
          #   [{"mount_id":1,"mount_point":"\/Media",...,
          #     "configuration":{"datadir":"\/srv\/media"},...}, ...]
          #
          #   select(.backendOptions.datadir == $d) | .id        -> (empty)
          #   select(.configuration.datadir == $d) | .mount_id    -> 2
          #
          # The empty result is why this guard never matched and why
          # `files_external:create` ran on EVERY provisioning pass: mount ids
          # 2, 3, 4 and 5 were four identical registrations of the same inbox,
          # one per deploy.  A guard that silently never matches is worse than
          # no guard, because the failure accumulates instead of announcing
          # itself.
          #
          # There is no `tr -d '\\'` on this pipeline, unlike the Media check
          # above: PHP escapes forward slashes as `\/`, which `grep` has to
          # have stripped but which is a VALID JSON escape that jq decodes
          # correctly on its own.  Stripping backslashes before jq would
          # corrupt any other escape in the document.
          inbox_id=$(nextcloud-occ files_external:list --output=json \
            | jq -r --arg d '${docsInbox}' \
                'first(.[] | select(.configuration.datadir == $d) | .mount_id) // empty')

          if [ -z "$inbox_id" ]; then
            # With --output=json, files_external:create writes the bare new
            # mount id and nothing else (Command/Create.php), so there is no
            # need to list again to find what was just made.
            inbox_id=$(nextcloud-occ files_external:create "Scan Inbox" \
              local null::null -c datadir=${docsInbox} --output=json)
          fi

          if [ -n "$inbox_id" ]; then
            nextcloud-occ files_external:option "$inbox_id" filesystem_check_changes 1
          else
            echo "nextcloud-provision: could not determine the Scan Inbox mount id" >&2
            echo "  The mount exists but its change-detection option is unset," >&2
            echo "  which means consumed scans will linger in the Files app." >&2
            echo "  Set it by hand: Settings -> External storage -> gear icon" >&2
            echo "  -> 'Filesystem check frequency' -> 'Once every direct access'." >&2
            exit 1
          fi
        '';
      };

      # `curl` is the test plan's instrument for proving this backend is
      # reachable from Traefik and from nowhere else.
      environment.systemPackages = with pkgs; [curl];
      documentation.enable = false;
      documentation.nixos.enable = false;
    };
  };
}
