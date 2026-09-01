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
    # systemPackages rather than a user's home.packages, and the reason is
    # Steam: "Add a Non-Steam Game" scans .desktop files and resolves the
    # entry's `Exec` to an absolute path, which it then stores verbatim in
    # shortcuts.vdf.  Eden's upstream desktop entry uses a bare `Exec=eden
    # %f`, so what Steam records is whatever PATH resolves to — and from
    # systemPackages that is /run/current-system/sw/bin/eden, a path that
    # stays valid across rebuilds.  A store path would have been baked in
    # and broken at the next GC.
    environment.systemPackages = [ pkgs.eden ];
  };
}
