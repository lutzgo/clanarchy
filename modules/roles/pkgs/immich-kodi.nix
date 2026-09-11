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
#     immich_url   https://photos.goclan.org     (note: THROUGH TRAEFIK — see
#                  containers/immich.nix's "THE KODI PATH" for why the add-on
#                  must not be pointed at 10.0.90.25:2283)
#     api_key      minted in Immich under Account Settings -> API Keys
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
