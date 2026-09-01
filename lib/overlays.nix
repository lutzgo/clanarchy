# nixpkgs overlays shared between this flake's two pkgs instances.
#
# There are two of them, and they are built in different places:
#
#   - the stable instance, built by `pkgsForSystem` in clan.nix, which
#     every machine on `clanarchy.channel = "stable"` uses;
#   - the unstable instance (`unstablePkgs` in lib/mk-machine.nix), which
#     is injected as the `pkgs-unstable` module arg everywhere and becomes
#     `pkgs` outright on machines set to `clanarchy.channel = "unstable"`
#     (birte).
#
# An overlay that must hold for a package regardless of which channel the
# machine tracks therefore has to be applied to both — otherwise the same
# package name means two different things depending on the machine, which
# is precisely how birte ended up with a stock ungoogled-chromium while
# every other machine got the hardened one.  Defining them once here keeps
# the two lists from drifting.
_final: prev: {
  # ── niri ────────────────────────────────────────────────────────────────
  # niri 25.08's test suite hits EMFILE (too many open files) in the Nix
  # sandbox.  Only the Niri machines (miralda, jens) build this, but the
  # override is cheap and channel-independent.
  niri = prev.niri.overrideAttrs (_: { checkPhase = ":"; });

  # ── ungoogled-chromium ──────────────────────────────────────────────────
  # Bake the privacy flags into the binary.  This cannot be done from a
  # NixOS module: `nixpkgs.overlays` is ignored once `nixpkgs.pkgs` is set
  # to an externally-created instance, which is the case for every machine
  # in this clan.
  ungoogled-chromium = prev.ungoogled-chromium.override {
    commandLineArgs = [
      "--no-pings"
      "--disable-search-engine-collection"
      "--extension-mime-request-handling=always-prompt-for-install"
    ];
  };
}
