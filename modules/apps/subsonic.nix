# Supersonic — a desktop client for the Navidrome/Subsonic API.
#
# Navidrome lives in containers/arr.nix on ernst and answers at
# navidrome.goclan.org.  That name is in `appApiHosts` (exempt from
# forward-auth, because the Subsonic protocol authenticates with a salted
# token in query parameters and cannot follow a 302 to a login portal) and in
# `wanExposed`, so this client works on the LAN and off it with no VPN.
# Credentials are the user's own Navidrome account — not an Authelia one.
#
# WHY SUPERSONIC AND NOT feishin/aonsoku.  All three are packaged and all
# three are maintained.  Supersonic is a native Go/Fyne binary; the other two
# are Electron and Tauri.  Both consumers here are constrained in a way that
# makes that the deciding factor rather than a preference: birte is a
# battery-powered handheld, and biene is a 1366x768 laptop.  A Chromium per
# music player is the wrong trade on either.
#
# THE PACKAGE NAME IS NOT THE SAME ON BOTH CHANNELS, which is why `package` is
# an option instead of being hardcoded.  See the comment on biene's override
# in machines/biene/configuration.nix.
{ config, lib, pkgs, ... }:
let cfg = config.clanarchy.apps.subsonic;
in {
  options.clanarchy.apps.subsonic = {
    enable = lib.mkEnableOption "Supersonic, a desktop Navidrome/Subsonic client";

    package = lib.mkOption {
      type        = lib.types.package;
      default     = pkgs.supersonic;
      defaultText = lib.literalExpression "pkgs.supersonic";
      description = ''
        Which Supersonic build to install.  The default is correct on
        nixpkgs-unstable, where Fyne's native Wayland support was folded into
        the main package and `supersonic-wayland` was removed outright.  On
        the stable channel the two are still separate derivations and a
        Wayland machine wants `pkgs.supersonic-wayland`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
