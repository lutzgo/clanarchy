# `go` — the couch user on ernst.
#
# ernst is primarily a headless NAS / VM host / GPU compute box; the HTPC
# stack is a second role layered on top (see roles.htpc in clan.nix and
# modules/roles/htpc.nix).  This file declares the user that role drives,
# the same way machines/birte/deck.nix declares `deck` for Jovian.
#
# Deliberately NOT in `wheel`: this account exists to sit in front of a TV.
# `roles/server.nix` sets `security.sudo.execWheelOnly`, so keeping `go` out
# of wheel means the living-room session cannot sudo even though the machine
# it runs on fronts the storage array.  The switcher doesn't need it — the
# session state dir is user-owned and the display-manager restart is granted
# by a narrow polkit rule in the role module.
{ config, pkgs, ... }:
{
  users.users.go = {
    isNormalUser = true;
    home = "/home/go";
    shell = pkgs.bashInteractive;
    # video/audio/input for the session; gamemode for gamescope's scheduling
    # hints.  No wheel, no networkmanager (ernst is networkd + wired).
    extraGroups = [ "video" "audio" "input" "gamemode" ];
    hashedPasswordFile =
      config.clan.core.vars.generators.go-password.files."hashed-password".path;
  };

  clan.core.vars.generators.go-password = {
    files."hashed-password" = {
      secret = true;
      neededFor = "users";
    };
    prompts."password" = {
      description = "Password for the go user (local login on the TV)";
      type = "hidden";
    };
    # Pipe via stdin so a leading '-' in the password isn't parsed as a flag.
    script = ''
      ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 -s < "$prompts/password" > "$out/hashed-password"
    '';
    runtimeInputs = [ pkgs.mkpasswd ];
  };

  # ernst rolls back BOTH zroot/root and zroot/home to @blank on every boot
  # (modules/zfs-impermanence.nix), so /home/go is wiped each time and only
  # what is declared here survives.  This is the fleet's normal posture and
  # is kept deliberately: the couch account's state stays auditable instead
  # of accumulating whatever Steam and Plasma happen to drop in $HOME.
  #
  # Everything Gaming Mode needs to not re-onboard on every reboot:
  environment.persistence."/persist".users.go = {
    directories = [
      ".config"      # Plasma / KDE config, gamescope + Steam client settings
      ".local/share" # Steam client data (the library itself is symlinked out, below)
      ".local/state" # systemd user state
      # ".steam" is contributed by modules/gaming-common.nix via
      # clanarchy.gaming.persistenceDirectories — not repeated here.
      ".cache"       # shader caches — re-derivable, but recompiling them on
                     # every boot is exactly the stutter this box exists to avoid
    ];
  };

  # ── THE LIVING-ROOM AUDIO CHAIN, and the settings it forces ──────────────
  #
  # Declared here rather than in modules/roles/htpc.nix because every value
  # below is a fact about ONE set of cables. The role owns the mechanism
  # (mediaClient.audioProfile, mediaClient.guiSettings); this owns the answer.
  #
  #   ernst dGPU HDMI ──> FeinTech AX211 audio extractor ──> LG TV  (HDMI 2.1,
  #                              │                                  4K120 path)
  #                              └──> Yamaha YSP-5600  (HDMI **IN 1**)
  #                                        └──> LG TV, second input
  #
  # THE EXTRACTOR'S DIP SWITCHES ARE AT 000 — "copy video EDID, synthesise
  # 7.1 DTS/Dolby/HD audio". That is load-bearing and not the factory
  # position. At 111 (copy/copy) the GPU is offered whatever the TV claims,
  # which is what the extractor exists to stop: the LG advertises no DTS at
  # all and only 2-channel LPCM. Before/after on the ELD, measured:
  #
  #   111  4 SADs: LPCM 2ch, AC-3 6ch, E-AC3 8ch, TrueHD 8ch, no DTS
  #   000  7 SADs: + LPCM 8ch, + DTS 8ch, + DTS-HD 8ch, all to 192 kHz
  #
  # THE SOUNDBAR MUST BE ON HDMI **IN 1**, and this is worth writing down
  # because getting it wrong costs an evening: the YSP's other HDMI socket is
  # OUT (ARC), and an output into an output negotiates nothing. The failure
  # looks like a dead extractor — its Amp LED never lights — and survives
  # every eARC and DIP permutation you try, because none of them are the
  # problem. IN 1 is also the HDCP 2.2 port.
  #
  # eARC IS OFF ON THE EXTRACTOR, deliberately. eARC reverses the direction of
  # the Amp output: instead of extracting audio from ernst, the box waits for
  # a return feed from the TV. Nothing here can supply that — the YSP-5600 is
  # a 2015 HDMI 2.0 device, ARC only — and switching it on silences
  # everything, since the TV also drops its own speakers. It is only worth
  # having if the TV's OWN apps need to reach the soundbar. They do not; the
  # source is ernst.
  #
  # DTS IS NOT BITSTREAMED even though the EDID offers it. Kodi's PipeWire
  # sink reports AC3/E-AC3/TrueHD only, so DTS decodes to 7.1 LPCM instead —
  # which the soundbar takes happily. Hence dtspassthrough stays off; turning
  # it on would claim a path that does not exist.
  clanarchy.roles.htpc.mediaClient = {
    # Without this the sink comes up stereo and Kodi reports "No passthrough
    # capabilities" — no Atmos, no bitstreaming, and no error to explain it.
    audioProfile = "output:hdmi-surround71-extra3";

    guiSettings =
      let
        # Exactly as Kodi stores it: the PipeWire node name, "|", the display
        # name. Both halves must match a device Kodi enumerated, and the
        # `-extra3`/"(HDMI 4)" tail is the connector the cable is in — so this
        # and audioProfile above change together or not at all.
        device =
          "PIPEWIRE:alsa_output.pci-0000_03_00.1.hdmi-surround71-extra3"
          + "|Navi 31 HDMI/DP Audio Digital Surround 7.1 (HDMI 4)";
      in
      {
        # WHICH CONNECTOR KODI DRAWS ON. Runtime state until 2026-09-15,
        # when it stopped being enough.
        #
        # Kodi in GBM mode picks a CARD before it reads this: CDRMUtils::
        # OpenDrm takes the first DRM device with any connected connector,
        # and only then does FindConnector look for this name WITHIN that
        # card — falling back to any connected connector there if the name
        # is absent. ernst has two cards with outputs on them (the iGPU and
        # the dGPU the TV hangs off), so "first device with something
        # plugged in" is not a decision, it is a coin flip.
        #
        # It landed wrong on 2026-09-15. Same hardware, no hotplug in seven
        # days of uptime, two consecutive runs of the same binary:
        #
        #   Sep 14  using connector: HDMI-A-1  'LG Electronics' 'LG TV SSCR2'
        #   Sep 15  using connector: HDMI-A-2  'PNP(GLI)'       'GLKVM'
        #
        # — a KVM capture dongle on the iGPU's HDMI port. Kodi was fine:
        # skin loaded, PVR started, widgets populated, rendering every frame
        # into a dongle nobody was watching. FROM THE SOFA THAT IS A HANG,
        # and it was diagnosed as one twice before the log was read. The
        # setting was ALREADY "HDMI-A-1" at the time and was powerless,
        # because the wrong card had been chosen before it was consulted.
        #
        # So this pin does not fix that, and must not be mistaken for the
        # fix: what fixes it is having only one card with an output on it,
        # or having both outputs on the SAME card, where this name then
        # decides correctly. The pin's job is narrower and still worth
        # having — Kodi rewrites guisettings.xml on exit, so a single
        # fallback to the wrong connector would persist the wrong value and
        # survive every rebuild after it.
        #
        # IF THE TV GOES DARK WHILE KODI IS CLEARLY ALIVE, read
        # ~/.kodi/temp/kodi.log for `FindConnector` and `[display-info]`
        # before touching anything else. Those two lines name the screen it
        # is actually drawing on, and they answer in one second a question
        # that otherwise looks like a hung session.
        "videoscreen.monitor" = "HDMI-A-1";

        "audiooutput.audiodevice" = device;
        "audiooutput.passthroughdevice" = device;

        # 10 = AE_CH_LAYOUT_7_1. The enum is Kodi's own, from
        # share/kodi/system/settings/settings.xml in the package — read there,
        # not guessed, because the numbering has no relation to channel count.
        "audiooutput.channels" = "10";

        # THE MASTER GATE. With this false the per-codec toggles below are
        # inert, which is a confusing way to have no Atmos while every setting
        # that appears to control Atmos reads "true".
        "audiooutput.passthrough" = "true";

        # Atmos rides inside Dolby Digital Plus on streaming sources, so E-AC3
        # is the switch that actually puts Atmos on the soundbar. TrueHD is
        # the rarer disc-era carrier and now works too — it needs 8-channel
        # HBR, which the stereo profile could not offer.
        "audiooutput.ac3passthrough" = "true";
        "audiooutput.eac3passthrough" = "true";
        "audiooutput.truehdpassthrough" = "true";

        # Backstop for sources whose codec cannot be bitstreamed: re-encode to
        # DD 5.1 rather than collapsing to stereo.
        "audiooutput.ac3transcode" = "true";
      };
  };

  # The library itself belongs on the bulk pool, not on zroot: zdata/games
  # already exists for exactly this (see machines/ernst/disko.nix, "future
  # Steam library"), and a mirrored 960 GB system pool is the wrong place for
  # hundreds of GB of games.
  #
  # `L+` forces the symlink each boot, so it is re-established after the
  # rollback regardless of what the persisted .local/share contains.
  systemd.tmpfiles.rules = [
    "d /srv/games/go 0700 go users - -"
    "L+ /home/go/.local/share/Steam - - - - /srv/games/go"
  ];
}
