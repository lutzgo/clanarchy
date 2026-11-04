# nixpkgs overlays for this flake's pkgs instance.
#
# Applied in TWO places, and both are needed:
#
#   modules/base.nix   `nixpkgs.overlays` — what every DEPLOYED machine uses
#   clan.nix           `pkgsForSystem`   — only the vars-generator copies
#
# This file once had to cover a stable and an unstable instance; that hazard
# is gone with the single channel.  The one that replaced it: until #406
# (2026-11-04) it was applied ONLY through pkgsForSystem, on the belief that
# `nixpkgs.overlays` is ignored once pkgsForSystem supplies `pkgs`.  With
# clan-core main pkgsForSystem never reaches nixosConfigurations, so nothing
# below was in effect on any machine — the chromium flags included.
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
  # Bake the privacy flags into the binary, so every launcher — desktop
  # file, Steam shortcut, a shell — gets them, not just ones that pass args.
  # `--extension-mime-request-handling` is the load-bearing one: without it
  # ungoogled-chromium ignores External Extensions, which is how lgo's
  # extensions are installed (modules/users/lgo/browsers.nix).
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

        # mcp 2.3.0 renamed streamablehttp_client -> streamable_http_client,
        # and open-webui 0.12.3 still imports the old spelling:
        #
        #   ImportError: cannot import name 'streamablehttp_client' from
        #   'mcp.client.streamable_http'
        #
        # which takes open-webui.service down outright. Verified on ernst:
        # the module defines `async def streamable_http_client` and nothing
        # named streamablehttp_client.
        #
        # An alias in the LIBRARY rather than a patch in the consumer, because
        # open-webui calls this from more than one place and the alias fixes
        # every call site at once without tracking them. Delete it when
        # open-webui catches up to the new name.
        mcp = pyPrev.mcp.overridePythonAttrs (old: {
          postPatch =
            (old.postPatch or "")
            + ''
              echo 'streamablehttp_client = streamable_http_client' \
                >> src/mcp/client/streamable_http.py
            '';
        });
      })
    ];
}
