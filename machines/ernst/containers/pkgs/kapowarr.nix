# machines/ernst/containers/pkgs/kapowarr.nix
#
# Kapowarr — M14.  Comic-book acquisition, fitting into the *arr suite: it
# manages volumes, searches GetComics, and hands files to a download client.
#
# Not in nixpkgs — no package and no module, surveyed against ernst's own pin
# on the session date (2026-08-28, nixpkgs fcb8fcd).
#
# ── MYLAR3 WAS CONSIDERED AND NOT CHOSEN.  RECORDING THE REASON ────────────
#
#   docs/roadmap.md requires this either way.  Mylar3 is the older and
#   more-mature comics automation tool, and "more mature" is a real argument
#   this repo normally respects.
#
#   It loses here on SHAPE, not on quality.  Mylar3 is built around Usenet-first
#   acquisition with NZB clients as the primary path — and this fleet has NO
#   USENET AT ALL.  That is measured, not assumed: M12 (e) checked the last 80
#   grabs across Sonarr and Radarr, found every one of them torrent protocol,
#   and found qBittorrent to be the only download client configured — which is
#   why uid 3013 (unpackerr) is still a reservation and not a service.
#
#   Kapowarr's primary path is GetComics (direct HTTP) plus a torrent client,
#   which is the acquisition shape this deployment actually has.  Choosing the
#   more mature tool whose main pathway is unused here would be choosing a
#   maturity we could not benefit from.
#
#   The trigger to revisit is the same one unpackerr's reservation carries: a
#   Usenet download client being added to this fleet.  Not a hunch.
#
# ── THE RELEASE ARTIFACT IS TAKEN, NOT THE GIT TREE ────────────────────────
#
#   docs/roadmap.md's packaging rule, settled by M12: take the upstream release
#   artifact when there is one, build from source only when there is not.  It
#   is what nixpkgs itself does for sonarr, radarr, prowlarr and bazarr.
#
#   V1.3.1 (2026-03-29) publishes `Kapowarr-release.zip`, so that is the
#   source.  Its top level is exactly `backend/`, `frontend/`, `Kapowarr.py`,
#   `requirements.txt` and `pyproject.toml` — no build step, no bundler, no
#   compiled asset: `frontend/` is server-rendered Flask templates plus static
#   SVGs, not a JS application.  (Contrast questarr.nix next door, which has a
#   real Vite build and no release artifact at all.)
#
#   Note the tag is `V1.3.1` with a CAPITAL V.  Upstream is inconsistent about
#   this across projects and the URL is case-sensitive.
#
# ── IT RE-EXECUTES ITSELF, AND THE WRAPPER HAS TO SURVIVE THAT ─────────────
#
#   Kapowarr.py is a supervisor: it re-runs itself as a subprocess and uses the
#   subprocess's exit code to implement in-app restart (the "Restart" button,
#   and the automatic restart after certain settings changes).  Reading
#   Kapowarr.py at V1.3.1:
#
#     comm = [py_exe, "-u", __file__] + argv[1:]
#     proc = Popen(comm, env={**environ, "KAPOWARR_RUN_MAIN": "1", ...})
#
#   `py_exe` is `sys.executable` and `__file__` is the store path, so the child
#   is the SAME interpreter running the SAME file — and `env` is a copy of the
#   parent's environment, so whatever makes the dependencies importable in the
#   parent is inherited by the child.
#
#   That is why this wraps `pythonEnv/bin/python` with the script as an added
#   flag, rather than patching a shebang: the interpreter that ends up in
#   `sys.executable` is then the one that already has the dependencies, and the
#   re-exec needs nothing further.  A shebang-patched script would put a bare
#   python in `sys.executable` and the restart would come back up without its
#   imports — a failure that only appears when someone presses Restart, which
#   is the worst time to find it.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  python3,
  makeWrapper,
  callPackage,
}:

let
  # Nine of the ten runtime dependencies are in nixpkgs; `bencoding` is not and
  # is hand-rolled next door.  The list follows upstream's requirements.txt at
  # V1.3.1 verbatim.
  bencoding = callPackage ./bencoding.nix { };

  pythonEnv = python3.withPackages (ps: [
    ps.typing-extensions
    ps.requests
    ps.beautifulsoup4
    ps.flask
    ps.waitress
    ps.cryptography
    ps.aiohttp
    ps.flask-socketio
    ps.websocket-client
    bencoding
  ]);
in
stdenvNoCC.mkDerivation rec {
  pname = "kapowarr";
  version = "1.3.1";

  src = fetchurl {
    url = "https://github.com/Casvt/Kapowarr/releases/download/V${version}/Kapowarr-release.zip";
    hash = "sha256-dDGONAGfjfIsl5Ri53DUOuReL8q9mWsSHsFTFzyaNtk=";
  };

  nativeBuildInputs = [
    unzip
    makeWrapper
  ];

  # The zip has no single root directory — it unpacks `backend/`, `frontend/`
  # and the two top-level files straight into the current directory.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  # `requests[socks]` in requirements.txt is the socks extra, which pulls
  # PySocks.  It is NOT added: this deployment gives Kapowarr no SOCKS proxy —
  # its downloads go out through the container's ordinary route — and an extra
  # that is never configured is closure for nothing.  If a proxy is ever
  # configured in its UI, `ps.pysocks` is the line to add, and the symptom
  # without it is an explicit "Missing dependencies for SOCKS support".
  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/kapowarr
    cp -r backend frontend Kapowarr.py $out/share/kapowarr/

    makeWrapper ${pythonEnv}/bin/python $out/bin/kapowarr \
      --add-flags "-u" \
      --add-flags "$out/share/kapowarr/Kapowarr.py"

    runHook postInstall
  '';

  meta = {
    description = "Comic book library manager and downloader for the *arr suite";
    homepage = "https://github.com/Casvt/Kapowarr";
    license = lib.licenses.gpl3Only;
    mainProgram = "kapowarr";
    platforms = lib.platforms.linux;
  };
}
