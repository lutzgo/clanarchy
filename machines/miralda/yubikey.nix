{ pkgs, lib, ... }:
let
  # gpg-agent only forwards DISPLAY (X11) to pinentry, not WAYLAND_DISPLAY.
  # This wrapper injects the Wayland session env so pinentry-gnome3 can open
  # a dialog even when called indirectly via the SSH auth flow.
  pinentryWrapper = pkgs.writeShellScript "pinentry-gnome3-wayland" ''
    # Inject Wayland/D-Bus env from the systemd user session so pinentry-gnome3
    # can open a dialog when invoked indirectly (e.g. via the SSH auth flow).
    uid=$(id -u)
    # Detect Wayland socket by scanning /run/user/<uid>/wayland-*
    wayland=$(ls /run/user/$uid/wayland-* 2>/dev/null \
              | head -1 | xargs basename 2>/dev/null || true)
    if [ -n "$wayland" ]; then
      export WAYLAND_DISPLAY="$wayland"
    fi
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
    exec ${pkgs.pinentry-gnome3}/bin/pinentry-gnome3 "$@"
  '';
in
{
  # PC/SC daemon — required for YubiKey OpenPGP and PIV apps
  # Start eagerly at boot (not socket-activated) so the card is enumerated
  # before scdaemon first connects; avoids "No such device" race on login.
  services.pcscd.enable = true;
  systemd.services.pcscd.wantedBy = [ "multi-user.target" ];

  # GnuPG agent with SSH support so the YubiKey auth subkey doubles as SSH key
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-gnome3;
  };

  # Override the pinentry-program to use the wrapper that injects Wayland env
  environment.etc."gnupg/gpg-agent.conf".text =
    lib.mkForce "pinentry-program ${pinentryWrapper}\n";

  # YubiKey udev rules (needed for non-root access)
  services.udev.packages = [ pkgs.yubikey-personalization ];

  # Trust clan machine host keys system-wide (plain ed25519, no cert chain).
  # Needed because lgo's SSH config forces HostKeyAlgorithms=ssh-ed25519 to
  # avoid publickey-hostbound-v00@openssh.com, which causes gnupg 2.4.x to
  # refuse signing with card-backed ed25519 keys.
  # ZeroTier IPs are listed alongside the primary hostnames so that
  # `clan machines update` (which connects via ZeroTier) doesn't prompt
  # interactively — and so the HostKeyAlgorithms match block in lgo's SSH
  # config (modules/users/lgo.nix) also covers those addresses.
  programs.ssh.knownHosts = {
    "miralda.goclan.org" = {
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBRTHrUg5ftPBfhAgjRUB9N2OUBvFDERLcRgAUu/BHBx";
    };
    # miralda ZeroTier IPv6 — same host key, different network path
    "fdda:106a:123a:d561:1099:93da:106a:123a" = {
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBRTHrUg5ftPBfhAgjRUB9N2OUBvFDERLcRgAUu/BHBx";
    };
    # biene — covers clan machines update via ZeroTier
    "biene.local" = {
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJrXALvNnbJlC+oQCZ8bf7FRFCbL28GjumRkmKcWF09c";
    };
    "fdda:106a:123a:d561:1099:93da:ef5d:598c" = {
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJrXALvNnbJlC+oQCZ8bf7FRFCbL28GjumRkmKcWF09c";
    };
  };

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
