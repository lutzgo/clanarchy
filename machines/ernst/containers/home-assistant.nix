# machines/ernst/containers/home-assistant.nix
#
# Home Assistant — the household's home-automation hub (M24 in
# docs/roadmap.md).  An nspawn container with TWO legs on br0, serving
# `ha.goclan.org` through Traefik on both entrypoints, with its own accounts
# and no forward-auth.
#
# ── WHAT THIS REPLACES ──────────────────────────────────────────────────────
#
#   A Home Assistant instance on a Raspberry Pi, outside this repo and outside
#   every control the rest of ernst has: no monitoring, no CrowdSec, no
#   impermanence, no ZFS snapshots, and no way to say what it is running.  The
#   desktop has been pointing a Noctalia `hassio` bar widget at it for months
#   (modules/desktop/noctalia-hm.nix) without the repo ever describing it.
#
#   IT STANDS UP EMPTY.  Nothing is migrated from the Pi — no configuration,
#   no history, no Zigbee network.  Devices are re-paired.  That was lgo's
#   call and it is the cheaper half of a decision whose expensive half is
#   below, under "IF RE-PAIRING TURNS OUT TO BE TOO MUCH".
#
# ── WHY THE nspawn TIER ─────────────────────────────────────────────────────
#
#   `services.home-assistant` is a first-class NixOS module, so architecture
#   invariant #1 puts it here: the podman tier exists for upstreams that ship
#   only an OCI image (storyteller, cwa, romm, tubesync), and this is not one.
#   A service moves UP a tier when it starts talking to the internet on its own
#   behalf with a killswitch requirement, not when it merely becomes reachable
#   from outside — containers/nextcloud.nix and containers/immich.nix both
#   argue this and this file takes the same side.
#
# ── TWO LEGS, AND THE SECOND ONE IS THE WHOLE POINT ─────────────────────────
#
#   eth0  VLAN 90 (Services)  — Traefik reaches the web UI here.  The ordinary
#                               shape every other container on this bridge has.
#   iot0  VLAN 20 (IoT)       — the segment the household's wifi devices are
#                               on.  This leg exists for DISCOVERY.
#
#   Unicast to VLAN 20 needs no leg at all: the UDM-Pro has all of LAN, IoT,
#   HA, DNS-Container, Servers and Matter in the `Internal` zone with
#   `Internal -> Internal: Allow All`, so a VLAN-90 address can already open a
#   socket to any IoT device.  What is NOT routable is mDNS and SSDP, which are
#   link-local by definition — and this repo has refused to relay them across a
#   firewall boundary twice, in writing:
#
#     "the fix for that is emphatically NOT to enable an SSDP/mDNS relay
#      across a firewall boundary to save one config field"
#         — M8's session prompt, docs/roadmap.md
#
#     "Add a VLAN here only if the host itself needs to speak on it — which
#      would also put Avahi's unpinned mDNS reflector onto that VLAN ... so it
#      is not a free change."
#         — machines/ernst/networking.nix, note 3
#
#   A second veth is the answer that is consistent with both: Home Assistant is
#   ON the segment it discovers, and no multicast crosses a boundary.  VLAN 20
#   is already tagged on ernst's trunk, so this costs no switch-port change.
#
#   WHY NOT VLAN 30, WHICH IS LITERALLY NAMED "HA".  It exists on the UDM-Pro
#   (10.0.30.0/24) and is deliberately NOT carried on ernst's trunk.  Carrying
#   it means a port-profile edit on USW Pro 24 PoE port 6, and it buys nothing:
#   the leg that matters is the one on the segment the DEVICES are on, and the
#   wifi devices are on 20.  VLAN 30 retires with the Pi.
#
# ── NO forward-auth ON THIS HOSTNAME ────────────────────────────────────────
#
#   `ha.goclan.org` is in `appApiHosts` (containers/ingress-policy.nix).  The
#   test that file states is whether EVERY client can render a login page and
#   follow a 302, and the companion app cannot: it exchanges credentials once
#   at /auth/token and then holds an authenticated WebSocket at /api/websocket
#   for the life of the session, with no browser anywhere in the process.  It
#   is also the endpoint the app PUSHES location to, in the background, with no
#   user present to log in to anything.
#
#   The compensations are unusually strong for a name in that list, and they
#   are named rather than assumed: Home Assistant ships `ip_ban_enabled` — a
#   real per-source ban written to ip_bans.yaml — and native TOTP MFA on its
#   own accounts.  Both are configured below.  `wan-ratelimit`,
#   `wan-login-ratelimit` and CrowdSec sit in front of them.
#
#   THE ip_ban CONTROL HAS A PREREQUISITE and it is one line: `trusted_proxies`
#   must name Traefik, or every request appears to come from 10.0.90.12 and the
#   ban either never fires or locks out the entire household at once.  This is
#   ledger row L14's lesson (containers/nextcloud.nix) in a second costume.
#
# ── THREAD AND MATTER ARE NOT IN THIS FILE.  DELIBERATELY. ──────────────────
#
#   Two Nabu Casa ZBT-2 radios are plugged into ernst.  One runs Zigbee through
#   ZHA, below.  The other is bound and aliased here and opened by nothing,
#   because the Thread half is M25 and it brings conflicts that do not belong
#   in the first deploy of a new container:
#
#     * `services.openthread-border-router` sets
#       net.ipv6.conf.<backbone>.accept_ra = 2 and
#       net.ipv6.conf.all.forwarding = 1 — a deliberate exception to standing
#       note SN2, which is why every interface in this file says otherwise;
#     * otbr-agent needs /dev/net/tun plus CAP_NET_ADMIN and CAP_NET_RAW inside
#       an nspawn container, which nothing on this host has yet;
#     * it wants avahi PUBLISHING inside the container, where this file wants
#       avahi nowhere near it;
#     * and the second ZBT-2 has to be reflashed with OpenThread RCP firmware,
#       a manual step outside the repo that would gate the whole deploy.
#
#   Binding the radio now costs nothing and makes M25 a service addition rather
#   than a container restart.
#
# ── THE CONTAINER IS CALLED `hass`, NOT `home-assistant` ────────────────────
#
#   Not a preference.  systemd-nspawn's --network-bridge names the host side of
#   the veth `vb-<container>`, and a Linux interface name is capped at 15
#   characters (IFNAMSIZ - 1).  `vb-home-assistant` is 17 and the link cannot
#   be created at all.  `vb-hass` is 7.
#
#   So: the FILE is home-assistant.nix, the SERVICE is home-assistant.service
#   inside, and the MACHINE is `hass` —
#   `machinectl`, `nixos-container run hass`, `systemctl restart container@hass`.
#
# ── HACS, AND THE LINE IT DRAWS THROUGH THIS CONTAINER ──────────────────────
#
#   The Home Assistant Community Store is installed, as a declarative custom
#   component: ./pkgs/hacs.nix builds it and `customComponents` below is the one
#   line that wires it in.  HACS ITSELF is therefore under the same control as
#   everything else on this host — a version in a file, a hash over the bytes,
#   and an update that is a deploy.
#
#   WHAT HACS DOWNLOADS IS NOT.  That is the whole trade and it should be made
#   out loud rather than discovered: HACS browses GitHub and writes what you
#   pick into ${configDir}/custom_components (integrations) and
#   ${configDir}/www/community (themes and Lovelace cards), at runtime, from the
#   browser.  Those files are STATE.  They land on zdata/state next to .storage,
#   they are covered by that dataset's snapshots, and nothing in this repo says
#   what they are.  `ls /srv/state/home-assistant/custom_components` on the host
#   is the only inventory there is.
#
#   THE TWO HALVES BEHAVE DIFFERENTLY AND THE DIFFERENCE IS NOT OBVIOUS:
#
#     * FRONTEND — themes and Lovelace cards.  Pure JavaScript served out of
#       www/community, no Python, nothing to reconcile.  These work exactly as
#       they do on Home Assistant OS, and they are the half nixpkgs has no
#       equivalent for at all.
#
#     * INTEGRATIONS — Python, and here there is a catch with teeth.  nixpkgs
#       builds Home Assistant with `--skip-pip`, so the runtime
#       `pip install --target deps` that satisfies a downloaded integration's
#       manifest requirements NEVER RUNS.
#
#       AND IT IS WORSE THAN THAT, WHICH IS WHY THERE IS A CHECKER BELOW.
#       Requirement checking sits behind THE SAME FLAG:
#
#           # homeassistant/requirements.py:167
#           if not self.hass.config.skip_pip:
#               await self._async_process_integration(integration, done)
#
#       So Home Assistant does not merely fail to install a missing
#       requirement — it never looks.  No RequirementsNotFound, no log line
#       naming pip, no repair issue.  The integration is loaded, it does
#       `import pyfoo`, and the first evidence is an ImportError raised from
#       inside somebody else's code.  For an integration that imports lazily
#       that can be days after the download, when a device is first used.
#
#       THERE IS THEREFORE NO UPSTREAM SIGNAL TO ALERT ON, so this file
#       manufactures one: `hass-hacs-deps.service` below reads the downloaded
#       manifests and resolves every requirement against the live environment.
#       It is hooked to home-assistant.service's start rather than to a timer,
#       because a newly downloaded integration does nothing until Home
#       Assistant is restarted — so the restart IS the moment the answer can
#       change.  A failure becomes a host-side metric within the minute through
#       the container-unit collector, and `hacs-deps-check` run by hand prints
#       the same report with the `extraPackages` block already filled in.
#
#       The fix it names is one option, not a redesign:
#
#           services.home-assistant.extraPackages = ps: [ ps.<thedep> ];
#
#       in this file, then redeploy.  Requirements with no nixpkgs packaging are
#       the case where the answer is to package the integration properly in
#       ./pkgs and drop it from HACS — which is the same work `customComponents`
#       exists for, arrived at from the other direction.
#
#   HACS CANNOT UPDATE ITSELF.  Its `update.hacs` entity rewrites
#   custom_components/hacs, which here is a symlink into the store.  Pressing
#   Install fails.  Bumping ./pkgs/hacs.nix is the upgrade path, and the failing
#   button is left visible on purpose — see that file.
#
#   SETUP IS A MANUAL STEP AND CANNOT BE OTHERWISE.  HACS authenticates to
#   GitHub through the device flow: Settings → Devices & Services → Add
#   Integration → HACS, then a code typed into github.com/login/device under a
#   GitHub account.  The token it receives is written to .storage, so it
#   survives deploys and reboots but is not in this repo and not in clan vars —
#   there is nothing to seed, which is the same reason the owner account has no
#   generator (below).
#
# ── WHAT IS DELIBERATELY NOT HERE ───────────────────────────────────────────
#
#   A clan vars generator.  Home Assistant creates its owner account through
#   the onboarding flow in the browser and keeps credentials in .storage; there
#   is nothing to seed and therefore no /run/hass-secrets staging unit.  Stated
#   so the absence reads as a decision.
#
#   A Prometheus scrape target.  Home Assistant's /api/prometheus is behind a
#   long-lived bearer token, so a job pointed at it without one could only ever
#   be `up == 0` — M13's Ollama lesson, and service-modules/monitoring.nix is
#   disciplined about not adding targets that cannot work.  What this container
#   DOES get for free, because it is nspawn and machinectl can see it, is
#   `ContainerSystemdUnitFailed`: any failed unit inside it becomes a host-side
#   metric within a minute.  If HA metrics are wanted later, the pattern to
#   copy is the Navidrome basic_auth.password_file job in that file.
#
#   Zigbee2MQTT and an MQTT broker.  ZHA is in-process, needs no broker, no
#   second port and no second web UI to route or explain.  The ZBT-2 is Nabu
#   Casa's own dongle and is first-class in ZHA.  Z2M's wider device support is
#   the reason to revisit this, and the migration is a re-pair either way.
#
# ── IF RE-PAIRING TURNS OUT TO BE TOO MUCH ──────────────────────────────────
#
#   ZHA can restore a coordinator backup — PAN ID, extended PAN ID and network
#   key — from the Pi's coordinator onto the ZBT-2, and every device keeps
#   working without being touched.  That is a change of PLAN, not of design:
#   nothing in this file moves, only the manual step that forms the network.
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

  # ── 286 IS NOT OURS TO CHOOSE, AND THAT IS THE POINT ──────────────────────
  #
  # This file was first written with 3038 — the next free number in the
  # 3000-block registry in machines/ernst/networking.nix — on the argument
  # Immich's and Nextcloud's rows there make: the nixpkgs module creates its
  # user with `isSystemUser` and no fixed uid, nspawn passes ids through
  # UNMAPPED, so whatever the container's useradd happens to pick is the number
  # that lands on every file on zdata.
  #
  # THAT ARGUMENT DOES NOT APPLY HERE.  It failed at evaluation:
  #
  #     error: The option `containers.hass.users.users.hass.uid' has
  #            conflicting definition values: 286 / 3038
  #
  # `hass` is a WELL-KNOWN NixOS STATIC ID — `ids.uids.hass` and
  # `ids.gids.hass` are both 286 — so the number is already fixed by nixpkgs
  # and cannot drift.  It is the same situation as PostgreSQL's uid 71 in
  # containers/nextcloud.nix: the 3000-block convention does not apply to it,
  # and it must not be renumbered into the block.
  #
  # So M24 CONSUMES NO NUMBER FROM THE 3000 BLOCK.  The registry in
  # machines/ernst/networking.nix records 286 alongside 71 for that reason, and
  # NEXT FREE there stays at 3038.
  #
  # What is still true is the half that matters for the bind mount: 286 is what
  # lands on every file in /srv/state/home-assistant, so hass-dirs below chowns
  # to it numerically.
  hassUid = 286;
  hassGid = 286;

  ##############################################################################
  # Peers, ports and paths.
  ##############################################################################

  # The one VLAN-90 peer allowed to reach this service.  Every client — browser
  # and companion app, on the LAN and from the internet — arrives through the
  # proxy.  Naming a peer's address here is the deliberate opposite of the rule
  # this file follows for its own; see the "BACKEND BYPASS HARDENING" section of
  # containers/traefik.nix, which owns that argument.
  traefikAddr = "10.0.90.12";

  # M26.  The arr container, because that is where the service index runs —
  # see containers/homepage.nix.  Named for the dashboard rather than for the
  # container so that grepping `dashboardAddr` across machines/ernst finds
  # every widening M26 made, in one pass.
  dashboardAddr = "10.0.90.13";

  # Home Assistant's own listener.  Plain HTTP; TLS is Traefik's.
  hassPort = 8123;

  # ── Leg 3: the AI link (M29) ──────────────────────────────────────────────
  #
  # A point-to-point /128 pair to the host, on no VLAN, carrying exactly three
  # things: the conversation agent, speech-to-text and text-to-speech.  Same
  # mechanism as containers/karakeep.nix's leg to llama-swap and declared the
  # same way — `exposeOn` entries in clan.nix put a socket on the host end and
  # one accept rule in ernst's firewall; this file supplies the third part, the
  # consumer pointed at the address rather than at localhost.
  #
  # ── THE INTERFACE NAME IS HOST-GLOBAL, AND THAT IS WHY IT IS `ai3` ────────
  #
  # `extraVeths.<name>` becomes nspawn's `--network-veth-extra=<name>`, which
  # with a single name is used for BOTH ends — so the name lands in ernst's one
  # flat interface namespace and two containers cannot share it.  Open WebUI
  # and karakeep both asked for `ai0`; Open WebUI silently got no leg at all
  # from M27's deploy until M29 found it.  The number now tracks the ULA
  # (fe91 -> ai1, fe92 -> ai2, fe93 -> ai3) and
  # machines/ernst/networking.nix asserts that no two containers collide.
  #
  # NOT ON THE IoT LEG AND NOT ON VLAN 90.  Either would work and both would be
  # worse: VLAN 90 would make the inference endpoint reachable from every other
  # service container, and VLAN 20 would put it on a segment full of devices
  # this house does not control.  The whole point of a /128 pair is that its
  # only peer is one host.
  aiVeth = "ai3";
  aiHost = "fdca:fe93::1";
  aiCont = "fdca:fe93::2";

  # M29b.  The agent's uid, allocated in the table in
  # machines/ernst/networking.nix, named here because `hass-dirs` has to create
  # a directory inside this container's state tree that the agent can write —
  # see the note at that unit for what it is for and what the mode change on
  # `www` does and does not expose.
  mnemeUid = 3039;

  # State: the configuration tree, the .storage blobs that hold accounts and
  # integration config, and the recorder's SQLite database.
  #
  # ON THE EXISTING zdata/state DATASET, NOT A NEW ONE, and that is a decision
  # rather than a shortcut.  docs/guides/ernst-zdata-datasets.md splits
  # datasets by WRITE PROFILE: 1M recordsize for large sequential media, the
  # 128K default for small random writes.  A SQLite recorder DB and a tree of
  # small JSON blobs is the second case exactly, which is what zdata/state
  # already is — measured on the host as recordsize=128K, exec=on,
  # com.sun:auto-snapshot=true.  A dedicated dataset would carry identical
  # properties and add a mount that can fail.
  stateRoot = "/srv/state/home-assistant";

  # Home Assistant's own default configDir, bound to stateRoot.  Using the
  # module's default rather than overriding it means `configDir`, the systemd
  # StateDirectory and the module's own tmpfiles rules all agree with nothing
  # overridden — the same trick as Immich's /var/lib/immich and Nextcloud's
  # /var/lib/nextcloud.
  configDir = "/var/lib/hass";

  ##############################################################################
  # The radios.
  ##############################################################################

  # TWO Nabu Casa ZBT-2 dongles, and they are the same product:
  #
  #     /dev/ttyACM0  Nabu_Casa ZBT-2  303a:831a  ID_SERIAL_SHORT=1CDBD45E613C
  #     /dev/ttyACM1  Nabu_Casa ZBT-2  303a:831a  ID_SERIAL_SHORT=DCB4D90E9BD0
  #
  # IDENTICAL VENDOR AND PRODUCT ID.  A udev rule matching on VID/PID alone
  # would create BOTH symlinks on BOTH devices, and ZHA would form its network
  # against whichever won the race — differently on different boots.
  # ID_SERIAL_SHORT is the only thing that tells them apart.
  #
  # And ttyACM0/ttyACM1 is enumeration order, which can flip on a kernel bump
  # or a USB reset.  This is containers/jellyfin.nix's renderD12{8,9} argument
  # in its sharpest form: there, a flip silently handed the container the wrong
  # GPU; here it would silently point ZHA at the Thread radio.
  #
  # The aliases are colon-free, which also matters: systemd-nspawn's
  # --bind=SRC:DST parser tokenizes on ':' and rejects source paths carrying
  # extra colons.  /dev/serial/by-id/usb-Nabu_Casa_ZBT-2_1CDBD45E613C-if00
  # happens to be colon-free and would work, but it encodes the serial in a
  # path that reads as noise at every use site.
  zigbeeSerial = "1CDBD45E613C";
  threadSerial = "DCB4D90E9BD0";

  zigbeeNode = "/dev/zigbee-coordinator";
  threadNode = "/dev/thread-radio";
in
{
  ##############################################################################
  # Host side — the udev aliases, the state directory, and the two veths.
  ##############################################################################

  # Stable, colon-free aliases for the two radios, keyed on SERIAL.  The
  # SYMLINK+= form adds an alias alongside the stock by-id/by-path links, so
  # nothing else on the host loses a name it already had.
  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="303a", ENV{ID_MODEL_ID}=="831a", ENV{ID_SERIAL_SHORT}=="${zigbeeSerial}", SYMLINK+="${lib.removePrefix "/dev/" zigbeeNode}"
    SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="303a", ENV{ID_MODEL_ID}=="831a", ENV{ID_SERIAL_SHORT}=="${threadSerial}", SYMLINK+="${lib.removePrefix "/dev/" threadNode}"
  '';

  # Belt-and-braces: block container start until the aliases exist.
  #
  # On a normal boot udev fires the rules above when cdc_acm enumerates the
  # dongles, and the symlinks are there long before any application service
  # starts, so this is redundant.  Where it earns its keep is the corner case
  # containers/jellyfin.nix measured: a runtime udev-rules reload
  # (`nixos-rebuild switch`, i.e. every deploy that touches this file) does NOT
  # re-fire "add" events against already-enumerated devices, so on the FIRST
  # deploy the rule never runs, the symlink never appears, and container@hass
  # dies with
  #
  #     systemd-nspawn: Failed to clone /dev/zigbee-coordinator:
  #                     No such file or directory
  #
  # five times into its start limit.
  #
  # The explicit trigger means a reload-then-start deploy does not have to wait
  # out the settle timeout; on a normal boot it is a no-op and the whole unit
  # completes in well under a second.
  #
  # `--exit-if-exists` takes ONE path, so there are two settle calls.  The
  # Thread radio is waited for even though nothing opens it: it is bind-mounted
  # below, and a bind source that does not exist fails the container start just
  # as hard as one that is never used.
  systemd.services.hass-radio-symlinks = {
    description = "Ensure the ZBT-2 radio aliases exist for container@hass";
    wantedBy    = [ "container@hass.service" ];
    before      = [ "container@hass.service" ];
    after       = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = false;
      ExecStart = [
        "${pkgs.systemd}/bin/udevadm trigger --subsystem-match=tty --action=add"
        "${pkgs.systemd}/bin/udevadm settle --exit-if-exists=${zigbeeNode} --timeout=30"
        "${pkgs.systemd}/bin/udevadm settle --exit-if-exists=${threadNode} --timeout=30"
      ];
    };
  };

  # ── NO tmpfiles RULES IN THIS FILE, AND containers/immich.nix IS WHY ───────
  #
  # That file records the measured failure: three of its four host-side
  # directories shipped as `systemd.tmpfiles.rules` and the container died five
  # times into its start limit, because activating a new configuration does not
  # re-run systemd-tmpfiles-setup.service in time for a container the same
  # activation starts.  Every host-side directory this container binds belongs
  # to the ordered unit below, and none of them is also a tmpfiles rule — two
  # declarations for one path is the M3 defect, where two rules that disagree
  # about mode take turns winning, one per deploy.
  systemd.services.hass-dirs = {
    description = "Verify /srv/state is mounted and create Home Assistant's directories";
    wantedBy   = [ "multi-user.target" ];
    after      = [ "srv-state.mount" ];
    requires   = [ "srv-state.mount" ];
    before     = [ "container@hass.service" ];
    requiredBy = [ "container@hass.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.util-linux pkgs.coreutils ];

    # BLOCKING (`requires` + `requiredBy`), not advisory, and for Nextcloud's
    # reason rather than arr's: a Home Assistant that starts without its state
    # is not a degraded Home Assistant, it is a NEW, EMPTY one on zroot.  It
    # will run the onboarding wizard again, accept an owner account, pair
    # devices, and lose all of it at the next boot — while reporting success
    # the entire time.
    #
    # It FAILS rather than repairing itself: a unit that silently fixes storage
    # layout hides the fact that the layout was wrong.
    script = ''
      set -eu

      # findmnt, not `mountpoint`: this has to check WHAT is mounted, not just
      # that something is.
      #
      # THE TARGET IS THE PARENT, NOT ${stateRoot}, and that is not tidiness.
      # `findmnt --target` on a path that DOES NOT EXIST YET returns nothing —
      # it does not walk up to the nearest existing ancestor — so checking
      # ${stateRoot} here would fail on every first run, before this unit has
      # had a chance to create it.  immich-dirs refused its own first deploy
      # that way on 2026-09-11.
      ssrc=$(findmnt --noheadings --output SOURCE --target /srv/state || true)
      if [ "$ssrc" != "zdata/state" ]; then
        echo "hass-dirs: /srv/state is not zdata/state (found '$ssrc')." >&2
        echo "  Refusing to create Home Assistant's state directory, because" >&2
        echo "  it would land on zroot and be rolled back on the next boot —" >&2
        echo "  taking the owner account and every paired device with it." >&2
        echo "  See docs/guides/ernst-zdata-datasets.md." >&2
        exit 1
      fi

      # NUMERIC ids on purpose: `hass` is a CONTAINER user and the host has no
      # matching passwd entry.  Same shape traefik.nix uses for uid 3005.
      #
      # 0700 IS ASKED FOR AND 0750 MAY BE WHAT LANDS, the way it did for
      # Nextcloud and Immich: the nixpkgs module ships its own tmpfiles rules
      # INSIDE the container, they run on every start against the same inodes
      # through the bind mount, and upstream wins.  It is NOT forced back —
      # declaring a competing rule for a path the module already declares is
      # the M3 defect.  The check that makes it harmless is specific rather
      # than reassuring: `getent group 286` ON THE HOST must return nothing,
      # so the group bit grants nobody anything.  `go`, the couch account that
      # autologins on the television without a password, is gid 100(users).
      # If a host-side group 286 is ever created, re-read this paragraph
      # rather than trusting it.
      install -d -o ${toString hassUid} -g ${toString hassGid} -m 0700 ${stateRoot}

      # ── SEED THE UI-MANAGED INCLUDE FILES ───────────────────────────────
      #
      # configuration.yaml below carries `automation: !include automations.yaml`
      # and its two siblings, which is what keeps the browser's automation,
      # script and scene editors working while configuration.yaml itself stays
      # declarative and read-only.
      #
      # Home Assistant does NOT tolerate a missing !include target — it raises
      # at startup and refuses to boot.  Home Assistant OS ships these files
      # pre-created for exactly this reason; nothing here would create them, so
      # this does.
      #
      # `-e` guarded, never truncating: after the first deploy these files are
      # owned by the UI editors and rewriting them would delete every
      # automation in the house.
      #
      # The empty values match what each domain expects — a list for
      # automations and scenes, a mapping for scripts.
      for f in automations.yaml scenes.yaml; do
        if [ ! -e "${stateRoot}/$f" ]; then
          echo "[]" > "${stateRoot}/$f"
          chown ${toString hassUid}:${toString hassGid} "${stateRoot}/$f"
          chmod 0600 "${stateRoot}/$f"
        fi
      done
      if [ ! -e "${stateRoot}/scripts.yaml" ]; then
        echo "{}" > "${stateRoot}/scripts.yaml"
        chown ${toString hassUid}:${toString hassGid} "${stateRoot}/scripts.yaml"
        chmod 0600 "${stateRoot}/scripts.yaml"
      fi

      # ── M29b: where the agent's pictures land ──────────────────────────
      #
      # Home Assistant serves `www/` at `/local/`, so a PNG written here is
      # reachable at https://ha.goclan.org/local/mneme/<name>.png — from the
      # Assist dialog, from the companion app, and from off the LAN, because
      # that name is already split-horizon behind Traefik.  mneme cannot serve
      # it itself: it listens on a point-to-point ULA that only this container
      # can reach, so a URL it produced would be unreachable from the browser
      # that has to display it.
      #
      # THIS IS THE PERMISSION CHANGE THAT MAKES IT POSSIBLE, and it is here
      # rather than in the agent's module because this file owns this tree.
      # `www` is created 0700 by HACS (which writes www/community), and 0700
      # means another uid cannot even TRAVERSE it — so the agent could not
      # reach a subdirectory of its own inside it.  0755 on the directory
      # only; nothing inside it changes owner or mode.
      #
      # What that exposes: the names of files under www/ become listable by
      # any local uid.  HACS already puts community frontend assets there, and
      # those are public JavaScript served to every browser that loads the
      # dashboard — so the directory's contents were never secret.  No file
      # mode is loosened.
      if [ -d "${stateRoot}/www" ]; then
        chmod 0755 "${stateRoot}/www"
      else
        install -d -o ${toString hassUid} -g ${toString hassGid} -m 0755 "${stateRoot}/www"
      fi
      # Owned by the agent, readable by Home Assistant and by the frontend.
      # uid ${toString mnemeUid} is allocated in machines/ernst/networking.nix; it is named
      # here because a bare number in a chown is how the two drift apart.
      install -d -o ${toString mnemeUid} -g ${toString mnemeUid} -m 0755 "${stateRoot}/www/mneme"
    '';
  };

  ##############################################################################
  # The two veths.
  ##############################################################################

  # Leg 1 — the host side of eth0, a VLAN-90 port on br0.  Identical rationale
  # to vb-nextcloud / vb-immich / vb-jellyfin; see containers/traefik.nix for
  # the long form of KeepMaster-not-Bridge and why a bridge port carries no
  # address of its own.
  systemd.network.networks."60-vb-hass" = {
    matchConfig.Name = "vb-hass";
    networkConfig = {
      KeepMaster          = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = 90; PVID = 90; EgressUntagged = 90; } ];
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Leg 2 — the host side of iot0, a VLAN-20 port on br0.
  #
  # `Bridge = "br0"`, NOT `KeepMaster`, and the difference is not cosmetic.
  # nspawn's --network-bridge creates the eth0 veth AND enslaves it, so
  # networkd must be told to keep its hands off the master (KeepMaster, leg 1).
  # --network-veth-extra, which is what `extraVeths` below becomes, creates the
  # pair and enslaves NOTHING — so here networkd owns the enslavement and
  # nothing competes for it.  This is machines/ernst/networking.nix's Pattern A
  # and it is the same shape containers/tvheadend.nix uses for fritz0.
  #
  # NOTE THE NAME.  --network-veth-extra names BOTH ends identically, so this
  # matches the plain `iot0` and not `vb-iot0`.
  systemd.network.networks."60-iot0" = {
    matchConfig.Name = "iot0";
    networkConfig = {
      Bridge              = "br0";
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = 20; PVID = 20; EgressUntagged = 20; } ];
    # A bridge port's terminal state is "enslaved"; it never becomes routable.
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Same VLAN race, same idempotent backstop, same "-" prefix as every other
  # nspawn container on br0: networkd applies [BridgeVLAN] only once it observes
  # the link's master, and nspawn sets that master out of band.  With
  # DefaultPVID = "none" on br0 a miss is fail-CLOSED — the port is dead rather
  # than silently joining VLAN 50.
  #
  # `bridge vlan show dev vb-hass` and `bridge vlan show dev iot0` are the
  # checks.
  systemd.services."container@hass".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev vb-hass vid 90 pvid untagged"
    "-${pkgs.iproute2}/bin/bridge vlan add dev iot0 vid 20 pvid untagged"
  ];

  # Avahi must not discover the IoT segment through this veth.  The host side
  # holds no address, so avahi has nothing to bind and would skip it anyway —
  # but containers/tvheadend.nix states the same exclusion rather than relying
  # on that accident, and during M8's Phase 0 the accident did not hold: a
  # briefly-addressed interface had ernst's mDNS on a foreign segment within
  # seconds.  modules/networking/mdns.nix runs the reflector with no interface
  # pinning, which is what makes this worth stating.
  services.avahi.denyInterfaces = [ "iot0" ];

  ##############################################################################
  # The container.
  ##############################################################################
  containers.hass = {
    autoStart = true;
    ephemeral = false;

    # Leg 1 — eth0 on br0 / VLAN 90.  MAC from the allocation table in
    # machines/ernst/networking.nix; the DHCP reservation 10.0.90.27 on the
    # UDM-Pro keys on it (manual step).  Sequence 13, and the last octet is
    # 8 + seq as everywhere else on this bridge.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = "02:00:00:90:00:13";

    # Leg 2 — iot0 on br0 / VLAN 20.  Same mechanism as tvheadend's fritz0 and
    # the monitoring container's mon0: nspawn --network-veth-extra names both
    # ends iot0.
    #
    # NO ADDRESS AND NO MAC HERE.  `extraVeths` has no MAC option at all, and
    # `localAddress` would be applied by container-init before networkd starts
    # and then fight it over the same interface — tvheadend.nix records that.
    # Both are set by the container's own networkd, below.
    extraVeths.iot0 = { };

    # Leg 3 — the AI link (M29).  UNLIKE iot0 this one DOES carry its addresses
    # here: nixos-containers adds the matching /128 host route on both sides
    # from these, and there is no bridge, no VLAN and no MAC to race over.
    # containers/karakeep.nix does exactly this and is the working example.
    extraVeths.${aiVeth} = {
      hostAddress6  = aiHost;
      localAddress6 = aiCont;
    };

    # ── THE eBPF DEVICE FILTER: GROUP FORM, NOT PATH FORM ─────────────────
    #
    # NixOS passes these straight through to systemd's DeviceAllow=
    # (nixos-containers.nix:341).  containers/jellyfin.nix names a PATH there
    # and that is right for a DRM render node, whose major:minor is fixed by
    # PCI topology.  It would be WRONG here: systemd stat()s the path once to
    # derive major:minor, and a USB-serial minor changes when the device
    # re-enumerates.  The filter would be correct at start and wrong after a
    # replug, denying a device that is plainly present.
    #
    # `char-ttyACM` is the device-node GROUP — major 166, confirmed in ernst's
    # /proc/devices — and covers every minor.  It is also exactly what the
    # nixpkgs home-assistant module emits for itself when a serial component is
    # enabled, so the two layers of filter agree instead of racing.
    #
    # The trap avoided here is service-modules/local-ai.nix's: naming a
    # DIRECTORY grants nothing, and because ANY DeviceAllow turns the filter
    # on, it takes access away.
    allowedDevices = [
      { node = "char-ttyACM"; modifier = "rw"; }
    ];

    bindMounts = {
      # The state tree, bound at the module's OWN default so configDir, the
      # StateDirectory and the module's tmpfiles rules all agree.
      "${configDir}" = {
        hostPath   = stateRoot;
        isReadOnly = false;
      };

      # The radios.  nspawn resolves the source, so the container gets a real
      # character device at a stable name rather than a dangling symlink.
      #
      # The Thread radio is bound and opened by nothing — see the header.
      #
      # ── THIS MOUNT DOES NOT FOLLOW RE-ENUMERATION.  KNOWN. ──────────────
      #
      # The bind is established once, at container start, and there is no udev
      # inside these containers to notice a replug.  If a dongle re-enumerates
      # while Home Assistant is running, the node in here keeps pointing at the
      # old major:minor and ZHA reports I/O errors against a device that looks
      # present.  Recovery is one command:
      #
      #     systemctl restart container@hass
      #
      # No precedent in this repo automates that, and it is deliberately not
      # built here: a host udev RUN+= that restarts the container is the
      # obvious fix and is its own failure mode against a flapping device.
      # These dongles are permanently seated in a server; build it if it bites.
      "${zigbeeNode}" = {
        hostPath   = zigbeeNode;
        isReadOnly = false;
      };
      "${threadNode}" = {
        hostPath   = threadNode;
        isReadOnly = false;
      };
    };

    config = { config, pkgs, lib, ... }: let
      # HACS — the Home Assistant Community Store.  The derivation, and the
      # reasons it is built from the release zip rather than the git tag, are in
      # ./pkgs/hacs.nix; what its presence means for this container is in the
      # "HACS" section of this file's header.
      #
      # `home-assistant.python3Packages.callPackage`, not the bare `pkgs` one,
      # and that is the same scope nixpkgs uses for everything under
      # `pkgs.home-assistant-custom-components`.  It matters twice: the
      # `aiogithubapi` the component propagates has to come from the SAME Python
      # set Home Assistant itself is built against or the module would install
      # two incompatible copies, and buildHomeAssistantComponent's
      # manifest-requirements check runs under that set's interpreter.
      # ── M29: bleak-esphome PINNED TO THE VERSION THE MANIFEST ASKS FOR ────
      #
      # The Home Assistant Voice Preview Edition is an ESPHome device, so the
      # hub needs the `esphome` integration (added to extraComponents below).
      # Its manifest at this release pins its requirements exactly:
      #
      #   core 2026.5.4  esphome/manifest.json
      #     aioesphomeapi==44.24.1        nixpkgs 26.05: 44.24.1   match
      #     esphome-dashboard-api==1.3.0  nixpkgs 26.05: 1.3.0     match
      #     bleak-esphome==3.7.3          nixpkgs 26.05: 3.7.5     MISMATCH
      #
      # NOTHING WOULD HAVE REPORTED THE MISMATCH.  nixpkgs builds Home Assistant
      # with `--skip-pip`, and requirement checking sits behind that same flag
      # (homeassistant/requirements.py:167) — the reason ./hacs-deps-check.py
      # exists at all.  That checker covers DOWNLOADED components and would not
      # have looked at this one, because `esphome` is built in.  So the version
      # skew would have surfaced, if at all, as an ImportError or a subtly wrong
      # BLE proxy from inside aioesphomeapi.
      #
      # `packageOverrides` is home-assistant's own supported hook
      # (pkgs/servers/home-assistant/default.nix:247), applied to the scope the
      # component's dependencies are resolved from, so this reaches the right
      # copy.  It rebuilds bleak-esphome and nothing else: nothing in this
      # closure depends on it, it depends on habluetooth rather than the
      # reverse.
      #
      # THE HASH WAS VERIFIED TWICE before it was written down, which is this
      # repository's rule for anything fetched (see clan.nix's SDXL entry for
      # why): `nix flake prefetch github:bluetooth-devices/bleak-esphome/v3.7.3`
      # and a `fetchFromGitHub` build against lib.fakeHash returned the same
      # value, at rev a6ccd5a657a997cd0551e4aa616ae867c3c46a43.
      hassPackage = pkgs.home-assistant.override {
        packageOverrides = _final: prev: {
          bleak-esphome = prev.bleak-esphome.overridePythonAttrs (old: rec {
            version = "3.7.3";
            src = pkgs.fetchFromGitHub {
              owner = "bluetooth-devices";
              repo  = "bleak-esphome";
              tag   = "v${version}";
              hash  = "sha256-zEa8l3ob05BoT/GHhwClzOreZyC3uPaG05VIJV7ZZ00=";
            };
            # The package's own pytest suite is left ON and PASSES at this
            # version — built and checked on ernst 2026-09-24 before this was
            # written down, rather than disabled pre-emptively the way a
            # downgrade usually is.
          });
        };
      };

      # ── HACS, AGAINST THE SAME PYTHON SET ───────────────────────────────
      #
      # `hassPackage.python3Packages`, NOT `pkgs.home-assistant.python3Packages`,
      # and the difference is load-bearing now that the line above overrides the
      # scope: the two would be different package sets, and the comment below
      # about installing two incompatible copies would stop being hypothetical.
      hacs = hassPackage.python3Packages.callPackage ./pkgs/hacs.nix { };

      # ── EVERY PACKAGED INTEGRATION, BEHIND ONE PYTHONPATH ENTRY ───────
      #
      # WHY NOT A CURATED LIST.  Home Assistant's "Add Integration" dialog
      # offers all ~1450 built-ins unconditionally — the list is HA's own
      # manifest index and knows nothing about how this build was assembled.
      # Any integration not named in Nix is therefore a trap: offered,
      # accepted, and then failing on import,
      #
      #     Error occurred loading flow for integration yamaha_musiccast:
      #     No module named 'aiomusiccast'
      #
      # with the fix being a file edit and a redeploy while you stand in front
      # of the device you were adding.  So: name all of them.
      #
      # THE FIRST ATTEMPT AT THIS (#229/#230) TOOK THE HUB DOWN, and the
      # reason is the whole design of what follows.  nixpkgs' module sets
      # `environment.PYTHONPATH = package.pythonPath` — ONE COLON-SEPARATED
      # ENTRY PER REQUIREMENT, in the unit's environment block:
      #
      #     1595 entries    = 162898 bytes
      #     MAX_ARG_STRLEN  = 32 * PAGE_SIZE = 131072 bytes
      #
      # execve() rejects any single argument or environment string over that,
      # so home-assistant.service failed with E2BIG on every start.  systemd
      # reports only `start-limit-hit`; `hacs-deps-check`, inheriting the same
      # PYTHONPATH, is what said `Argument list too long`.  Not a degraded
      # integration — no hub at all.
      #
      # `hassPythonEnv` below is the fix: ONE buildEnv holding every
      # requirement, so PYTHONPATH is a single ~93-byte path and the limit
      # stops being reachable at any component count.
      #
      # WHAT HAD TO BE GOT RIGHT, because it is silent when wrong:
      #
      #   * ALL OUTPUTS, not just the default one.  nixpkgs puts grpcio's and
      #     pyopenssl's python modules in their `dev` outputs, and
      #     makePythonPath includes those.  A first version of this linked
      #     only default outputs and `import grpc` vanished — no build error,
      #     no warning, just a module that is not there.  `d.outputs` below is
      #     load-bearing.
      #
      #   * `extraPackages` MUST BE FOLDED IN TOO.  Forcing PYTHONPATH
      #     replaces the module's value wholesale, and the module's value is
      #     `componentBuildInputs ++ extraBuildInputs`.  Leaving the second
      #     half out would silently drop the HACS requirements below — which
      #     is why `hassExtraPackages` is a binding used in both places
      #     rather than a list written twice.
      #
      #   * `ignoreCollisions` is unavoidable at ~1400 components and is the
      #     residual risk: conflicts resolve first-wins, which is not
      #     guaranteed to match sys.path order.  Checked before deploying —
      #     400 of the 1587 top-level modules imported, 399 succeeded, and the
      #     one failure (`clementineremote`, a protobuf codegen mismatch)
      #     fails identically with the unmerged 1595-entry path, so it is
      #     upstream and not an artefact of merging.
      #
      # EVALUATING IS STILL NOT BUILDING.  `tryEval` proves a component's
      # requirements can be *described*; `kef` evaluates and then fails to
      # build, because aiokef 0.2.17 calls asyncio.get_event_loop() at
      # construction (raises on python3.14) and cache.nixos.org 404s its
      # output.  Nothing at evaluation time predicts that, so the deny-list is
      # empirical.  Re-derive it after any nixpkgs bump, before deploying:
      #
      #     nix build --dry-run .#nixosConfigurations.ernst.config.system.build.toplevel
      #
      # Anything under "these N derivations will be built" that is a
      # `python3.14-*` package is a component requirement with no binary
      # cache; map it back with
      #
      #     awk '/^    "/{c=$1} /<pkgname>/{print c}' \
      #       <nixpkgs>/pkgs/servers/home-assistant/component-packages.nix
      #
      # and add that component here.  Units, `etc`, `system-path` and the
      # system closure are always in that list and are not a signal.
      unbuildableComponents = [
        "kef" # aiokef 0.2.17: get_event_loop() at init, broken on python3.14
      ];

      buildableComponents =
        let
          evaluates = component:
            let
              result = builtins.tryEval (builtins.deepSeq
                (map (drv: drv.outPath)
                  (hassPackage.getPackages component hassPackage.python3Packages))
                true);
            in
            result.success && result.value;
          usable = component:
            !(builtins.elem component unbuildableComponents) && evaluates component;
        in
        builtins.filter usable hassPackage.availableComponents;

      # Used twice on purpose — see the `extraPackages` note above.
      hassExtraPackages = ps: [
        # philips_airplus (HACS) — manifest wants paho-mqtt>=2.1,<3.
        ps.paho-mqtt
      ];

      # ── TWO DISTRIBUTIONS, ONE IMPORT NAME: `brotlipy` IS EXCLUDED ────────
      #
      # `ignoreCollisions` above resolves same-PATH conflicts first-wins, and
      # the note there calls that the residual risk.  THIS IS A DIFFERENT AND
      # WORSE SHAPE, and it is not a collision at all — the two paths do not
      # overlap, so nothing warns:
      #
      #   Brotli 1.2.0   installs  site-packages/brotli.py     (a MODULE)
      #   brotlipy 0.7.0 installs  site-packages/brotli/       (a PACKAGE)
      #
      # Python's FileFinder checks directory loaders before file loaders, so in
      # one merged site-packages the PACKAGE always wins and `import brotli` is
      # brotlipy — measured under the service's own interpreter:
      #
      #   brotli.__file__ = …/hass-python-deps/…/brotli/__init__.py
      #
      # AND aiohttp 3.13.5 CANNOT DRIVE brotlipy.  Its BrotliDecompressor picks
      # a branch by feature detection (compression_utils.py:310):
      #
      #   if hasattr(self._obj, "decompress"):
      #       return self._obj.decompress(data, max_length)   # brotlipy
      #   return self._obj.process(data, max_length)          # Brotli
      #
      # brotlipy's `Decompressor.decompress(self, data)` takes no max_length —
      # it never gained one — so the branch aiohttp selects FOR it raises
      #
      #   TypeError: Decompressor.decompress() takes 2 positional arguments
      #              but 3 were given
      #
      # which aiohttp re-raises as `Can not decode content-encoding: br`.  Every
      # brotli-encoded response this hub fetches fails.  HACS is what surfaced
      # it, three times per start, because data-v2.hacs.xyz serves `br`:
      # `async_handle_removed_repositories` dies in `startup_tasks`, so the
      # store comes up without its removed-repository list on every boot.
      #
      # NOT A MISSING DEPENDENCY, AND NOT FIXABLE BY ADDING ONE.  Both
      # distributions are present and correct; the defect is that they share an
      # import name and the wrong one is reachable.  Dropping brotlipy leaves
      # `brotli.py` unshadowed, and Brotli's `Decompressor` has no `decompress`
      # attribute at all, so aiohttp takes its `process(data, max_length)`
      # branch — verified against the real interpreter before this was written:
      #
      #   PYTHONPATH=<Brotli only> python3.14 -c 'import brotli
      #     d = brotli.Decompressor()
      #     print(hasattr(d, "decompress"), d.process(brotli.compress(b"x"), 99))'
      #   False b'x'
      #
      # NOTHING LOSES A CAPABILITY.  brotlipy enters this closure through
      # exactly one component — `surepetcare`, via surepy's propagated inputs
      # (the only reference in this channel's component-packages.nix) — and
      # neither surepy nor anything else here imports brotli directly: they
      # declare it so that aiohttp can decode `br`, which is precisely what
      # this restores.  urllib3 does the same feature detection and works
      # against either distribution.
      #
      # THE FILTER IS BY `pname`, WHICH ONLY WORKS WHILE BOTH SURVIVE.  If a
      # future nixpkgs bump drops Brotli out of this closure, the filter would
      # remove the only `brotli` there is and `import brotli` would fail
      # outright for surepetcare — a silently worse outcome than the bug.  The
      # throw below is what makes that a build failure instead.
      shadowedDists = [ "brotlipy" ];

      hassPythonEnv =
        let
          ps = hassPackage.python3Packages;
          deps = lib.unique (
            lib.concatMap (c: hassPackage.getPackages c ps) buildableComponents
            ++ hassExtraPackages ps
          );
          fullClosure = ps.requiredPythonModules deps;
          closure =
            lib.filter (d: !(lib.elem (d.pname or "") shadowedDists)) fullClosure;
          keptPnames = map (d: d.pname or "") closure;
          allOutputs =
            lib.concatMap (d: map (o: d.${o}) (d.outputs or [ "out" ])) closure;

          # `throw` and not `assertions`, for containers/traefik.nix's reason:
          # it fires wherever this is evaluated — `nix flake check`, the CI
          # eval, `nix build --dry-run` — and cannot be demoted to a warning.
          env = pkgs.buildEnv {
            name = "hass-python-deps";
            paths = allOutputs;
            pathsToLink = [ "/lib/${ps.python.libPrefix}/site-packages" ];
            ignoreCollisions = true;
          };
        in
        if !(lib.elem "brotli" keptPnames) then
          throw ''
            home-assistant.nix: brotlipy is filtered out of hassPythonEnv so
            that `import brotli` resolves to Brotli — but Brotli is no longer
            in this closure, so the filter would leave NO brotli at all and
            the surepetcare component would fail to import.
            Re-read the "TWO DISTRIBUTIONS, ONE IMPORT NAME" block above and
            re-derive the fix against the current channel.
          ''
        else
          env;

      # ── THE REQUIREMENTS CHECKER ────────────────────────────────────────
      #
      # Why it exists at all is in the "HACS" section of the header: under
      # `--skip-pip` Home Assistant never checks a downloaded integration's
      # requirements, so there is no upstream failure to alert on and one has
      # to be manufactured.
      #
      # THE INTERPRETER IS THE WHOLE POINT.  A checker that answers "is pyfoo
      # importable?" against any Python other than the one
      # home-assistant.service runs under is answering a different question,
      # and answering it confidently.  So it is the same interpreter, with
      # PYTHONPATH set to the same `package.pythonPath` the module hands the
      # service (home-assistant.nix:983) — what this can import is by
      # construction what Home Assistant can import.
      #
      # `packaging` has to be added explicitly.  It is NOT in the runtime
      # PYTHONPATH — checked, 168 entries and none of them packaging — which is
      # a little surprising for a requirements checker to need and exactly the
      # kind of thing that would otherwise be discovered as an ImportError in
      # the alerting path itself.
      #
      # ── READ THE PATH OFF THE SERVICE, NOT OFF THE PACKAGE OPTION ────────
      #
      # `config.services.home-assistant.package.pythonPath` IS THE WRONG
      # ANSWER, and it is wrong in the direction that does real damage.  The
      # module does not run the package named by that option: it runs a LOCAL
      # override of it (home-assistant.nix:126-137) that folds in
      # `extraComponents`, `extraPackages`, and every custom component's
      # propagated inputs.  `cfg.package` is the input to that override, not
      # its result, so its pythonPath is missing all of them.
      #
      # Caught by testing the checker against a synthetic library rather than
      # by reading the module: it reported `aiogithubapi` — HACS's own
      # requirement, which this file demonstrably installs and which
      # `systemctl show` confirms is on the service's path — as NOT INSTALLED.
      # A checker that fails on a healthy hub is worse than no checker, because
      # its alert trains you to ignore it.
      #
      # `systemd.services.home-assistant.environment.PYTHONPATH` is the value
      # the module assigns from the overridden package (home-assistant.nix:983),
      # so it is the literal string the running service gets — the only
      # definition of "what Home Assistant can import" that cannot drift.
      hassPythonPath = config.systemd.services.home-assistant.environment.PYTHONPATH;

      # The interpreter itself is safe to take from the option: an override
      # that adds packages does not change the Python VERSION, and this is only
      # used to pick the matching `packaging`.
      checkPython =
        config.services.home-assistant.package.python3Packages.python.withPackages
          (ps: [ ps.packaging ]);

      hacsDepsCheck = pkgs.writeShellApplication {
        name = "hacs-deps-check";
        runtimeInputs = [ ];
        text = ''
          export PYTHONPATH=${hassPythonPath}
          exec ${checkPython}/bin/python3 \
            ${./hacs-deps-check.py} "''${1:-${configDir}/custom_components}"
        '';
      };
    in {
      system.stateVersion = "26.05";

      ##########################################################################
      # Networking — two legs, one netns.
      ##########################################################################
      networking.useHostResolvConf = false;
      networking.useNetworkd = true;
      services.resolved.enable = true;

      # ── resolved MUST NOT HOLD :5353, AND MUST NOT ANSWER ON THE IoT VLAN ──
      #
      # Measured on the first deploy (2026-09-16), inside the running container:
      #
      #     ss -lunp | grep 5353
      #       0.0.0.0:5353   users:((".hass-wrapped",pid=282))
      #       0.0.0.0:5353   users:(("systemd-resolve",pid=65))
      #       [::]:5353      users:(("systemd-resolve",pid=65))
      #
      # TWO mDNS SOCKETS IN ONE NETNS.  Per-link mDNS was already off —
      # `resolvectl status` showed `-mDNS` on both eth0 and iot0, because
      # neither .network unit sets MulticastDNS — so resolved was not answering
      # or querying, and this is precautionary rather than a measured failure.
      # What it closes is narrow and would be miserable to debug: multicast
      # responses are delivered to EVERY socket joined to 224.0.0.251, so
      # python-zeroconf gets those regardless, but a UNICAST mDNS response
      # (what a QU query asks for) is load-balanced between the two sockets by
      # SO_REUSEPORT. The symptom would be discovery that finds most devices
      # most of the time, which reads as a flaky network rather than as a
      # second listener.
      #
      # Turning it off at the daemon rather than per-link is what makes
      # resolved release the socket entirely — and it takes the stray `[::]`
      # listener with it, which is an SN2 tidy-up this container otherwise gets
      # right everywhere else.
      #
      # LLMNR goes too, for containers/tvheadend.nix's reason rather than this
      # one: it was `+LLMNR` on BOTH links, so the container was answering name
      # queries on the household IoT segment. Nothing here wants that, and a
      # hub that responds to broadcast name lookups on the VLAN it is meant to
      # be quietly observing is the opposite of the posture the avahi
      # `denyInterfaces` line on the host takes.
      #
      # Nothing is lost: this container resolves through Technitium on eth0,
      # declared explicitly below, and Home Assistant brings its own mDNS
      # stack (python-zeroconf) which is the one doing the discovery.
      services.resolved.settings.Resolve = {
        MulticastDNS = "no";
        LLMNR        = "no";
      };

      # eth0 — VLAN 90.  The same block as every sibling container: DHCP
      # against the UDM-Pro reservation, resolver declared rather than
      # inherited.
      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          DNS          = "10.0.5.3";
          Domains      = "~. skynet.lan";
          IPv6AcceptRA = false;
          # SN2: v4 only.  M18 measured that IPv6AcceptRA alone blocks an RA
          # but NOT link-local assignment; this is the line that actually makes
          # `ip -6 addr show dev eth0` empty.
          LinkLocalAddressing = "no";
        };
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      # iot0 — VLAN 20, the discovery leg.
      systemd.network.networks."20-iot0" = {
        matchConfig.Name = "iot0";
        networkConfig = {
          DHCP                = "ipv4";
          IPv6AcceptRA        = false;
          LinkLocalAddressing = "no";
        };

        # ── UseGateway = false IS LOAD-BEARING ────────────────────────────
        #
        # Both legs take DHCP, and both DHCP servers hand out a default route.
        # Without this, the container ends up with TWO `default via` entries
        # and its path to the internet is decided by whichever lease was
        # applied last — which is a coin toss on every boot, and a coin toss
        # that changes which VLAN Home Assistant's outbound traffic (updates,
        # weather, the companion app's push relay) is seen leaving on.
        #
        # UseRoutes = false for the same reason one level down: a classless
        # static route option on VLAN 20 would install routes here that belong
        # to the other leg's routing decision.  VLAN 20 is ON-LINK for this
        # interface, and on-link is the whole job — the /24 route networkd
        # derives from the address is all this leg needs.
        #
        # DNS stays on eth0's Technitium (10.0.5.3), so UseDNS/UseDomains are
        # off for the same non-negotiable reason they are off there: an IoT
        # VLAN's DHCP server is not this container's resolver.
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
          UseGateway = false;
          UseRoutes  = false;
        };

        # THE MAC IS PINNED HERE because `extraVeths` has no option for it and
        # the UDM-Pro reservation has to key on a value this repo chose rather
        # than on whatever nspawn derives from the machine name.  First entry
        # in the VLAN 20 allocation table in machines/ernst/networking.nix.
        linkConfig = {
          MACAddress       = "02:00:00:20:00:01";
          # NOT "routable".  A DHCP problem on the IoT VLAN must leave a
          # RUNNING container with one failed unit and a working web UI, not a
          # host-side restart loop that takes the whole hub down because a
          # lease did not arrive.
          RequiredForOnline = "no";
        };
      };

      # ai3 — the point-to-point link to the host (M29).
      #
      # No DHCP, no RA, no gateway: a /128 on each end and an explicit link
      # route to the peer.  nixos-containers already applied both addresses
      # from `extraVeths` above; this unit is what keeps networkd from
      # reconsidering them and what installs the route, exactly as
      # containers/karakeep.nix's `20-ai2` does.
      systemd.network.networks."20-${aiVeth}" = {
        matchConfig.Name = aiVeth;
        address = [ "${aiCont}/128" ];
        routes  = [ { Destination = "${aiHost}/128"; Scope = "link"; } ];
        networkConfig.IPv6AcceptRA = false;
        # A veth has no carrier until BOTH ends exist, and the host end is
        # created by the same nspawn invocation that starts this container.
        # "routable" here would hang wait-online on the host's own timing.
        linkConfig.RequiredForOnline = "no";
      };

      # Same 20 s cap as every sibling: a DHCP failure must leave a RUNNING
      # container with one failed unit, not a host-side restart loop.
      systemd.network.wait-online.timeout = 20;

      # ── The container firewall — the only enforcement point for br0-local
      #    traffic, since those frames are one L2 hop and the UDM-Pro never
      #    sees them.
      #
      #   8123/tcp  from Traefik, and — since M26 — from the arr container.
      #             Every client of the web UI and of the companion app's API
      #             arrives through the proxy.
      #
      #             THE SECOND SOURCE IS THE SERVICE INDEX (containers/
      #             homepage.nix), reading /api/states with a long-lived access
      #             token to render lights-on and people-home counts.  It is
      #             worth more than one line, because this one interacts with
      #             the control this container leans on: HA's `ip_ban_enabled`
      #             keys on the client address, and `http.trusted_proxies`
      #             names Traefik — so requests arriving from .13 are NOT a
      #             trusted proxy and are banned on their own address if the
      #             token is wrong.  That is the correct behaviour and the
      #             right blast radius (a wrong token bans the dashboard, not
      #             the house), but it means a 403 on this tile after a token
      #             rotation may be a BAN and not an auth failure.  Clear it
      #             with `ip_bans.yaml`, not by widening trusted_proxies —
      #             adding .13 there would let a compromised dashboard forge
      #             X-Forwarded-For and evade the ban entirely.
      #   5353/udp  mDNS, ON iot0 ONLY.
      #   1900/udp  SSDP, ON iot0 ONLY.
      #
      # THE TWO UDP RULES ARE THE WHOLE REASON THE SECOND LEG EXISTS.  Both
      # protocols work by the client LISTENING for multicast responses, so
      # without an inbound accept python-zeroconf and the ssdp component send
      # queries and hear nothing — and the leg is decorative while looking
      # correct.  That failure mode is silent: discovery simply finds nothing,
      # which is indistinguishable from a household with no discoverable
      # devices.
      #
      # `-i iot0` rather than the `-s <addr>/32` form every other container in
      # this repo uses, and the difference is deliberate: the sources here are
      # multicast groups (224.0.0.251, 239.255.255.250) and every device on the
      # segment, so there is no address to name.  The INTERFACE is the
      # restriction — nothing on VLAN 90 gains a port from these two lines.
      #
      # extraCommands, not extraInputRules: the latter is declared
      # unconditionally but consumed only under networking.nftables, so here it
      # would produce no rule and no warning.  containers/traefik.nix is the
      # only nftables container on this machine.
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${traefikAddr}/32   --dport ${toString hassPort} -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${dashboardAddr}/32 --dport ${toString hassPort} -j nixos-fw-accept
        iptables -A nixos-fw -i iot0 -p udp --dport 5353 -j nixos-fw-accept
        iptables -A nixos-fw -i iot0 -p udp --dport 1900 -j nixos-fw-accept
      '';

      ##########################################################################
      # The service.
      ##########################################################################
      services.home-assistant = {
        enable = true;
        inherit configDir;

        # The bleak-esphome pin (M29) — see the long note at `hassPackage`.
        # The module wraps THIS in a further local override that folds in
        # extraComponents and the custom components, so what actually runs is a
        # derivative of it; that is exactly why ./hacs-deps-check.py reads its
        # PYTHONPATH off the SERVICE and not off this option.
        package = hassPackage;

        # `zha` is what puts the ZBT-2 to work, and it is also what makes the
        # nixpkgs module do the in-container half of the device plumbing for
        # us: it is in that module's `componentsUsingSerialDevices` list, so
        # home-assistant.service is emitted with
        #
        #     DeviceAllow      = char-ttyACM rw, char-ttyAMA rw, char-ttyUSB rw
        #     SupplementaryGroups = dialout
        #
        # `dialout` is statically gid 27 in nixpkgs' ids.nix, on the host and
        # in here alike, so the bound node's root:dialout 0660 ownership
        # resolves across the bind mount with nothing to reconcile by hand.
        # That is the one thing about this passthrough that needed no work.
        #
        # The rest are the ordinary household set.  `default_config` below
        # pulls in most integrations; these are the ones it does not, or that
        # must be present before the UI can offer them.
        #
        # THIS LIST NO LONGER DECIDES WHAT THE UI CAN OFFER — the
        # `++ buildableComponents` at the end adds every other packaged
        # integration, which the merged `hassPythonEnv` above is what makes
        # possible.  The names are kept because they are the record of what
        # this household actually depends on, and because naming them makes
        # the build FAIL if one ever stops being packaged, where the filtered
        # set would quietly drop it.
        extraComponents = lib.unique ([
          "zha"           # Zigbee, via the ZBT-2 on /dev/zigbee-coordinator
          "mobile_app"    # the companion app's registration + push endpoint
          "zeroconf"      # mDNS discovery — the iot0 leg's reason to exist
          "ssdp"          # SSDP discovery, same
          "met"           # weather, met.no: no API key, no account
          "radio_browser" # offered by the onboarding wizard; absent = a 404
          "backup"        # HA's own backup UI, onto the state tree

          # ── M29: the local AI path ──────────────────────────────────────
          #
          # `ollama` IS THE CONVERSATION AGENT, and it is not talking to
          # Ollama.  This release has no `llama_cpp` integration — that landed
          # in 2026.8, and ernst is on 26.05's 2026.5.4 — and
          # `openai_conversation` here has no base-URL option, so it can only
          # reach api.openai.com.  `ollama` is the only conversation platform
          # in this release that can be pointed at a local endpoint, so
          # service-modules/local-ai.nix's mneme daemon presents the Ollama
          # wire protocol on [fdca:fe93::1]:11435 and translates.  The full
          # argument is in that module's roles.agent header.
          #
          # When this hub's nixpkgs reaches 2026.8, `llama_cpp` replaces this
          # line and the browser-side change is deleting one integration and
          # adding another against the same daemon.
          "ollama"

          # Wyoming — the protocol Assist speaks to speech services.  Both
          # servers run on the host (roles.voice) and are reached over the same
          # ai3 leg.  `default_config` does NOT pull this in.
          "wyoming"

          # The pipeline itself and its two halves.  `default_config` brings
          # `conversation` and `assist_pipeline`, but `stt` and `tts` are only
          # loaded as dependencies of a provider — and they have to be
          # offerable before the Voice assistants UI can build a pipeline, so
          # all four are named rather than inferred.
          "conversation"
          "assist_pipeline"
          "stt"
          "tts"

          # ── The Voice Preview Edition is an ESPHome device ───────────────
          #
          # It is not a Wyoming satellite and does not need one: the hardware
          # runs microWakeWord ON DEVICE and speaks the ESPHome native API to
          # this hub, which then drives the pipeline built from the Wyoming
          # STT/TTS servers on the host.  So there is no
          # `services.wyoming.openwakeword` anywhere in this fleet and there
          # should not be — wake-word detection on the server would be a second
          # implementation of a job the satellite already does better, on audio
          # it would have to stream continuously.
          #
          # THIS IS THE ONE COMPONENT HERE WITH A PINNED DEPENDENCY.  See the
          # `hassPackage` note above: the manifest wants bleak-esphome==3.7.3
          # and nixpkgs 26.05 ships 3.7.5.
          #
          # It also depends on `bluetooth`, which it pulls in itself — that is
          # the BLE-proxy half of the device, and it is why this integration
          # carries dbus-fast, habluetooth and bluetooth-auto-recovery.
          # ernst's own Bluetooth adapter is not involved and is not required.
          "esphome"

          # ── Added because the UI offered them and they did not work ────────
          #
          # The two that started all of this.  Both were listed in "Add
          # Integration", both failed their config flow on import, and both
          # have their requirement packaged in nixpkgs — they were simply not
          # named here.  Naming a component is the whole fix; the module pulls
          # the requirement in from component-packages.nix.
          "yamaha_musiccast"      # the Yamaha AV receiver, MusicCast API
          "dwd_weather_warnings"  # DWD severe-weather warnings, by warncell

          # `kef` is the counter-example, and it is excluded by
          # `unbuildableComponents` above rather than merely unnamed here.
        ] ++ buildableComponents);

        # ── Requirements for HACS-downloaded integrations ────────────────────
        #
        # `extraComponents` above covers BUILT-IN integrations.  This covers the
        # other half: an integration HACS downloaded into
        # ${configDir}/custom_components is not in any nixpkgs component list,
        # so there is nothing to name — its requirements have to be added to
        # the environment directly, by hand, here.
        #
        # THIS LIST IS DERIVED, NOT AUTHORED.  `hacs-deps-check` reads the
        # downloaded manifests and prints exactly this block; see the HACS
        # section of the header and `hass-hacs-deps.service` below.  Run it
        # after installing anything through HACS rather than waiting for the
        # ImportError:
        #
        #     nixos-container run hass -- hacs-deps-check
        #
        # Each entry names the component that wants it, because nothing else in
        # the tree records the connection — delete the component in HACS and
        # this line is the only thing left pointing at it.
        # The list itself lives at `hassExtraPackages` in the `let` above,
        # because `hassPythonEnv` has to fold in exactly the same packages —
        # forcing PYTHONPATH replaces the module's `componentBuildInputs ++
        # extraBuildInputs` wholesale, and writing the list twice is how the
        # second half goes missing.
        extraPackages = hassExtraPackages;

        # ── HACS ──────────────────────────────────────────────────────────
        #
        # One entry, and the module does the rest: it symlinks
        # $out/custom_components/hacs into ${configDir}/custom_components, adds
        # `hacs` to the component list, and — the part that is easy to miss —
        # folds the component's propagated `aiogithubapi` into the Home
        # Assistant Python environment (home-assistant.nix:135).  That last one
        # is not a nicety; see ./pkgs/hacs.nix on `--skip-pip`.
        #
        # THE ACTIVATION IS SAFE FOR WHAT HACS DOWNLOADS.  The module's
        # preStart sweeps ${configDir}/custom_components, but it only unlinks
        # entries that are SYMLINKS POINTING INTO THE STORE
        # (home-assistant.nix:937-942).  Everything HACS fetches is a real
        # directory of real files, so a deploy walks straight past it.  A
        # component that later gains a nixpkgs packaging is therefore a
        # two-step migration and not a collision: remove it in HACS first, add
        # it here second, because a store symlink and a downloaded directory
        # cannot occupy the same name.
        customComponents = [ hacs ];

        # ── configuration.yaml IS DECLARATIVE AND READ-ONLY ────────────────
        #
        # `configWritable` is left at its `false` default, so the file is a
        # symlink into the store and the browser cannot edit it.  That is the
        # intent: what this file declares should be what is running.
        #
        # It does NOT make Home Assistant a read-only appliance.  Integrations,
        # devices, entities, users, dashboards and helpers all live in
        # .storage/ and are managed entirely through the UI — which is how Home
        # Assistant is meant to be used, and none of it belongs in Nix.
        config = {
          # The meta-integration: ~40 components including recorder, history,
          # logbook, the energy dashboard, and config-flow discovery.
          default_config = { };

          homeassistant = {
            name = "Home";
            time_zone = "Europe/Berlin";
            unit_system = "metric";
            temperature_unit = "C";

            # BOTH URLs ARE THE SAME NAME, and that is correct here rather than
            # lazy.  containers/traefik.nix serves `goclan.org` split-horizon:
            # Technitium answers ha.goclan.org with Traefik's VLAN-90 address
            # inside the house, and the public zone answers it with the WAN
            # address outside.  One name, two answers, so a single value is
            # right for both — and it is the value that has to appear in the
            # companion app's QR codes and in every notification link.
            external_url = "https://ha.goclan.org";
            internal_url = "https://ha.goclan.org";
          };

          http = {
            # SN2 — v4 ONLY, stated rather than inherited.  The module's
            # default for this option is [ "0.0.0.0" "::" ], and the rendered
            # configuration.yaml carries both unless it is overridden here.
            #
            # Nothing could reach the v6 listener today: no interface in this
            # container has an IPv6 address, because both `.network` units above
            # set LinkLocalAddressing = "no".  It is dropped anyway, for the
            # reason containers/traefik.nix spends a paragraph on its own
            # wildcard listeners — a socket that shows up in `ss -ltn` and that
            # the iptables rules below do not cover is a question someone has to
            # answer later, and the answer being "harmless" does not save them
            # the work of establishing it.
            server_host = [ "0.0.0.0" ];

            # ── THE LINE THAT TURNS A CONTROL INTO A DECORATION ────────────
            #
            # Every request arrives from Traefik, so without these two Home
            # Assistant sees 10.0.90.12 as the client for all of them.  The
            # consequences are not subtle:
            #
            #   * ip_ban_enabled below counts failures per source address, so
            #     it would either never fire (one proxy, never enough failures
            #     attributed to a real attacker) or fire once and ban THE PROXY
            #     — taking the entire household offline in a single stroke;
            #   * the logbook, the mobile_app's device tracking and every
            #     access log entry would name the proxy instead of the client.
            #
            # This is ledger row L14's Nextcloud lesson in a second costume,
            # and it is the reason that row says to re-read it here.  Verify it
            # rather than trusting it: two deliberate bad logins from a phone
            # must put THE PHONE'S address in ip_bans.yaml's counters, never
            # 10.0.90.12.
            use_x_forwarded_for = true;
            trusted_proxies = [ traefikAddr ];

            # Home Assistant's own brute-force control, and the first of the
            # compensations containers/ingress-policy.nix demands for a name
            # that Authelia never sees.  A source that fails this many logins
            # is written to ip_bans.yaml and refused at the application layer,
            # permanently, until a human removes the line.
            #
            # It is per-SOURCE and not per-account, which is the opposite of
            # Nextcloud's throttle — so the two names in appApiHosts are
            # defended differently and neither file should be read as
            # describing the other.
            ip_ban_enabled = true;
            login_attempts_threshold = 5;
          };

          # ── THE UI EDITORS, KEPT WORKING ──────────────────────────────────
          #
          # `!include` rather than inline values.  These three domains are the
          # ones Home Assistant's browser editors write to, and pointing them
          # at files under configDir is what lets the household build an
          # automation without a deploy.
          #
          # The nixpkgs module unquotes a leading-bang string into a real YAML
          # tag when it renders configuration.yaml, which is why these are
          # plain strings.
          #
          # THE FILES MUST EXIST — Home Assistant raises on a missing !include
          # target and refuses to start.  hass-dirs above seeds all three, once,
          # and never truncates them afterwards.
          automation = "!include automations.yaml";
          scene      = "!include scenes.yaml";
          script     = "!include scripts.yaml";
        };
      };

      # NO `users.users.hass.uid` HERE.  The nixpkgs module already sets it from
      # `ids.uids.hass`, and restating the same number is an option conflict
      # rather than a no-op — see the note on `hassUid` in the let block above,
      # which is where the number this container's files carry is documented.

      ##########################################################################
      # The HACS requirements checker.
      ##########################################################################

      # ── HOOKED TO HOME ASSISTANT'S START, NOT TO A TIMER ──────────────────
      #
      # A timer would be the reflex and it would be worse in both directions:
      # noisier, because the answer cannot change between restarts, and slower,
      # because a download made at 09:00 would wait for the next firing.
      #
      # The answer changes at exactly one moment.  A HACS download is inert
      # until Home Assistant is restarted — that is why HACS itself puts a
      # "restart required" notice on every install — so the restart is both the
      # moment new state takes effect and the moment it becomes checkable.
      # `wantedBy` + `after` on home-assistant.service puts the check there.
      #
      # WantedBy, NOT RequiredBy, and the asymmetry is deliberate: Home
      # Assistant must not be held up or taken down by its own checker.  A
      # `Wants=` dependency lets this fail on its own while the hub runs, which
      # is the correct blast radius for a report about an integration that was
      # already not going to work.
      #
      # IT IS SUPPOSED TO FAIL LOUDLY.  A failed unit here is not an
      # inconvenience to be suppressed — it is the entire signal, because the
      # thing it reports has no upstream signal at all.  ernst's container-unit
      # collector walks `machinectl list` on a one-minute timer and turns it
      # into `clanarchy_container_systemd_unit_failed{container="hass"}` →
      # `ContainerSystemdUnitFailed` (service-modules/monitoring.nix, added by
      # PR #139 after soularr.service failed 1,412 times over nine days inside
      # the arr container without ever alerting).  A failed ONESHOT is the
      # exact case that PR was written for: nothing stays in a bad state long
      # enough to be noticed any other way.
      # ── THE LINE THAT MAKES ~1450 COMPONENTS POSSIBLE ───────────────────
      #
      # Replaces the module's colon-separated list of one store path per
      # requirement with the single merged environment.  See the long note at
      # `hassPythonEnv` for why the module's own value cannot be used at this
      # component count: 1595 entries is 162898 bytes and execve() rejects any
      # environment string over 131072, so the hub does not start at all.
      #
      # `hacs-deps-check` reads its interpreter and PYTHONPATH off THIS value
      # (see `hassPythonPath` above), so the checker follows automatically and
      # keeps answering the question it exists to answer.
      systemd.services.home-assistant.environment.PYTHONPATH = lib.mkForce
        "${hassPythonEnv}/lib/${hassPackage.python3Packages.python.libPrefix}/site-packages";

      systemd.services.hass-hacs-deps = {
        description = "Check HACS-downloaded integrations for unsatisfiable Python requirements";
        wantedBy = [ "home-assistant.service" ];
        after    = [ "home-assistant.service" ];
        serviceConfig = {
          Type            = "oneshot";
          RemainAfterExit = true;
          ExecStart       = "${hacsDepsCheck}/bin/hacs-deps-check ${configDir}/custom_components";

          # Read-only, and as the service user rather than root: it inspects
          # the same tree home-assistant.service owns and has no business being
          # able to change it.
          User            = "hass";
          Group           = "hass";
          ProtectSystem   = "strict";
          ProtectHome     = true;
          PrivateTmp      = true;
          NoNewPrivileges = true;
        };
      };

      # `curl` is the test plan's instrument for proving this backend is
      # reachable from Traefik and from nowhere else.  `hacs-deps-check` is the
      # same report the unit above emits, on demand and with the
      # `extraPackages` block already filled in:
      #
      #     nixos-container run hass -- hacs-deps-check
      environment.systemPackages = with pkgs; [ curl hacsDepsCheck ];
      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
