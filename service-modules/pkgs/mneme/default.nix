# mneme — the household agent daemon.
#
# THE SCRIPT LIVES BESIDE ITS DEPLOYMENT, which is the same reason
# machines/ernst/rom-import.sh does: a tool that is packaged somewhere else and
# referenced from here drifts from the thing it talks to, and the drift is only
# visible at runtime.  ./mneme.py is the whole daemon and this file is how it
# is built.
#
# THE TESTS RUN AT BUILD TIME, and that is not decoration.  Everything in
# ./test_mneme.py covers the Ollama <-> OpenAI translation, which is the one
# part of this service with no observable failure mode: a mis-paired
# tool_call_id or a dropped tool call does not crash anything, it produces an
# assistant that quietly does not act on the house.  M24b's lesson generalises
# — a clean build is not evidence that the wiring is right — so the build is
# made to check the half that it can.
{ lib
, stdenvNoCC
, python3
, makeWrapper
, git
}:

let
  python = python3.withPackages (ps: [ ps.aiohttp ]);
in
# `git` is a CHECK input only, never a runtime one.  The memory tests make a
# real repository and assert that a write becomes a commit — that is the whole
# audit story, so testing it against a mock would test the mock.  At runtime
# the binary comes from the unit's own PATH (see roles.agent), which keeps it
# out of this closure and keeps which git is in use visible in the unit.
stdenvNoCC.mkDerivation {
  pname   = "mneme";
  version = "0.1.0";

  # AN EXPLICIT FILE SET, not `./.`.  Running the tests in the worktree leaves
  # a __pycache__ beside them; with a bare path that directory enters the
  # derivation and changes its hash depending on whether anyone has run python
  # in this checkout.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./mneme.py
      ./memory.py
      ./tools.py
      ./lint.py
      ./test_mneme.py
      ./soul
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild     = true;

  doCheck = true;
  nativeCheckInputs = [ git ];
  checkPhase = ''
    runHook preCheck
    # The wiki tests commit, so git needs an identity and a deterministic
    # default branch; a sandbox has neither and git's own defaults warn.
    export HOME=$TMPDIR
    export GIT_CONFIG_GLOBAL=$TMPDIR/gitconfig
    git config --global user.email test@localhost
    git config --global user.name test
    git config --global init.defaultBranch main
    ${python}/bin/python3 test_mneme.py
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    # All four modules into one directory: python puts a script's own directory
    # on sys.path, so `from memory import Wiki` resolves with no PYTHONPATH and
    # no package boilerplate.
    for m in mneme memory tools lint; do
      install -Dm0644 "$m.py" "$out/lib/mneme/$m.py"
    done

    # The constitution ships as data, not as a string literal in the daemon, so
    # that `cat` on a running host shows exactly what the model is told and so
    # that M29b can extend it without touching the Python.
    mkdir -p "$out/share/mneme"
    cp -r soul "$out/share/mneme/soul"

    makeWrapper "${python}/bin/python3" "$out/bin/mneme" \
      --add-flags "$out/lib/mneme/mneme.py"

    # The nightly pass gets its own entry point rather than a flag on the
    # daemon: it is a oneshot on a timer with an alert pointed at it, and a
    # mode switch inside a long-running server is a worse thing to alert on.
    makeWrapper "${python}/bin/python3" "$out/bin/mneme-lint" \
      --add-flags "$out/lib/mneme/lint.py"

    runHook postInstall
  '';

  # Consumed by service-modules/local-ai.nix so the unit cannot name a path
  # that the package does not install.
  passthru.soulSubdir = "share/mneme/soul";

  meta = with lib; {
    description = "Prompt-injecting proxy between Home Assistant and llama-swap";
    mainProgram = "mneme";
    platforms   = platforms.linux;
    license     = licenses.mit;
  };
}
