{ pkgs, ... }:
{
  # ── Printing (CUPS + hplip) ───────────────────────────────────────────────
  services.printing = {
    enable = true;
    drivers = [ pkgs.hplip ];
  };

  # ── Scanning (SANE + hplip backend) ──────────────────────────────────────
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.hplip ];
  };

  # ── Avahi — zero-conf network printer/scanner discovery ──────────────────
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # ── User groups ───────────────────────────────────────────────────────────
  users.users.lgo.extraGroups = [ "lp" "scanner" ];
}
