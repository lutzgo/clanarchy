# machines/ernst/containers/arr/users.nix
#
# The container's users and groups — twenty-two numeric ids that are also
# numbers on zdata, because nspawn passes them through unmapped.
#
# ── THIS FILE CO-DEFINES containers.arr ─────────────────────────────────────
#
# It creates no container; see ./video.nix for the mechanism. It is separate
# from ./common.nix because "which service is in `media` and why" is a
# question with twenty-two answers, and none of them is needed to read the
# container's own definition.
#
# THE ids THEMSELVES ARE NOT HERE: they are rows in
# machines/ernst/allocations.nix, read through ./ids.nix. This file decides
# GROUP MEMBERSHIP, which is what makes the *arr hardlink domain work.
{ config, lib, pkgs, ... }:
let
  ids = import ./ids.nix;

  # The old flat names — see ./video.nix.
  sonarrUid = ids.uids.sonarr;
  radarrUid = ids.uids.radarr;
  prowlarrUid = ids.uids.prowlarr;
  bazarrUid = ids.uids.bazarr;
  cleanuparrUid = ids.uids.cleanuparr;
  mediathekarrUid = ids.uids.mediathekarr;
  jellyseerrUid = ids.uids.jellyseerr;
  janitorrUid = ids.uids.janitorr;
  scraparrUid = ids.uids.scraparr;
  lidarrUid = ids.uids.lidarr;
  soularrUid = ids.uids.soularr;
  kapowarrUid = ids.uids.kapowarr;
  questarrUid = ids.uids.questarr;
  audiobookshelfUid = ids.uids.audiobookshelf;
  binderyUid = ids.uids.bindery;
  komgaUid = ids.uids.komga;
  navidromeUid = ids.uids.navidrome;
  prowlarrGid = ids.gids.prowlarr;
  jellyseerrGid = ids.gids.jellyseerr;
  scraparrGid = ids.gids.scraparr;
  questarrGid = ids.gids.questarr;
  mediaGid = ids.gids.media;
in
{
  containers.arr.config = { config, pkgs, lib, ... }: {
  ##########################################################################
  # Users.  Numeric ids are the interface across the nspawn boundary.
  ##########################################################################

  # gid 3000 — must match the host numerically or every file these services
  # write lands in a group the host cannot name.  Fixed on the host in
  # containers/jellyfin.nix.
  users.groups.media = { gid = mediaGid; };

  # Sonarr and Radarr: `media` as the PRIMARY group.  The upstream modules
  # create users.users.{sonarr,radarr} only when `user` is left at its
  # default name, and set uid from config.ids.uids.* (274 / 275).  We keep
  # the default names — so the module still creates the accounts and we do
  # not have to restate `home` — and override just the uid.
  #
  # mkForce is required (the module's definition is a plain one), and
  # isSystemUser must come with it: NixOS asserts that a user is either
  # isNormalUser or "effectively a system user", and the latter is inferred
  # from uid < 1000.  3002 is not, so the inference stops working the
  # moment the uid is overridden.  Without isSystemUser this fails
  # evaluation with "Exactly one of ... isSystemUser and ... isNormalUser
  # must be set", which reads like a typo and is not one.
  users.users.sonarr = {
    isSystemUser = true;
    uid          = lib.mkForce sonarrUid;
  };
  users.users.radarr = {
    isSystemUser = true;
    uid          = lib.mkForce radarrUid;
  };

  # Prowlarr: its own user and group, declared in full because the upstream
  # module declares none — see the DynamicUser note under services.prowlarr
  # below.  No media membership: it never touches a file under /srv/media.
  users.users.prowlarr = {
    isSystemUser = true;
    uid          = prowlarrUid;
    group        = "prowlarr";
    home         = "/var/lib/prowlarr";
  };
  users.groups.prowlarr = { gid = prowlarrGid; };

  # ── M12 users ─────────────────────────────────────────────────────────
  #
  # BAZARR takes the same shape as sonarr/radarr and for the same reason:
  # it writes .srt sidecars NEXT TO THE MEDIA, so `media` must be its
  # PRIMARY group, not a supplementary one.  The header's PrivateUsers
  # explanation is the reason and is not re-derived here.
  #
  # Simpler than sonarr/radarr in one respect, though: the upstream module
  # declares users.users.bazarr WITHOUT a uid (it leaves the allocation to
  # NixOS), so setting one here is a new definition of an unset option and
  # needs no mkForce.  The module also declares the `bazarr` GROUP only
  # when services.bazarr.group == "bazarr"; it is "media" below, so no
  # stray group is created.
  users.users.bazarr.uid = bazarrUid;

  # CLEANUPARR and MEDIATHEKARR are declared in full — there is no upstream
  # module for either, so nothing else creates them.
  #
  # Both take `media` as PRIMARY, and for once the reason is not
  # PrivateUsers (neither unit sets it):
  #
  #   cleanuparr    DELETES files under /srv/media.  Removing a directory
  #                 entry needs write on the PARENT directory, and those
  #                 are 2770 root:media — so group membership is the whole
  #                 of its access, and a supplementary membership squashed
  #                 by some future hardening directive would present as a
  #                 cleaner that silently cleans nothing.
  #   mediathekarr  WRITES video into the download tree and then remuxes
  #                 it in place.
  #
  # `home` points at each service's state directory so that anything
  # reaching for $HOME lands somewhere writable rather than at /.
  users.users.cleanuparr = {
    isSystemUser = true;
    uid          = cleanuparrUid;
    group        = "media";
    home         = "/var/lib/cleanuparr";
  };
  users.users.mediathekarr = {
    isSystemUser = true;
    uid          = mediathekarrUid;
    group        = "media";
    home         = "/var/lib/mediathekarr";
  };

  # ── M13 users ─────────────────────────────────────────────────────────
  #
  # JELLYSEERR is declared in full even though `services.seerr` exists,
  # because that module creates NO user at all — it runs DynamicUser and
  # therefore has nothing to name.  Turning DynamicUser off (see its block)
  # means this file owns the account outright.
  #
  # OWN GROUP, NO MEDIA.  It is the prowlarr shape and for the prowlarr
  # reason: Jellyseerr talks to Sonarr, Radarr and Jellyfin over REST and
  # never opens a file under /srv/media.  Giving it gid 3000 "so it matches
  # the others" would be a strictly larger blast radius for no capability —
  # and this is the one service in the container that the whole household
  # can reach without authenticating to Authelia, so it is the last one
  # that should hold a handle to 47 TB.
  users.users.jellyseerr = {
    isSystemUser = true;
    uid          = jellyseerrUid;
    group        = "jellyseerr";
    home         = "/var/lib/seerr";
  };
  users.groups.jellyseerr = { gid = jellyseerrGid; };

  # JANITORR takes `media` as PRIMARY, and here the reason IS the one the
  # cleanuparr block dismisses: it deletes files it does not own.  Removing
  # a directory entry needs write on the PARENT directory, and those are
  # 2770 root:media — so group membership is the whole of its access.
  #
  # It also CREATES: the "Leaving Soon" symlink tree under
  # /srv/media/leaving-soon, which Jellyfin reads as an extra library.
  users.users.janitorr = {
    isSystemUser = true;
    uid          = janitorrUid;
    group        = "media";
    home         = "/var/lib/janitorr";
  };

  # SCRAPARR: own group, no media.  It reads REST APIs and serves
  # /metrics; it has no reason to be able to name a file in the library.
  users.users.scraparr = {
    isSystemUser = true;
    uid          = scraparrUid;
    group        = "scraparr";
    home         = "/var/empty";
  };
  users.groups.scraparr = { gid = scraparrGid; };

  # ── M14 users ─────────────────────────────────────────────────────────
  #
  # LIDARR takes the sonarr/radarr shape exactly, mkForce and all: the
  # servarr module declares users.users.lidarr WITH a uid, taken from
  # config.ids.uids.lidarr, so this is an override of an existing plain
  # definition and not a new one.  isSystemUser must come with it for the
  # reason the sonarr block gives — 3017 is not < 1000, so NixOS stops
  # inferring "effectively a system user" and asserts.
  #
  # media PRIMARY, and here the PrivateUsers reason does NOT apply: unlike
  # sonarr's and radarr's, LIDARR'S UPSTREAM UNIT HAS NO HARDENING AT ALL
  # (see its service block below).  It is media-primary because it must
  # hardlink out of slskd's download tree, and that access is entirely its
  # group membership — the same argument the cleanuparr block makes.
  users.users.lidarr = {
    isSystemUser = true;
    uid          = lib.mkForce lidarrUid;
  };

  # SOULARR, KAPOWARR and AUDIOBOOKSHELF are declared in full where nothing
  # else creates them, and `home` points at each one's state directory so
  # anything reaching for $HOME lands somewhere writable rather than at /.
  #
  # SOULARR IS media PRIMARY, AND THAT IS NOT OBVIOUS.  It looks like a
  # pure REST client — it drives Lidarr and slskd over HTTP — which would
  # make it the prowlarr shape, own group and no media.  It is not: it
  # reads ID3 tags out of the downloaded files with `music-tag` to decide
  # whether a release actually matches, and it moves rejected downloads
  # aside.  Both need real access to slskd's tree under /srv/media.
  users.users.soularr = {
    isSystemUser = true;
    uid          = soularrUid;
    group        = "media";
    home         = "/var/lib/soularr";
  };

  users.users.kapowarr = {
    isSystemUser = true;
    uid          = kapowarrUid;
    group        = "media";
    home         = "/var/lib/kapowarr";
  };

  # M17 — BINDERY: media PRIMARY, the kapowarr shape and for the kapowarr
  # reason.  It downloads into /srv/media/torrents/books and files into
  # /srv/media/library/books, and every file it creates must stay
  # manageable by the group (UMask 0002 in its unit is the other half).
  users.users.bindery = {
    isSystemUser = true;
    uid          = binderyUid;
    group        = "media";
    home         = "/var/lib/bindery";
  };

  # AUDIOBOOKSHELF is media PRIMARY for a tree that is NOT /srv/media, and
  # the distinction is worth stating so nobody "fixes" it later.
  #
  # Its library is /srv/audiobooks, a separate dataset (see the header of
  # the let-binding above).  That tree is 2770 root:media, so `media` is
  # what gets it write access there — and it is shared with Storyteller,
  # which writes synced EPUB3s into the same tree from a different
  # container as a different uid.  A private `audiobookshelf` group would
  # mean the two services could not see each other's output, which is the
  # entire reason they are on one dataset.
  #
  # The module declares users.users.audiobookshelf without a uid (leaving
  # allocation to NixOS), so setting one needs no mkForce — the bazarr
  # situation.  It declares the `audiobookshelf` GROUP only when group ==
  # "audiobookshelf"; it is "media" below, so no stray group appears.
  users.users.audiobookshelf.uid = audiobookshelfUid;

  # ── 2026-09-08: KOMGA and NAVIDROME.  media PRIMARY, READ-ONLY BY UNIT ─
  #
  # `media` because the library directories are 2770 root:media, i.e. mode
  # 0 for world — there is no way to read them from outside the group, so
  # group membership is not optional.
  #
  # THAT GRANT IS WRITE, AND IT IS TAKEN BACK PER UNIT.  2770 means group
  # write, so `media` alone would let either of these modify the library
  # the *arr manage.  Neither should ever do that: Komga can delete book
  # files from its UI, and Navidrome is explicitly required not to touch
  # the tree Lidarr owns.  What enforces it is a read-only bind in each
  # unit's own mount namespace (`BindReadOnlyPaths` / `ReadOnlyPaths`
  # below), which the process cannot undo — not the group, and not a
  # setting inside the application that a future admin could toggle.
  #
  # Both modules declare their user WITHOUT a uid, so pinning one here is
  # a merge and needs no mkForce (the bazarr/audiobookshelf situation, not
  # the sonarr one).  Both declare their private group only when
  # `group == "<name>"`; it is "media" for both, so no stray group appears.
  users.users.komga = {
    isSystemUser = true;
    uid          = komgaUid;
    group        = "media";
    home         = "/var/lib/komga";
  };
  users.users.navidrome = {
    isSystemUser = true;
    uid          = navidromeUid;
    group        = "media";
    home         = "/var/lib/navidrome";
  };

  # QUESTARR: own group, no media — the prowlarr shape.  It talks to IGDB
  # and Prowlarr over REST and writes only to /srv/games/questarr, which is
  # a different dataset and not part of the hardlink domain.  It has no
  # reason to be able to name a file in the media library.
  users.users.questarr = {
    isSystemUser = true;
    uid          = questarrUid;
    group        = "questarr";
    home         = "/var/lib/questarr";
  };
  users.groups.questarr = { gid = questarrGid; };
  };
}
