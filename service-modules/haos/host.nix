# service-modules/haos/host.nix — roles.host of @clanarchy/haos.
#
# Runs one Home Assistant OS guest under QEMU/KVM as a plain systemd unit,
# `haos-<name>.service`.  The design is in ../haos.md; the notes here are about
# HOW, and each one exists because the obvious spelling fails.
#
# ── NOT microvm.nix, NOT libvirt ────────────────────────────────────────────
#
#   microvm.nix builds the guest from a NixOS configuration; HAOS is a
#   finished appliance image, so there is nothing for it to build.  libvirt
#   would put the definition in a domain XML outside the repo.  A unit that
#   execs qemu is the only shape in which every property of the VM is a line
#   in a file someone can review.
#
# ── THE DISK IS A RAW ZVOL, AND THE IMAGE IS FETCHED ONLY TO SEED IT ────────
#
#   A qcow2 file on a ZFS dataset is copy-on-write on copy-on-write: two
#   allocators, two layers of metadata and fragmentation per guest write.  A
#   zvol with cache=none + io_uring + an iothread is one layer.
#
#   The image is downloaded at RUNTIME, only when the zvol is empty, and
#   checked against a pinned sha256.  NOT `fetchurl`: that would put ~400 MiB
#   in the system closure forever for a file read once.  After the seed, the
#   disk is state — HAOS updates itself from its own UI, and the pinned version
#   only says what a NEW instance starts from.
#
#   A SEED THAT DIES HALF-WAY IS NOT A DISK.  The zvol carries a user property,
#   `clanarchy:seeded`, set to `no` at creation and `yes` only after the image
#   is fully written; any other value re-seeds on the next start rather than
#   booting a truncated image.
#
# ── QEMU RUNS AS ITS OWN USER; THE ROOT PART IS ExecStartPre ────────────────
#
#   Opening a zvol, /dev/vhost-net and a USB device node all need privileges a
#   VM process should not hold for its lifetime.  So `+`-prefixed ExecStartPre
#   does the root-only work (create/seed the zvol, chown the device nodes it
#   resolved, copy the OVMF variable store), and qemu itself runs as
#   `haos-<name>` in group `kvm`.
#
#   NO FIXED UID, and that is deliberate rather than an omission.  The only
#   files this user owns on zdata are the OVMF variable store, and the
#   ExecStartPre re-chowns it on every start — so a uid that moves between
#   boots costs nothing, which is the property a 3000-block number exists to
#   buy.  The zvol and the USB nodes are chowned at start too.
#
# ── USB: RESOLVED BY SERIAL OR PORT AT START, PASSED BY BUS+PORT ────────────
#
#   qemu's `usb-host` matches either vendor:product (useless when two dongles
#   are the same product — the ZBT-2 pair is) or hostbus+hostport/hostaddr.
#   hostaddr changes on every re-enumeration.  So ExecStartPre walks
#   /sys/bus/usb/devices, finds exactly one device per entry by
#   vendor + product + (serial and/or kernel port name), and hands qemu that
#   device's bus and port.  qemu re-attaches a device replugged into the SAME
#   port by itself; the udev rule below keeps the new node owned by the guest
#   user so it can.
#
#   EXACTLY ONE MATCH OR THE VM DOES NOT START.  Zero means a dongle is
#   missing; two means the selector is ambiguous.  Either way booting would
#   hand the guest the wrong radio or none, which is worse than a failed unit
#   naming the entry.
#
# ── THE FIREWALL IS ON THE HOST, IN THE BRIDGE ──────────────────────────────
#
#   HAOS has no user-configurable firewall and the Supervisor listens on ports
#   of its own (4357 observer, every add-on's).  Traffic between this guest and
#   a container on the same VLAN is switched inside br0 and never reaches the
#   gateway, so a gateway rule would not see it either.  One nftables table in
#   the `bridge` family, per instance, filters every frame bridged TOWARDS each
#   tap: established, ARP and DHCP replies, then each `allowFrom`, then drop.
#
#   NATIVE nft, NOT networking.nftables, because a host on the iptables
#   firewall never loads `networking.nftables.tables`.  Where the host does
#   run nftables, the table goes there instead, so `nftables.service`'s
#   `flush ruleset` cannot silently delete it on reload.
#
#   FAIL-CLOSED: the VM's unit Requires= the filter's unit.  No filter, no VM.
{lib}: {
  description = "A Home Assistant OS guest under QEMU/KVM.";

  interface.options = let
    allowType = lib.types.submodule {
      options = {
        peer = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Source address. Null admits any source — what a multicast discovery protocol needs.";
        };
        proto = lib.mkOption {
          type = lib.types.enum ["tcp" "udp" "icmpv6"];
          default = "tcp";
          description = ''
            `icmpv6` takes `port = null` (it has no ports) and admits every
            ICMPv6 type: neighbour discovery, router solicitations, MLD.  A
            segment the guest speaks IPv6 on needs it, because neighbour
            advertisements are not tracked as replies, so `established` never
            admits them.  Without it unicast IPv6 dies at address resolution.
          '';
        };
        port = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.port lib.types.str);
          description = ''
            Destination port, or a range as "a:b".  Null admits every port of
            `proto` and has NO DEFAULT on purpose: opening everything is
            something a reader must see written down.  Same vocabulary as
            `clanarchy.containers.<name>.allowFrom`.
          '';
        };
      };
    };

    nicType = lib.types.submodule {
      options = {
        tap = lib.mkOption {
          type = lib.types.strMatching "[a-zA-Z0-9_-]{1,15}";
          description = ''
            Host interface name.  HOST-GLOBAL — it shares one namespace with
            every container veth — and at most 15 characters (IFNAMSIZ).
          '';
        };
        mac = lib.mkOption {
          type = lib.types.strMatching "([0-9a-f]{2}:){5}[0-9a-f]{2}";
          description = ''
            Guest MAC, lower case.  On a DHCP segment the address is a
            reservation keyed on this, so a typo does not fail — it takes a
            pool lease.
          '';
        };
        kind = lib.mkOption {
          type = lib.types.enum ["bridged" "p2p"];
          description = ''
            `bridged`: a port on `bridge`, untagged member of `vlan`.
            `p2p`: no bridge; a /128 on the host end and a route to the guest
            end, for reaching a loopback-bound producer through a
            service-modules/local-ai/bridges.nix socket.
          '';
        };
        bridge = lib.mkOption {
          type = lib.types.str;
          default = "br0";
        };
        vlan = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "VLAN for a bridged NIC (PVID, egress untagged). Null leaves the bridge's default.";
        };
        hostAddress6 = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "p2p only: host end, without prefix length.";
        };
        guestAddress6 = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "p2p only: guest end, without prefix length. Configured INSIDE HAOS by hand; declared here for the route.";
        };
        allowFrom = lib.mkOption {
          type = lib.types.listOf allowType;
          default = [];
          description = "Bridged only: what may reach the guest through this NIC. Everything else is dropped in the bridge.";
        };
      };
    };

    usbType = lib.types.submodule {
      options = {
        name = lib.mkOption {
          type = lib.types.strMatching "[a-z0-9-]+";
          description = "Label, used in the qemu device id and in error messages.";
        };
        vendorId = lib.mkOption {
          type = lib.types.strMatching "[0-9a-f]{4}";
        };
        productId = lib.mkOption {
          type = lib.types.strMatching "[0-9a-f]{4}";
        };
        serial = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "The device's USB serial (sysfs `serial`). The best selector when the device has one.";
        };
        port = lib.mkOption {
          type = lib.types.nullOr (lib.types.strMatching "[0-9]+-[0-9.]+");
          default = null;
          description = ''
            Kernel port name, e.g. "3-2.1" (bus 3, port path 2.1) — the
            directory name under /sys/bus/usb/devices.  For a device with no
            serial: pins it to a physical socket, so moving it to another
            socket is a config change.
          '';
        };
      };
    };
  in {
    name = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9-]{1,10}";
      default = "haos";
      description = "Instance name: unit `haos-<name>`, user `haos-<name>`, /run/haos-<name>.";
    };

    image = {
      version = lib.mkOption {
        type = lib.types.str;
        default = "18.4";
        description = "HAOS release a NEW disk is seeded from. Ignored once the disk exists — HAOS updates itself.";
      };
      sha256 = lib.mkOption {
        type = lib.types.strMatching "[0-9a-f]{64}";
        default = "756ec485b1b153099ca53e88a5eebd63a801d56b791afe5c6d63ef94a35dc02d";
        description = "Hex sha256 of haos_ova-<version>.qcow2.xz (GitHub's release asset digest).";
      };
    };

    vcpus = lib.mkOption {
      type = lib.types.ints.between 1 64;
      default = 2;
    };
    memoryMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
    };
    hugepages = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Back guest RAM with 2 MiB hugepages reserved at boot (`hugepages=` on
        the kernel command line, so fragmentation cannot make the reservation
        fail later).  Fewer TLB misses for the guest; the cost is that the
        memory is taken from the host at boot whether the VM runs or not,
        and the ZFS ARC cannot use it.
      '';
    };
    cpuAffinity = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "12-15";
      description = "systemd CPUAffinity= for the qemu process. Null: scheduler's choice.";
    };

    disk = {
      zvol = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+";
        example = "zdata/vm/hass";
        description = "Zvol holding the guest disk. Created (with a mountpoint=none parent) if absent.";
      };
      sizeGiB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 64;
        description = "Size at creation. Growing it later is `zfs set volsize=`; HAOS grows its data partition itself.";
      };
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      example = "/srv/state/haos-hass";
      description = "Persistent host-side state: the OVMF variable store. Must be on `stateGuard.source`.";
    };
    stateGuard = {
      mount = lib.mkOption {
        type = lib.types.str;
        default = "/srv/state";
      };
      source = lib.mkOption {
        type = lib.types.str;
        default = "zdata/state";
        description = "Expected filesystem source of `stateGuard.mount`. Start is refused otherwise — state on a rolled-back root is lost at the next boot.";
      };
    };

    nics = lib.mkOption {
      type = lib.types.listOf nicType;
      default = [];
      description = "Guest NICs, in PCI order — which is the order HAOS names them in, so append rather than insert.";
    };

    usb = lib.mkOption {
      type = lib.types.listOf usbType;
      default = [];
      description = "Host USB devices handed to the guest exclusively.";
    };

    metrics.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Declare the `haos-<name>-metrics` clan vars generator, which PROMPTS
        for a Home Assistant long-lived access token for Prometheus.  Turn
        this on only once the token exists — a pending prompt blocks every
        `clan machines update`, for every machine.  The scrape itself is
        configured in @clanarchy/monitoring (`mediaStack.homeAssistant*`).
      '';
    };
  };

  perInstance = {settings, ...}: {
    nixosModule = {
      config,
      pkgs,
      lib,
      ...
    }: let
      s = settings;
      unit = "haos-${s.name}";
      user = unit;
      runDir = "/run/${unit}";
      pool = lib.head (lib.splitString "/" s.disk.zvol);
      zvolParent = lib.concatStringsSep "/" (lib.init (lib.splitString "/" s.disk.zvol));
      zvolDev = "/dev/zvol/${s.disk.zvol}";

      bridged = lib.filter (n: n.kind == "bridged") s.nics;
      p2p = lib.filter (n: n.kind == "p2p") s.nics;

      queuesFor = n:
        if n.kind == "bridged"
        then lib.min s.vcpus 4
        else 1;

      imageUrl = "https://github.com/home-assistant/operating-system/releases/download/${s.image.version}/haos_ova-${s.image.version}.qcow2.xz";

      ovmf = pkgs.OVMF.fd;

      # ── qemu's command line ──────────────────────────────────────────────
      hex2 = i: lib.toLower (lib.fixedWidthString 2 "0" (lib.toHexString i));

      # Each NIC at a FIXED PCI address, from 0x10 upwards in list order.
      # HAOS's NetworkManager names interfaces by slot (enp0s16, enp0s17, …)
      # and keys its saved settings on that name, so a NIC that moved slot
      # would come up unconfigured.
      nicArgs = lib.concatLists (lib.imap0 (i: n: let
          q = queuesFor n;
        in [
          "-netdev"
          ("tap,id=net${toString i},ifname=${n.tap},script=no,downscript=no,vhost=on"
            + lib.optionalString (q > 1) ",queues=${toString q}")
          "-device"
          ("virtio-net-pci,netdev=net${toString i},mac=${n.mac},bus=pcie.0,addr=0x${hex2 (16 + i)}"
            + lib.optionalString (q > 1) ",mq=on,vectors=${toString (2 * q + 2)}")
        ])
        s.nics);

      # RAM is always an explicit memfd backend; whether it is hugetlb-backed
      # is decided at START by the prestart (see "hugepages" there), so the
      # backend object comes from /run/haos-<name>/mem.args.
      machineArg = "q35,accel=kvm,memory-backend=ram0";
      hugePages = s.memoryMiB / 2;

      qemuArgs =
        [
          "-name"
          "${unit},process=${unit}"
          "-nodefaults"
          "-no-user-config"
          "-machine"
          machineArg
          "-cpu"
          "host"
          "-smp"
          "${toString s.vcpus},sockets=1,cores=${toString s.vcpus},threads=1"
          "-m"
          "${toString s.memoryMiB}M"
        ]
        ++ [
          "-drive"
          "if=pflash,format=raw,unit=0,readonly=on,file=${ovmf}/FV/OVMF_CODE.fd"
          "-drive"
          "if=pflash,format=raw,unit=1,file=${s.stateDir}/OVMF_VARS.fd"
          "-object"
          "iothread,id=io0"
          "-blockdev"
          "driver=host_device,node-name=disk0,filename=${zvolDev},cache.direct=on,aio=io_uring,discard=unmap"
          "-device"
          "virtio-blk-pci,drive=disk0,iothread=io0,bootindex=1"
          "-device"
          "virtio-rng-pci"
          "-device"
          "qemu-xhci,id=xhci"
        ]
        ++ nicArgs
        ++ [
          "-chardev"
          "socket,id=ser0,path=${runDir}/serial.sock,server=on,wait=off"
          "-serial"
          "chardev:ser0"
          "-qmp"
          "unix:${runDir}/qmp.sock,server=on,wait=off"
          "-display"
          "none"
          "-vga"
          "none"
        ];

      # ── ExecStartPre (root) ──────────────────────────────────────────────
      usbLine = d: "resolve_usb ${lib.escapeShellArgs [d.name d.vendorId d.productId (toString d.serial) (toString d.port)]}";

      prestart = pkgs.writeShellApplication {
        name = "${unit}-prestart";
        runtimeInputs = with pkgs; [coreutils util-linux zfs curl xz qemu-utils systemd gawk];
        text = ''
          # ── state is where it must be ──────────────────────────────────────
          src=$(findmnt --noheadings --output SOURCE --target ${s.stateGuard.mount} || true)
          if [ "$src" != ${lib.escapeShellArg s.stateGuard.source} ]; then
            echo "${unit}: ${s.stateGuard.mount} is '$src', expected '${s.stateGuard.source}'." >&2
            echo "  Refusing to start: the OVMF variable store would land on a" >&2
            echo "  filesystem that is rolled back on the next boot." >&2
            exit 1
          fi
          install -d -m 0750 -o root -g root ${s.stateDir}
          if [ ! -e ${s.stateDir}/OVMF_VARS.fd ]; then
            install -m 0600 ${ovmf}/FV/OVMF_VARS.fd ${s.stateDir}/OVMF_VARS.fd
          fi
          chown ${user}:${user} ${s.stateDir}/OVMF_VARS.fd
          chmod 0600 ${s.stateDir}/OVMF_VARS.fd
          chgrp ${user} ${s.stateDir}
          chmod 0750 ${s.stateDir}

          # ── the disk ───────────────────────────────────────────────────────
          if ! zpool list -H -o name ${pool} >/dev/null 2>&1; then
            echo "${unit}: pool '${pool}' is not imported; not creating a disk anywhere else." >&2
            exit 1
          fi
          if ! zfs list -H -o name ${lib.escapeShellArg zvolParent} >/dev/null 2>&1; then
            zfs create -p -o mountpoint=none ${lib.escapeShellArg zvolParent}
          fi
          if ! zfs list -H -o name ${lib.escapeShellArg s.disk.zvol} >/dev/null 2>&1; then
            echo "${unit}: creating ${s.disk.zvol} (${toString s.disk.sizeGiB} GiB)"
            zfs create -V ${toString s.disk.sizeGiB}G \
              -o volblocksize=16K -o compression=lz4 \
              -o com.sun:auto-snapshot=true -o clanarchy:seeded=no \
              ${lib.escapeShellArg s.disk.zvol}
          fi

          seeded=$(zfs get -H -o value clanarchy:seeded ${lib.escapeShellArg s.disk.zvol})
          if [ "$seeded" != "yes" ]; then
            udevadm settle --timeout=30
            for _ in $(seq 1 30); do [ -e ${zvolDev} ] && break; sleep 1; done
            [ -e ${zvolDev} ] || { echo "${unit}: ${zvolDev} never appeared" >&2; exit 1; }

            tmp=$(mktemp -d ${s.stateDir}/seed.XXXXXX)
            trap 'rm -rf "$tmp"' EXIT
            echo "${unit}: seeding ${s.disk.zvol} from HAOS ${s.image.version}"
            curl -fL --retry 3 -o "$tmp/haos.qcow2.xz" ${lib.escapeShellArg imageUrl}
            echo "${s.image.sha256}  $tmp/haos.qcow2.xz" | sha256sum -c -
            xz -dc "$tmp/haos.qcow2.xz" > "$tmp/haos.qcow2"
            qemu-img convert -n -f qcow2 -O raw "$tmp/haos.qcow2" ${zvolDev}
            sync
            zfs set clanarchy:seeded=yes clanarchy:seeded-from=${s.image.version} ${lib.escapeShellArg s.disk.zvol}
            rm -rf "$tmp"
            trap - EXIT
          fi
          chown ${user} "$(readlink -f ${zvolDev})"

          # ── memory ─────────────────────────────────────────────────────────
          # The `hugepages=` kernel parameter only takes effect at BOOT, and
          # the deploy that introduces it is not one.  So reserve at runtime
          # when the boot-time pool is short, and if fragmentation still
          # leaves too few free, start on ordinary memory and SAY so rather
          # than leave the house's hub down until someone reboots the host.
          ${
            if s.hugepages
            then ''
              need=${toString hugePages}
              free=$(awk '/^HugePages_Free:/ {print $2}' /proc/meminfo)
              if [ "$free" -lt "$need" ]; then
                total=$(cat /proc/sys/vm/nr_hugepages)
                echo $(( total + need - free )) > /proc/sys/vm/nr_hugepages || true
                free=$(awk '/^HugePages_Free:/ {print $2}' /proc/meminfo)
              fi
              if [ "$free" -ge "$need" ]; then
                printf '%s\n' -object "memory-backend-memfd,id=ram0,size=${toString s.memoryMiB}M,hugetlb=on,hugetlbsize=2M,prealloc=on" > ${runDir}/mem.args
              else
                echo "${unit}: only $free of $need 2 MiB hugepages free — starting on ordinary memory. A reboot applies the boot-time reservation." >&2
                printf '%s\n' -object "memory-backend-memfd,id=ram0,size=${toString s.memoryMiB}M" > ${runDir}/mem.args
              fi
            ''
            else ''
              printf '%s\n' -object "memory-backend-memfd,id=ram0,size=${toString s.memoryMiB}M" > ${runDir}/mem.args
            ''
          }
          chown ${user} ${runDir}/mem.args

          # ── USB passthrough ────────────────────────────────────────────────
          : > ${runDir}/usb.args
          resolve_usb() {
            local name=$1 vid=$2 pid=$3 serial=$4 port=$5
            local matches=() d
            for _ in $(seq 1 30); do
              matches=()
              for d in /sys/bus/usb/devices/*; do
                [ -f "$d/idVendor" ] || continue
                [ "$(cat "$d/idVendor")" = "$vid" ] || continue
                [ "$(cat "$d/idProduct")" = "$pid" ] || continue
                if [ -n "$serial" ]; then [ "$(cat "$d/serial" 2>/dev/null)" = "$serial" ] || continue; fi
                if [ -n "$port" ]; then [ "$(basename "$d")" = "$port" ] || continue; fi
                matches+=("$d")
              done
              [ "''${#matches[@]}" -ge 1 ] && break
              sleep 1
            done
            if [ "''${#matches[@]}" -ne 1 ]; then
              echo "${unit}: USB '$name' ($vid:$pid serial='$serial' port='$port') matched ''${#matches[@]} devices, need exactly 1:" >&2
              printf '  %s\n' "''${matches[@]}" >&2
              exit 1
            fi
            d=''${matches[0]}
            local kname bus hport dev
            kname=$(basename "$d")
            bus=$(cat "$d/busnum")
            hport=''${kname#*-}
            dev=$(printf '/dev/bus/usb/%03d/%03d' "$bus" "$(cat "$d/devnum")")
            chown ${user} "$dev"
            printf '%s\n' -device "usb-host,bus=xhci.0,hostbus=$bus,hostport=$hport,id=usb-$name" >> ${runDir}/usb.args
            echo "${unit}: USB '$name' -> $kname ($dev)"
          }
          ${lib.concatMapStringsSep "\n" usbLine s.usb}
          chown ${user} ${runDir}/usb.args
        '';
      };

      start = pkgs.writeShellApplication {
        name = "${unit}-start";
        runtimeInputs = [pkgs.qemu_kvm];
        text = ''
          mapfile -t mem < ${runDir}/mem.args
          mapfile -t usb < ${runDir}/usb.args
          exec qemu-system-x86_64 ${lib.escapeShellArgs qemuArgs} "''${mem[@]}" "''${usb[@]}"
        '';
      };

      # QEMU on SIGTERM quits WITHOUT telling the guest — a power cut, for a
      # guest running a recorder database.  So stop asks for an ACPI power
      # button press and waits for the process to leave on its own; systemd's
      # SIGTERM after this is only the backstop.
      stop = pkgs.writeShellApplication {
        name = "${unit}-stop";
        runtimeInputs = with pkgs; [socat coreutils];
        text = ''
          printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"system_powerdown"}' \
            | socat -t2 - UNIX-CONNECT:${runDir}/qmp.sock >/dev/null || true
          for _ in $(seq 1 110); do
            kill -0 "''${MAINPID:-0}" 2>/dev/null || exit 0
            sleep 1
          done
          echo "${unit}: guest did not power off in 110 s; systemd will SIGTERM qemu." >&2
        '';
      };

      # ── the bridge filter ───────────────────────────────────────────────
      table = "haos_${lib.replaceStrings ["-"] ["_"] s.name}";
      isV6 = a: a != null && lib.hasInfix ":" a;
      ruleFor = a:
        lib.concatStringsSep " " (
          lib.optional (a.peer != null) "${
            if isV6 a.peer
            then "ip6"
            else "ip"
          } saddr ${a.peer}"
          ++ [
            "meta l4proto ${
              if a.proto == "icmpv6"
              then "ipv6-icmp"
              else a.proto
            }"
          ]
          ++ lib.optional (a.port != null) "th dport ${lib.replaceStrings [":"] ["-"] (toString a.port)}"
          ++ ["accept"]
        );
      chainName = n: "to_${lib.replaceStrings ["-"] ["_"] n.tap}";
      tableBody = ''
        chain forward {
          type filter hook forward priority filter; policy accept;
        ${lib.concatMapStrings (n: "  oifname \"${n.tap}\" jump ${chainName n}\n") bridged}}
        ${lib.concatMapStrings (n: ''
            chain ${chainName n} {
              ct state established,related accept
              ether type arp accept
              meta l4proto udp udp sport 67 udp dport 68 accept
            ${lib.concatMapStrings (a: "  ${ruleFor a}\n") n.allowFrom}  counter drop
            }
          '')
          bridged}
      '';
      useNftablesModule = config.networking.nftables.enable;
      rulesetFile = pkgs.writeText "${unit}-filter.nft" ''
        table bridge ${table}
        delete table bridge ${table}
        table bridge ${table} {
        ${tableBody}
        }
      '';
      filterUnit = "${unit}-filter";

      tapDeviceUnits = map (n: "sys-subsystem-net-devices-${n.tap}.device") s.nics;
    in {
      imports = [./registry.nix];

      assertions = [
        {
          assertion = lib.all (n: n.kind == "bridged" || (n.hostAddress6 != null && n.guestAddress6 != null)) s.nics;
          message = "@clanarchy/haos(${s.name}): every p2p NIC needs hostAddress6 and guestAddress6.";
        }
        {
          assertion = lib.all (n: n.kind == "p2p" || (n.hostAddress6 == null && n.guestAddress6 == null)) s.nics;
          message = "@clanarchy/haos(${s.name}): hostAddress6/guestAddress6 are p2p-only; a bridged NIC gets its address from its segment.";
        }
        {
          assertion = lib.all (n: lib.all (a: a.proto != "icmpv6" || a.port == null) n.allowFrom) s.nics;
          message = "@clanarchy/haos(${s.name}): an icmpv6 allowFrom entry takes port = null; ICMPv6 has no ports.";
        }
        {
          assertion = lib.all (n: n.kind == "bridged" || n.allowFrom == []) s.nics;
          message = "@clanarchy/haos(${s.name}): allowFrom on a p2p NIC filters nothing — the consumer side of a p2p leg is the host's firewall (local-ai bridges.nix).";
        }
        {
          assertion = let
            ids = map (d: "${d.vendorId}:${d.productId}") s.usb;
            ambiguous = lib.filter (d: d.serial == null && d.port == null && lib.count (x: x == "${d.vendorId}:${d.productId}") ids > 1) s.usb;
          in
            ambiguous == [];
          message = "@clanarchy/haos(${s.name}): two USB entries share a vendor:product and at least one names neither serial nor port, so they cannot be told apart.";
        }
        {
          assertion = lib.length (lib.unique (map (n: n.tap) s.nics)) == lib.length s.nics;
          message = "@clanarchy/haos(${s.name}): two NICs share a tap name.";
        }
        {
          assertion = lib.count (i: i) (lib.mapAttrsToList (_: v: v.hugepages) config.clanarchy.haos.instances) <= 1;
          message = "@clanarchy/haos: only one instance per machine may set hugepages — the reservation is a single kernel parameter.";
        }
      ];

      clanarchy.haos.instances.${s.name} = {
        taps = map (n: n.tap) s.nics;
        hostAddresses6 = map (n: n.hostAddress6) p2p;
        macs = lib.listToAttrs (map (n: lib.nameValuePair (toString n.vlan) n.mac) (lib.filter (n: n.vlan != null) bridged));
        inherit (s) hugepages;
      };

      users.users.${user} = {
        isSystemUser = true;
        group = user;
        extraGroups = ["kvm"];
        description = "Home Assistant OS guest ${s.name}";
      };
      users.groups.${user} = {};

      boot.kernelModules = ["vhost_net" "nf_conntrack_bridge"];
      boot.kernelParams = lib.optionals s.hugepages [
        "hugepagesz=2M"
        "hugepages=${toString hugePages}"
      ];

      # vhost-net for the guest user, and a replugged passthrough device stays
      # the guest's — ExecStartPre only chowns what exists at start.
      services.udev.extraRules =
        ''
          KERNEL=="vhost-net", GROUP="kvm", MODE="0660"
        ''
        + lib.concatMapStrings (d:
          ''SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="${d.vendorId}", ATTR{idProduct}=="${d.productId}"''
          + lib.optionalString (d.serial != null) '', ATTR{serial}=="${d.serial}"''
          + lib.optionalString (d.port != null) '', KERNEL=="${d.port}"''
          + ''            , OWNER="${user}"
          '')
        s.usb;

      # ── taps ────────────────────────────────────────────────────────────
      # A netdev, because nothing else creates these.  (microvm.nix creates
      # its own taps, which is why wg-qbittorrent.nix must NOT declare one.)
      systemd.network.netdevs = lib.listToAttrs (map (n:
        lib.nameValuePair "40-${n.tap}" {
          netdevConfig = {
            Name = n.tap;
            Kind = "tap";
          };
          tapConfig = {
            User = user;
            Group = user;
            VNetHeader = true;
            MultiQueue = queuesFor n > 1;
          };
        })
      s.nics);

      systemd.network.networks =
        lib.listToAttrs (map (n:
          lib.nameValuePair "60-${n.tap}" {
            matchConfig.Name = n.tap;
            networkConfig = {
              Bridge = n.bridge;
              LinkLocalAddressing = "no";
              IPv6AcceptRA = false;
              # A tap has no carrier until qemu opens it; enslave and apply
              # the VLAN before that, not whenever the guest happens to boot.
              ConfigureWithoutCarrier = true;
            };
            bridgeVLANs = lib.optionals (n.vlan != null) [
              {
                VLAN = n.vlan;
                PVID = n.vlan;
                EgressUntagged = n.vlan;
              }
            ];
            linkConfig.RequiredForOnline = "no";
          })
        bridged)
        // lib.listToAttrs (map (n:
          lib.nameValuePair "60-${n.tap}" {
            matchConfig.Name = n.tap;
            address = ["${n.hostAddress6}/128"];
            routes = [{Destination = "${n.guestAddress6}/128";}];
            networkConfig = {
              # IPv6 link-local stays ON here, unlike every bridged port: the
              # guest resolves the host end by neighbour discovery.  No RA is
              # accepted, and no DAD — the address must exist before the
              # guest does, so the loopback bridges' sockets have it.
              LinkLocalAddressing = "ipv6";
              IPv6AcceptRA = false;
              IPv6DuplicateAddressDetection = 0;
              ConfigureWithoutCarrier = true;
            };
            linkConfig.RequiredForOnline = "no";
          })
        p2p);

      # EVERY tap, not only the bridged ones.  A host-side mDNS reflector on a
      # bridged tap would be exactly the relay across a firewall boundary this
      # repo refuses, and the tap carries no host address anyway.  On a p2p
      # tap it is worse: the guest announces its one hostname on each of its
      # NICs, the reflector carries the announcement from one p2p leg into
      # the other (and onto br0, where the UDM-Pro's reflector takes it
      # further), and the guest sees its own name claimed with a different
      # address.  It loses the tie-break and renames itself, which re-announces
      # and loops.  Measured on ernst on 2026-11-05 while only the bridged taps
      # were denied: about 18 packets a second, and the name at
      # homeassistant82520.local.  No p2p leg carries anything mDNS is for.
      services.avahi.settings.server."deny-interfaces" = map (n: n.tap) s.nics;

      # ── the filter ──────────────────────────────────────────────────────
      networking.nftables.tables = lib.mkIf useNftablesModule {
        ${table} = {
          family = "bridge";
          content = tableBody;
        };
      };

      systemd.services.${filterUnit} = lib.mkIf (!useNftablesModule) {
        description = "Bridge filter in front of the ${unit} guest";
        wantedBy = ["multi-user.target"];
        before = ["${unit}.service"];
        after = ["systemd-modules-load.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # modprobe here as well as in boot.kernelModules: those load at
          # boot, and the first deploy is not a boot.
          ExecStartPre = "${pkgs.kmod}/bin/modprobe nf_conntrack_bridge";
          ExecStart = "${pkgs.nftables}/bin/nft -f ${rulesetFile}";
          ExecReload = "${pkgs.nftables}/bin/nft -f ${rulesetFile}";
          ExecStop = "${pkgs.nftables}/bin/nft delete table bridge ${table}";
        };
        reloadIfChanged = true;
      };

      # ── the VM ──────────────────────────────────────────────────────────
      systemd.services.${unit} = {
        description = "Home Assistant OS guest ${s.name}";
        wantedBy = ["multi-user.target"];
        after =
          ["network.target" "systemd-networkd.service" "zfs.target" "systemd-udev-settle.service"]
          ++ lib.optional (!useNftablesModule) "${filterUnit}.service"
          ++ lib.optional useNftablesModule "nftables.service"
          ++ tapDeviceUnits;
        requires =
          tapDeviceUnits
          ++ lib.optional (!useNftablesModule) "${filterUnit}.service"
          ++ lib.optional useNftablesModule "nftables.service";
        unitConfig.RequiresMountsFor = [s.stateDir];
        # Restarting the guest because its unit file changed would reboot the
        # house's lights on every deploy that touched an unrelated line here.
        # The new command line takes effect at the next stop/start.
        restartIfChanged = false;
        serviceConfig =
          {
            Type = "simple";
            User = user;
            Group = user;
            SupplementaryGroups = ["kvm"];
            RuntimeDirectory = unit;
            RuntimeDirectoryMode = "0750";
            ExecStartPre = "+${prestart}/bin/${unit}-prestart";
            ExecStart = "${start}/bin/${unit}-start";
            ExecStop = "${stop}/bin/${unit}-stop";
            TimeoutStartSec = "15min"; # a first start downloads and writes the image
            TimeoutStopSec = 120;
            Restart = "on-failure";
            RestartSec = 10;
            LimitMEMLOCK = "infinity";
            ProtectSystem = "strict";
            # `-`: systemd builds this namespace before ANY ExecStartPre runs,
            # `+`-prefixed included, so a path the prestart is about to create
            # fails the whole unit with 226/NAMESPACE.  Measured on the first
            # deploy (2026-11-05, 100 restarts).  By the time qemu starts the
            # directory exists and is writable as intended.
            ReadWritePaths = ["-${s.stateDir}"];
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
          }
          // lib.optionalAttrs (s.cpuAffinity != null) {CPUAffinity = s.cpuAffinity;};
      };

      # ── metrics: the token Prometheus presents ──────────────────────────
      clan.core.vars.generators."${unit}-metrics" = lib.mkIf s.metrics.enable {
        files."token".secret = true;
        prompts."token" = {
          description = "Home Assistant long-lived access token for Prometheus (${s.name}: Profile → Security → Long-lived access tokens)";
          type = "hidden";
        };
        script = ''
          tr -d '[:space:]' < "$prompts/token" > "$out/token"
        '';
      };
    };
  };
}
