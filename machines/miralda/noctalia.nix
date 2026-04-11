{ ... }:
{
  # PAM service required by Noctalia's lockscreen (PamContext in QML).
  # Must be system-level — cannot be set from Home Manager.
  security.pam.services.noctalia = {
    # Uncomment after enrolling fingerprints with: sudo fprintd-enroll lgo
    fprintAuth = true;
  };
}
