{ config, lib, pkgs, ... }:
let cfg = config.clanarchy.apps.emulation;
in {
  options.clanarchy.apps.emulation = {
    # Switch emulation is deliberately its own switch rather than part of a
    # blanket "emulation" flag, because on birte it fills a specific hole:
    # RetroDECK removed Switch support permanently in February 2026 (DMCA
    # exposure the volunteer project chose not to carry), and its own
    # announcement tells users to run a Switch emulator themselves alongside
    # it.  Everything from the Switch-1 era backwards is RetroDECK's job;
    # this is the one console it no longer covers.
    switch.enable = lib.mkEnableOption "Nintendo Switch emulation (Eden)";
  };

  config = lib.mkIf cfg.switch.enable {
    # systemPackages rather than a user's home.packages, because a non-Steam
    # shortcut has to keep working across rebuilds.
    #
    # ── CORRECTION.  An earlier revision of this comment claimed Steam
    # RESOLVES a desktop entry's `Exec` to an absolute path and stores that.
    # It does not.  Read out of birte's own shortcuts.vdf on 2026-09-01:
    #
    #   Chromium       Exe = "chromium"                     ← bare, verbatim
    #   Eden           Exe = "eden"                          ← bare, verbatim
    #   Google Chrome  Exe = "/nix/store/awfz…-google-chrome-151…/bin/…"
    #
    # Steam stores the `Exec` field LITERALLY.  Eden's upstream entry is a
    # bare `Exec=eden %f`, so the shortcut is a bare name resolved through
    # PATH at launch time — which works only because
    # /run/current-system/sw/bin is on the gamescope session's PATH, i.e.
    # because the package is in systemPackages.  So the conclusion below
    # stands; the reasoning that was written for it did not.
    #
    # google-chrome shows the other half: its entry carries an ABSOLUTE
    # Exec, so Steam baked a /nix/store path into shortcuts.vdf, and that
    # shortcut will break at the next chrome update plus GC.  Nothing here
    # can prevent that — it is a property of that package's desktop entry —
    # so re-adding it by browsing to /run/current-system/sw/bin is the
    # workaround, and docs/guides/birte-emulation.md records it.
    environment.systemPackages = [ pkgs.eden ];
  };
}
