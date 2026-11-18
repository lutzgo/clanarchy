# machines/ernst/containers/pkgs/cleanuparr.nix
#
# Cleanuparr — M12 (d).  Not in nixpkgs (surveyed against ernst's own pin on
# 2026-08-26, the session date).
#
# The "why a release artifact, and why a pinned hash rather than a flake input"
# argument is written out once, in umlautadaptarr.nix in this directory.  It
# applies here unchanged and is not repeated.
#
# ── This one is a SINGLE-FILE self-contained publish, and that is different ──
#
#   UmlautAdaptarr's zip is an ordinary publish tree: an apphost, loose native
#   .so files, managed .dlls.  autoPatchelf walks it and there is nothing more
#   to say.
#
#   Cleanuparr's zip is ONE 197 MB ELF plus two loose natives (libe_sqlite3.so,
#   libMono.Unix.so) and wwwroot.  The .NET runtime and every managed assembly
#   are BUNDLED INSIDE the executable.  autoPatchelf can only see and fix the
#   outer apphost — the bundled natives are extracted by the host at RUN time,
#   into DOTNET_BUNDLE_EXTRACT_BASE_DIR, long after any build-time patching
#   could reach them.
#
#   So this derivation does two things umlautadaptarr.nix does not:
#
#     1. LD_LIBRARY_PATH on the wrapper.  The extracted natives are unpatched
#        ELFs with no RPATH, and they need libstdc++/libgcc_s (the apphost's
#        own DT_NEEDED list already names both), plus openssl and zlib for the
#        crypto and compression shims.  Without it the app dies at first
#        managed call with a dlopen failure naming a file in a temp directory —
#        which reads as a corrupt install and is not one.
#
#     2. DOTNET_BUNDLE_EXTRACT_BASE_DIR is pinned by the UNIT, not here — see
#        containers/arr/.  The default is $TMPDIR/.net/<app>/<hash>, and
#        with PrivateTmp = true that is a fresh tmpfs on every start, i.e. an
#        80 MB extraction per restart.  Pointing it at the cache directory
#        makes it extract once.
#
# ── WHEN THIS GOES TO 2.11 OR LATER: a checklist (written 2026-11-18) ─────────
#
#   Not bumped ad hoc: versions move here with the regular updates only.
#   2.11.1 was built and smoke-tested on 2026-11-18 (same zip layout, this
#   derivation unchanged, /health 200) and then deliberately NOT shipped.
#
#   1. Bump `version` and `hash` together.  The asset name and the zip's
#      top-level directory have kept the `Cleanuparr-<v>-linux-amd64` shape
#      through 2.11.1; if `installPhase`'s `cp` fails, that changed.
#   2. Read the release notes from 2.10.5 up to the new version for
#      "Breaking Changes".  2.11.0's were Seeker-internal (cycle tracking,
#      episode search mode) and migrate the DB on first start.  ZFS snapshots
#      of /srv/state cover a rollback; take a manual one if in doubt.
#   3. After deploy, in the UI → Seeker: ENABLE THE LIDARR INSTANCE.  Lidarr
#      joined proactive search (missing albums + quality/CF upgrades) in 2.11
#      (upstream #870).  Replacement searches after a removal already covered
#      Lidarr before that — see docs/runbooks/bindery-dead-torrent-sweep.md,
#      and do not re-add the timer #470 removed.
#   4. Expect Lidarr indexer load to rise: 32k+ missing albums (2026-11-17).
#      Start with a long search interval and the "exclude recent grabs"
#      option (2.11.0), and watch Prowlarr's per-indexer limits.
#   5. 2.11.1 also fixes two security bugs (#896: a temporary login token was
#      fully authenticated; #897: TLS certificates were not validated on
#      outbound HTTPS).  Nothing here talks HTTPS to the *arrs (loopback
#      HTTP), so the urgency is low, but it is a reason not to sit on 2.10.x.
#   6. Confirm in the log that Lidarr items still say `[Lidarr] skip | item is
#      missing the content id` only for unmatched downloads.
#
# ── Configuration is a DATABASE, not this file ───────────────────────────────
#
#   Cleanuparr v2 keeps its configuration in SQLite under its config directory
#   and is configured entirely through its web UI.  Only three things are
#   environment variables: PORT, BASE_PATH, and CLEANUPARR_CONFIG_PATH (the
#   non-Docker override for the config directory).  Everything else — which
#   *arrs, which download client, the strike thresholds, and in particular the
#   hardlink/orphan cleaner's own settings — is UI state.
#
#   That makes first-run configuration a MANUAL STEP, in the same shape as the
#   *arr root folders in containers/arr/ and for the same reason: faking it
#   from Nix would create a second source of truth for state the application
#   owns.  The PR body carries the steps, and the conservative-first-deploy
#   rule M12 (d) sets out is part of them — a cleaner that deletes is a cleaner
#   that can delete the wrong thing.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
  makeWrapper,
  zlib,
  openssl,
  icu,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "cleanuparr";
  version = "2.10.5";

  src = fetchurl {
    url = "https://github.com/Cleanuparr/Cleanuparr/releases/download/v${finalAttrs.version}/Cleanuparr-${finalAttrs.version}-linux-amd64.zip";
    hash = "sha256-Xnmmq5K+2rV2iDz9PuutelmuR2oR4H1cO4l5Va/zqso=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    zlib
    openssl
    icu
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/cleanuparr
    cp -r Cleanuparr-${finalAttrs.version}-linux-amd64/. $out/share/cleanuparr/
    chmod +x $out/share/cleanuparr/Cleanuparr

    # See the header: the extracted bundle natives are never patched, so the
    # runtime linker has to be told where their dependencies live.  This is the
    # same set autoPatchelf resolved for the outer apphost.
    makeWrapper $out/share/cleanuparr/Cleanuparr $out/bin/cleanuparr \
      --set ASPNETCORE_CONTENTROOT $out/share/cleanuparr \
      --prefix LD_LIBRARY_PATH : "${
      lib.makeLibraryPath [
        stdenv.cc.cc.lib
        zlib
        openssl
        icu
      ]
    }"

    runHook postInstall
  '';

  meta = {
    description = "Cleans stalled, blocked, orphaned and unlinked downloads out of the *arr stack";
    homepage = "https://github.com/Cleanuparr/Cleanuparr";
    license = lib.licenses.gpl3Only;
    platforms = ["x86_64-linux"];
    sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    mainProgram = "cleanuparr";
  };
})
