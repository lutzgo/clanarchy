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

  # ── User groups ───────────────────────────────────────────────────────────
  users.users.lgo.extraGroups = [ "lp" "scanner" ];
}
