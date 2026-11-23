# machines/ernst/yt-audio.nix — YouTube playlists → Audiobookshelf and Navidrome.
#
# THE SHAPE.  An unlisted YouTube playlist is the inbox: "Save → <playlist>"
# in the YouTube app is the whole user interface.  Once a day `yt-audio-import`
# runs yt-dlp over each configured playlist, keeps the audio only, and files it
# straight into the library its playlist names.  The video half of the same
# idea is TubeSync (containers/tubesync.nix), which already does exactly this
# for video, so it is not duplicated here.
#
#   playlist "→ Hörspiel"  →  /srv/audiobooks/library/<Channel>/<Title>/  →  Audiobookshelf
#   playlist "→ Kinder"    →  /srv/audiobooks/kinder/<Channel>/<Title>/   →  Audiobookshelf (Kinder)
#   `add-book <playlist>`  →  /srv/audiobooks/{library,kinder}/<Author>/<Title>/, one book
#   playlist "→ Musik"     →  /srv/media/library/music/_youtube/<Artist>/ →  Navidrome
#   playlist "→ Jellyfin"  →  TubeSync → /srv/media/youtube/video/       →  Jellyfin
#
# WHY NOT A NEXTCLOUD WATCH FOLDER, which was the first idea: the thing you
# have in hand when you find a video is the YouTube app, and a playlist is one
# tap from there.  A watch folder would need the link copied into a file.
#
# WHY NOT TubeSync FOR THE AUDIO TOO.  It can download audio-only, but it only
# writes under its own /downloads (/srv/media/youtube), and neither library
# reads that: Navidrome reads one MusicFolder (bind-mounted RO into its chroot
# by the nixpkgs module) and Audiobookshelf reads /srv/audiobooks, a different
# dataset.  Pointing them at TubeSync's tree means bind mounts into two
# sandboxes plus a second Audiobookshelf library; writing into the libraries
# they already read means neither.
#
# WHY `_youtube/` INSIDE THE MUSIC LIBRARY.  Navidrome 0.64 can hold more than
# one library, but only the default one is declarative; a second is UI state
# AND a path the module does not bind into the chroot.  `_youtube/` sits beside
# `_playlists/` (see sldl-playlists in containers/arr/music.nix) under the same
# leading-underscore convention: not an artist, and Lidarr lists it as an
# unmapped folder exactly as it already lists `_playlists/`.
#
# THE PLAYLIST LIST IS NOT IN THIS REPO.  The repo is public, and an unlisted
# playlist is private only for as long as its link is.  It lives in
# ${stateDir}/playlists on ernst — see docs/guides/youtube.md for the format
# and the one command that writes it.
{
  lib,
  pkgs,
  ...
}: let
  stateDir = "/srv/state/yt-audio";
  absRoot = "/srv/audiobooks"; # library/ and kinder/ — the two Audiobookshelf libraries
  musicLib = "/srv/media/library/music";

  ytAudioImport = pkgs.writeShellApplication {
    name = "yt-audio-import";
    # yt-dlp from nixpkgs is already wrapped with ffmpeg (extract, embed) and
    # deno (current yt-dlp needs a JS runtime to solve YouTube's challenges).
    runtimeInputs = with pkgs; [yt-dlp coreutils findutils gnugrep systemd];
    text = ''
      STATE=${stateDir}
      CONF=${stateDir}/playlists
      BOOKS=${stateDir}/books
      ABS_ROOT=${absRoot}
      MUSIC_ROOT=${musicLib}/_youtube

      ${builtins.readFile ./yt-audio-import.sh}
    '';
  };
in {
  environment.systemPackages = [ytAudioImport];

  # By hand: `systemctl start --no-block yt-audio-import`, then
  # `journalctl -fu yt-audio-import`.  Without --no-block the command waits
  # for the whole download, which looks like a hang.
  systemd.services.yt-audio-import = {
    description = "Download new videos from the YouTube audio playlists into Audiobookshelf and Navidrome";
    wants = ["network-online.target"];
    after = ["network-online.target" "srv-media.mount" "srv-audiobooks.mount" "srv-state.mount"];
    # yt-dlp's own state; deno also wants a writable home for its cache.
    environment = {
      HOME = stateDir;
      XDG_CACHE_HOME = "${stateDir}/cache";
    };
    serviceConfig = {
      Type = "oneshot";
      # `+`: runs outside the sandbox below, so the state directory exists
      # before ReadWritePaths needs it.  Not tmpfiles: a `d` rule can run
      # before zdata/state is mounted and create the directory underneath the
      # mount — the hazard courses.nix's perms unit exists for.
      ExecStartPre = "+${pkgs.coreutils}/bin/install -d -m 0750 -g media ${stateDir}";
      ExecStart = lib.getExe ytAudioImport;
      # Root with the media group, the sldl-playlists arrangement: both
      # libraries are 2770 root:media, so the group grants write and the
      # setgid bit keeps it on everything created below them.  UMask 0007
      # gives 0660 files and 2770 directories — the libraries' own modes.
      Group = "media";
      UMask = "0007";
      ProtectSystem = "strict";
      ReadWritePaths = [stateDir "${absRoot}/library" "${absRoot}/kinder" musicLib];
      PrivateTmp = true;
      NoNewPrivileges = true;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.yt-audio-import = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "05:30";
      Persistent = true;
    };
  };
}
