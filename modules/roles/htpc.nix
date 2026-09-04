# HTPC role — couch machine: boots into Steam Big Picture, switches to a
# KDE Plasma desktop and back.  The Steam Deck experience on ordinary
# hardware.
#
# ── Why this is not Jovian ────────────────────────────────────────────────
# Jovian-NixOS is Steam *Deck hardware* enablement (Deck kernel, OLED
# panel, controller, power, firmware) and upstream supports only
# nixos-unstable.  Gaming Mode itself is not Jovian's: nixpkgs 26.05 ships
# `programs.steam.gamescopeSession`, which registers a gamescope-driven
# Steam session with the display manager.  A desktop HTPC needs the
# session, not the Deck hardware — so this role runs entirely on the
# fleet's stable channel and stays compatible with ZFS.  birte still uses
# Jovian because birte really is a Deck.
#
# ── What Jovian *does* provide that we reimplement ────────────────────────
# `steamos-session-select`, the helper behind Steam's in-UI "Switch to
# Desktop" button.  It is not in nixpkgs (checked 26.05: absent from both
# nixos/modules and pkgs).  Rather than adopting Jovian for one script, the
# role ships its own — see the session plumbing below.
#
# ── How switching works ───────────────────────────────────────────────────
# `services.displayManager.defaultSession` is evaluated at build time, so it
# cannot be flipped at runtime.  Instead the display manager is pointed at a
# single wrapper session, `clanarchy-htpc`, whose Exec reads a state file and
# execs either the gamescope Steam session or Plasma.  Switching is then
# "write the file, restart the display manager" — the same shape as SteamOS.
#
#   /var/lib/clanarchy-session/current
#     "gamescope" | "plasma" | "kodi" | "bigscreen"
#
# The directory is owned by the couch user so the switch needs no root, and a
# polkit rule lets that user restart display-manager.service (and nothing
# else).
#
# ── The third mode: bigscreen ─────────────────────────────────────────────
# "bigscreen" is not a display-manager session.  Plasma Bigscreen only exists
# on nixpkgs-unstable, and its Plasma generation cannot share a system with
# the 6.6.6 one this machine runs — see modules/desktop/bigscreen.nix for the
# full reasoning — so it lives in an nspawn container that owns the TV GPU
# outright.  Selecting it therefore means "stop the display manager, start
# the container" rather than "exec a different session binary", and the two
# arms are mutually exclusive because both want KMS on the same card.
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.roles.htpc;

  stateDir = "/var/lib/clanarchy-session";
  stateFile = "${stateDir}/current";

  # Presence of this file means "bigscreen is the active mode".
  #
  # It exists so the display manager can be kept from starting *at all* in
  # that mode, via ConditionPathExists below.  The alternative — letting the
  # DM start and having the boot dispatcher stop it again — races with
  # autologin and shows a Plasma session flashing up on the TV before it is
  # torn down.  A condition is evaluated at unit start, so the DM is simply
  # skipped instead.
  flagFile = "${stateDir}/bigscreen-active";

  # Drop-box the Bigscreen container writes into to ask for a session change.
  #
  # The container has no route to host systemd, and giving it one (the host
  # D-Bus socket, or systemctl over the boundary) would hand it far more than
  # "switch my session".  Instead the only thing that crosses is a short
  # string in a file on the already-shared state directory; the host reads it,
  # validates it against the same three names the switcher accepts, and acts.
  requestFile = "${stateDir}/request";

  # The nspawn unit backing the "bigscreen" mode. Named here so the switcher,
  # the boot dispatcher and the polkit rule cannot drift apart.
  bigscreenUnit = "container@${config.clanarchy.desktop.bigscreen.containerName}.service";

  # The exact set of units the couch user may start/stop. Kept as a list so
  # the polkit rule below is a membership test rather than a growing chain of
  # string comparisons.
  manageableUnits = [
    "display-manager.service"
  ]
  ++ lib.optional cfg.bigscreen.enable bigscreenUnit;

  # Wait for the TV before handing the card to a compositor.
  #
  # gamescope opens the DRM node of the GPU it selects, and if that card has no
  # connected connector it fails backend creation and then segfaults on the way
  # out.  Verified on ernst 2026-08-19, three times in a row:
  #
  #   drm: opening DRM node '/dev/dri/card1'
  #   drm:   HDMI-A-1 (disconnected)     [DP-1..3 likewise]
  #   drm: cannot find any connected connector!
  #   Error drm: Failed to find a primary plane
  #   Failed to create backend.
  #   steam-gamescope: … Segmentation fault (core dumped)
  #
  # A TV that is switched off — or showing another input — drops HPD, so the
  # connector really does read `disconnected`.  That is the ordinary resting
  # state of a living-room machine, not an edge case, and it must not be what
  # decides whether the machine has a session.  Without this the session exits
  # in under a second, SDDM falls back to the greeter, and the TV shows a login
  # form forever after — the couch user never gets Big Picture at all.
  #
  # Waiting holds the VT instead, and Big Picture starts the moment the TV
  # wakes.  It applies to every arm: Plasma's kwin has no more to do with a
  # card that has no output than gamescope does.
  #
  # The card is resolved from the PCI address at RUNTIME and never from a cardN
  # name: numbering on this board is inverted (the dGPU is card1) and can flip
  # on a kernel bump — the same reason machines/ernst/containers/jellyfin.nix
  # pins the iGPU by PCI path.
  #
  # Fail-open when the address resolves to no DRM card: that is a configuration
  # error rather than a dark TV, and blocking on it would turn a typo into a
  # machine with neither a session nor a greeter.  Start, fail visibly, and let
  # the relogin loop below make the failure repeat where it can be read.
  # Sound has to come out of the same card the picture does.
  #
  # A GPU's HDMI audio is function .1 of the same PCI device as its display
  # function .0, so the TV's speakers hang off `<gpu>.1` and nothing else. On
  # a two-GPU box both cards present an HDMI sink, they arrive with identical
  # priority (600/600 as shipped), and which one WirePlumber picks as default
  # is then down to enumeration order — i.e. whichever card the kernel probed
  # first. On ernst that lands on the *iGPU*, whose HDMI goes to the KVM and
  # not to the living room: picture on the TV, sound into a device with no
  # speakers attached. Observed 2026-09-04 — Jellyfin played Avatar with the
  # default sink on "Radeon HD Audio Controller" and no audio in the room.
  #
  # Derived from `display.gpuPciAddress` rather than written out separately so
  # the two cannot drift: the option that decides which card draws the picture
  # is the one that decides where the sound goes.
  #
  # Matched on the PCI prefix and not the full node name, because the trailing
  # part encodes which HDMI connector is in use (`hdmi-stereo-extra3` = the
  # TV's current HDMI 4). Moving the cable to another port on the same card
  # renames the node; it must not silently un-fix this.
  tvAudioNodeMatch =
    let
      # 0000:03:00.0 (display) -> 0000:03:00.1 (its HDMI audio function)
      audioAddress = (lib.removeSuffix ".0" cfg.display.gpuPciAddress) + ".1";
      # PipeWire spells PCI addresses with underscores for the colons, keeping
      # the dot before the function: 0000:03:00.1 -> 0000_03_00.1
      prefix = "alsa_output.pci-" + builtins.replaceStrings [ ":" ] [ "_" ] audioAddress + ".";
    in
    "~" + builtins.replaceStrings [ "." ] [ "\\." ] prefix + ".*";

  waitForDisplay = lib.optionalString (cfg.display.gpuPciAddress != null) ''
    drmDir=/sys/bus/pci/devices/${cfg.display.gpuPciAddress}/drm
    set -- "$drmDir"/card[0-9]*
    if [ ! -d "$1" ]; then
      printf 'clanarchy-session: no DRM card at PCI %s — starting anyway\n' \
        '${cfg.display.gpuPciAddress}' >&2
    else
      card=$1
      waited=0
      until [ -n "''${connected:-}" ]; do
        for statusFile in "$card"/*/status; do
          [ -e "$statusFile" ] || continue
          [ "$(< "$statusFile")" = connected ] && connected=yes
        done
        [ -n "''${connected:-}" ] && break
        if [ $(( waited % 60 )) -eq 0 ]; then
          printf 'clanarchy-session: no connected output on %s — waiting for the TV\n' \
            "$card" >&2
        fi
        ${pkgs.coreutils}/bin/sleep 2
        waited=$(( waited + 2 ))
      done
    fi
  '';

  # Runtime session dispatcher.  Runs as the logged-in user; only reads.
  #
  # `steam-gamescope` is referenced through /run/current-system/sw/bin rather
  # than by store path on purpose: nixpkgs builds it as a private `let`
  # binding inside programs/steam.nix and only exposes it by appending it to
  # environment.systemPackages when gamescopeSession.enable is set.  It is
  # NOT part of `programs.steam.package` — pointing there yields a path that
  # does not exist, and the session fails to start.  The system profile is
  # the only stable handle we get.
  sessionRun = pkgs.writeShellScript "clanarchy-session-run" ''
    set -eu
    mode="$(cat ${stateFile} 2>/dev/null || echo ${cfg.defaultSession})"
    ${waitForDisplay}
    case "$mode" in
      ${
        # "bigscreen" lands on Plasma only while that arm is actually built.
        # If the display manager is running at all then bigscreen is not the
        # active mode — the boot dispatcher stops the DM before starting the
        # container — so reaching this point with mode=bigscreen means
        # something got out of step, and Plasma is a usable desktop rather
        # than a black screen.
        #
        # With the arm not built, a recorded "bigscreen" is stale state from
        # when it was (the value survives in /persist), and honouring it would
        # land the couch user in a mouse-and-keyboard desktop on a machine
        # configured to boot into Big Picture.  Let it fall through to the
        # default instead.
        if cfg.bigscreen.enable then "plasma|bigscreen)" else "plasma)"
      } exec ${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland ;;
      ${lib.optionalString cfg.mediaClient.enable ''
        kodi|media)
          # NOT exec: we need to run something after Kodi exits.
          #
          # Kodi's power menu offers "Exit", and the display manager is set to
          # relogin, so the wrapper would be re-entered, read "kodi" from the
          # state file again and restart Kodi — an inescapable loop on a
          # machine whose only input device may be a game controller. Dropping
          # back to the gaming session on exit mirrors what SteamOS does with
          # its own mode switch, and leaves the couch user somewhere they can
          # navigate rather than staring at the same screen they just tried to
          # leave.
          #
          # Only rewritten when Kodi exits cleanly. A crash leaves the choice
          # alone, so the relogin brings Kodi back rather than silently
          # demoting the machine out of media mode because of a segfault.
          if ${cfg.mediaClient.exe} ${cfg.mediaClient.arguments}; then
            printf 'gamescope\n' > ${stateFile}
          fi
          exit 0
          ;;
      ''}
      *)      exec /run/current-system/sw/bin/steam-gamescope ;;
    esac
  '';

  # One wrapper session for the display manager to target.
  sessionFile =
    (pkgs.writeTextDir "share/wayland-sessions/clanarchy-htpc.desktop" ''
      [Desktop Entry]
      Name=Clanarchy HTPC
      Comment=Steam Big Picture or Plasma, selected at runtime
      Exec=${sessionRun}
      Type=Application
    '').overrideAttrs
      (_: { passthru.providedSessions = [ "clanarchy-htpc" ]; });

  # The switcher.  Accepts our own names plus the ones SteamOS uses, so the
  # same binary can back the `steamos-session-select` shim below.
  sessionSelect = pkgs.writeShellApplication {
    name = "clanarchy-session-select";
    # coreutils for touch/rm on the flag file. Not optional: this is also
    # invoked from clanarchy-session-request.service, whose PATH is systemd's
    # minimal one rather than a login shell's.
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      mode="''${1:-}"
      case "$mode" in
        gamescope|gamescope-wayland|steamos|gaming) mode=gamescope ;;
        plasma|plasma-wayland|plasma-x11|desktop)   mode=plasma ;;
        ${lib.optionalString cfg.mediaClient.enable ''
          kodi|media|tv)                             mode=kodi ;;
        ''}
        ${
          # Only accept "bigscreen" when the container was actually built —
          # otherwise the switcher would happily record a mode whose unit
          # does not exist and leave the machine with no session at all.
          lib.optionalString cfg.bigscreen.enable ''
            bigscreen|tv|mediacenter)                   mode=bigscreen ;;
          ''
        }
        *)
          echo "usage: clanarchy-session-select {gamescope|plasma${
            lib.optionalString cfg.mediaClient.enable "|kodi"
          }${lib.optionalString cfg.bigscreen.enable "|bigscreen"}}" >&2
          exit 2
          ;;
      esac

      # The state dir is owned by the HTPC user (tmpfiles rule below), so
      # this deliberately does not need root.
      printf '%s\n' "$mode" > ${stateFile}

      # The display manager and the Bigscreen container both want KMS on the
      # TV's GPU, so exactly one of them may run.  Whichever we are leaving
      # is stopped first and allowed to release the card before the other is
      # started — hence stop/start rather than a single restart on this path.
      #
      # The flag file is what keeps the two apart across reboots: while it
      # exists the display manager's start condition fails, so nothing else
      # has to remember to hold it back.
      if [ "$mode" = bigscreen ]; then
        touch ${flagFile}
        systemctl stop display-manager.service || true
        exec systemctl start ${bigscreenUnit}
      fi

      ${lib.optionalString cfg.bigscreen.enable ''
        rm -f ${flagFile}
        systemctl stop ${bigscreenUnit} || true
      ''}

      # Restarting the display manager tears down the current session —
      # this is how SteamOS does it too, and why the write happens first.
      exec systemctl restart display-manager.service
    '';
  };

  # Steam's Big Picture "Switch to Desktop" button shells out to
  # `steamos-session-select`.  Provide it under that name so the in-UI
  # button works instead of only our own launcher.
  steamosShim = pkgs.writeShellApplication {
    name = "steamos-session-select";
    runtimeInputs = [ sessionSelect ];
    text = ''
      # Steam passes "plasma" / "plasma-wayland" / "desktop" here; anything
      # we don't recognise falls through to the usage error.
      mode="''${1:-desktop}"
      ${lib.optionalString cfg.bigscreen.enable ''
        # With the Bigscreen arm built, "leave Gaming Mode" should land on the
        # TV shell rather than a mouse-and-keyboard Plasma desktop — Steam's
        # own "Switch to Desktop" button is the only in-UI exit from Big
        # Picture, and on a couch machine the thing you want on the other side
        # of it is Bigscreen.  Plain Plasma is still reachable deliberately,
        # via `clanarchy-session-select plasma`.
        case "$mode" in
          plasma|plasma-wayland|plasma-x11|desktop) mode=bigscreen ;;
        esac
      ''}
      exec clanarchy-session-select "$mode"
    '';
  };

  # Artwork for the media client's Steam entry.
  #
  # Both are rasterised from the app's own scalable icon: Steam's image
  # loader handles PNG/JPG/TGA but not SVG, so pointing the shortcut at
  # `hicolor/scalable` directly yields an entry with no icon at all.
  #
  # The 600×900 tile is the one that matters — it is what Big Picture shows
  # in the library grid, and Steam's fallback for a shortcut without one is a
  # grey rectangle with the name printed on it.
  #
  # The background is deliberately dark rather than the app's own brand
  # colours: Jellyfin's mark *is* a purple-to-blue gradient, so putting it on
  # that same gradient renders the logo all but invisible (tried, looked like
  # a broken image). Dark backing makes it pop, and Steam does not draw the
  # name over portrait art, so the label is baked in.
  mediaArtwork =
    let
      src = cfg.mediaClient.artwork;
      label = lib.escapeShellArg cfg.mediaClient.name;
    in
    {
      icon = pkgs.runCommand "media-client-icon.png" {
        nativeBuildInputs = [ pkgs.librsvg ];
      } "rsvg-convert -w 256 -h 256 ${src} -o $out";

      cover = pkgs.runCommand "media-client-cover.png" {
        nativeBuildInputs = [ pkgs.librsvg pkgs.imagemagick ];
      } ''
        rsvg-convert -w 380 -h 380 ${src} -o logo.png
        magick -size 600x900 gradient:'#241a33-#0c0c12' \
          logo.png -gravity center -geometry +0-70 -composite \
          -font ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf \
          -pointsize 64 -fill '#f2f2f7' -gravity center -annotate +0+220 ${label} \
          png:$out
      '';
    };

  # The client as Big Picture launches it: scaled for the couch.
  #
  # A wrapper rather than launch options on the Steam entry, because Steam
  # stores those in the same binary blob as everything else and a
  # `VAR=x %command%` prefix is Steam-version-dependent shell handling we
  # would rather not depend on. A wrapper is just a program, and it works
  # identically if someone runs it from a terminal to debug.
  #
  # Referenced through /run/current-system/sw/bin for the same reason
  # mediaClient.exe is: the Steam app id is derived from the exe string, so a
  # store path that moves each rebuild would orphan the library entry.
  mediaClientTvLauncher = pkgs.writeShellApplication {
    name = "clanarchy-media-client-tv";
    text = ''
      export QT_SCALE_FACTOR=${cfg.mediaClient.scaleFactor}
      exec ${cfg.mediaClient.exe} "$@"
    '';
  };

  # Whatever the Steam entry should actually run — the wrapper when a scale
  # factor is configured, the client itself when it is not.
  mediaClientShortcutExe =
    if cfg.mediaClient.scaleFactor == null then
      cfg.mediaClient.exe
    else
      "/run/current-system/sw/bin/clanarchy-media-client-tv";

  # Desktop-mode launcher for the trip back, so returning to Gaming Mode
  # doesn't require a terminal.
  returnLauncher = pkgs.makeDesktopItem {
    name = "clanarchy-return-to-gaming";
    desktopName = "Return to Gaming Mode";
    comment = "Restart into the Steam Big Picture session";
    icon = "steam";
    exec = "${sessionSelect}/bin/clanarchy-session-select gamescope";
    categories = [ "Game" ];
  };
in
{
  imports = [
    ../desktop/kde.nix
    ../desktop/bigscreen.nix
    ../gaming-common.nix
  ];

  options.clanarchy.roles.htpc = {
    enable = lib.mkEnableOption "HTPC role (Steam Big Picture + Plasma with runtime session switching)";

    user = lib.mkOption {
      type = lib.types.str;
      description = ''
        The couch user. Owns the session state directory and is the one
        permitted to restart the display manager, so it must be a real
        declared NixOS user.
      '';
      example = "htpc";
    };

    defaultSession = lib.mkOption {
      type = lib.types.enum [ "gamescope" "plasma" "kodi" "bigscreen" ];
      default = "gamescope";
      description = ''
        Which session to land in when no choice has been made yet — i.e.
        first boot, and after `/persist` is reset. Deck-like behaviour is
        `gamescope`; `kodi` for a machine that is mostly for watching things;
        `plasma` if it should feel like a desktop that happens to game.

        `kodi` requires `mediaClient.enable`, `bigscreen` requires
        `bigscreen.enable`.
      '';
    };

    display.gpuPciAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "0000:03:00.0";
      description = ''
        PCI address of the GPU the TV hangs off.

        When set, the session waits for a connected connector on that card
        before starting a compositor, instead of starting one against a card
        with no output — which gamescope answers with a failed backend and a
        segfault, and which then drops the machine to a login screen it will
        never leave on its own.

        Find it with `lspci -D | grep VGA`, and confirm which card actually
        drives the TV with:

        ```
        for c in /sys/class/drm/card*-*/; do
          printf '%s %s\n' "$(basename "$c")" "$(cat "$c/status")"
        done
        ```

        Deliberately a PCI address and not a `cardN` name: numbering is not
        stable across kernel bumps, and on a two-GPU box a flip would point
        this at the wrong head.

        Leave null on a machine with a single GPU and a permanently attached
        display; the wait is then skipped entirely.
      '';
    };

    display.hdr.enable = lib.mkEnableOption ''
      HDR output in the gamescope session, via gamescope's `--hdr-enabled`.

      Off by default because it depends entirely on the panel: gamescope
      drives the display in an HDR colourspace and tone-maps SDR content up
      into it, which on a set that handles HDR badly looks worse than plain
      SDR, not better.

      It is not only for games. Without it the session is SDR, so HDR video
      played by the media client is delivered to an SDR output and comes out
      washed out — which is the usual reason a client is left force-
      transcoding HDR to SDR on the server instead of direct-playing it.
      Turning this on is what makes turning that off worthwhile
    '';

    bigscreen = {
      enable = lib.mkEnableOption ''
        the Plasma Bigscreen mode, run from an nspawn container carrying its
        own nixpkgs channel.

        Off by default because it is a heavier proposition than the other two
        arms: it builds a second, complete Plasma generation from
        nixpkgs-unstable (see modules/desktop/bigscreen.nix for why it cannot
        share the host's), and it takes exclusive KMS ownership of the TV's
        GPU while active
      '';

      gpu.pciAddress = lib.mkOption {
        type = lib.types.str;
        description = ''
          PCI address of the GPU driving the TV — passed straight through to
          `clanarchy.desktop.bigscreen.gpu.pciAddress`, which documents how
          to find it.
        '';
        example = "0000:03:00.0";
      };

      uid = lib.mkOption {
        type = lib.types.int;
        description = ''
          Numeric uid of the couch user. Must match the host's, since nspawn
          does not remap ids across the bind-mounted home.
        '';
        example = 1001;
      };

      gid = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Numeric primary gid of the couch user. Same matching requirement as `uid`.";
      };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = ''
          Applications to install inside the container. Must come from
          `pkgs-unstable`, not the host's `pkgs` — see the corresponding
          option in modules/desktop/bigscreen.nix.
        '';
        example = lib.literalExpression "[ pkgs-unstable.jellyfin-media-player ]";
      };
    };

    mediaClient = {
      enable =
        lib.mkEnableOption "a couch media client alongside the gaming session"
        // { default = true; };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.kodi-gbm.withPackages (p: [ p.jellyfin ]);
        defaultText = lib.literalExpression "pkgs.kodi-gbm.withPackages (p: [ p.jellyfin ])";
        description = ''
          Media client to install. Kodi with the Jellyfin add-on, talking to
          the Jellyfin server ernst already runs in an nspawn container.

          ── Why not Jellyfin Media Player ────────────────────────────────
          It was the obvious choice and it does not work here. JMP is a Qt
          shell that is supposed to play through mpv, advertising mpv's codec
          support to the server. The nixpkgs build ships no web client (975 KB
          total, no JS at all), so it loads jellyfin-web from the server — and
          the mpv player plugin never registers into that page. Measured on
          ernst 2026-09-04: the client's own log shows jellyfin-web loading
          `htmlVideoPlayer` and no JMP player, and the playback URL carries

            VideoCodec=av1,h264,vp9   AudioCodec=aac,opus,flac
            TranscodeReasons=ContainerNotSupported,VideoCodecNotSupported,
                             AudioCodecNotSupported

          i.e. QtWebEngine's HTML5 <video> capabilities, not mpv's. So every
          HEVC file is transcoded to H.264 and every Dolby track flattened to
          stereo AAC, no matter what JMP's own audio and video settings say —
          those settings feed the mpv path, which is not the one running. On
          this hardware that meant a 4K Dolby Vision tone-map on the iGPU at
          0.87x realtime: a film that could not finish.

          Kodi decodes in-process. It direct-plays HEVC and Dolby Vision and
          bitstreams AC3/E-AC3/TrueHD to the receiver, so the server does no
          work at all.

          ── Why not Plasma Bigscreen ─────────────────────────────────────
          Not packaged in 26.05 — the top-level attribute is a throwing alias
          pointing at `kdePackages.plasma-bigscreen`, which does not exist.

          `kodi-wayland` rather than plain `kodi`: the session it launches
          into is gamescope, which is a Wayland compositor.
        '';
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "Kodi";
        description = "Name the client appears under in the Steam library.";
      };

      persistenceDirectories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ".kodi" ];
        description = ''
          Home-relative directories the client keeps its state in, added to
          the couch user's impermanence set.

          Not optional in practice. Home is rolled back on every boot here,
          and Kodi keeps everything — the Jellyfin add-on, the server it is
          paired with, the login, the library cache, every setting — under
          `~/.kodi`. Without this the client comes up as a fresh install after
          each reboot and someone has to re-add the server from the sofa.
        '';
      };

      exe = lib.mkOption {
        type = lib.types.str;
        default = "/run/current-system/sw/bin/kodi-standalone";
        description = ''
          Binary the Steam shortcut launches. Deliberately a
          `/run/current-system/sw/bin` path and not a store path: Steam
          derives a non-Steam shortcut's app id from the exe string, so a
          path that changes on every rebuild would make Steam treat the entry
          as a brand-new game each time — new id, artwork gone, controller
          layout gone.

          `kodi-wayland` still installs its binary as plain `kodi`; there is
          no separate `kodi-wayland` executable.
        '';
      };

      arguments = lib.mkOption {
        type = lib.types.str;
        default = "--windowing=gbm";
        description = ''
          Launch options. `--windowing=gbm` is what Kodi's own
          `kodi-gbm.desktop` session entry uses, and it is the whole point of
          running the client as a session: in GBM mode Kodi talks to KMS
          directly, with no compositor in the way.

          That buys two things it cannot have as a window inside gamescope.
          It can change the display mode, so a 23.976p film plays at 23.976
          Hz instead of juddering against a 60 Hz output — on a TV that is
          the single biggest picture-quality difference available here. And
          it drives HDR itself rather than through gamescope's tone-mapping.

          The catch is that GBM mode has no device selection at all, which on
          a two-GPU box sends Kodi to the wrong card. That is solved by the
          udev rules under `services.udev.extraRules` below — read those
          before changing anything here, because this option only works at
          all because of them.
        '';
      };

      artwork = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = "${cfg.mediaClient.package}/share/icons/hicolor/scalable/apps/kodi.svg";
        defaultText = lib.literalExpression ''"''${package}/share/icons/hicolor/scalable/apps/kodi.svg"'';
        description = ''
          Source SVG the library icon and grid tile are rendered from. Steam's
          image loader does not read SVG, so both are rasterised at build
          time; the tile is the app logo centred on a dark backing, because
          the alternative Steam draws for art-less shortcuts is a grey box
          with the name in it.

          Set to null to install the shortcut with no artwork — necessary if
          `package` is swapped for a client that does not ship that path.
        '';
      };

      scaleFactor = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Qt scale factor applied when the client is launched from the gaming
          session, via `QT_SCALE_FACTOR`.

          Null for Kodi, which is not a Qt application and scales its own
          10-foot skin to whatever resolution it is given — the problem below
          simply does not arise. It is kept because it is real for any Qt or
          Electron client someone swaps in.

          Needed because the two sessions handle a 4K TV completely
          differently. Plasma scales the output (ernst's TV output is at
          scale 2), so the client looks right there with no help. The
          gamescope session runs raw native resolution — nixpkgs starts it as
          `gamescope --steam -- steam -tenfoot`, with no `-W`/`-H` — and
          Steam's own Deck UI compensates internally. A Qt/QtWebEngine app
          dropped into that gets no such treatment and renders at true 3840
          pixels wide, which from a sofa is unreadable.

          So this is deliberately *not* set on the desktop entry, only on the
          Steam shortcut: setting it globally would double-scale the client
          in Plasma, which already scales it once.

          Set to null to launch the client unwrapped, e.g. on a 1080p TV where
          neither session needs the help.
        '';
      };

      steamShortcut.enable = lib.mkEnableOption ''
        a Steam library entry for the media client, so it is launchable from
        inside Big Picture.

        Off by default, because the client is its own session arm — reached
        with `clanarchy-session-select kodi` rather than from Steam's
        library. The two are close to mutually exclusive in practice: a GBM
        build talks to KMS directly and is not a Wayland client, so it cannot
        run as a window inside gamescope at all. Enabling this alongside the
        default `package` would produce a library entry that fails to start.

        Worth turning on only with a `package` and `exe` swapped for a
        windowed build — and then think twice, because two ways to launch the
        same client with different picture quality is a trap for whoever else
        uses the TV
      '';
    };

    controller.enable =
      lib.mkEnableOption ''
        wireless Xbox controller support — Bluetooth plus the xpadneo driver.

        Wired controllers already work without this: xpad is in-tree and
        `hardware.steam-hardware.enable` (which programs.steam brings in)
        ships the udev rules. This is for Xbox One S / Series pads over
        Bluetooth, which the in-tree driver handles poorly — xpadneo is what
        gives correct button mapping, rumble and battery reporting.

        Worth a deliberate look on a machine that is also a NAS: it puts a
        Bluetooth stack on the box, which is attack surface that was not
        there before. The radio is host hardware and the driver is a kernel
        module, so neither can live in a container — only the *use* of the
        controller does, via /dev/input

        This is the software half only, and it cannot conjure a working
        radio. ernst's onboard MediaTek MT7927 has no Bluetooth support on
        the current kernel and no firmware blob published, so a USB dongle
        (or a cable) is what actually carries a pad there — see
        docs/guides/htpc-controllers.md
      ''
      // {
        default = true;
      };

    autologin.enable = lib.mkEnableOption ''
      passwordless autologin for the couch user.

      Off by default, and worth a deliberate decision: on a machine that
      also serves a NAS, autologin means anyone with physical access lands
      in a logged-in session with that user's rights. Enable it for the
      living-room-appliance feel; leave it off to keep a login prompt in
      front of the array
    '';

    screenLocker.enable = lib.mkEnableOption ''
      Plasma's screen locker in the desktop arm.

      Off by default, because on a TV it locks you out rather than securing
      anything. Plasma autolocks after five idle minutes and then demands the
      couch user's password — which on this fleet is a clan var nobody has
      memorised, typed on whatever input device happens to be in the room.
      Meanwhile it guards nothing: with `autologin.enable` the machine already
      hands that session to anyone who walks up and presses power, so the
      locker only ever stands between the sofa and a session it will give away
      on the next reboot anyway.

      Turn it on for a couch machine that is somewhere semi-public *and* has
      autologin off, where the lock is a real boundary rather than a puzzle
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.defaultSession == "bigscreen" -> cfg.bigscreen.enable;
        message = ''
          clanarchy.roles.htpc.defaultSession = "bigscreen" requires
          clanarchy.roles.htpc.bigscreen.enable = true — otherwise the
          container the boot dispatcher would start does not exist.
        '';
      }
      {
        assertion = cfg.defaultSession == "kodi" -> cfg.mediaClient.enable;
        message = ''
          clanarchy.roles.htpc.defaultSession = "kodi" requires
          clanarchy.roles.htpc.mediaClient.enable = true — otherwise the
          machine boots into a session arm whose binary is not installed.
        '';
      }
    ];

    # KDE Plasma 6 + SDDM + pipewire + fonts. The role owns the decision;
    # the desktop module owns the implementation.
    clanarchy.desktop.kde.enable = true;

    # Bigscreen mode. The role holds the couch-user identity; the desktop
    # module owns the container and the GPU plumbing.
    clanarchy.desktop.bigscreen = lib.mkIf cfg.bigscreen.enable {
      enable = true;
      user = cfg.user;
      inherit (cfg.bigscreen)
        uid
        gid
        extraPackages
        ;
      gpu.pciAddress = cfg.bigscreen.gpu.pciAddress;
    };

    # Hand the couch session exactly one GPU: the TV's.
    #
    # Kodi's GBM backend has no device selection. It opens DRM cards in
    # enumeration order and keeps the first with a *connected* connector —
    # `KODI_GBM_DEVICE` does not exist in Kodi 21 (set it and the binary never
    # reads it), and `videoscreen.monitor` is consulted only after a card has
    # already been opened. On a two-GPU box that means it takes whichever card
    # the kernel happened to probe first. On ernst that is the iGPU, whose
    # HDMI-A-2 is permanently connected to the Comet KVM, so Kodi rendered a
    # 2560x1440 picture into the KVM while the TV stayed black.
    #
    # Since the mechanism cannot be told which card to use, it is told which
    # cards it may open. Deny every DRM card node to the session user, then
    # re-allow the one the TV hangs off — so Kodi's open() fails on everything
    # else and its loop walks on to the right card by itself. Written as
    # deny-then-allow rather than naming the iGPU, so a third GPU appearing
    # later is excluded by default instead of silently becoming a candidate.
    #
    # Both halves are needed, because the couch user reaches a card two ways:
    #   TAG-="uaccess"   stops systemd-logind granting a per-session ACL
    #   GROUP="root"     stops the `video` group membership granting it
    # Removing only one leaves access intact — verified on ernst 2026-09-04,
    # where dropping uaccess alone still left `user:go:rw-` on the node.
    #
    # Scoped to `card[0-9]*`, the KMS nodes. Render nodes (`renderD*`) are
    # deliberately untouched: that is how the Jellyfin container reaches the
    # iGPU for VAAPI (machines/ernst/containers/jellyfin.nix) and how ROCm
    # reaches the dGPU. This restricts who may *drive a display*, not who may
    # compute.
    services.udev.extraRules = lib.mkIf (cfg.display.gpuPciAddress != null) ''
      SUBSYSTEM=="drm", KERNEL=="card[0-9]*", TAG-="uaccess", GROUP="root", MODE="0660"
      SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ENV{ID_PATH}=="pci-${cfg.display.gpuPciAddress}", TAG+="uaccess", GROUP="video", MODE="0660"
    '';

    # Make the TV's HDMI audio the default sink — see tvAudioNodeMatch above.
    #
    # A priority bump rather than a hardcoded default: WirePlumber picks the
    # highest-priority *available* sink, so if the TV is off at login and its
    # sink is absent, this degrades to the iGPU rather than to silence, and
    # snaps back when the TV returns. Naming one node as "the" default cannot
    # do that.
    #
    # It also stays out of the user's way. An explicit choice in System
    # Settings is stored in ~/.local/state/wireplumber (persisted for the
    # couch user) and still wins over priority — this only decides what
    # happens when nobody has chosen, which includes every fresh install.
    services.pipewire.wireplumber.extraConfig."51-htpc-tv-audio" =
      lib.mkIf (cfg.display.gpuPciAddress != null) {
        "monitor.alsa.rules" = [
          {
            matches = [ { "node.name" = tvAudioNodeMatch; } ];
            actions.update-props = {
              "priority.session" = 2000;
              "priority.driver" = 2000;
            };
          }
        ];
      };

    # Kill Plasma's screen locker on the TV.
    #
    # Written to /etc/xdg rather than the couch user's ~/.config for two
    # reasons: it needs no per-user plumbing (there is no home-manager for the
    # couch account), and /etc/xdg is on `XDG_CONFIG_DIRS` in the Plasma
    # session, so KConfig picks it up as a system default. Home is rolled back
    # on every boot here, which a user-level file would have to survive.
    #
    # `[$i]` is KDE's kiosk immutability marker. It does more than set a
    # default: it makes the group unwritable from user config, so the System
    # Settings toggle is greyed out instead of silently re-enabling a lockout
    # that then persists in /persist. LockOnResume matters as much as Autolock
    # on a TV — the panel dropping DPMS and coming back is a "resume", so
    # without it the lock returns the first time someone turns the telly off
    # and on again.
    environment.etc."xdg/kscreenlockerrc" = lib.mkIf (!cfg.screenLocker.enable) {
      text = ''
        [Daemon][$i]
        Autolock=false
        LockOnResume=false
      '';
    };

    # Wireless controller support.
    #
    # xpadneo is a kernel module and the radio is host hardware, so both are
    # necessarily host-side even though the session that consumes the pad may
    # be containerised: a container shares the host kernel and cannot load a
    # driver of its own. What crosses the boundary is the resulting evdev
    # node — /dev/input is already bound into the Bigscreen container, so a
    # controller paired here shows up there with no further plumbing.
    hardware.bluetooth = lib.mkIf cfg.controller.enable {
      enable = true;
      # A TV appliance should not need someone to run `bluetoothctl power on`
      # after every reboot before the pad works.
      powerOnBoot = true;
    };

    hardware.xpadneo.enable = lib.mkIf cfg.controller.enable true;

    # Steam + Proton-GE.  `persistenceDirectories` keeps its default
    # ([ ".steam" ]): HTPC machines are impermanent like the rest of the
    # fleet — home is rolled back on boot — so the Steam runtime bootstrap
    # genuinely does need declaring.  The remaining per-user paths
    # (.config, .local/share, .local/state, .cache) are declared by the
    # machine's user module, which is also where the library symlink lives.
    clanarchy.gaming = {
      enable = true;
      user = cfg.user;

      # Put the media client in the Steam library. Steam keeps non-Steam
      # shortcuts in a binary blob under a directory named after the account's
      # steamid — unknowable at build time — so this is a runtime merge rather
      # than a file we can write; modules/gaming-shortcuts.nix has the detail.
      shortcuts = lib.optional (cfg.mediaClient.enable && cfg.mediaClient.steamShortcut.enable) {
        inherit (cfg.mediaClient) name arguments;
        exe = mediaClientShortcutExe;
        tags = [ "Media" ];
        icon = if cfg.mediaClient.artwork == null then null else mediaArtwork.icon;
        coverArt = if cfg.mediaClient.artwork == null then null else mediaArtwork.cover;
      };
    };

    # The stock gamescope Steam session from nixpkgs — no Jovian.
    programs.steam.gamescopeSession.enable = true;

    # nixpkgs builds the launcher as
    #   gamescope --steam ${args} -- steam ${steamArgs}
    # so this lands before the `--`, i.e. as a gamescope flag rather than a
    # Steam one. See programs/steam.nix in nixpkgs.
    programs.steam.gamescopeSession.args = lib.mkIf cfg.display.hdr.enable [ "--hdr-enabled" ];

    # Steam and Proton are unfree.  birte gets this from the pkgs instance
    # built in lib/mk-machine.nix (`allowUnfree = true` baked in), but HTPC
    # machines run on the stable channel where nothing sets it.
    #
    # A predicate rather than a blanket `allowUnfree`: this role is expected
    # to land on otherwise-headless boxes (ernst fronts the NAS array), and
    # "we needed Steam" shouldn't quietly open the whole machine to unfree
    # packages.  Extend the list when a genuinely required package is
    # rejected, rather than widening to allowUnfree.
    #
    # NOTE: `nixpkgs.config` cannot be set on machines using
    # `clanarchy.channel = "unstable"` (an externally-created pkgs instance
    # trips a NixOS assertion), so this role and that option are mutually
    # exclusive by construction.
    nixpkgs.config.allowUnfreePredicate =
      pkg:
      builtins.elem (lib.getName pkg) [
        "steam"
        "steam-unwrapped"
        "steam-original"
        "steam-run"
        "steam-jupiter-unwrapped"
        "proton-ge-bin"
      ];

    # Point the display manager at the wrapper session rather than at
    # "steam" or "plasma" directly; the wrapper decides at launch.
    services.displayManager.sessionPackages = [ sessionFile ];
    services.displayManager.defaultSession = "clanarchy-htpc";

    services.displayManager.autoLogin = lib.mkIf cfg.autologin.enable {
      enable = true;
      user = cfg.user;
    };

    # Autologin again when a session ends, rather than once per display-manager
    # start.
    #
    # SDDM's default (Relogin=false) is right for a desktop: log out, get the
    # greeter. On an appliance it is a one-way door — any session exit, whether
    # a crash or Steam's own "Exit" item, parks the TV on a login form that
    # nobody in the living room has a keyboard for, and it stays there until
    # someone SSHes in and restarts the display manager. That is exactly what
    # ernst was found doing on 2026-08-19: autologin had worked, the session
    # died against a dark TV, and the greeter sat on tty1 for hours.
    #
    # Paired with waitForDisplay above, which is what keeps this from becoming
    # a hot crash-relogin loop while the TV is off — the session blocks instead
    # of exiting, so there is nothing to relogin.
    services.displayManager.sddm.autoLogin.relogin = lib.mkIf cfg.autologin.enable true;

    # The media client is installed system-wide (not just into the session)
    # so it shows up in Plasma's launcher too, and so `mediaClient.exe` can
    # be a stable /run/current-system/sw/bin path rather than a store path
    # that moves on every rebuild.
    #
    # Getting it into *Big Picture* is a separate job — see the shortcuts
    # wiring under clanarchy.gaming above.  This used to be a documented
    # manual step (Library → Add a Non-Steam Game, once, by hand); it is now
    # declared, which also means it comes back on its own after an
    # impermanence rollback wipes the Steam config.
    environment.systemPackages = [
      sessionSelect
      steamosShim
      returnLauncher
    ]
    ++ lib.optional cfg.mediaClient.enable cfg.mediaClient.package
    ++ lib.optional (cfg.mediaClient.enable && cfg.mediaClient.scaleFactor != null) mediaClientTvLauncher;

    # Owned by the couch user so switching needs no privilege escalation.
    #
    # The *file* is declared too, not just the directory, and that is the whole
    # point of the second rule. The switcher is a shell redirect into an
    # existing path, so whoever creates the file first owns it — and running
    # `clanarchy-session-select` once as root over SSH (the obvious thing to do
    # when the TV is unreachable) leaves behind a root-owned `current` that the
    # couch user can no longer write. The symptom is bad: every later switch
    # from the sofa dies with "Permission denied" before it reaches the
    # display-manager restart, so the Return to Gaming Mode launcher silently
    # does nothing at all. Hit on ernst 2026-09-04, by exactly that route.
    #
    # `f` seeds it with the configured default when absent; `z` re-asserts
    # ownership on every boot, which is what actually repairs the root-owned
    # case rather than merely avoiding it.
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 ${cfg.user} ${config.users.users.${cfg.user}.group} -"
      "f ${stateFile} 0644 ${cfg.user} ${config.users.users.${cfg.user}.group} - ${cfg.defaultSession}"
      "z ${stateFile} 0644 ${cfg.user} ${config.users.users.${cfg.user}.group} -"
    ];

    # The media client's own state. Home is rolled back on every boot, and
    # Kodi keeps the Jellyfin add-on, the paired server, the login and every
    # setting under ~/.kodi — so without this the client is a fresh install
    # after each reboot and someone re-adds the server from the sofa.
    environment.persistence."/persist".users.${cfg.user} =
      lib.mkIf (cfg.mediaClient.enable && cfg.mediaClient.persistenceDirectories != [ ]) {
        directories = cfg.mediaClient.persistenceDirectories;
      };

    # Survive impermanence rollback, so the machine comes back up in the
    # session it was left in.
    environment.persistence."/persist".directories = [
      stateDir
    ]
    # Controller pairings. This machine rolls its root back on every boot, so
    # without persisting them the pad would have to be re-paired after each
    # reboot — exactly the papercut impermanence is meant to make you notice
    # once and then fix for good.
    ++ lib.optional cfg.controller.enable "/var/lib/bluetooth";

    # Boot dispatcher.
    #
    # The other two arms are display-manager sessions, so graphical.target
    # brings them up on its own.  Bigscreen is a container that must instead
    # replace the display manager, and `services.displayManager.defaultSession`
    # is a build-time value that cannot express "no DM at all today".  So the
    # choice is re-applied once at boot from the same state file the switcher
    # writes, which also makes the machine come back up in the mode it was
    # left in after a reboot.
    systemd.services.clanarchy-htpc-boot = lib.mkIf cfg.bigscreen.enable {
      description = "Apply the persisted HTPC session choice at boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-user-sessions.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.systemd pkgs.coreutils ];
      # Only has to handle the container half now.  The display manager takes
      # care of itself: its start condition tests the same flag file, so in
      # bigscreen mode it is skipped rather than started-and-stopped, and this
      # no longer has to race it.
      script = ''
        mode="$(cat ${stateFile} 2>/dev/null || echo ${cfg.defaultSession})"

        # Reconcile the flag with the recorded mode, so a hand-edited state
        # file or a first boot with defaultSession = "bigscreen" still lines up.
        if [ "$mode" = bigscreen ]; then
          touch ${flagFile}
          systemctl start ${bigscreenUnit}
        else
          rm -f ${flagFile}
          systemctl stop ${bigscreenUnit} || true
        fi
      '';
    };

    # The display manager must not run while Bigscreen owns the GPU.
    #
    # A failed condition is not a failed unit: systemd records
    # "Condition check resulted in ... being skipped" and moves on, so
    # graphical.target still completes and nothing shows up in
    # `systemctl --failed`.
    systemd.services.display-manager.unitConfig =
      lib.mkIf cfg.bigscreen.enable { ConditionPathExists = "!${flagFile}"; };

    # Host-side listener for session-change requests from inside the container.
    #
    # A path unit rather than a socket: the payload is one short word, the
    # writer is an unprivileged desktop launcher with no networking, and a
    # file on a directory both sides already share needs no new plumbing.
    systemd.paths.clanarchy-session-request = lib.mkIf cfg.bigscreen.enable {
      description = "Watch for session-change requests from the Bigscreen container";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = requestFile;
        # The request file lives in a directory the couch user owns, so it may
        # legitimately not exist yet at boot.
        MakeDirectory = false;
      };
    };

    systemd.services.clanarchy-session-request = lib.mkIf cfg.bigscreen.enable {
      description = "Apply a session-change request from the Bigscreen container";
      path = [ pkgs.coreutils ];
      serviceConfig.Type = "oneshot";
      # Runs as root, so no polkit hop — but it only ever passes the request
      # through the same switcher the couch user could have called directly,
      # which rejects anything outside the known session names. The container
      # gains no capability it did not already have from a host login; it just
      # gains a way to ask from where it actually is.
      script = ''
        req="$(cat ${requestFile} 2>/dev/null || true)"
        : > ${requestFile} || true

        [ -n "$req" ] || exit 0
        exec ${sessionSelect}/bin/clanarchy-session-select "$req"
      '';
    };

    # Let the couch user manage *only* the display manager and, when the
    # bigscreen arm is built, its container. Narrower than adding them to
    # wheel or handing out a blanket systemd sudo rule.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        var allowed = ${builtins.toJSON manageableUnits};
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            allowed.indexOf(action.lookup("unit")) !== -1 &&
            subject.user == "${cfg.user}") {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
