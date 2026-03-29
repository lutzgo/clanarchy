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

  # Allow PC/SC access for SSH users — pcscd uses PolicyKit and by default
  # only permits "active" (local graphical) sessions. This rule grants access
  # unconditionally so ykman PIV operations work over SSH.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id === "org.debian.pcsc-lite.access_pcsc" ||
          action.id === "org.debian.pcsc-lite.access_card") {
        return polkit.Result.YES;
      }
    });
  '';
}
