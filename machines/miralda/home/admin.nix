{ pkgs, ... }:
{
  home.username = "admin";
  home.homeDirectory = "/home/admin";
  home.stateVersion = "25.11";

  programs.git.enable = true;
  programs.zsh.enable = true;

  home.packages = with pkgs; [
    htop
    ripgrep
    fd
  ];
}
