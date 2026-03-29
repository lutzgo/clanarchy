{ pkgs, ... }:
{
  # PC/SC daemon — required for YubiKey OpenPGP and PIV apps
  services.pcscd.enable = true;

  # GnuPG agent with SSH support so the YubiKey auth subkey doubles as SSH key
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

  # YubiKey udev rules (needed for non-root access)
  services.udev.packages = [ pkgs.yubikey-personalization ];
}
