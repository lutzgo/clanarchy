# modules/roles/pkgs/immich-kodi.nix
#
# The Immich add-on for Kodi, so the living-room TV can browse the photo
# library ernst serves (M22).  There is nothing in nixpkgs to use instead:
# `kodiPackages` has no Immich add-on at any channel, and Immich ships no
# first-party TV client for anything but Android TV.
#
# ── WHICH ADD-ON, AND WHY THIS ONE ──────────────────────────────────────────
#
#   Three unofficial ones exist and none is endorsed by Immich:
#
#     vladd11/immich-kodi              a browsing plugin — albums, timeline,
#                                      slideshow.  THIS ONE, by lgo's choice.
#     don-philipe/plugin.image.immich   the other browsing plugin; its README
#                                      warns it may not keep up with Immich's
#                                      API, and it is installed by zipping the
#                                      repository by hand.
#     screensaver.immich.slideshow      a SCREENSAVER, not a browser.  It shows
#                                      pictures when nobody is watching, which
#                                      is the opposite of the requirement.
#
#   WHAT THAT COSTS, STATED UP FRONT.  This is third-party code we now own
#   until somebody packages a better one: Immich's API moves fast, the add-on's
#   own version string has never left 1.0.0, and there is no binary cache and
#   no maintainer relationship.  If a future Immich bump breaks it, the failure
#   is a photo browser on the TV, not the library — the server, the phones, the
#   web UI and the import are all untouched by it.  That containment is the
#   whole reason it is acceptable to ship an unofficial add-on here at all.
#
# ── PINNED TO A TAG, AND THE TAG IS THE TIP ─────────────────────────────────
#
#   `prerelease-7`, commit a325601, published 2026-03-01.  Checked the same day
#   this was written: the repository's `pushed_at` is that same timestamp, so
#   the tag IS the default branch's head — pinning it costs nothing against
#   `main` and gains a name that means something.  66 stars, MIT, not archived.
#
#   The upstream default branch is `main`, not `master`.  Noted because
#   `raw.githubusercontent.com/.../master/...` also answers, so a careless
#   update can end up pinning a stale branch that merely exists.
#
# ── NO DEPENDENCIES, VERIFIED BY READING IT ─────────────────────────────────
#
#   `addon.xml` requires only `xbmc.python` 3.0.0, and the sources import
#   `http.client`, `urllib.parse`, `datetime` and Kodi's own xbmc* modules —
#   all standard library or supplied by Kodi.  `iso8601.py` is vendored.  So
#   there is no `extraRuntimeDependencies` here and none is missing: nothing
#   needs `requests`, and a Python environment does not have to be assembled.
#
# ── THE ID IS NOT WHAT THE FILE IS CALLED ───────────────────────────────────
#
#   `namespace` MUST be `plugin.video.immich`, which is the `id` in upstream's
#   addon.xml, even though the add-on `<provides>image</provides>` and appears
#   under Pictures rather than Videos in Kodi's UI.  Upstream named it that way
#   and Kodi keys the installed directory, the settings file and every
#   `plugin://` URL on the id — so "correcting" it to plugin.image.immich would
#   produce an add-on Kodi installs and can never launch.
#
# ── CONFIGURATION IS RUNTIME STATE AND CANNOT BE SET HERE ───────────────────
#
#   Two settings, both in `resources/settings.xml` and both empty by default:
#
#     immich_url   http://127.0.0.1:2283   on ernst — the loopback proxy in
#                  machines/ernst/immich-kodi-proxy.nix, which forwards to
#                  https://photos.goclan.org THROUGH TRAEFIK (see
#                  containers/immich.nix's "THE KODI PATH" for why it must not
#                  be 10.0.90.25:2283)
#     api_key      EMPTY.  The proxy adds the real key.  The add-on sends it
#                  as a `|x-api-key=` URL suffix, which Kodi writes into
#                  kodi.log and Textures13.db — so a key set here leaks into
#                  every log and every snapshot.  Measured 2026-11-07.
#
#   Kodi keeps add-on settings in ~/.kodi, which this repo does not manage, so
#   this is the same shape as the `youtube` add-on's API key and `pvr-hts`'s
#   server address: installed and INERT until someone opens its settings.  The
#   add-on itself knows — with no URL set it opens its own settings dialog on
#   first launch rather than failing silently.
#
#   Two further settings exist and their defaults are the right ones:
#   `shared_only` (false — browse the whole library, not just shared albums)
#   and `asset_name`.
{
  lib,
  buildKodiAddon,
  fetchFromGitHub,
}:
buildKodiAddon rec {
  pname = "immich";
  namespace = "plugin.video.immich";
  version = "1.0.0-prerelease-7";

  src = fetchFromGitHub {
    owner = "vladd11";
    repo = "immich-kodi";
    rev = "a325601e54ca89b5d92b2cf8503aab4240f2565a";
    hash = "sha256-BgfgLpDySP+Os7kf2cxks/+rfdi2djDOEwnltGmKoEY=";
  };

  # ── IMMICH 3 BROKE THE ALBUM LIST, AND THIS IS THE CONTAINMENT CASHED IN ──
  #
  #   The header predicted it: "If a future Immich bump breaks it, the failure
  #   is a photo browser on the TV".  MEASURED 2026-11-03 against ernst's
  #   Immich 3.3.5: GET /api/albums returns 594 albums and NONE carries
  #   `ownerId`, `owner` or `assets`.  models.py declares every Album field
  #   required, so the first album raised
  #
  #     TypeError: Album.__init__() missing 3 required positional
  #                arguments: 'ownerId', 'owner', and 'assets'
  #
  #   and Kodi showed an error instead of the album list.  Upstream #38 is the
  #   same crash from another direction (an empty album has no startDate /
  #   endDate / lastModifiedAssetTimestamp) and is still open; upstream has
  #   not moved since this pin.
  #
  #   The patch makes every Album field optional except the two the add-on
  #   reads unconditionally, `albumName` and `id` — album.py touches only
  #   those plus `startDate` and `albumThumbnailAssetId`, both already behind
  #   an `if`.  Checked against the live response: unpatched fails on it with
  #   the error above, patched parses all 594.
  #
  #   DROP IT when bumping past a release that fixes upstream #38, after
  #   checking the new models.py — `patches` failing to apply is the reminder.
  #
  # ── AND IT BROKE THE PHOTOS THEMSELVES: TIMELINE MONTHS AND ALBUM CONTENTS ─
  #
  #   MEASURED 2026-11-06 against Immich 3.3.5, the add-on run outside Kodi
  #   with stubbed xbmc modules:
  #
  #     timeline month   TypeError: ItemAsset.__init__() missing 'deviceAssetId'
  #                      and 'deviceId' — Immich 3 no longer sends them
  #     open an album    KeyError: 'assets' — GET /api/albums/{id} no longer
  #                      carries the album's contents
  #
  #   The second patch makes every ItemAsset field optional except `id` (the
  #   add-on reads id, type, the dates, originalFileName, originalMimeType and
  #   exifInfo.dateTimeOriginal, and exifInfo now defaults to an empty one), and
  #   fetches an album's contents from POST /api/search/metadata with
  #   `albumIds`, paged at 1000.  Patched, the same run listed 2324 of 2324,
  #   2275 of 2275 and 14 of 14 album assets and every asset of three months.
  #
  # ── TIMELINE ENTRIES ARE MONTHS, AND NOW SAY SO ────────────────────────────
  #
  #   Each timeline entry is a MONTH bucket, labelled upstream with the month's
  #   first day ("01.11.2026"), which reads as "nothing newer than the 1st".
  #   The third patch labels it "November 2026" from Kodi's own month strings
  #   (#21-#32, checked in Kodi 21.3's strings.po), so it follows the UI
  #   language.
  patches = [
    ./immich-kodi-immich3-album.patch
    ./immich-kodi-immich3-assets.patch
    ./immich-kodi-month-labels.patch
  ];

  meta = {
    homepage = "https://github.com/vladd11/immich-kodi";
    description = "Browse an Immich photo library from Kodi";
    longDescription = ''
      Unofficial Kodi client for Immich: albums, timeline and slideshow, over
      Immich's REST API with an API key. Not endorsed by the Immich project.
    '';
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
