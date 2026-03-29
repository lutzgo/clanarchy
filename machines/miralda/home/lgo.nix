{ pkgs, inputs, ... }:
{
  home.username = "lgo";
  home.homeDirectory = "/home/lgo";
  home.stateVersion = "25.11";

  programs.git = {
    enable = true;
    # GPG commit signing via YubiKey
    signing.signByDefault = true;
    extraConfig.gpg.program = "gpg2";
  };

  programs.zsh.enable = true;

  home.packages = with pkgs; [
    htop
    ripgrep
    fd

    # GPG / YubiKey
    gnupg
    yubikey-manager       # ykman — YubiKey configuration tool
    yubikey-personalization
    pcsctools              # pcsc_scan — verify card is seen

    # Age / clan secret management
    age
    ssh-to-age            # converts SSH pubkey to age recipient format

    # Clan management
    inputs.clan-core.packages.${pkgs.system}.clan-cli
  ];
}
