# Plasma Bigscreen — KDE's 10-foot TV shell, running inside a declarative
# systemd-nspawn container that carries its own nixpkgs channel.
#
# ── Why a container, and not just a session ───────────────────────────────
# Plasma Bigscreen is not in nixpkgs 26.05 (the top-level attribute is a
# throwing alias and `kdePackages.plasma-bigscreen` does not exist).  It
# appears only on nixpkgs-unstable, at 6.7.4.  The fleet's stable machines
# are on Plasma 6.6.6, and the two generations cannot share a system:
#
#   1. `bin/plasma-bigscreen-wayland` is an unwrapped /bin/sh script.  Only
#      its `--exit-with-session=` argument gets store-path substitution;
#      `startplasma-wayland` is invoked bare, off PATH.  On a 26.05 host
#      that resolves to plasma-workspace 6.6.6, which would then be handed
#      Bigscreen's 6.7.4 shell and libplasma.
#
#   2. Worse, and unfixable with a PATH prefix: both generations ship
#      systemd *user* units under identical names — plasma-plasmashell.service,
#      plasma-workspace-wayland.target, plasma-kcminit.service, and the rest.
#      `services.desktopManager.plasma6.enable` (which the HTPC role pulls in
#      via modules/desktop/kde.nix) registers 6.6.6's copies system-wide.
#      6.7.4's startplasma starts those targets *by name*, so systemd hands
#      it the 6.6.6 units and launches 6.6.6 binaries.  Registering 6.7.4's
#      units alongside collides on the same names — one generation wins and
#      the other breaks.
#
# A container is the smallest boundary that makes both generations coexist:
# it gets its own /nix/store view, its own systemd user-unit namespace, and
# its own `nixpkgs.pkgs`, while sharing the host kernel and the GPU.
#
# ── What was verified on ernst before this module was written ─────────────
# Ad-hoc `systemd-nspawn` runs against the real 7900 XTX, as an unprivileged
# uid with only video/input/render supplementary groups:
#
#   * DRM master works across the container boundary.  `open()` +
#     DRM_IOCTL_SET_MASTER on the card node succeed — but ONLY once the
#     device cgroup permits it.  Without a DeviceAllow entry the open fails
#     EPERM even as root, which is what `allowedDevices` below is for.
#   * KWin initialises its DRM backend and creates a DrmOutput on the TV
#     connector, compiles radeonsi shaders, and loads its effects.
#   * It works *because* the container has no logind.  KWin has no libseat
#     backend and no seatless DRM path; on the host it asks logind for the
#     device and gets EPERM from an SSH session with no seat.  Inside the
#     container logind is absent entirely, so KWin falls back to opening the
#     node directly — which the cgroup now allows.
#   * /dev/tty0 does not exist inside the container and cannot be made to.
#     There is therefore no VT switching.  For a dedicated TV appliance that
#     costs nothing, but it does mean this session can never be one arm of a
#     VT-switched multi-seat setup.
#   * /run/opengl-driver must exist inside the container or gbm device
#     creation fails; `hardware.graphics.enable` below is what provides it.
#
# ── Numeric ID matching ───────────────────────────────────────────────────
# nspawn does not remap uids/gids here, so `uid`/`gid` and the video / input
# / render / audio group numbers MUST match the host's, exactly as
# machines/ernst/containers/jellyfin.nix already documents for `media`.
# Otherwise the bind-mounted home is owned by a stranger and the device
# nodes are unopenable.
{ config, lib, pkgs, pkgs-unstable, ... }:
let
  cfg = config.clanarchy.desktop.bigscreen;

  # Colon-free stable aliases for the GPU nodes.
  #
  # The obvious source path — /dev/dri/by-path/pci-0000:03:00.0-card — cannot
  # be used as an nspawn bind source: the --bind=SRC:DST parser tokenises on
  # ':' and rejects sources carrying extra colons.  This is the same wall
  # jellyfin.nix hit, and the same way around it: a udev rule matching on
  # ENV{ID_PATH} publishes a colon-free alias for the same physical device,
  # preserving the PCI-topology stability guarantee that raw cardN numbering
  # does not have.
  #
  # That guarantee is load-bearing on a dual-GPU box.  On ernst today the
  # dGPU is card1 and the iGPU is card0 — the *opposite* of the PCI ordering
  # — and a kernel bump may flip them.  A flip would hand the TV session the
  # iGPU (breaking the KVM console it is reserved for) and take the compute
  # card away from ROCm.
  cardAlias = "/dev/${cfg.deviceAlias}-card";
  renderAlias = "/dev/${cfg.deviceAlias}-render";

  containerName = cfg.containerName;
in
{
  options.clanarchy.desktop.bigscreen = {
    enable = lib.mkEnableOption "Plasma Bigscreen TV shell in an nspawn container";

    containerName = lib.mkOption {
      type = lib.types.str;
      default = "bigscreen";
      description = ''
        Name of the nspawn container. Also fixes the unit name the session
        switcher starts and stops (`container@<name>.service`).
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      description = ''
        Couch user *inside* the container. Declared by this module in the
        container's own user database — it does not have to exist on the
        host, but if it does (so the host can own the persisted home), the
        `uid`/`gid` below must match the host's.
      '';
      example = "go";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      description = ''
        Numeric uid for `user`. nspawn does not remap ids here, so this must
        equal the host uid that owns `statePath`.
      '';
      example = 1001;
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 100; # "users"
      description = ''
        Numeric primary gid for `user`. Must match the host, same reasoning
        as `uid`.
      '';
    };

    gpu.pciAddress = lib.mkOption {
      type = lib.types.str;
      description = ''
        PCI address of the GPU driving the TV, in `domain:bus:slot.func`
        form as it appears in `lspci` and in udev's ID_PATH — e.g.
        "0000:03:00.0". Find it with:

            ls -l /dev/dri/by-path/     # map card/render nodes to PCI paths
            lspci -nn | grep -i vga     # identify which card is which

        This is deliberately a PCI address rather than the device paths the
        brief for this module originally suggested: every stable by-path
        node name contains colons, and nspawn cannot bind such a source.
        The address is the stable input from which this module derives
        colon-free aliases.
      '';
      example = "0000:03:00.0";
    };

    deviceAlias = lib.mkOption {
      type = lib.types.str;
      default = "clanarchy-bigscreen";
      description = ''
        Basename for the colon-free /dev aliases this module publishes via
        udev: `/dev/<alias>-card` and `/dev/<alias>-render`. Change it only
        if it would collide with another consumer's alias.
      '';
    };

    statePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/${cfg.containerName}-home";
      defaultText = lib.literalExpression ''"/var/lib/''${containerName}-home"'';
      description = ''
        Host directory bind-mounted as the couch user's home inside the
        container. Kept outside the container's own root so a container
        rebuild does not discard Plasma's configuration.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Extra applications to install *inside* the container — e.g. a
        Jellyfin client for the TV.

        These must be drawn from the same package set the container runs on
        (nixpkgs-unstable), not from the host's stable `pkgs`. Machine
        modules receive it as the `pkgs-unstable` module argument, so write
        `[ pkgs-unstable.jellyfin-media-player ]`. Passing a stable package
        here would drag a second, conflicting Qt/KDE closure into the
        session.
      '';
      example = lib.literalExpression "[ pkgs-unstable.jellyfin-media-player ]";
    };

    audio.enable =
      lib.mkEnableOption "PipeWire inside the container, with the host's sound devices bound in"
      // { default = true; };

    cec.enable =
      lib.mkEnableOption ''
        HDMI-CEC passthrough, so a TV remote can drive the session.

        Note this needs a kernel CEC device (/dev/cec*). Most discrete AMD
        and NVIDIA cards do not expose one — ernst has none — in which case
        the udev rule below simply matches nothing and the option is inert.
        It costs a `libcec` in the container closure and nothing else
      ''
      // { default = true; };
  };

  config = lib.mkIf cfg.enable {

    ############################################################################
    # Host side — device aliases, their start-ordering guard, and the home dir.
    ############################################################################

    # Publish colon-free aliases for the TV GPU's card and render nodes.
    # SYMLINK+= adds an alias alongside the stock by-path/by-id links, so no
    # existing consumer (jellyfin's iGPU alias, ROCm's use of this same card)
    # loses a name it already relies on.
    services.udev.extraRules = ''
      SUBSYSTEM=="drm", ENV{ID_PATH}=="pci-${cfg.gpu.pciAddress}", KERNEL=="card*", SYMLINK+="${cfg.deviceAlias}-card"
      SUBSYSTEM=="drm", ENV{ID_PATH}=="pci-${cfg.gpu.pciAddress}", KERNEL=="renderD*", SYMLINK+="${cfg.deviceAlias}-render"
    '';

    # Same guard jellyfin.nix uses, and for the same corner case: a runtime
    # udev-rules reload (`nixos-rebuild switch`) does not re-fire "add" events
    # for already-enumerated DRM devices, so a freshly-added rule does not run
    # and the container would fail to start with "Failed to clone
    # /dev/clanarchy-bigscreen-card: No such file or directory". Triggering the
    # subsystem explicitly makes reload-then-start deploys work without waiting
    # out the settle timeout; on a normal boot both steps are no-ops.
    systemd.services."${containerName}-drm-symlinks" = {
      description = "Ensure ${cardAlias} exists for container@${containerName}";
      wantedBy = [ "container@${containerName}.service" ];
      before = [ "container@${containerName}.service" ];
      after = [ "systemd-udevd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        ExecStart = [
          "${pkgs.systemd}/bin/udevadm trigger --subsystem-match=drm --action=add"
          "${pkgs.systemd}/bin/udevadm settle --exit-if-exists=${cardAlias} --timeout=30"
        ];
      };
    };

    # The couch user's home lives on the host so it survives container
    # rebuilds. Ownership must be the numeric ids the container will use.
    systemd.tmpfiles.rules = [
      "d ${cfg.statePath} 0700 ${toString cfg.uid} ${toString cfg.gid} -"
    ];

    # Impermanence: the fleet rolls root back on boot, so an un-persisted
    # home would mean re-onboarding Plasma on every reboot.
    environment.persistence."/persist".directories = [ cfg.statePath ];

    ############################################################################
    # The container.
    ############################################################################
    containers.${containerName} = {
      # Not autoStart: the TV session owns the GPU's KMS state, and starting
      # it at boot would fight whatever the host display manager is doing.
      # The session switcher in modules/roles/htpc.nix starts and stops it.
      autoStart = false;
      ephemeral = false;
      privateNetwork = false; # shares the host netns, as jellyfin does

      # Device cgroup. This is the entry that makes DRM master reachable at
      # all — verified on ernst: without it, open() on the card node returns
      # EPERM inside the container even for root, and KWin reports
      # "No suitable DRM devices have been found".
      #
      # The DRM nodes are named individually rather than via the char-drm
      # group so the container gets *this* GPU and cannot touch the iGPU that
      # the KVM console depends on.
      allowedDevices =
        [
          {
            node = cardAlias;
            modifier = "rw";
          }
          {
            node = renderAlias;
            modifier = "rw";
          }
          # Keyboards, remotes and gamepads. Granted as a class because input
          # devices are hotplugged and their event numbers are not stable.
          {
            node = "char-input";
            modifier = "rw";
          }
        ]
        ++ lib.optional cfg.audio.enable {
          node = "char-alsa";
          modifier = "rw";
        }
        ++ lib.optional cfg.cec.enable {
          node = "char-cec";
          modifier = "rw";
        };

      bindMounts = {
        "${cardAlias}" = {
          hostPath = cardAlias;
          isReadOnly = false;
        };
        "${renderAlias}" = {
          hostPath = renderAlias;
          isReadOnly = false;
        };
        "/dev/input" = {
          hostPath = "/dev/input";
          isReadOnly = false;
        };
        "/home/${cfg.user}" = {
          hostPath = cfg.statePath;
          isReadOnly = false;
        };
      }
      // lib.optionalAttrs cfg.audio.enable {
        "/dev/snd" = {
          hostPath = "/dev/snd";
          isReadOnly = false;
        };
      };

      ##########################################################################
      # The container's own NixOS system — an entire Plasma generation.
      ##########################################################################
      config =
        { lib, pkgs, ... }:
        {
          system.stateVersion = "26.05";

          # The whole point of the container: its own channel, so Plasma
          # 6.7.4 and its systemd user units are internally consistent and
          # never meet the host's 6.6.6.
          #
          # Note `nixpkgs.config` must NOT be set anywhere in this container
          # config — supplying `pkgs` externally trips a NixOS assertion if
          # both are present. Unfree permissions, if ever needed, belong in
          # the pkgs instance built in lib/mk-machine.nix.
          nixpkgs.pkgs = pkgs-unstable;

          networking.useHostResolvConf = lib.mkForce true;

          # Creates /run/opengl-driver, without which gbm device creation
          # fails and KWin finds no usable DRM device. Verified failure mode.
          hardware.graphics.enable = true;

          # Numeric ids pinned to the host's — nspawn does not remap them, so
          # a mismatch means the bind-mounted home belongs to a stranger and
          # the device nodes cannot be opened. Values cross-checked against
          # `getent group video render input audio` on ernst.
          users.groups.video.gid = 26;
          users.groups.input.gid = 174;
          users.groups.render.gid = 303;
          users.groups.audio.gid = 17;

          users.users.${cfg.user} = {
            isNormalUser = true;
            uid = cfg.uid;
            group = "users";
            home = "/home/${cfg.user}";
            # video + render: open the DRM nodes. input: read evdev.
            # audio: ALSA/PipeWire access to the HDMI audio device.
            extraGroups = [
              "video"
              "render"
              "input"
            ]
            ++ lib.optional cfg.audio.enable "audio";

            # No display manager: nspawn has no VT for one to run on, so the
            # session is started directly as a systemd service instead.
            #
            # `linger` is what makes that possible. startplasma-wayland drives
            # the session through systemd *user* units, which need a running
            # user@<uid>.service. Normally logind starts that on login; there
            # are no logins here, so lingering starts it unconditionally.
            linger = true;
          };
          users.groups.users.gid = cfg.gid;

          services.dbus.enable = true;

          fonts.packages = with pkgs; [
            noto-fonts
            noto-fonts-color-emoji
            inter
          ];

          security.rtkit.enable = lib.mkIf cfg.audio.enable true;
          services.pipewire = lib.mkIf cfg.audio.enable {
            enable = true;
            alsa.enable = true;
            alsa.support32Bit = true;
            pulse.enable = true;
          };

          environment.systemPackages =
            [
              pkgs.kdePackages.plasma-bigscreen

              # Required, not optional. The Bigscreen homescreen plasmoid ships
              # indicators/KdeConnect.qml and indicators/PairWindow.qml, both
              # of which `import org.kde.kdeconnect` — but kdeconnect-kde is
              # not in plasma-bigscreen's closure at 6.7.4 (verified: zero
              # paths). Without it the homescreen dies with
              #   module "org.kde.kdeconnect" is not installed
              #
              # The QML is loaded by *plasmashell*, which renders the plasmoid
              # — not by the plasma-bigscreen-wayland launcher — so wrapping
              # that launcher's QML2_IMPORT_PATH, the fix usually suggested for
              # this bug, addresses the wrong process. Putting the package in
              # the system environment is what actually gets its QML onto the
              # path plasmashell searches.
              #
              # TODO: drop once plasma-bigscreen declares this dependency
              # itself. Re-check with:
              #   nix path-info -r <plasma-bigscreen> | grep -c kdeconnect
              pkgs.kdePackages.kdeconnect-kde
            ]
            ++ cfg.extraPackages
            # cec-client, for checking whether the TV's remote is seen at all.
            ++ lib.optional cfg.cec.enable pkgs.libcec;

          # The session itself.
          #
          # KWin is pinned to the TV GPU via KWIN_DRM_DEVICES. On a
          # single-GPU machine this is redundant; on ernst it is what keeps
          # the compositor off the iGPU that the KVM console owns.
          systemd.services.plasma-bigscreen = {
            description = "Plasma Bigscreen session";
            wantedBy = [ "multi-user.target" ];
            after = [
              "dbus.service"
              "user@${toString cfg.uid}.service"
            ];
            environment = {
              XDG_RUNTIME_DIR = "/run/user/${toString cfg.uid}";
              KWIN_DRM_DEVICES = cardAlias;
              # Qt logs to journald by default when it detects systemd,
              # which makes `machinectl shell` debugging harder than it
              # needs to be. Keep messages on stderr so they land in the
              # unit's journal with the unit's own metadata.
              QT_FORCE_STDERR_LOGGING = "1";
            };
            serviceConfig = {
              User = cfg.user;
              Group = "users";
              # logind is absent in a container, so nothing else creates
              # /run/user/<uid>. Plasma requires it.
              RuntimeDirectory = "user/${toString cfg.uid}";
              RuntimeDirectoryMode = "0700";
              ExecStart = "${pkgs.kdePackages.plasma-bigscreen}/bin/plasma-bigscreen-wayland";
              Restart = "on-failure";
              RestartSec = 3;
              TTYPath = "/dev/null";
            };
          };
        };
    };
  };
}
