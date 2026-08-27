# Tvheadend, built from upstream source — because nixpkgs REMOVED it.
#
# ── WHY THIS DERIVATION EXISTS (checked 2026-08-27) ─────────────────────────
#
#   The M8 milestone brief asserted "tvheadend is in nixpkgs; no image escape
#   hatch is needed".  That premise died between the brief and the build:
#   nixpkgs removed both `pkgs.tvheadend` and `services.tvheadend` — the
#   rename.nix tombstone says "nobody was willing to maintain them and they
#   were stuck on an unmaintained version that required FFmpeg 4" (nixpkgs
#   PR #332259).  It is gone from nixos-unstable too, verified 2026-08-27.
#
#   The FFmpeg-4 coupling that killed the nixpkgs package lives ENTIRELY in
#   Tvheadend's transcoding feature (libav).  This deployment never
#   transcodes — Tvheadend remuxes MPEG-TS to Jellyfin and Jellyfin's own
#   ffmpeg does all codec work on the iGPU — so `--disable-libav` removes the
#   dependency instead of pinning an EOL FFmpeg.  That is the whole trick.
#
# ── VERSION PIN ─────────────────────────────────────────────────────────────
#
#   Upstream has cut no stable release since v4.2.8 (2018); v4.3 is a 2017
#   pre-release tag and master is where nine years of development (and the
#   SAT>IP client fixes we rely on) live.  Every distro that ships 4.3 ships
#   a git snapshot; so does this file.  Pinned by REV, not branch — bump by
#   picking a new rev and updating `hash` (nix flake prefetch
#   github:tvheadend/tvheadend/<rev> prints it).
#
# ── THE THREE FLAGS THAT MUST NEVER BE DROPPED ──────────────────────────────
#
#   --disable-ffmpeg_static   default is YES and it DOWNLOADS an ffmpeg
#                             source tree during the build — sandbox death.
#   --disable-pcloud_cache    default is YES; same problem, a binary-cache
#                             download from pcloud (successor of the
#                             bintray_cache the old nixpkgs derivation
#                             disabled).
#   --disable-dvbscan         default is YES and fetches the dtv-scan-tables
#                             at build time; we substitute the nixpkgs
#                             dtv-scan-tables package path instead (the same
#                             move the old nixpkgs derivation made).
#
#   The rest: libav per the header; hdhomerun_{server,static} because the
#   static lib is another build-time download and no HDHomeRun exists here;
#   vue_build because the experimental Vue web UI needs a node toolchain at
#   build time (the classic ExtJS UI is in-tree and is the one that works);
#   linuxdvb because ernst has no local DVB hardware — the FRITZ!Box's tuners
#   arrive via the SAT>IP client (satip_client stays at its default: yes).
#
#   --nowerror because master tracks no fixed compiler; GCC 15 promotes
#   warnings this snapshot has not yet cleaned up, and chasing them with
#   per-warning -Wno-error flags (as the old derivation did for GCC 12) is a
#   treadmill.
{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  pkg-config,
  python3,
  which,
  gettext,
  openssl,
  uriparser,
  zlib,
  avahi,
  dbus,
  pcre2,
  bzip2,
  gnutar,
  dtv-scan-tables,
  libdvbcsa,
}:

stdenv.mkDerivation rec {
  pname = "tvheadend";
  version = "4.3-unstable-2026-08-22";

  src = fetchFromGitHub {
    owner = "tvheadend";
    repo = "tvheadend";
    rev = "45cbe4adb651149b00460f43ac56cf7a2b57a499";
    hash = "sha256-jOqpMjLEsQAsAtPMJT+7e01x/QcUKxHSNQteFf7k9tk=";
  };

  nativeBuildInputs = [
    makeWrapper
    pkg-config
    python3
    which
    gettext
  ];

  buildInputs = [
    openssl
    uriparser
    zlib
    avahi
    dbus
    pcre2
    bzip2
    libdvbcsa
  ];

  enableParallelBuilding = true;

  configureFlags = [
    "--nowerror"
    "--disable-libav"
    "--disable-ffmpeg_static"
    "--disable-pcloud_cache"
    "--disable-dvbscan"
    "--disable-hdhomerun_client"
    "--disable-hdhomerun_server"
    "--disable-hdhomerun_static"
    "--disable-vue_build"
    "--disable-linuxdvb"
    "--disable-bundle"
    "--disable-ccache"
  ];

  preConfigure = ''
    # Runtime paths compiled into the binary.  --replace-fail so upstream
    # moving either string breaks the build loudly instead of silently
    # shipping /usr paths that do not exist in the container.
    substituteInPlace src/config.c \
      --replace-fail /usr/bin/tar ${gnutar}/bin/tar
    substituteInPlace src/input/mpegts/scanfile.c \
      --replace-fail '"/usr/share/dvb"' '"${dtv-scan-tables}/share/dvbv5"'

    # support/version falls back to rpm/version when there is no .git (a
    # fetchFromGitHub tree has none) and no debian/changelog (upstream ships
    # none).  Without this the binary reports 0.0.0-unknown.
    echo ${version} > rpm/version
  '';

  postInstall = ''
    # config backup/restore shells out to tar and bzip2 at runtime.
    wrapProgram $out/bin/tvheadend \
      --prefix PATH : ${lib.makeBinPath [ bzip2 gnutar ]}
  '';

  meta = {
    description = "TV streaming server and digital video recorder (from-source build, transcoding disabled)";
    homepage = "https://tvheadend.org";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "tvheadend";
  };
}
