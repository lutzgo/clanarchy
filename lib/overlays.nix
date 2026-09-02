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
_final: prev:
let
  # ── steamSafe: strip the Steam Runtime's library paths ──────────────────
  #
  # Steam exports its own LD_LIBRARY_PATH — the bundled Ubuntu-12 Steam
  # Runtime — to everything it launches, and those libraries shadow the ones
  # every Nix binary is linked against.  Measured on birte:
  #
  #   chromium: /games/ubuntu12_32/steam-runtime/usr/lib/x86_64-linux-gnu/
  #             libnss3.so: version `NSS_3.30' not found (required by chromium)
  #
  # It is not browser-specific: with that variable set, plain coreutils fails
  # the same way (`head`, `tr`: libattr.so.1: version `ATTR_1.3' not found).
  # The symptom is a non-Steam shortcut that works perfectly from the KDE menu
  # and does nothing whatsoever from Gaming Mode.
  #
  # The per-shortcut remedy is Launch Options — `env -u LD_LIBRARY_PATH
  # -u LD_PRELOAD %command%` — which has to be typed into Steam once per
  # shortcut, on a handheld with no keyboard.  Wrapping the binaries instead
  # fixes it for every launcher, needs no Steam state, and cannot be lost when
  # a shortcut is re-added.
  #
  # SAFE EVERYWHERE, which is why this lives in the shared overlay rather than
  # being scoped to birte: outside Steam these variables are unset, so the
  # wrapper is a no-op on every other machine.  Nothing in this fleet sets
  # LD_LIBRARY_PATH for a desktop application deliberately.
  #
  # symlinkJoin rather than overrideAttrs: these are large packages (chromium
  # is hours of build) and the wrapper only needs to sit in front of the
  # existing binary.  `meta` is carried over explicitly — symlinkJoin does not
  # inherit it, and dropping it would lose `mainProgram` (breaking
  # `lib.getExe`) and, for google-chrome, the unfree licence that
  # allowUnfreePredicate checks against.
  steamSafe =
    pkg: binaries:
    (prev.symlinkJoin {
      name = "${pkg.pname or pkg.name}-steam-safe";
      paths = [ pkg ];
      nativeBuildInputs = [ prev.makeWrapper ];
      postBuild = prev.lib.concatMapStrings (b: ''
        if [ -e "$out/bin/${b}" ]; then
          wrapProgram "$out/bin/${b}" --unset LD_LIBRARY_PATH --unset LD_PRELOAD
        fi
      '') binaries;
    })
    // {
      inherit (pkg) meta;
      inherit (pkg) version;
    };
in
{
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
  # Wrapped afterwards so the flags and the Steam-Runtime shim compose:
  # `.override` first (it is a package argument), `steamSafe` second (it wraps
  # the built result).
  ungoogled-chromium = steamSafe (prev.ungoogled-chromium.override {
    commandLineArgs = [
      "--no-pings"
      "--disable-search-engine-collection"
      "--extension-mime-request-handling=always-prompt-for-install"
    ];
  }) [ "chromium" "chromium-browser" ];

  # ── google-chrome ───────────────────────────────────────────────────────
  # Same shim.  NOTE: unlike chromium's, Chrome's upstream desktop entry
  # carries an ABSOLUTE Exec, so a Steam shortcut created from it stores a
  # /nix/store path and keeps launching the OLD, unwrapped binary.  Wrapping
  # is necessary but not sufficient there — that shortcut has to be re-pointed
  # at /run/current-system/sw/bin/google-chrome-stable.  See
  # docs/guides/birte-emulation.md.
  google-chrome = steamSafe prev.google-chrome [ "google-chrome-stable" "google-chrome" ];

  # ── eden ────────────────────────────────────────────────────────────────
  # The Switch emulator is launched from Steam by design (that is the whole
  # point of the shortcut), so it is the package most exposed to this.
  eden = steamSafe prev.eden [ "eden" "eden-cli" "eden-room" ];
}
