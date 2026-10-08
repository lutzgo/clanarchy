# machines/ernst/courses.nix — the Courses library and the `course-import` tool.
#
# WHAT THIS IS FOR.  Video courses bought from a teaching platform (Proko, so
# far) watched in Jellyfin as a TV show, with metadata that is written locally
# and never looked up.
#
# WHY IT IS NOT IN THE TV-SHOWS LIBRARY, which is the obvious place to put it:
# Jellyfin's metadata settings are PER LIBRARY, not per show.  A course has no
# TheTVDB entry and never will, so every scan of a library it sits in produces
# a failed identification and, worse, an occasional wrong match against a real
# series with a similar name.  The only switch that stops that is "disable
# internet metadata", and in TV-Shows that switch would apply to all 155 real
# series as well.  A second library is the only scope at which "local NFO only"
# can be expressed.
#
# WHY SONARR IS NOT INVOLVED.  Sonarr cannot hold a series that is not on
# TheTVDB — there is no manual-entry path and no alternative metadata source;
# upstream's own answer is "add it to TVDB first".  Nothing here is or can be
# *arr-managed, which is also why the library root is a sibling of tvshows/
# rather than a directory inside it: Sonarr's root folder scan would otherwise
# list every course as an unmapped folder forever.
#
# THE LAYOUT, decided per course by its manifest:
#
#   /srv/media/library/courses/
#     Proko - Drawing Basics/
#       tvshow.nfo
#       Season 01/                                  <- chapter "Getting Started"
#         season.nfo
#         Proko - Drawing Basics - S01E01 - Learning How to Draw.mp4
#         Proko - Drawing Basics - S01E01 - Learning How to Draw.nfo
#         Proko - Drawing Basics - S01E01 - Learning How to Draw.en.srt
#         Proko - Drawing Basics - S01E01 - Learning How to Draw.txt
#
# One show per COURSE and one season per CHAPTER.  The alternative — one show
# with a season per course — was rejected because Drawing Basics alone is 185
# lessons, and a flat 185-episode season loses the chapter structure that is
# the only navigation the course actually has.
#
# See docs/guides/courses.md for the ingest workflow and the Jellyfin library
# settings, which are UI state and NOT declarative.
{ pkgs, ... }:

let
  # Must agree with containers/jellyfin.nix (mediaGid) and containers/arr.nix.
  # The library is 2770 root:media like every other directory under
  # /srv/media/library, so Jellyfin (uid 964, member of media) can read it.
  mediaGid = 3000;

  libraryDir = "/srv/media/library/courses";

  # Ingest is a sibling of cwa's under /srv/media/ingest, which puts it on the
  # SAME dataset as the library.  That is load-bearing: course-import moves
  # files rather than copying them, and a move within one dataset is a rename —
  # instant, and with no window in which a half-written 3 GB lesson is visible
  # to a Jellyfin scan of the library.
  ingestDir = "/srv/media/ingest/courses";

  # One JSON file per course, named for the course slug.  Adding a course is
  # adding a file here; adding a chapter is editing one.  Nothing in this
  # module needs to change for either.
  manifestDir = ./courses;
in
{
  systemd.tmpfiles.rules = [
    "d ${libraryDir} 2770 root ${toString mediaGid} -"
    "d ${ingestDir}  0750 root ${toString mediaGid} -"
  ];

  # The tmpfiles rules above are ordered against srv-media.mount only
  # IMPLICITLY, via local-fs.target.  That is the hazard containers/jellyfin.nix
  # keeps its own `jellyfin-library-perms` backstop for: a `d` rule that runs
  # before zdata/media is mounted creates the directory on the underlying root
  # filesystem, where the mount then hides it — so the library silently does not
  # exist inside the dataset, and the bind mount into the container resolves to
  # an empty directory on zroot.  This unit is the same backstop for the two
  # paths this module owns, and must never be edited to disagree with the rules
  # above.  Idempotent: chown/chmod on an already-correct directory is a no-op.
  systemd.services.courses-library-perms = {
    description = "Create and permission the Jellyfin Courses library and ingest directories";
    wantedBy    = [ "multi-user.target" ];
    before      = [ "container@jellyfin.service" ];
    after       = [ "srv-media.mount" ];
    requires    = [ "srv-media.mount" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.coreutils}/bin/mkdir -p ${libraryDir} ${ingestDir}"
        "${pkgs.coreutils}/bin/chown root:${toString mediaGid} ${libraryDir} ${ingestDir}"
        "${pkgs.coreutils}/bin/chmod 2770 ${libraryDir}"
        "${pkgs.coreutils}/bin/chmod 0750 ${ingestDir}"
      ];
    };
  };

  ##############################################################################
  # `course-import` — filing a downloaded batch of lessons into the library.
  #
  # This lives here, rather than in a script pasted into the guide, for the same
  # reason `rom-import` lives in containers/romm.nix: the constants below are
  # DEFINED in this file, and a copy of them in a document is a copy that goes
  # stale silently.  The tool is generated from the same `let` bindings the
  # tmpfiles rules and the Jellyfin bind mount are, so it cannot disagree with
  # the deployment.
  ##############################################################################
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "course-import";

      runtimeInputs = with pkgs; [
        coreutils findutils gnused gawk
        jq               # the manifests
        ffmpeg-headless  # ffprobe, for <runtime> in the episode NFO
      ];

      text = ''
        LIB=${libraryDir}
        INGEST=${ingestDir}
        MANIFESTS=${manifestDir}
        MEDIA_GID=${toString mediaGid}

        ${builtins.readFile ./course-import.sh}
      '';
    })
  ];
}
