{
  pkgs,
  ...
}: let
  schemePath = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
in {
  stylix = {
    enable = true;
    polarity = "dark"; # Catppuccin Mocha is a dark scheme

    base16Scheme = schemePath;
    image = pkgs.nixos-artwork.wallpapers.nineish-catppuccin-mocha.gnomeFilePath;

    fonts = {
      serif = {
        package = pkgs.nerd-fonts.monaspace;
        name = "MonaspiceXe Nerd Font Propo";
      };
      sansSerif = {
        package = pkgs.nerd-fonts.monaspace;
        name = "MonaspiceNe Nerd Font Propo";
      };
      monospace = {
        package = pkgs.nerd-fonts.monaspace;
        name = "MonaspiceAr Nerd Font Mono";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      sizes = {
        applications = 9;
        terminal = 10;
        desktop = 9;
        popups = 9;
      };
    };

    cursor = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
      size = 24;
    };

    targets.regreet.enable  = true; # GTK4 login screen — themed by Stylix
    targets.plymouth.enable = true; # Boot splash
  };
}
