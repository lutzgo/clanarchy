{ pkgs, lib, ... }:
let
  # gpg-agent only forwards DISPLAY (X11) to pinentry, not WAYLAND_DISPLAY.
  # This wrapper injects the Wayland/Qt env so pinentry-qt can open a dialog
  # even when called indirectly via the SSH auth flow.
  #
  # pinentry-gnome3 was rejected: it calls gcr_system_password_finish via
  # D-Bus (org.gnome.keyring.SystemPrompter) which requires gnome-keyring-daemon.
  # On Niri there is no GNOME session, so the D-Bus peer is absent and every
  # PIN prompt silently fails → "agent refused operation".
  # pinentry-qt draws its own Qt dialog directly on Wayland — no GNOME needed.
  pinentryWrapper = pkgs.writeShellScript "pinentry-qt-wayland" ''
    # Inject Wayland/D-Bus/Qt env from the systemd user session so pinentry-qt
    # can open a dialog when invoked indirectly (e.g. via the SSH auth flow).
    uid=$(id -u)
    # Detect Wayland socket by scanning /run/user/<uid>/wayland-*
    wayland=$(ls /run/user/$uid/wayland-* 2>/dev/null \
              | head -1 | xargs basename 2>/dev/null || true)
    if [ -n "$wayland" ]; then
      export WAYLAND_DISPLAY="$wayland"
      export QT_QPA_PLATFORM="wayland"
    fi
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
    exec ${pkgs.pinentry-qt}/bin/pinentry-qt "$@"
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
    pinentryPackage = pkgs.pinentry-qt;
  };

  # Override the pinentry-program to use the wrapper that injects Wayland env
  environment.etc."gnupg/gpg-agent.conf".text =
    lib.mkForce "pinentry-program ${pinentryWrapper}\n";

  # YubiKey udev rules (needed for non-root access)
  services.udev.packages = [ pkgs.yubikey-personalization ];

  # Clan host keys used to be pinned here, by hand, for the two machines that
  # existed at the time.  They are now generated for the whole fleet — including
  # every ZeroTier address — from the committed vars, in
  # modules/networking/clan-known-hosts.nix (imported fleet-wide by commonBase).
  # Do not reintroduce a hand-written list: the two machines added after this
  # one was written never got their ZeroTier entries, which broke deploys the
  # moment ZeroTier won a reachability race.

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
