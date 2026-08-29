# machines/ernst/containers/pkgs/bencoding.nix
#
# bencoding — M14.  A bencode encoder/decoder, and a DEPENDENCY of
# kapowarr.nix rather than something this deployment runs on its own.
#
# Not in nixpkgs: surveyed against ernst's own pin on the session date
# (2026-08-28, nixpkgs fcb8fcd).  Nine of Kapowarr's ten runtime dependencies
# ARE there — typing_extensions, requests, beautifulsoup4, flask, waitress,
# cryptography, aiohttp, flask-socketio, websocket-client — so this one file is
# the whole of that derivation's vendoring cost.
#
# ── WHY KAPOWARR NEEDS IT ───────────────────────────────────────────────────
#
#   Kapowarr talks to torrent clients (qBittorrent, Transmission) and reads
#   .torrent files, which are bencoded.  It is a leaf dependency: nothing else
#   in this container imports it.
#
# ── fetchPypi, NOT fetchFromGitHub, AND THE REASON IS UNUSUAL ───────────────
#
#   The upstream repository (github.com/dust8/bencoding) publishes NO TAGS AT
#   ALL — checked 2026-08-28.  There is therefore no git revision that
#   corresponds to "0.2.6" other than by trusting a commit message, and pinning
#   a bare rev would mean this file's version string and its source have no
#   verifiable relationship.
#
#   The PyPI sdist does have that relationship: the version is part of the
#   artifact's identity and the hash pins the bytes.  So the sdist is the
#   honest source here, and it is the one case in ./pkgs where PyPI beats git.
#
#   Kapowarr requires `bencoding ~= 0.2`; 0.2.6 is the newest 0.2.x.
{
  lib,
  python3Packages,
}:

python3Packages.buildPythonPackage rec {
  pname = "bencoding";
  version = "0.2.6";
  format = "setuptools";

  src = python3Packages.fetchPypi {
    inherit pname version;
    hash = "sha256-Q8zjHUhj4p1rxhFVHU6fJlK+KZXp1eFbRtg4PxgNREA=";
  };

  # The sdist ships no tests directory.  pythonImportsCheck is the guard.
  doCheck = false;

  pythonImportsCheck = [ "bencoding" ];

  meta = {
    description = "Bencode encoder and decoder";
    homepage = "https://github.com/dust8/bencoding";
    license = lib.licenses.mit;
  };
}
