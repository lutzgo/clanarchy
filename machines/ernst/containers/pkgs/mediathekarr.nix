# machines/ernst/containers/pkgs/mediathekarr.nix
#
# MediathekArr — M12 (f).  Not in nixpkgs (surveyed against ernst's own pin on
# 2026-08-26, the session date).
#
# ── This one is built FROM SOURCE, and the two siblings in this directory are
#    not.  The difference is upstream's, not a preference ────────────────────
#
#   UmlautAdaptarr and Cleanuparr each publish a linux-x64 release asset, so
#   those derivations take the published artifact — the same shape nixpkgs uses
#   for sonarr, radarr, prowlarr and bazarr.  MediathekArr publishes NONE:
#   every release from v1.0-beta.5 through v1.0-beta.12 has an empty assets
#   array, and upstream's only binary channel is a Docker image.  A Docker
#   image is exactly what M12 rejects, so this is the case the "hand-rolled
#   derivation" language was written for, and buildDotnetModule is the answer.
#
# ── READ THE TAG, NOT `main`.  They are different trees ──────────────────────
#
#   This cost a round in the session that wrote this file and would cost
#   another, because every signal points the wrong way.
#
#   `main` is 8 commits "ahead" of v1.0-beta.12 and the repository's pushed_at
#   is 2026-08-10, so the tag looks six months stale.  It is not: those 8
#   commits are LICENSE and README edits, and — the part that matters — `main`
#   is a DIVERGED, OLDER tree.  It carries a single-process Dockerfile whose
#   ENTRYPOINT is MediathekArrServer.dll, a DownloadService that hardcodes its
#   output directory relative to the assembly location, and a routine that
#   DOWNLOADS A STATIC FFMPEG BUILD FROM johnvansickle.com AT RUNTIME into that
#   same directory.  None of that survives being installed into a read-only
#   store, and none of it is what upstream ships.
#
#   The tag's tree (f5bd04d6) is the real v1.0-beta.12 and is sane: paths come
#   from environment variables, ffmpeg comes from FFMPEG_PATH or $PATH, and
#   mkvmerge comes from $PATH.
#
#   fetchFromGitHub with `tag =` fetches the tag, so this file is correct — but
#   anyone reading upstream in a browser lands on `main` by default and will
#   conclude this derivation is wrong.  It is not.
#
# ── UPSTREAM IS TWO PROCESSES, AND THE DOCS DO NOT SAY SO ────────────────────
#
#   The tagged Dockerfile publishes two projects and starts both from
#   docker_start.sh:
#
#     MediathekArrServer      port 5008   the NEWZNAB INDEXER.  This is what
#                                         Prowlarr is pointed at; it answers
#                                         /api?t=caps with a Newznab caps
#                                         document.
#     MediathekArrDownloader  port 5007   the SABNZBD SHIM *and* the setup
#                                         WIZARD.  This is what Sonarr/Radarr
#                                         add as a download client, and the
#                                         page a human opens once to configure
#                                         the thing.
#
#   Upstream's docker-compose publishes only 5007, and its README only ever
#   mentions 5007, which makes it very easy to package half the product: an
#   indexer that answers searches, and nothing that can ever download a result.
#   That is the fails-by-succeeding shape M12 warns about twice, so BOTH are
#   built here and containers/arr.nix runs both.
#
#   The two are shipped as two attributes rather than one merged directory
#   because each project publishes its own appsettings.Production.json — the
#   files that carry 5007 and 5008 — and publishing both into one output would
#   have one silently overwrite the other.
#
# ── What it is, because it decides the uid ───────────────────────────────────
#
#   Upstream's own words: "Indexer: MediathekArr is pretending to be a usenet
#   indexer, but is actually just fetching and parsing search results from
#   MediathekViewWeb.  Downloader: MediathekArr is pretending to be a SABnzbd
#   usenet downloader but is actually just downloading the video and subtitles
#   via HTTP directly from the Mediatheken."
#
#   The downloader half is why this service gets a media-group uid while
#   Prowlarr, the other "indexer", gets none: it WRITES VIDEO FILES into the
#   download tree, then remuxes them with ffmpeg and mkvmerge.  That argument
#   is made where it belongs, in containers/arr.nix.
#
#   ffmpeg and mkvtoolnix are therefore RUNTIME DEPENDENCIES, not optional
#   extras — upstream's Dockerfile apt-installs both and adds the mkvtoolnix
#   third-party repository to get a current mkvmerge.  They are wrapped onto
#   PATH below so nothing reaches for the network to find them.
{
  lib,
  buildDotnetModule,
  fetchFromGitHub,
  dotnetCorePackages,
  makeWrapper,
  ffmpeg,
  mkvtoolnix-cli,
  which,
}:

let
  version = "1.0-beta.12";

  src = fetchFromGitHub {
    owner = "PCJones";
    repo = "MediathekArr";
    tag = "v${version}";
    hash = "sha256-BZEQElAqlJQAH3NQg/8ESnd/FViXlrYDfPXrG9scF4Q=";
  };

  # One shape, twice.  The only differences between the indexer and the
  # downloader are the project, the executable and the port, so everything
  # else is written once.
  mkComponent =
    {
      pname,
      projectFile,
      executable,
      listen,
      description,
    }:
    buildDotnetModule {
      inherit pname version src projectFile;

      nugetDeps = ./mediathekarr-deps.json;

      # net9.0, from the .csproj files.  Named explicitly rather than taking
      # the default: the default SDK moves with nixpkgs, and a .NET major bump
      # under a project that pins net9.0 is a build failure discovered at
      # deploy time.
      dotnet-sdk = dotnetCorePackages.sdk_9_0;
      dotnet-runtime = dotnetCorePackages.aspnetcore_9_0;

      executables = [ executable ];

      nativeBuildInputs = [ makeWrapper ];

      # ASPNETCORE_ENVIRONMENT is not decoration.  The port lives in
      # appsettings.PRODUCTION.json, which ASP.NET only loads when the
      # environment name matches; upstream's Dockerfile sets it for exactly
      # this reason.  Without it both processes would bind ASP.NET's default
      # and answer nothing where Prowlarr and Sonarr are pointed.
      #
      # Kestrel__Endpoints__Http__Url is set ANYWAY, and deliberately.  The
      # environment configuration provider is registered after the JSON ones,
      # so this wins over appsettings.Production.json — which means the port
      # this service listens on is stated in this repository rather than
      # inherited from a file inside a tarball.  It also makes the two
      # components independent of each other's appsettings.
      #
      # ── THE BIND ADDRESS IS PER-COMPONENT, AND IT BIT ─────────────────
      #
      # Both components were originally pinned to 127.0.0.1 on the reasoning
      # that "nothing outside the container should reach either".  That is
      # true of the INDEXER and false of the DOWNLOADER, and the difference
      # only shows up once Traefik is in front:
      #
      #   mediathekarr.goclan.org → 502 Bad Gateway
      #
      # Traefik lives in its own container at 10.0.90.12 and dials
      # 10.0.90.13:5007.  A process bound to 127.0.0.1 inside the arr
      # container is not on that address, so the connection is refused and
      # Traefik reports 502.  Measured 2026-08-26; `ss -ltn` inside the
      # container showed `127.0.0.1:5007` while bazarr (6767) and cleanuparr
      # (11011), which work, were on 0.0.0.0.
      #
      # So the downloader binds all interfaces and its exposure is controlled
      # where every other exposure in this container is controlled — the
      # source-restricted firewall list in containers/arr.nix, which admits
      # 5007 from 10.0.90.12 and nothing else.  The INDEXER stays on
      # 127.0.0.1: its only client is Prowlarr, in this same netns, so it
      # gets both the firewall's default-deny AND a loopback bind.
      #
      # --chdir is NOT tidiness.  The downloader serves its setup wizard from
      #   Path.Combine(Directory.GetCurrentDirectory(), "static", "download")
      # — the CURRENT WORKING DIRECTORY, not the content root, so
      # ASPNETCORE_CONTENTROOT does not help.  Without --chdir the process
      # aborts at startup with DirectoryNotFoundException on <cwd>/static/
      # download/ before it binds anything.  Measured 2026-08-26.
      #
      # It is applied to both components so that neither depends on where
      # systemd happened to leave the process.
      postFixup = ''
        wrapProgram $out/bin/${executable} \
          --chdir $out/lib/${pname} \
          --set ASPNETCORE_ENVIRONMENT Production \
          --set Kestrel__Endpoints__Http__Url "${listen}" \
          --prefix PATH : ${
            lib.makeBinPath [
              ffmpeg
              mkvtoolnix-cli
              # `which` IS A RUNTIME DEPENDENCY, and it is not obvious.
              #
              # Measured on ernst 2026-08-26, first deploy: the downloader
              # read its config, initialised, and then aborted with
              #
              #   An error occurred trying to start process 'which' …
              #   No such file or directory
              #   Main process exited, code=dumped, signal=ABRT
              #
              # FfmpegUtils.EnsureFfmpegExistsAsync and its mkvmerge twin do
              # not probe $PATH themselves — they SHELL OUT to `which` via
              # Process.Start and read its stdout.  systemd's unit PATH is
              # coreutils/findutils/gnugrep/gnused/systemd, and `which` is in
              # none of them.
              #
              # THE LOCAL SMOKE TEST HID THIS.  Run by hand it logged
              # "mkvmerge found in PATH" and "ffmpeg found in PATH" — because
              # the interactive shell's PATH had `which` in it.  A smoke test
              # inherits the tester's environment; a unit does not.
              which
            ]
          }
      '';

      meta = {
        inherit description;
        homepage = "https://github.com/PCJones/MediathekArr";
        license = lib.licenses.gpl3Only;
        platforms = [ "x86_64-linux" ];
        mainProgram = executable;
      };
    };
in
{
  indexer = mkComponent {
    pname = "mediathekarr-indexer";
    projectFile = "MediathekArrServer/MediathekArrServer.csproj";
    executable = "MediathekArrServer";
    # LOOPBACK ONLY.  Prowlarr is in the same netns and reaches it on
    # 127.0.0.1; nothing else ever should.  Belt and braces with the
    # firewall, which does not name 5008 either.
    listen = "http://127.0.0.1:5008";
    description = "ARD/ZDF Mediathek as a Newznab indexer for Prowlarr";
  };

  downloader = mkComponent {
    pname = "mediathekarr-downloader";
    projectFile = "MediathekArr/MediathekArrDownloader.csproj";
    executable = "MediathekArrDownloader";
    # ALL INTERFACES, necessarily — Traefik dials it at 10.0.90.13:5007 to
    # serve the setup wizard, and a loopback bind returns 502 Bad Gateway.
    # Exposure is the firewall's job here, exactly as it is for bazarr and
    # cleanuparr: 5007 is admitted from 10.0.90.12 and refused from
    # everything else.
    listen = "http://[::]:5007";
    description = "SABnzbd-shaped downloader and setup wizard for MediathekArr";
  };
}
