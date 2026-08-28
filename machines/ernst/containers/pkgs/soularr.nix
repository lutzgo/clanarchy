# machines/ernst/containers/pkgs/soularr.nix
#
# Soularr — M14.  The bridge between Lidarr's "wanted" list and slskd: it reads
# what Lidarr is missing, searches Soulseek through slskd's REST API, grabs the
# best match, and hands the finished download back to Lidarr for import.
#
# Not in nixpkgs — no package and no module, surveyed against ernst's own pin
# on the session date (2026-08-28, nixpkgs fcb8fcd).
#
# ── IT IS A SCRIPT, NOT A PACKAGE, AND THE DERIVATION HAS TO SAY SO ─────────
#
#   There is no setup.py, no pyproject.toml and no setup.cfg in the tree at
#   v1.2.2 — checked, not assumed.  Upstream's own install instructions are
#   "pip install -r requirements.txt; python soularr.py".
#
#   So this is NOT buildPythonApplication (which needs a build system to
#   invoke): it is a plain stdenv derivation that copies the tree into the
#   store and wraps the entry point against a python environment carrying the
#   three dependencies.  scraparr.nix is the counter-example in this same
#   directory — that one really is a setuptools package, and gets the easy
#   treatment.
#
# ── IT IS A ONE-SHOT, NOT A DAEMON.  THIS DECIDES THE UNIT ─────────────────
#
#   docs/roadmap.md's M14 prompt lists Soularr beside Lidarr and Kapowarr as
#   though all three were services.  They are not the same shape: Soularr runs,
#   does a pass, and EXITS.  Upstream's Docker image fakes a daemon with a
#   `SCRIPT_INTERVAL` sleep loop, and its README's non-Docker instruction is a
#   cron entry.
#
#   containers/arr.nix therefore runs it from a systemd TIMER, not a
#   `Restart=always` service — see the soularr block there.  A `simple` unit
#   would enter a restart loop by design and every successful pass would be
#   logged as a service exit.
#
#   The corollary is the lock file: soularr.py writes `.soularr.lock` into its
#   --var-dir and refuses to start if it is present, which is what stops two
#   timer firings from overlapping on a long search.  That is why --var-dir
#   points at persistent state and not at a tmpfs.
#
# ── THE BUNDLED FLASK WEB UI IS DELIBERATELY NOT PACKAGED ──────────────────
#
#   The tree carries webui/webui.py plus templates and static assets, and
#   requirements.txt lists flask and waitress for it.  It is not installed here
#   and its two dependencies are not in the closure.
#
#   The reason is the same one containers/arr.nix applies to every port it does
#   not open: this would be a SECOND admin surface — one with no Traefik route,
#   no Authelia middleware and no argument for its existence — in a container
#   whose entire port policy is one explicit list.  Soularr's real interface is
#   Lidarr's wanted list, which already has a route and an identity provider in
#   front of it.
#
#   If a later milestone wants the web UI, it needs a port in that list, a
#   router, an `access_control` rule and a reason — not a quiet addition here.
#
# ── VERSION PINNING ────────────────────────────────────────────────────────
#
#   v1.2.2 (2026-04-28) is the newest release; it carries no release assets, so
#   the source tag is the artifact.  Pinned with a version and a hash rather
#   than a flake input, for the reason docs/roadmap.md's packaging section
#   gives: `nix flake update` must not be able to move a service silently.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  makeWrapper,
  callPackage,
}:

let
  # slskd-api is hand-rolled next door; the other two are in nixpkgs, and
  # `pyarr` is there at EXACTLY the 5.2.0 upstream's requirements.txt pins
  # (checked 2026-08-28), so nothing has to be overridden to satisfy it.
  slskd-api = callPackage ./slskd-api.nix { };

  pythonEnv = python3.withPackages (ps: [
    ps.music-tag
    ps.pyarr
    slskd-api
  ]);
in
stdenvNoCC.mkDerivation rec {
  pname = "soularr";
  version = "1.2.2";

  src = fetchFromGitHub {
    owner = "mrusse";
    repo = "soularr";
    tag = "v${version}";
    hash = "sha256-gtz99+DiFjJZuq54qo5C+5Exx++S+ePzldgDM9NHAOA=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # No build system, so no configure/build phase to run.
  dontConfigure = true;
  dontBuild = true;

  # soularr.py is copied rather than symlinked, and the wrapper passes the
  # store path explicitly: the script resolves nothing relative to its own
  # location, so the only thing that has to be right is that the interpreter
  # can find its three dependencies.
  #
  # --config-dir and --var-dir are NOT defaulted here.  Upstream defaults both
  # to `os.getcwd()`, which for a systemd unit is `/`, and a service that
  # silently reads a config from the root directory is worse than one that
  # fails.  containers/arr.nix passes both explicitly.
  installPhase = ''
    runHook preInstall

    install -Dm644 soularr.py $out/share/soularr/soularr.py

    # The shipped config.ini is an EXAMPLE full of placeholder credentials.  It
    # is installed as documentation only, under a name that cannot be mistaken
    # for live configuration — the real one is rendered into a tmpfs at run
    # time from staged secrets (see containers/arr.nix).
    install -Dm644 config.ini $out/share/doc/soularr/config.ini.example

    makeWrapper ${pythonEnv}/bin/python $out/bin/soularr \
      --add-flags "$out/share/soularr/soularr.py"

    runHook postInstall
  '';

  meta = {
    description = "Connects Lidarr's wanted list to Soulseek downloads via slskd";
    homepage = "https://github.com/mrusse/soularr";
    license = lib.licenses.gpl3Only;
    mainProgram = "soularr";
    platforms = lib.platforms.linux;
  };
}
