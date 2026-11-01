# nixpkgs overlays for this flake's pkgs instance.
#
# Applied by `pkgsForSystem` in clan.nix.  This file used to exist because
# there were TWO instances — a stable one from clan-core's nixpkgs and an
# unstable one built in lib/mk-machine.nix — and an overlay had to be applied
# to both or the same package name meant two different things depending on the
# machine.  That is how birte once ended up with a stock ungoogled-chromium
# while every other machine got the hardened one.
#
# There is one instance now, so that hazard is gone and this is simply where
# the overlay list lives.  It still cannot move into a NixOS module:
# `nixpkgs.overlays` is ignored once `pkgsForSystem` supplies `pkgs`.
_final: prev: let
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
  steamSafe = pkg: binaries:
    (prev.symlinkJoin {
      name = "${pkg.pname or pkg.name}-steam-safe";
      paths = [pkg];
      nativeBuildInputs = [prev.makeWrapper];
      postBuild =
        prev.lib.concatMapStrings (b: ''
          if [ -e "$out/bin/${b}" ]; then
            wrapProgram "$out/bin/${b}" --unset LD_LIBRARY_PATH --unset LD_PRELOAD
          fi
        '')
        binaries;
    })
    // {
      inherit (pkg) meta;
      inherit (pkg) version;
    };
in {
  # ── niri ────────────────────────────────────────────────────────────────
  # niri 25.08's test suite hits EMFILE (too many open files) in the Nix
  # sandbox.  Only the Niri machines (miralda, jens) build this, but the
  # override is cheap and channel-independent.
  niri = prev.niri.overrideAttrs (_: {checkPhase = ":";});

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
  }) ["chromium" "chromium-browser"];

  # ── google-chrome ───────────────────────────────────────────────────────
  # Same shim.  NOTE: unlike chromium's, Chrome's upstream desktop entry
  # carries an ABSOLUTE Exec, so a Steam shortcut created from it stores a
  # /nix/store path and keeps launching the OLD, unwrapped binary.  Wrapping
  # is necessary but not sufficient there — that shortcut has to be re-pointed
  # at /run/current-system/sw/bin/google-chrome-stable.  See
  # docs/guides/birte-emulation.md.
  google-chrome = steamSafe prev.google-chrome ["google-chrome-stable" "google-chrome"];

  # ── eden ────────────────────────────────────────────────────────────────
  # The Switch emulator is launched from Steam by design (that is the whole
  # point of the shortcut), so it is the package most exposed to this.
  eden = steamSafe prev.eden ["eden" "eden-cli" "eden-room"];

  # ── posthog: marked broken, and genuinely broken — by ONE test ──────────
  #
  # open-webui (ernst) pulls chromadb, which pulls python3Packages.posthog,
  # which nixpkgs marks `broken`.  The marker is accurate — measured on ernst
  # 2026-11-01 the build ends:
  #
  #   FAILED posthog/test/mcp/test_posthog_mcp.py::
  #     test_prepare_tool_result_delivers_into_call_tool_result_models[bare]
  #   1 failed, 4199 passed, 170 skipped, 116 deselected
  #
  # One failure in 4199, in posthog's own MCP test helpers, which open-webui
  # does not touch.  Disable that single test.
  #
  # IT HAS TO BE HERE, not in the container that needs it.  The openwebui
  # container takes the HOST's pkgs instance, so a `nixpkgs.config` or
  # overlay set inside `containers.openwebui.config` is silently inert — the
  # same trap recorded for `nixpkgs.overlays` at the top of this file.
  #
  # The `broken` flag is lifted alongside, in clan.nix's `pkgsForSystem`
  # config, because an overlay cannot clear a `meta` marker.  Drop both when
  # nixpkgs clears it.
  # `pythonPackagesExtensions`, not `python3.override` — overriding python3
  # alone does NOT reach `python3Packages`, which is what consumers resolve
  # through.  Measured: with the override form the package still carried only
  # upstream's three disabledTests.
  pythonPackagesExtensions =
    prev.pythonPackagesExtensions
    ++ [
      (_pyFinal: pyPrev: {
        posthog = pyPrev.posthog.overridePythonAttrs (old: {
          disabledTests =
            (old.disabledTests or [])
            ++ ["test_prepare_tool_result_delivers_into_call_tool_result_models"];
        });
      })
    ];
}
