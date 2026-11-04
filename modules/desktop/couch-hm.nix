# Home Manager additions for the COUCH accounts — deck on birte (Desktop Mode)
# and go on ernst (the TV's desktop arm). Imported per user, by
# machines/birte/deck.nix and modules/roles/htpc.nix.
#
# Everything else they share with lgo (bar, plugins, launcher, niri look,
# palette): see `lgoLayout` in noctalia-hm.nix and modules/desktop/niri-look.nix.
# This file is only what a couch screen needs DIFFERENTLY:
{
  lib,
  pkgs,
  inputs,
  ...
}: let
  oniri = import inputs.oniri {inherit pkgs;};
in {
  # The dock, always visible. noctalia-hm.nix gives every non-lgo user a dock
  # with auto_hide — which only appears when the pointer touches the bottom
  # edge, so on a touchscreen (the Deck) or with a controller (the TV) it
  # simply never shows. The launcher button sits at its start.
  programs.noctalia.settings.dock = {
    enabled = true;
    auto_hide = lib.mkForce false;
    launcher_position = "start";
  };

  # Autostart restated without KeePassXC — no password manager on a shared
  # couch screen. niri-hm.nix starts Noctalia, Oniri and KeePassXC.
  programs.niri.settings.spawn-at-startup = lib.mkForce [
    {command = ["uwsm" "app" "--" "noctalia"];}
    {command = ["uwsm" "app" "--" "${oniri}/bin/oniri"];}
  ];

  # No Nextcloud sync client (noctalia-hm.nix starts one for every niri user).
  # The unit stays defined; it is just not pulled in.
  systemd.user.services.nextcloud-client.Install.WantedBy = lib.mkForce [];
}
