# machines/ernst/containers/mail.nix
#
# Mail — the household's own SMTP and IMAP server for @goclan.org (M31).  An
# nspawn container on VLAN 90 running simple-nixos-mailserver: Postfix,
# Dovecot, Rspamd, Redis and kresd.  Five mailboxes — admin@, lutz@, sarinah@,
# max@ and go@ — spoken to by aerc on miralda and jens, K-9 on Sarinah's and
# Max's phones, and Thunderbird on biene.  Everyone is reachable under both
# their username and their name (`lgo@` → `lutz@`); see the alias table below.
#
# The operator's half — the DNS record set, the UDM-Pro checklist, the
# reputation pre-flight, client setup and the smarthost escape hatch — is
# docs/guides/mail.md.  Read it before deploying; three of the steps there
# have to happen before this container is useful and one of them takes days.
#
# ── THIS IS THE HIGHEST-RISK SERVICE ON THE HOST, AND THE RISK IS NOT ──────
#    INTRUSION
#
#   Every other container here fails closed and quietly: the service is down,
#   somebody notices, it comes back.  A mail server fails in two ways that are
#   both silent and both expensive.  It can accept mail and lose it — which is
#   why /var/lib/postfix (the QUEUE, not just config) is bound out to zdata
#   below, and why mail-dirs refuses to start rather than create a directory
#   on zroot.  And it can send mail that is quietly discarded by the receiver,
#   which looks exactly like the recipient ignoring you.
#
#   THE SECOND FAILURE WAS THE EXPECTED STATE OF THIS BOX WHEN M31 WAS
#   PLANNED, AND IT IS NO LONGER.  Both halves of the problem were measured,
#   and both were then fixed by work outside this repo:
#
#                      2026-09-29 (planning)          2026-10-06 (now)
#     public IPv4      78.94.91.74                    unchanged
#     PTR              ip-078-094-091-074.um19        mail.goclan.org
#                      .pools.vodafone-ip.de          — Vodafone set it on request
#     FCrDNS           n/a                            CONFIRMED, both directions
#     outbound :25     OPEN (reached Gmail's and      unchanged
#                      iCloud's MX directly)
#     Barracuda        LISTED (127.0.0.2)             DELISTED
#     Spamhaus/others  not listed                     not listed
#
#   THAT ORDER MATTERS AND IS THE POINT OF KEEPING THE OLD COLUMN.  The design
#   below was chosen while the right-hand column did not exist: direct sending
#   was picked over a smarthost relay and over a VPS relay, knowing that
#   Outlook would reject and Gmail/GMX/Web.de would junk.  The reputation work
#   in docs/guides/mail.md — a free Barracuda delisting, and one phone call to
#   Vodafone that turned out to be answerable — is what moved it.  A reader who
#   finds this file in a year should know the direct path is viable HERE
#   because of two specific external facts, not because direct sending from a
#   residential line is generally fine.  It is not.
#
#   SO THE SMARTHOST ESCAPE HATCH STAYS DOCUMENTED AND STAYS DISABLED.  If the
#   PTR is ever lost — a tariff change, a pool renumbering, a support ticket
#   handled by someone else — the symptom is mail silently landing in junk, and
#   the fix is one `relayhost` block.  That it changes nothing else is a
#   property of the stack: Rspamd signs DKIM BEFORE Postfix hands the message
#   off, so moving to a relay preserves DKIM and DMARC alignment and touches no
#   mailbox, no key and no client.
#
# ── WHY THE nspawn TIER ────────────────────────────────────────────────────
#
#   simple-nixos-mailserver is a set of NixOS modules over first-class
#   nixpkgs services; there is no OCI image involved, so the podman tier that
#   exists here for storyteller / cwa / romm / tubesync does not apply.  It is
#   also not a microvm: the microvm tier on this host is scoped by M3 to the
#   one workload that talks to the open internet ON ITS OWN BEHALF, dialling
#   out to arbitrary peers under a VPN.  A mail server talks to the open
#   internet too, but it does so as a server, on four known ports, with the
#   host's kernel — the same posture as Traefik, which has been the fleet's
#   internet-facing edge since M18 and is an nspawn container.
#
# ── FOUR HOUSE CONVENTIONS BREAK HERE, AND THEY ALL BREAK FOR ONE REASON ───
#
#   Every other user-facing service on ernst is reached through Traefik on one
#   hostname over HTTPS.  Mail is not HTTP.  SMTP, IMAP and ManageSieve are
#   their own protocols on their own ports, and SMTP on :25 carries no SNI at
#   all, so there is nothing for a TCP router to key a hostname on.
#   traefik.nix declares no TCP routers and no TCP entrypoints today, and
#   adding them would still not cover :25.  So:
#
#   1. THIS SERVICE IS NOT IN ingress-policy.nix, and that is not an omission.
#      That file's three lists classify HOSTNAMES ROUTED THROUGH THE PROXY by
#      whether their clients can follow a 302.  No hostname here is routed
#      through the proxy, so there is no entry to make and the `withWan` guard
#      in traefik.nix has nothing to check.  The one mail-adjacent thing that
#      IS HTTP — the MTA-STS policy file at mta-sts.goclan.org — rides Traefik
#      normally, and is the one exception: an nginx vhost further down this
#      file, routed as `mtasts`, in `appApiHosts` and `wanExposed`, ledger
#      row L23.  It is served from HERE rather than a web container so the
#      policy and the MX it names cannot drift.
#
#   2. ITS FIREWALL ACCEPTS FROM THE WHOLE INTERNET.  Every sibling container
#      lists named peers (Traefik, the index, monitoring) and refuses
#      everything else, and each carries a note that `curl` from ernst itself
#      is refused BY DESIGN.  That negative control is INVERTED here for the
#      four mail ports: :25 must answer any MTA on earth, and :465/:993/:4190
#      must answer Sarinah's phone from whatever address her carrier gives it.
#      It still holds for the exporter port, which is the one rule below that
#      names a peer.
#
#   3. CROWDSEC DOES NOT COVER IT.  crowdsec.nix has exactly one acquisition,
#      `_SYSTEMD_UNIT=traefik.service`, and lives in Traefik's netns because
#      that is the only place with both the pre-DNAT source address and a hook
#      the packet traverses.  Nothing about that reaches this container.  Mail
#      auth brute-force is handled by fail2ban INSIDE the container instead,
#      reading Postfix's and Dovecot's own journal.  Two bouncers on one host
#      is not duplication when they are watching two disjoint sets of packets.
#
#   4. IT DOES NOT PIN TECHNITIUM.  Every other container carries
#      `DNS = 10.0.5.3; Domains = "~. skynet.lan"` on its eth0.  This one runs
#      kresd instead (`mailserver.localDnsResolver`, upstream's default),
#      doing its own recursion from the container.  That is a requirement, not
#      a preference: DNSBL operators refuse queries that arrive via a shared
#      resolver — the Spamhaus 127.255.255.254 above is exactly that refusal,
#      returned both from miralda and from ernst — so an Rspamd pointed at
#      Technitium would silently score every message as if every blocklist
#      were empty.  The cost is that this container cannot resolve
#      `*.skynet.lan`, and it has no reason to.
#
# ── IT TAKES uid/gid 3041 AND 3043, AND THAT IS RECORDED ON PURPOSE ───────
#
#   3041 is `virtualMail`, the owner of the Maildir on zdata, pinned through
#   `mailserver.storage.{uid,gid}` rather than left at upstream's 5000.  3043
#   is `redis-rspamd`, which owns the Bayes classifier.  The 3000 block exists
#   for ids that become visible ON THE POOL, and those are the two here that
#   do.
#
#   3043 AND NOT 3042, because M32 landed first and took 3042 for its `docsin`
#   ingest group.  The two milestones were developed concurrently and each
#   reserved the other's numbers in prose — M32 left 3041 and VLAN seq 17 for
#   this one, this one left seq 18 — and the single number neither side
#   reserved is the one that collided.
#
#   THE FOUR DAEMON uids ARE UPSTREAM-STATIC AND MUST NOT BE RENUMBERED INTO
#   THE BLOCK: postfix 13, postdrop 14, dovecot2 46, rspamd 225, all from
#   nixpkgs `nixos/modules/misc/ids.nix`.  Pinning a 3000-block number on top
#   of one of those is an option conflict at EVAL, which is how M24 learned
#   this with `conflicting definition values: 286 / 3038` for hass.  Only 3041
#   and 3043 are claimed in machines/ernst/networking.nix; the rest are noted
#   there as deliberately outside.
#
# ── NO NEW DATASET ─────────────────────────────────────────────────────────
#
#   Everything lands under /srv/state/mail on `zdata/state`: 128K recordsize,
#   exec on, `com.sun:auto-snapshot=true`.  A Maildir is many small files,
#   which is an argument for its own dataset only if you want separate
#   snapshot granularity or a quota — neither is wanted yet, and M24, M26 and
#   M27 each made and wrote down the same call.  Adding one later is a
#   `zfs create -o mountpoint=legacy` plus a matching block in
#   docs/guides/ernst-zdata-datasets.md IN THE SAME PR, because disko does not
#   create datasets on an existing pool.
#
#   SAY THE QUIET PART: those ZFS snapshots are the ONLY backup this fleet
#   has.  There is no borg, no restic, no replication anywhere in this repo.
#   For media that was a shrug — it is re-acquirable.  Mail is not.
{ config, pkgs, lib, inputs, ... }:

let
  ##############################################################################
  # Identity.
  #
  # ONLY virtualMail is ours.  postfix 13 / postdrop 14 / dovecot2 46 /
  # rspamd 225 come from nixpkgs ids.nix and are referenced numerically below
  # wherever the HOST has to name them, because those are CONTAINER users and
  # the host has no matching passwd entries — the same reason miniflux-dirs
  # writes 71 for postgres rather than the name.
  ##############################################################################
  vmailUid = 3041;
  vmailGid = 3041;

  # Redis, which is where Rspamd's BAYES CLASSIFIER lives.  Pinned for the
  # ordinary 3000-block reason and not for a clever one: `redis-rspamd` is a
  # per-server user, so unlike postfix/dovecot2/rspamd it has no entry in
  # nixpkgs ids.nix, nixpkgs declares it `isSystemUser` with no uid, and
  # nspawn passes container ids through UNMAPPED — so whatever useradd
  # happens to pick owns /srv/state/mail/redis on the pool.  Let it drift and
  # Redis cannot read its own dump after a rebuild.
  #
  # `services.redis.servers.rspamd` keeps `User=` and does NOT use
  # DynamicUser, so `StateDirectory=redis-rspamd` stays at /var/lib/redis-rspamd
  # and does not migrate to /var/lib/private — the trade crowdsec, ollama and
  # music-assistant each had to make is not owed here, and the bind mount is
  # safe as written.
  # 3043, NOT 3042, and the number moved after this branch was written: M32
  # landed first and took 3042 for its `docsin` ingest group.  Both milestones
  # reserved the other's number in prose while developing concurrently — M32
  # left 3041 and VLAN seq 17 for this one, this one left seq 18 — and the one
  # number neither side reserved is the one that collided.
  redisUid = 3043;
  redisGid = 3043;

  dovecotUid = 46;   # nixpkgs ids.nix — reads the password hashes
  rspamdUid  = 225;  # nixpkgs ids.nix — reads the DKIM private key

  ##############################################################################
  # Peers, ports and paths.
  ##############################################################################
  # The monitoring container (M6).  The ONLY named peer in this file's
  # firewall, because it is the only inbound flow here that is not "the
  # internet".
  monitoringAddr = "10.0.90.14";

  mailAddr = "10.0.90.31";

  # prometheus-postfix-exporter's upstream default.  Queue depth and deferred
  # count, which is the whole reason this target clears SN3 — see the metrics
  # note further down.
  exporterPort = 9154;

  # Traefik, which reaches exactly one thing in this container: the MTA-STS
  # policy file.  Named here rather than inlined because it is the ONLY
  # address in this file that is a named peer alongside monitoring — every
  # other port deliberately answers the whole internet.
  traefikAddr = "10.0.90.12";

  # The MTA-STS policy, served over plain HTTP to Traefik, which terminates
  # TLS for it on the existing *.goclan.org wildcard.  8080 because nothing
  # else in this container listens there; it is not reachable from the WAN
  # and carries no mail protocol.
  mtaStsPort = 8080;

  baseDomain = "goclan.org";

  # The name in the MX record, in the SMTP HELO, and on the TLS certificate.
  # It must resolve publicly to 78.94.91.74 and internally to mailAddr; both
  # halves are manual, and docs/guides/mail.md says so twice because missing
  # the internal half presents as a HANG rather than an error (LAN clients
  # recurse to the public view and hairpin at a UDM-Pro that does not hairpin).
  fqdn = "mail.${baseDomain}";

  stateRoot = "/srv/state/mail";

  ##############################################################################
  # Secrets staging.
  #
  # NOT a bind of /run/secrets itself: that path is a symlink to a
  # per-generation directory which is REPLACED on every deploy, so an nspawn
  # bind established at container start would keep exposing a deleted
  # generation.  A directory we own has a stable identity and is rewritten in
  # place.  containers/traefik.nix carries the long form of this.
  ##############################################################################
  secretsDir = "/run/mail-secrets";

  acctGen = config.clan.core.vars.generators.mail-accounts;
  dkimGen = config.clan.core.vars.generators.mail-dkim;

  # noreply@'s credential — declared further down in this file, read here and
  # by containers/nextcloud.nix, which takes the plaintext half.
  systemSenderGen = config.clan.core.vars.generators.mail-system-sender;

  # Declared in containers/traefik.nix.  THE SAME CREDENTIAL, REACHED ACROSS
  # RATHER THAN PROMPTED TWICE — it is one Cloudflare API token, already
  # scoped Zone:DNS:Edit + Zone:Zone:Read on goclan.org, and a second
  # generator asking for it again would mean two copies to rotate and a silent
  # divergence when only one gets updated.  This file adds its own units to
  # that file's `restartUnits` list further down; list options merge across
  # modules, and adding to `restartUnits` does not change the generator's file
  # set, so `clan vars generate` will not re-prompt for it.
  #
  # containers/authelia.nix's "one generator per relying party" rule is not in
  # tension with this.  That rule exists because a generator is ATOMIC, so
  # folding a new file into an old one rotates unrelated secrets as a side
  # effect.  Nothing is being added to this generator — it is being READ.
  acmeGen = config.clan.core.vars.generators.traefik-acme;
in
{
  # The three mailbox passwords.  NOT DECLARED HERE, even though this is the
  # only machine that serves mail, because a clan var reaches only the
  # machines whose configuration declares its generator — and aerc on miralda
  # and jens needs lutz's plaintext to authenticate.  One generator in one
  # module, imported by both consumers; that file's header carries the full
  # argument, including why splitting it in two would let the two copies of
  # lutz's password diverge.
  imports = [ ../../../modules/mail-accounts.nix ];

  clanarchy.mail.accounts.enable = true;
  # `root`, the default, restated to be explicit: there is no `lgo` on ernst,
  # and nothing here reads the plaintext.  miralda and jens set `lgo`.
  clanarchy.mail.accounts.plaintextOwner = "root";

  ##############################################################################
  # Host side — the directories, the secrets and the veth.
  ##############################################################################

  # ── NO tmpfiles RULES IN THIS FILE, AND containers/immich.nix IS WHY ───────
  #
  # That file records the measured failure: host-side directories shipped as
  # `systemd.tmpfiles.rules` and the container died five times into its start
  # limit with `Failed to clone …: No such file or directory`, because
  # activating a new configuration does not re-run systemd-tmpfiles-setup in
  # time for a container the same activation starts.
  systemd.services.mail-dirs = {
    description = "Verify /srv/state is mounted and create the mail server's directories";
    wantedBy   = [ "multi-user.target" ];
    after      = [ "srv-state.mount" ];
    requires   = [ "srv-state.mount" ];
    before     = [ "container@mail.service" ];
    requiredBy = [ "container@mail.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.util-linux pkgs.coreutils ];

    # BLOCKING (`requires` + `requiredBy`), not advisory, and harder here than
    # anywhere else this pattern is used.  A Miniflux that starts without its
    # database loses subscriptions, which are re-addable.  A mail server that
    # starts without /var/vmail accepts mail into a directory on zroot and
    # loses it at the next boot — and the sender got a 250, so nobody will ever
    # retry.  It FAILS rather than repairing itself: a unit that silently fixes
    # storage layout hides the fact that the layout was wrong.
    script = ''
      set -eu

      # THE TARGET IS THE PARENT, NOT ${stateRoot}.  `findmnt --target` on a
      # path that does not exist yet returns nothing — it does not walk up to
      # the nearest existing ancestor — so checking the leaf would fail on
      # every first run, before this unit has had a chance to create it.
      # immich-dirs refused its own first deploy that way on 2026-09-11.
      ssrc=$(findmnt --noheadings --output SOURCE --target /srv/state || true)
      if [ "$ssrc" != "zdata/state" ]; then
        echo "mail-dirs: /srv/state is not zdata/state (found '$ssrc')." >&2
        echo "  Refusing to create the mail spool, because it would land on" >&2
        echo "  zroot and be rolled back on the next boot — taking every" >&2
        echo "  message delivered since with it." >&2
        echo "  See docs/guides/ernst-zdata-datasets.md." >&2
        exit 1
      fi

      # NUMERIC ids on purpose: every one of these is a CONTAINER user and the
      # host has no matching passwd entry.  Same shape miniflux-dirs uses for
      # postgres 71 and traefik.nix for uid 3005.
      install -d -o root -g root -m 0755 ${stateRoot}

      # The Maildir.  0700 — nothing outside the container has any business
      # reading the household's mail, including root-adjacent tooling on the
      # host that might wander in.
      install -d -o ${toString vmailUid} -g ${toString vmailGid} -m 0700 ${stateRoot}/vmail

      # THE QUEUE, and the reason this one is bound out at all.  Postfix holds
      # accepted-but-undelivered mail here; on a residential line with
      # deferrals being normal (see the header) that is not an empty directory.
      # Ownership is left to Postfix's own setup, which builds a tree with
      # several owners and modes under it — this only has to exist and be root.
      install -d -o root -g root -m 0755 ${stateRoot}/postfix

      # Dovecot's indices.  Rebuildable in principle, but rebuilding them for a
      # multi-gigabyte mailbox is a visible outage for the person whose client
      # is resyncing, so they persist.
      install -d -o root -g root -m 0755 ${stateRoot}/dovecot

      # Rspamd's own state, and Redis's, which is where the BAYES CLASSIFIER
      # lives.  Losing this is not fatal and is not harmless: the filter
      # forgets everything the household has taught it and starts scoring from
      # the static rules alone.
      install -d -o ${toString rspamdUid} -g ${toString rspamdUid} -m 0700 ${stateRoot}/rspamd
      install -d -o ${toString redisUid} -g ${toString redisGid} -m 0700 ${stateRoot}/redis

      # ACME state for the mail certificate.  Its own, NOT a share of
      # Traefik's acme.json — see the security.acme block below.
      install -d -o root -g root -m 0755 ${stateRoot}/acme
    '';
  };

  # ── Stage the account hashes, the DKIM key and the ACME token ─────────────
  #
  # ROTATING ANY OF THESE needs a restart, not just a deploy: this unit's
  # script embeds the sops PATH and not the contents, so systemd sees an
  # unchanged unit and does not re-run a oneshot that is RemainAfterExit.  The
  # generators therefore carry `restartUnits`.  By hand it is:
  #     systemctl restart mail-secrets container@mail
  systemd.services.mail-secrets = {
    description = "Stage the mail server's credentials for container@mail";
    after       = [ "local-fs.target" ];
    before      = [ "container@mail.service" ];
    requiredBy  = [ "container@mail.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];

    # ── OWNERSHIP IS PER READER, NOT PER FILE ───────────────────────────────
    #
    #   dovecot reads the three password hashes as uid 46.
    #   rspamd reads the DKIM private key as uid 225.
    #   PID 1 reads cloudflare.env as an EnvironmentFile before lego ever
    #   starts, so that one is root:root — the same distinction
    #   containers/miniflux.nix draws against containers/nextcloud.nix.
    #
    # ── GUARDED, BECAUSE THIS UNIT CAN TAKE THE MAIL SERVER DOWN ────────────
    #
    #   `mail-accounts` is PROMPTED, so a `clan machines update ernst` run
    #   before `clan vars generate ernst` has files that do not exist and clan
    #   renders the missing `.path` as the literal string `/no-such-path`.
    #   Read naively under `set -euo pipefail` that kills this unit, and this
    #   unit is `requiredBy = container@mail.service`.  That is SN5's shape,
    #   and it is what took RomM down on 2026-09-07.
    #
    #   So every value is read only if its file is readable.  A missing hash
    #   yields an EMPTY file, which Dovecot treats as a password that can never
    #   match — the account exists and cannot be logged into.  That is the
    #   right failure: one mailbox unreachable and loudly so, rather than the
    #   whole server refusing to start, and emphatically not an account that
    #   authenticates with anything.
    script = ''
      set -euo pipefail

      # 0711: traversable by anyone, listable by nobody.
      install -d -m 0711 -o root -g root ${secretsDir}
      umask 077

      readvar() { [ -r "$1" ] && cat "$1" || true; }

      # Write to .tmp, set the final owner and mode THERE, then rename —
      # containers/miniflux.nix's shape, and rename is the load-bearing part.
      # `install` straight onto the destination would truncate it in place, so
      # a reader arriving mid-rewrite would see an empty credential rather
      # than the old one.  `umask 077` above means the .tmp is never
      # world-readable even for the moment before the chmod.
      stage() {
        src="$1"; dst="$2"; owner="$3"
        readvar "$src" > "$dst.tmp"
        chown "$owner":0 "$dst.tmp"
        chmod 0400 "$dst.tmp"
        mv -f "$dst.tmp" "$dst"
      }

      # Generated from the generator's OWN file list rather than typed out, so
      # a sixth mailbox added in modules/mail-accounts.nix cannot be staged
      # here by half.  A hash that is declared but never staged produces an
      # account Dovecot refuses every password for, which reads as a typo.
      ${lib.concatMapStringsSep "\n      "
          (f: "stage ${acctGen.files.${f}.path} ${secretsDir}/${f} ${toString dovecotUid}")
          (lib.filter (lib.hasSuffix ".hash") (lib.attrNames acctGen.files))}

      # noreply@ comes from its OWN generator (see mail-system-sender below),
      # so it is not in the loop above — that one walks `mail-accounts` only.
      # Staged identically: Dovecot reads it, so uid 46.
      stage ${systemSenderGen.files."noreply.hash".path} ${secretsDir}/noreply.hash ${toString dovecotUid}

      # The DKIM private key.  GENERATED, not prompted, so it is always
      # present — but staged through the same guard so that a fleet restored
      # from a tree without it degrades to "outgoing mail is unsigned" rather
      # than "the container will not start".  Unsigned is already the worst
      # case for deliverability here and the log says so.
      stage ${dkimGen.files."dkim.key".path} ${secretsDir}/dkim.key ${toString rspamdUid}

      # Traefik's Cloudflare token, for this container's own ACME client.
      # root:root because PID 1 opens an EnvironmentFile while it builds the
      # execution context.
      stage ${acmeGen.files."cloudflare.env".path} ${secretsDir}/cloudflare.env 0
    '';
  };

  ##############################################################################
  # The DKIM keypair.
  #
  # ── A CLAN VAR, NOT GENERATED STATE, AND THIS IS THE ONE PLACE IT MATTERS ──
  #
  #   simple-nixos-mailserver will happily generate a DKIM key into /var/dkim
  #   on first start and skip regeneration afterwards.  That is fine right up
  #   until the directory is lost — a reinstall, a bad restore, a dataset that
  #   turned out not to be mounted — at which point it silently mints a NEW key
  #   while DNS still publishes the old public half.  Every outgoing message
  #   then fails DKIM, which on this IP means everything lands in junk, and
  #   nothing in any log on this host says why.
  #
  #   `dkim.domains.<d>.selectors.<s>.keyFile` takes the key outright, so it
  #   comes from sops like every other secret, survives a reinstall, and — the
  #   practical part — the public record can be PUBLISHED BEFORE the first
  #   deploy, because `clan vars get ernst mail-dkim/dkim.txt` exists as soon as
  #   the generator has run.  DNS propagation and first delivery stop racing.
  #
  #   The secret/public pair is modules/nix-remote-builder.nix's shape:
  #   `dkim.key` secret, `dkim.txt` not.  `dkim.txt` is a PUBLIC KEY — it is
  #   about to be a TXT record readable by the entire internet — and marking it
  #   secret would only mean needing sops to read something Cloudflare serves.
  #
  #   NOT SHARED: only ernst signs mail.  Rotating is a new selector, not a new
  #   key under the old name — publish the second TXT, switch the selector,
  #   remove the first after a week.  Overwriting `mail` in place breaks every
  #   message in flight.
  ##############################################################################
  clan.core.vars.generators.mail-dkim = {
    files."dkim.key" = {
      secret       = true;
      restartUnits = [ "mail-secrets.service" "container@mail.service" ];
    };
    files."dkim.txt".secret = false;

    runtimeInputs = [ pkgs.rspamd pkgs.coreutils ];

    # rspamadm writes the private key to -k and the DNS record to stdout.
    # 2048-bit RSA: RFC 8301 sets the floor at 1024 and recommends 2048, and
    # ed25519 is still rejected as invalid by enough validators that
    # simple-nixos-mailserver's own option documentation warns against using it
    # alone.  On an IP with this reputation, nothing gets to be clever.
    script = ''
      set -euo pipefail
      rspamadm dkim_keygen -d ${baseDomain} -s mail -b 2048 -k "$out/dkim.key" > "$out/dkim.txt"
      if [ ! -s "$out/dkim.key" ] || [ ! -s "$out/dkim.txt" ]; then
        echo "  ✗ rspamadm dkim_keygen produced an empty key or record" >&2
        exit 1
      fi
    '';
  };

  ##############################################################################
  # noreply@ — the credential Nextcloud sends system mail with.
  #
  # ── GENERATED, NOT PROMPTED, AND THAT IS WHY IT IS ITS OWN GENERATOR ───────
  #
  #   Nobody types this password: one machine hands it to another.  A prompt
  #   would be a human-chosen secret for an account no human logs into, and it
  #   would make this generator block every deploy of every machine until
  #   somebody answered it — which is what the prompted `mail-accounts`
  #   already does and the reason adding a sixth mailbox there would have
  #   RE-PROMPTED ALL FIVE existing passwords.  A generator is satisfied only
  #   when every file it declares exists, so a new file in an old generator
  #   re-runs the whole thing.  A separate generator re-runs only itself.
  #
  #   It is NOT shared: both readers — this container and Nextcloud's — are on
  #   ernst, so a per-machine var reaches both.  containers/nextcloud.nix
  #   reads it across, the way every consumer reads the OIDC pairs declared in
  #   containers/authelia.nix.
  #
  # ── BOTH HALVES, FOR THE USUAL REASON ─────────────────────────────────────
  #
  #   Dovecot verifies the hash; Nextcloud must send the password itself,
  #   because SMTP AUTH has no hash-only shape.  Same split as lutz's, and the
  #   same shape as modules/nix-remote-builder.nix's keypair.
  #
  #   `tr -d` on the base64 punctuation follows containers/nextcloud.nix's
  #   admin password: this string is pasted into a JSON blob and read back by
  #   PHP, and the punctuation buys nothing while costing quoting mistakes.
  ##############################################################################
  clan.core.vars.generators.mail-system-sender = {
    files."noreply.hash" = {
      secret       = true;
      restartUnits = [ "mail-secrets.service" "container@mail.service" ];
    };
    files."noreply.plain" = {
      secret       = true;
      restartUnits = [ "nextcloud-secrets.service" "container@nextcloud.service" ];
    };

    runtimeInputs = [ pkgs.coreutils pkgs.openssl pkgs.mkpasswd ];
    script = ''
      set -euo pipefail
      pw=$(openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-48)
      if [ "''${#pw}" -lt 32 ]; then
        echo "  ✗ openssl produced a short password (''${#pw} chars)" >&2
        exit 1
      fi
      printf '%s' "$pw" > "$out/noreply.plain"
      printf '%s' "$pw" | mkpasswd -s > "$out/noreply.hash"
      if [ ! -s "$out/noreply.hash" ]; then
        echo "  ✗ mkpasswd produced nothing" >&2
        exit 1
      fi
    '';
  };

  # Make Traefik's Cloudflare token restart THIS container's staging too, so a
  # rotation does not leave the mail certificate renewing against a dead
  # credential.  A list option merged from a second module; containers/
  # traefik.nix still owns the generator and its prompt.
  clan.core.vars.generators.traefik-acme.files."cloudflare.env".restartUnits = [
    "mail-secrets.service"
    "container@mail.service"
  ];

  # Host side of the container's veth — a VLAN-90 port on br0.  Identical
  # rationale to vb-miniflux / vb-nextcloud / vb-jellyfin; see containers/
  # traefik.nix for the long form of KeepMaster-not-Bridge and why a bridge
  # port carries no address of its own.
  systemd.network.networks."60-vb-mail" = {
    matchConfig.Name = "vb-mail";
    networkConfig = {
      KeepMaster          = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = 90; PVID = 90; EgressUntagged = 90; } ];
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Same VLAN race, same idempotent backstop, same "-" prefix as every other
  # nspawn container on br0: networkd applies [BridgeVLAN] only once it observes
  # the link's master, and nspawn sets that master out of band.  With
  # DefaultPVID = "none" on br0 a miss is fail-CLOSED.
  # `bridge vlan show dev vb-mail` is the check.
  systemd.services."container@mail".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev vb-mail vid 90 pvid untagged"
  ];

  ##############################################################################
  # The container.
  ##############################################################################
  containers.mail = {
    autoStart = true;
    ephemeral = false;

    # MAC from the allocation table in machines/ernst/networking.nix; the DHCP
    # reservation 10.0.90.31 on the UDM-Pro keys on it (manual step).  Sequence
    # 17, and the last octet is 8 + seq as everywhere else on this bridge.
    #
    # The container is `mail` and not `mailserver` for the reason hass is not
    # `home-assistant`: nspawn names the host veth `vb-<container>` and an
    # interface name caps at 15 characters, which fails at container START and
    # not at eval, so a clean build proves nothing about it.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = "02:00:00:90:00:17";

    bindMounts = {
      # The Maildir.
      "/var/vmail" = {
        hostPath   = "${stateRoot}/vmail";
        isReadOnly = false;
      };

      # The QUEUE — accepted-but-undelivered mail.  This is the bind that makes
      # a container restart lossless.
      "/var/lib/postfix" = {
        hostPath   = "${stateRoot}/postfix";
        isReadOnly = false;
      };

      "/var/lib/dovecot" = {
        hostPath   = "${stateRoot}/dovecot";
        isReadOnly = false;
      };

      # Rspamd's state, and Redis's — the Bayes classifier.
      "/var/lib/rspamd" = {
        hostPath   = "${stateRoot}/rspamd";
        isReadOnly = false;
      };
      "/var/lib/redis-rspamd" = {
        hostPath   = "${stateRoot}/redis";
        isReadOnly = false;
      };

      # This container's own ACME account and certificate.
      "/var/lib/acme" = {
        hostPath   = "${stateRoot}/acme";
        isReadOnly = false;
      };

      "${secretsDir}" = {
        hostPath   = secretsDir;
        isReadOnly = true;
      };
    };

    config = { config, pkgs, lib, ... }: {
      imports = [ inputs.simple-nixos-mailserver.nixosModules.default ];

      system.stateVersion = "26.05";

      ##########################################################################
      # Networking — one leg, and the ONE container on this host that does not
      # point at Technitium.  See convention 4 in the header: Rspamd's DNSBL
      # lookups must come from a resolver that is not shared, or every
      # blocklist silently reads as empty.  `mailserver.localDnsResolver`
      # (default true) is what provides kresd; these lines only make sure
      # nothing overrides resolv.conf out from under it.
      ##########################################################################
      networking.useHostResolvConf = false;
      networking.useNetworkd = true;

      # ── resolved OFF, AND THIS IS THE LINE THE WHOLE DNSBL ARGUMENT ──────
      #    HANGS ON
      #
      #   Every sibling container leaves systemd-resolved on, because
      #   `networking.useNetworkd = true` turns it on by default and pointing
      #   it at Technitium is the right answer there.  Here it is the wrong
      #   one twice over.  Left enabled, resolved owns /etc/resolv.conf via
      #   the 127.0.0.53 stub, kresd sits on 127.0.0.1:53 with nothing talking
      #   to it, and — because this link deliberately takes no DNS= and sets
      #   UseDNS=false — resolved falls through to its compiled-in FallbackDNS
      #   at Cloudflare and Google.  Which is to say: every Rspamd blocklist
      #   query would arrive at Spamhaus from a public resolver and be REFUSED
      #   with 127.255.255.254, exactly as measured in the header, and the
      #   filter would read every list as empty and say nothing about it.
      #
      #   Off, `networking.resolvconf.enable` flips true (its default is the
      #   negation of this) and the kresd module's own
      #   `resolvconf.useLocalResolver = mkDefault true` writes
      #   `nameserver 127.0.0.1`.  That is upstream's intended wiring; it is
      #   only reachable once resolved is out of the way.
      #
      #   The assertion below is the check, because this is a SILENT failure:
      #   mail still flows, spam just stops being caught.
      services.resolved.enable = false;

      assertions = [
        {
          assertion = config.networking.resolvconf.useLocalResolver;
          message = ''
            containers/mail.nix: /etc/resolv.conf would not point at kresd.

            Rspamd's DNSBL lookups must come from this container's own
            recursive resolver — a query that arrives at Spamhaus via a shared
            or public resolver is refused, and Rspamd scores the refusal as
            "not listed".  The filter keeps running and stops working.
          '';
        }
      ];

      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          IPv6AcceptRA = false;
          # SN2: v4 only.  M18 measured that IPv6AcceptRA alone blocks an RA
          # but NOT link-local assignment; this is the line that actually makes
          # `ip -6 addr show dev eth0` empty.
          #
          # It matters more here than in any sibling.  A v6 listener on :25
          # would be reachable from the internet WITHOUT passing the UDM-Pro
          # DNAT, so it would carry no ledger row and no port forward to
          # remove — and fail2ban's jails below are v4 chains.  Reachable and
          # unbannable at once is exactly what SN2 exists to prevent.
          LinkLocalAddressing = "no";
        };
        # No DNS= / Domains= here, unlike every sibling: kresd is the resolver.
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      # Same 20 s cap as every sibling: a DHCP failure must leave a RUNNING
      # container with one failed unit, not a host-side restart loop.
      systemd.network.wait-online.timeout = 20;

      # ── The firewall, and the inverted negative control ───────────────────
      #
      #   `mailserver.openFirewall` opens exactly the ports the enables below
      #   turn on: 25, 465, 993, 4190.  ON ALL INTERFACES AND FROM EVERY
      #   SOURCE, which is the point — :25 must answer any MTA on earth and the
      #   client ports must answer Sarinah's phone from whatever address her
      #   carrier hands it.  This is the one container here that cannot work
      #   from a peer list.
      #
      #   SO THE USUAL NEGATIVE CONTROL IS INVERTED FOR THOSE FOUR PORTS.
      #   `nc -vz 10.0.90.31 25` from ernst SUCCEEDS, and that is correct; in
      #   every sibling file the equivalent is refused by design and a reader
      #   who has internalised that will misread a success here as a leak.
      #
      #   IT STILL HOLDS FOR THE EXPORTER.  9154 is the one rule below that
      #   names a peer, and `curl http://10.0.90.31:9154/metrics` from ernst IS
      #   REFUSED — ernst is 10.0.50.10 and matches nothing.
      #
      #   extraCommands, not extraInputRules: the latter is declared
      #   unconditionally but consumed only under networking.nftables, so here
      #   it would produce no rule and no warning.
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${monitoringAddr}/32 --dport ${toString exporterPort} -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${traefikAddr}/32    --dport ${toString mtaStsPort}  -j nixos-fw-accept
      '';

      ##########################################################################
      # The MTA-STS policy file.
      #
      # ── THE ONE PIECE OF MAIL THAT DOES RIDE TRAEFIK ──────────────────────
      #
      #   Convention 1 in the header says this container has no hostname on
      #   the proxy, and that is still true of SMTP, IMAP and ManageSieve.
      #   MTA-STS is the exception the header already names: RFC 8461 puts the
      #   policy at a fixed HTTPS URL, so it is HTTP, so it goes where all HTTP
      #   goes here.  It is served from THIS container rather than a web one
      #   because the policy's only content is this server's own MX and the
      #   two must not drift.
      #
      # ── WHY A WEB SERVER AT ALL ───────────────────────────────────────────
      #
      #   Traefik is a proxy and has no static-file capability; every service
      #   in traefik.nix is a loadBalancer to a backend.  The alternatives were
      #   a Yaegi plugin — which containers/traefik.nix rejects on principle,
      #   an unpinned network fetch at proxy startup — or parking the file in
      #   an unrelated web container, which spreads mail across two.  nginx is
      #   already in this fleet and this vhost is four lines.
      #
      # ── `mode: testing`, NOT `enforce` ────────────────────────────────────
      #
      #   Testing means senders CHECK the policy and REPORT failures, but still
      #   deliver if TLS does not validate.  Enforce means they bounce instead.
      #   This is DMARC's `p=none` again, for the same reason and with the same
      #   escalation: a certificate renewal that goes wrong under `enforce`
      #   does not degrade mail, it STOPS it, and the first symptom is a sender
      #   bouncing silently to someone else's postmaster.  Move to `enforce`
      #   once the TLS-RPT reports (now enabled, and this is what makes them
      #   meaningful) have been clean for a few weeks.
      #
      #   `max_age` 86400 and not the RFC's suggested weeks: in testing mode a
      #   short cache is the point, because it is what lets a bad policy be
      #   withdrawn in a day rather than inherited by every sender for a month.
      #   Raise it with the move to enforce.
      #
      #   THE `id` IN THE _mta-sts TXT RECORD MUST CHANGE whenever this file
      #   does, or senders keep the cached copy — the record is the version
      #   stamp and the file is the payload.  docs/guides/mail.md pairs them.
      ##########################################################################
      services.nginx = {
        enable = true;
        # No recommended*Settings: this vhost serves one 100-byte static file
        # to remote MTAs. Gzip, proxy tuning and the TLS defaults are all for
        # workloads this is not, and TLS in particular is Traefik's job here.
        virtualHosts."mta-sts.${baseDomain}" = {
          listen = [ { addr = "0.0.0.0"; port = mtaStsPort; } ];
          locations."= /.well-known/mta-sts.txt" = {
            # CRLF line endings: RFC 8461 §3.2 specifies them, and while most
            # implementations tolerate LF there is no reason to find out which
            # do not.
            alias = pkgs.writeText "mta-sts.txt" (
              lib.concatStringsSep "\r\n" [
                "version: STSv1"
                "mode: testing"
                "max_age: 86400"
                "mx: ${fqdn}"
                ""
              ]
            );
            extraConfig = ''
              default_type text/plain;
              add_header Cache-Control "max-age=86400";
            '';
          };
        };
      };

      ##########################################################################
      # The mail server.
      ##########################################################################
      mailserver = {
        enable = true;

        # A fresh install on the nixos-26.05 branch starts at the branch's
        # current migration level.  It is NOT `system.stateVersion` and not a
        # string; upstream's assertions name the value to move to when a
        # migration is owed, and moving it without running the migration is
        # how data gets lost.
        stateVersion = 5;

        fqdn    = fqdn;
        domains = [ baseDomain ];

        # Only required by tlsrpt today, but it is the address RFC 2142 says
        # must exist and it is aliased onto admin@ below, so state it.
        systemContact = "postmaster@${baseDomain}";

        # The Maildir's owner, pinned into the 3000 block rather than left at
        # upstream's 5000 — see the uid note in the header.
        storage = {
          uid = vmailUid;
          gid = vmailGid;
        };

        # ── The five mailboxes ──────────────────────────────────────────────
        #
        #   hashedPasswordFile, not hashedPassword: the latter is a convenience
        #   that puts the hash in the world-readable Nix store.  These come out
        #   of sops via mail-secrets above.
        #
        #   EVERY PERSON IS REACHABLE UNDER BOTH THEIR NAMES.  This fleet
        #   identifies people by a three-letter username (`lgo`, `sgo`, `mgo`)
        #   and addresses them by their first name — containers/authelia.nix
        #   carries the same split, and `go` is the one account where the two
        #   coincide.  So each mailbox lives at the human address and carries
        #   its username form as an alias: mail to `lgo@` lands in `lutz@`.
        #
        #   THAT IS ROUTING, NOT A SECOND ACCOUNT.  An alias costs no mailbox,
        #   no password and no Maildir — it is a line in Postfix's virtual map.
        #   What it buys is that neither form ever bounces, which matters
        #   precisely because the household will use both without thinking
        #   about which one is canonical.
        #
        #   ALIASES, NOT A CATCH-ALL.  A catch-all was considered and rejected:
        #   it turns admin@ into the noisiest mailbox in the house the first
        #   time a dictionary attack finds the domain, and Rspamd then has to
        #   earn its keep on traffic that should never have been accepted.
        #
        #   `sabine@` IS DELIBERATELY ABSENT.  An earlier revision aliased it
        #   onto Sarinah's mailbox, because Authelia's account for her was then
        #   called `sabine`.  PR #278 renamed that account to `sarinah` and
        #   #280 renamed it again to `sgo`, so the address is no longer an
        #   identifier for anything — and it never received mail, because this
        #   server did not exist.  An alias for an address that was never
        #   deliverable and now names nobody is just a trap for the next
        #   reader.  Her Unix username on biene is still `sabine`
        #   (modules/users/sabine.nix) and that is untouched and unrelated.
        accounts."admin@${baseDomain}" = {
          hashedPasswordFile = "${secretsDir}/admin.hash";
          # RFC 2142's required addresses, plus the DMARC/TLS-RPT rua target.
          # An MX with no postmaster@ and no abuse@ is a small red flag to some
          # receivers and a large one to every abuse desk — and this server can
          # afford neither.
          #
          # THEY LIVE ON THEIR OWN MAILBOX RATHER THAN ON A PERSON'S, which is
          # the whole reason admin@ exists as a fifth account: DMARC aggregate
          # reports are daily XML from every receiver that bothers, and abuse@
          # is by construction where strangers complain.  Neither belongs in an
          # inbox somebody reads for correspondence.
          aliases = [
            "postmaster@${baseDomain}"
            "abuse@${baseDomain}"
            "hostmaster@${baseDomain}"
            "dmarc@${baseDomain}"
          ];
        };

        accounts."lutz@${baseDomain}" = {
          hashedPasswordFile = "${secretsDir}/lutz.hash";
          aliases = [ "lgo@${baseDomain}" ];
        };

        accounts."sarinah@${baseDomain}" = {
          hashedPasswordFile = "${secretsDir}/sarinah.hash";
          aliases = [ "sgo@${baseDomain}" ];
        };

        accounts."max@${baseDomain}" = {
          hashedPasswordFile = "${secretsDir}/max.hash";
          aliases = [ "mgo@${baseDomain}" ];
        };

        # The couch/admin account.  NO ALIAS, and that is not an oversight:
        # `go` is already both the username and the local part, so there is no
        # second form to route.  containers/htpc.nix owns the Unix user of the
        # same name on ernst; this mailbox is unrelated to it beyond sharing a
        # word.
        accounts."go@${baseDomain}" = {
          hashedPasswordFile = "${secretsDir}/go.hash";
        };

        # The sixth mailbox, and the only one no human reads.  Nextcloud
        # authenticates as this to send share links, calendar invitations and
        # password resets — see containers/nextcloud.nix.
        #
        # A REAL MAILBOX AND NOT AN ALIAS, because SMTP AUTH needs a login of
        # its own: an alias is a routing rule, not an identity Dovecot can
        # authenticate.  The Maildir it gets is the point rather than waste —
        # bounces and out-of-office replies to automated mail land somewhere
        # inspectable instead of in a person's inbox, which is the whole
        # reason this is not just `admin@`.
        #
        # NO USERNAME ALIAS, unlike the five above: there is no person behind
        # it, so there is no second name to be reachable under.
        accounts."noreply@${baseDomain}" = {
          hashedPasswordFile = "${secretsDir}/noreply.hash";
        };

        # ── Ports: wrapper-mode only, which is upstream's default and RFC
        #    8314's recommendation.  143, 587, 110 and 995 all stay OFF.
        #
        #   Leaving 587 off is a real decision and not an oversight: aerc, K-9
        #   and Thunderbird all speak implicit TLS on 465, so 587 would add a
        #   STARTTLS port — downgradeable by an active attacker — to the
        #   internet-facing surface in exchange for compatibility with no
        #   client this household owns.
        enableImapSsl       = true;
        enableSubmissionSsl = true;
        enableManageSieve   = true;

        # See the firewall note above: this opens exactly the four ports the
        # enables turn on.
        openFirewall = true;

        # ── The special-use folders ─────────────────────────────────────────
        #
        #   ALL FIVE ARE RESTATED, INCLUDING THE FOUR THAT MATCH UPSTREAM, and
        #   that is not verbosity.  `mailserver.mailboxes` carries no `type`,
        #   so it is a freeform attrset — and an option's `default` applies
        #   only when there is NO definition.  Naming one mailbox here
        #   replaces the whole set, silently taking Drafts, Sent and Junk with
        #   it.  Adding `Archive` alone would have deleted three working
        #   folders.
        #
        #   TWO CHANGES FROM UPSTREAM'S DEFAULT, both found by using it:
        #
        #     Trash was `auto = "no"` — declared, so clients know what it is
        #     called, but never created.  Nextcloud Mail and K-9 both then
        #     show no Trash folder and deleting falls back to an IMAP flag,
        #     which is not what anybody means by delete.
        #
        #     Archive was absent entirely.  It is in RFC 6154 and every client
        #     here has a one-key archive action; without the folder the key
        #     does nothing.
        #
        #   `auto = "subscribe"` and not `"create"`: create makes the folder
        #   exist, subscribe also puts it in the client's list.  An unsubscribed
        #   folder is invisible in Nextcloud Mail, which is the same symptom as
        #   it not existing and a longer walk to diagnose.
        #
        #   EXACTLY ONE `\\Junk` IS REQUIRED — dovecot.nix derives the Rspamd
        #   learn-as-spam target from this attrset and asserts on the count.
        #   `fts_autoindex = false` on Trash and Junk follows upstream: there
        #   is no reason to spend index on either.
        mailboxes = {
          Trash   = { auto = "subscribe"; special_use = "\\Trash";   fts_autoindex = false; };
          Junk    = { auto = "subscribe"; special_use = "\\Junk";    fts_autoindex = false; };
          Drafts  = { auto = "subscribe"; special_use = "\\Drafts"; };
          Sent    = { auto = "subscribe"; special_use = "\\Sent"; };
          Archive = { auto = "subscribe"; special_use = "\\Archive"; };
        };

        # ── DKIM from sops, not from /var/dkim ──────────────────────────────
        #   The long argument is on the mail-dkim generator above.
        dkim.domains.${baseDomain}.selectors.mail.keyFile = "${secretsDir}/dkim.key";

        # ── Both report SENDERS are ON, and they were not always ────────────
        #
        #   These make this server mail DAILY REPORTS TO STRANGERS about their
        #   SPF/DKIM failures and TLS negotiations — aggregate DMARC reports to
        #   whatever `rua=` each sending domain publishes, and TLS-RPT summaries
        #   to whatever `_smtp._tls` asks for.  That is ordinary good
        #   citizenship on a healthy IP and it is how the ecosystem notices its
        #   own breakage.
        #
        #   THEY SHIPPED OFF, DELIBERATELY, AND THE REASON IS WORTH KEEPING.
        #   M31 was built while this address was Barracuda-listed behind a
        #   generic pool PTR, and unsolicited daily volume to parties who never
        #   asked, from a sender they have no relationship with, is the exact
        #   traffic shape that deepens a reputation problem rather than one it
        #   survives.  Both halves of that premise then expired — the delisting
        #   took and Vodafone set the PTR (the header's before/after table) —
        #   and the delivery gate in docs/guides/mail.md passed end to end:
        #   inbound from Gmail arrived, the reply went out.
        #
        #   SO THIS IS A SEPARATE COMMIT FROM THE ONE THAT PROVED DELIVERY, on
        #   purpose.  Flipping them in the same change would have put two
        #   untested things in one deploy, and the first of them was the one
        #   the whole milestone turned on.
        #
        #   IF DELIVERABILITY EVER DEGRADES, THESE ARE THE FIRST THING BACK
        #   OFF — before the smarthost, before anything else.  They are the
        #   only outbound traffic this server generates that nobody asked for,
        #   so they are the cheapest thing to stop sending.
        #
        #   NOTE WHAT THIS DOES NOT AFFECT.  RECEIVING reports is a property of
        #   our own _dmarc and _smtp._tls records pointing at dmarc@goclan.org;
        #   it needs no option here and has worked since those records were
        #   published.  Turning these on is about what we WRITE, not what we
        #   read; `_smtp._tls` went in with MTA-STS, so the reading half works
        #   too.
        dmarcReporting.enable = true;
        tlsrpt.enable         = true;

        # ── TLS ─────────────────────────────────────────────────────────────
        #   The cert itself is requested by the security.acme block below.
        x509.useACMEHost = fqdn;

        # monit.  Off: this fleet has one alerting path (the ntfy topic) and
        # monit's notifier is SMTP, so it would be a mail server emailing about
        # itself. Unit state reaches Alertmanager through the ordinary
        # `clanarchy-container-units` collector; queue depth reaches Prometheus
        # through the exporter below.
        monitoring.enable = false;
      };

      # ── A SECOND ACME CLIENT, NOT A SHARE OF TRAEFIK'S acme.json ──────────
      #
      #   Traefik holds one wildcard (goclan.org + *.goclan.org) in a single
      #   JSON blob at /srv/state/traefik/acme.json, written by lego as Traefik
      #   drives it.  Reaching into that file from another container would mean
      #   parsing a private on-disk format on a schedule, with no signal when
      #   the renewal that was supposed to refresh it did not happen.
      #
      #   Requesting mail.goclan.org separately costs one more certificate and
      #   buys a normal, observable renewal with its own systemd timer and its
      #   own failure.  IT DOES NOT COLLIDE WITH TRAEFIK'S RATE LIMIT: Let's
      #   Encrypt's five-duplicates-per-week ceiling is per exact name set, and
      #   `mail.goclan.org` alone is a different set from
      #   `goclan.org + *.goclan.org`.
      #
      #   DNS-01, like Traefik, and for the harder version of Traefik's reason:
      #   HTTP-01 would need :80 forwarded from the WAN, which this fleet
      #   deliberately does not do and which three separate comments in
      #   traefik.nix warn against opening.
      security.acme = {
        acceptTerms = true;
        defaults.email = "lutz0go@gmail.com";
        certs.${fqdn} = {
          dnsProvider = "cloudflare";
          # `environmentFile`, not `credentialsFile` — 26.05 renamed it, and
          # not to `credentialFiles`, which is the different (per-variable,
          # LoadCredential-backed) option next to it.  This one is a KEY=value
          # file read as systemd's EnvironmentFile, which is exactly the shape
          # containers/traefik.nix's generator already emits.
          environmentFile = "${secretsDir}/cloudflare.env";
          # Same public resolvers and the same 60 s delay traefik.nix pins, and
          # for the two reasons recorded there: Technitium is authoritative for
          # the per-service LAN zones and would answer an authoritative
          # NXDOMAIN for _acme-challenge forever, and goclan.org's SOA minimum
          # of 1800 caches a too-early NXDOMAIN for thirty minutes, poisoning
          # every retry.  Measured 2026-08-23.
          dnsResolver         = "1.1.1.1:53";
          dnsPropagationCheck = true;
          reloadServices      = [ "postfix.service" "dovecot.service" ];
        };
      };

      # ── AND THE TWO DAEMONS HAVE TO BE IN THE `acme` GROUP, WHICH ────────
      #    simple-nixos-mailserver DOES NOT DO FOR YOU
      #
      #   `mailserver.x509.useACMEHost` sets `reloadServices` on the cert and
      #   nothing else — it points Postfix and Dovecot at
      #   /var/lib/acme/<fqdn>/{fullchain,key}.pem and does not arrange for
      #   either to be able to READ them.  The acme module writes that
      #   directory `u=rwX,g=rX,o=` owned by `acme:acme`, and smtpd runs as
      #   `postfix`, so without these two lines every TLS handshake fails on a
      #   key the process cannot open.
      #
      #   Checked on the evaluated config rather than assumed:
      #   `users.groups.acme.members` is empty and neither daemon carried the
      #   group.  The symptom would have been a container that starts cleanly
      #   and then refuses :465 and :993 — the two ports the whole household
      #   uses — with the failure in a TLS log line and not in unit state.
      users.users.postfix.extraGroups  = [ "acme" ];
      users.users.dovecot2.extraGroups = [ "acme" ];

      # Pin Redis's ids — see the `redisUid` note at the top of this file.
      # nspawn passes ids through unmapped, so an unpinned per-server user is
      # a number chosen by useradd that ends up owning Bayes on zdata.
      users.users.redis-rspamd.uid  = redisUid;
      users.groups.redis-rspamd.gid = redisGid;

      # ── fail2ban, because CrowdSec cannot see this container ──────────────
      #
      #   :465 and :993 are about to accept password authentication from the
      #   whole internet, and SMTP/IMAP brute force is relentless and cheap.
      #   CrowdSec's single acquisition is Traefik's journal (crowdsec.nix), so
      #   none of this traffic reaches it.
      #
      #   `backend = "systemd"` is the module default and is what makes this
      #   work in nspawn at all — there is no /var/log/mail.log here, only the
      #   journal.
      #
      #   RFC1918 IS WHITELISTED, and crowdsec.nix's whitelist is why: a
      #   household member mistyping their password from the sofa must not get
      #   the LAN banned.  The blast radius is smaller here than it is at the
      #   proxy, but the reasoning is identical and the fix is one line.
      services.fail2ban = {
        enable = true;
        bantime  = "1h";
        maxretry = 5;
        ignoreIP = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" ];

        jails.postfix-sasl.settings = {
          filter   = "postfix[mode=auth]";
          action   = ''iptables-multiport[name=postfix-sasl, port="25,465"]'';
          maxretry = 5;
        };

        # aggressive mode also counts aborted connections, which is most of
        # what an IMAP password sweep looks like from the server's side.
        jails.dovecot.settings = {
          filter   = "dovecot[mode=aggressive]";
          action   = ''iptables-multiport[name=dovecot, port="993,4190"]'';
          maxretry = 5;
        };
      };

      # ── Metrics — and this one genuinely clears SN3 ───────────────────────
      #
      #   SN3 forbids a scrape job that can only ever read `up == 0`, because
      #   such a target is indistinguishable from an outage and unit state
      #   already covers that.  Nextcloud, Home Assistant and Karakeep each
      #   carry a written refusal on those grounds.
      #
      #   This is not that.  QUEUE DEPTH AND DEFERRAL AGE ARE UNANSWERABLE FROM
      #   UNIT STATE: a mail server whose queue is filling because a receiver
      #   started deferring is perfectly healthy by every systemd measure, and
      #   on this host that is the single most likely thing to go wrong.  It is
      #   the metric the header's whole deliverability argument predicts.
      #
      #   It reads the journal rather than a logfile (`systemd.enable`,
      #   default) so nothing has to write /var/log/mail.log for it.  It binds
      #   0.0.0.0 rather than the module's localhost default because it has to
      #   be reachable across the veth; what bounds it is the single accept
      #   rule above.
      services.prometheus.exporters.postfix = {
        enable        = true;
        listenAddress = "0.0.0.0";
        port          = exporterPort;
        systemd.enable = true;
      };

      environment.systemPackages = with pkgs; [
        # For the verification steps in docs/guides/mail.md — an SMTP
        # conversation from inside the container, and a DNS answer that came
        # through kresd rather than through whatever the operator's laptop
        # thinks.
        swaks
        dig
      ];

      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
