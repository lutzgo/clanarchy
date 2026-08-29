# machines/ernst/containers/pkgs/slskd-api.nix
#
# slskd-api — M14.  A Python client for slskd's REST API, and a DEPENDENCY of
# soularr.nix rather than something this deployment runs on its own.
#
# Not in nixpkgs: surveyed against ernst's own pin on the session date
# (2026-08-28, nixpkgs fcb8fcd) — `python3Packages.slskd-api` does not exist,
# while `pyarr` (soularr's other dependency) does, at exactly the 5.2.0 the
# upstream requirements.txt pins.  So this is the only Python dependency M14's
# music half has to hand-roll.
#
# ── THE VERSION IS 0.1.5 ON PURPOSE, AND IT IS NOT THE LATEST ────────────────
#
#   PyPI's latest is 0.2.4.  Soularr pins `slskd-api==0.1.5` — checked on BOTH
#   the v1.2.2 release tag and the `main` branch on 2026-08-28, because a pin
#   that upstream has already moved past on main is a pin about to expire, and
#   this one has not moved.
#
#   Taking 0.2.4 "because it is newer" would be this repo choosing a dependency
#   version its consumer has never been tested against, to fix nothing.  The
#   0.1.x → 0.2.x boundary is where the client's method signatures changed;
#   Soularr calls those methods.  Follow the consumer's pin, and revisit when
#   the consumer does.
#
# ── SOURCE IS GITHUB, NOT PyPI, AND THAT IS FORCED ──────────────────────────
#
#   PyPI has NO sdist for 0.1.5 — the only artifact is
#   `slskd_api-0.1.5-py3-none-any.whl`.  fetchPypi's default `format = "setuptools"`
#   fetches the sdist and would fail on a version that has none.  The upstream
#   git tag v0.1.5 exists and carries the full tree, so it is what is used.
#
#   (A wheel could be unpacked instead, and is strictly worse: it discards the
#   tests and the metadata, and nixpkgs' own convention is source where source
#   exists.)
#
# ── THE PATCH IS NOT COSMETIC: UPSTREAM TAKES ITS VERSION FROM `git` ────────
#
#   setup.py declares no version at all.  It sets `setup_requires =
#   ["setuptools-git-versioning"]` and templates the version from `{tag}` — so
#   the version is READ OUT OF THE GIT REPOSITORY AT BUILD TIME.
#
#   fetchFromGitHub produces a tarball with no `.git`, and a Nix build sandbox
#   has no network to fetch the build-time requirement from either.  Without
#   the patch the build fails at `Getting build dependencies for wheel` with
#   "ERROR Missing dependencies: setuptools-git-versioning" — measured, not
#   predicted.  Adding that package as a build input would NOT fix it: it would
#   then run and find no tag, because there is no repository.
#
#   So the version is pinned statically to the same string `version` above
#   already claims.  That makes the derivation's version and the built
#   package's metadata agree by construction, which the git-derived version
#   could not do from a tarball.
#
#   `format = "setuptools"`, not `pyproject = true`: there is no pyproject.toml
#   in this tree at all (checked at the tag — 404), only setup.py.
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonPackage rec {
  pname = "slskd-api";
  version = "0.1.5";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "bigoulours";
    repo = "slskd-python-api";
    tag = "v${version}";
    hash = "sha256-Kyzbd8y92VFzjIp9xVbhkK9rHA/6KCCJh7kNS/MtixI=";
  };

  # See the header.  Two edits, in this order:
  #
  #   1. delete the `setuptools_git_versioning={...}` block — with an explicit
  #      version it is an unrecognised setup() kwarg, and leaving it would mean
  #      a warning on every build for a setting nothing reads;
  #   2. turn the setup_requires line into the static version.
  #
  # `--replace-fail` on step 2 so that an upstream restructuring breaks the
  # build loudly here rather than silently leaving the git-versioning path in
  # place to fail later with a worse message.  Step 1's sed range is anchored
  # on both ends for the same reason.
  #
  # NOT a multi-line substituteInPlace pattern: Nix's indented-string literal
  # strips the common leading whitespace, so the pattern that reaches sh no
  # longer matches the file's own indentation.  Measured — the first attempt
  # failed with "pattern doesn't match anything in file".
  postPatch = ''
    sed -i '/^    setuptools_git_versioning={$/,/^    },$/d' setup.py
    substituteInPlace setup.py \
      --replace-fail 'setup_requires = ["setuptools-git-versioning"],' 'version="${version}",'
  '';

  build-system = [ python3Packages.setuptools ];

  dependencies = [ python3Packages.requests ];

  # The test suite drives a LIVE slskd instance — it needs a reachable server,
  # an API key and, for the transfer tests, a peer on the Soulseek network.
  # None of that exists in a Nix build sandbox, and a check that cannot run is
  # not a check that passed.  pythonImportsCheck below is the real guard: it is
  # what catches a missing dependency, which is the only failure mode packaging
  # a pure-Python client can actually introduce.
  doCheck = false;

  pythonImportsCheck = [ "slskd_api" ];

  meta = {
    description = "Python client for the slskd REST API";
    homepage = "https://github.com/bigoulours/slskd-python-api";
    license = lib.licenses.agpl3Only;
  };
}
