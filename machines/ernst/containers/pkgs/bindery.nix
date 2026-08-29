# machines/ernst/containers/pkgs/bindery.nix
#
# Bindery — M17.  Ebook (and audiobook-capable) acquisition: the successor
# picked for the archived Readarr.  Monitors authors, searches Newznab/Torznab
# indexers, hands downloads to a torrent client, files the results.
#
# Not in nixpkgs — no package and no module, surveyed against ernst's own pin
# on the session date (2026-08-29).
#
# ── THE RELEASE ARTIFACT IS TAKEN, NOT THE GIT TREE ────────────────────────
#
#   docs/roadmap.md's packaging rule, settled by M12.  v1.33.2 publishes
#   per-platform tarballs WITH a checksums file and per-asset SPDX SBOMs —
#   the tidiest upstream release discipline of anything packaged in this
#   repo so far.  The sha256 below was verified against upstream's
#   bindery_1.33.2_checksums.txt at fetch time (2026-08-29), so the pin and
#   upstream's own attestation agree.
#
#   The tarball is flat: CHANGELOG.md, LICENSE, README.md,
#   THIRD_PARTY_LICENSES.md and one static Go binary (`bindery`, ELF, no
#   INTERP — pure-Go SQLite via modernc.org/sqlite, so no cgo and no shared
#   libraries to patchelf).  Verified by running it on miralda before this
#   file was written: it starts, logs its version, serves its UI, and its
#   API answers 401 without a key.
#
# ── ONE TRAP, MEASURED, THAT THE UNIT IN arr.nix MUST HANDLE ───────────────
#
#   BINDERY_DB_PATH does NOT follow BINDERY_DATA_DIR.  With DATA_DIR set and
#   DB_PATH unset, the log shows dataDir at the configured path and dbPath
#   still at the compiled-in default /config/bindery.db — and the service
#   dies on `mkdir /config: permission denied`.  Exactly M14's defect class
#   ("a service whose state directory is empty on first run"), found by
#   running the binary rather than by reading about it.  The unit sets BOTH.
#
# ── UPSTREAM'S OWN DESCRIPTION IS THE STALE ARTIFACT, NOT THE SURVEY ───────
#
#   The GitHub repo description still reads "for Usenet … download via
#   SABnzbd", which is what a 2026-08-28 survey (recorded in the M14 section
#   of docs/roadmap.md) took at its word — and this fleet measured zero
#   Usenet in M12, which made Bindery look like a poor fit.  The README and
#   settings surface at v1.33.2 tell the current story: qBittorrent /
#   Transmission / Deluge / rTorrent as first-class download clients, and
#   Torznab (Prowlarr) beside Newznab.  M17's survey re-checked and is
#   right; the description is marketing that lagged the code.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation rec {
  pname = "bindery";
  version = "1.33.2";

  src = fetchurl {
    url = "https://github.com/vavallee/bindery/releases/download/v${version}/bindery_${version}_linux_amd64.tar.gz";
    hash = "sha256-cJJO6c+a1hRBBowDDT/TYInd7wJHjUqLhOMdKuSezgE=";
  };

  # Flat tarball — no single root directory.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 bindery $out/bin/bindery

    runHook postInstall
  '';

  meta = {
    description = "Automated book download manager — the modern replacement for Readarr";
    homepage = "https://github.com/vavallee/bindery";
    changelog = "https://github.com/vavallee/bindery/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "bindery";
    platforms = [ "x86_64-linux" ];
  };
}
