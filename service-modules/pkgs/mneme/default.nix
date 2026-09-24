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
}:

let
  python = python3.withPackages (ps: [ ps.aiohttp ]);
in
stdenvNoCC.mkDerivation {
  pname   = "mneme";
  version = "0.1.0";

  # AN EXPLICIT FILE SET, not `./.`.  Running the tests in the worktree leaves
  # a __pycache__ beside them; with a bare path that directory enters the
  # derivation and changes its hash depending on whether anyone has run python
  # in this checkout.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./mneme.py ./test_mneme.py ./soul ];
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild     = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python}/bin/python3 test_mneme.py
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm0644 mneme.py "$out/lib/mneme/mneme.py"

    # The constitution ships as data, not as a string literal in the daemon, so
    # that `cat` on a running host shows exactly what the model is told and so
    # that M29b can extend it without touching the Python.
    mkdir -p "$out/share/mneme"
    cp -r soul "$out/share/mneme/soul"

    makeWrapper "${python}/bin/python3" "$out/bin/mneme" \
      --add-flags "$out/lib/mneme/mneme.py"

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
