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
  # ── Full-screen windows: bar and dock only on an empty workspace ─────────
  #
  # `smart_auto_hide` (Noctalia: "hide while the active workspace has
  # windows; show when it is empty") on both, and `reserve_space = false`,
  # which is the half that actually gives windows the screen: a reserved
  # exclusive zone stays reserved while the bar or dock is hidden. So a
  # window — maximized by Oniri — fills the screen, and closing the last one
  # brings bar and dock back.
  #
  # NOT the plain `auto_hide`: that reveals on pointer approach to the edge,
  # and neither a touchscreen (the Deck) nor a controller (the TV) has a
  # pointer to approach with. That is why the dock "was not visible" before.
  programs.noctalia.settings.bar.default = {
    smart_auto_hide = true;
    reserve_space = false;
  };

  programs.noctalia.settings.dock = {
    enabled = true;
    auto_hide = lib.mkForce false;
    smart_auto_hide = true;
    reserve_space = false;

    # As set in the UI on birte, 2026-11-04. Chromium is installed for both
    # couch accounts by the chromium role (clan.nix: birte → deck, ernst → go).
    pinned = ["chromium"];
    launcher_icon = "rocket";
    launcher_position = "start";

    # The top bar's transparency (lgo's `bar.default.background_opacity`,
    # noctalia-hm.nix), so the two read as one surface. mkOverride 40 because
    # noctalia-hm.nix sets the dock's at mkForce (50) against Stylix's own
    # value — this one has to beat that. Written as a number, not read from
    # the bar's setting: reading `settings` while defining `settings` recurses.
    background_opacity = lib.mkOverride 40 0.49;
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
