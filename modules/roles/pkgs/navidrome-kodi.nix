# modules/roles/pkgs/navidrome-kodi.nix
#
# The Navidrome add-on for Kodi, so the living-room TV can play the music
# library ernst already serves.  There is nothing in nixpkgs to use instead:
# `kodiPackages` has no Navidrome add-on and no Subsonic client of any name —
# checked by filtering the whole attribute set, not by looking for the obvious
# spelling.
#
# ── THE SERVER IS ALREADY HERE, WHICH IS MOST OF WHY THIS IS CHEAP ──────────
#
#   Navidrome runs inside the `arr` container on ernst, port 4533, and answers
#   at https://navidrome.goclan.org.  It is in `appApiHosts` (forward-auth is
#   permanently off it — the Subsonic API authenticates with a salted token in
#   query parameters and cannot follow a 302 to a login portal) and in
#   `wanExposed`.  So this add-on needs no Traefik change, no UDM-Pro
#   inter-VLAN rule, and no VPN — unlike `pvr-hts`, which needed two firewalls.
#   See docs/guides/navidrome-clients.md, which this add-on joins as the third
#   deployed client.
#
#   USE THE TRAEFIK NAME, NOT 10.0.90.13:4533, for the same reason the Immich
#   add-on uses photos.goclan.org: the hostname works identically on the LAN
#   and off it, and it is the address every other client in that guide already
#   uses.
#
# ── WHICH ADD-ON, AND WHAT IT COSTS ─────────────────────────────────────────
#
#   colinfredynand/plugin.kodi.navidrome, 34 stars, GPL-3.0, not archived,
#   default branch `main`.  There is no established alternative: the Subsonic
#   corner of Kodi is thin, and this is the one that is maintained and that
#   targets Navidrome specifically rather than Subsonic-in-general.
#
#   STATED UP FRONT, as with the Immich add-on: this is third-party code with
#   no binary cache and no maintainer relationship, and we own it until
#   somebody packages a better one.  The containment is the same and is the
#   reason it is acceptable — a break here loses music on the TV.  Navidrome
#   itself, the library on disk, Music Assistant, Supersonic and sonic-tui are
#   all untouched by it.
#
# ── PINNED TO A TAG, AND THE TAG IS ESSENTIALLY THE TIP ─────────────────────
#
#   `v0.6.0`, commit 306096c, published 2026-09-13; the repository's
#   `pushed_at` is 2026-09-14, so the tag is one day behind the default
#   branch's head.  Pinning the tag gains a name that means something and
#   loses nothing anyone has described.
#
#   NOTE THE ANNOTATED TAG.  `git/ref/tags/v0.6.0` answers with the TAG
#   OBJECT's sha (b2d2e91…), not the commit's.  Dereference it — `git/tags/…`
#   — or the pin names an object `fetchFromGitHub` will not give you the tree
#   of.  The rev below is the commit.
#
#   The upstream release also ships a ready-made `plugin.kodi.navidrome.zip`
#   whose internal directory is already named for the add-on id, so it
#   installs by hand through Kodi's "Install from zip file".  That is the
#   right route for a machine this repo does not manage.  It is the wrong one
#   here: ernst rolls back `/home/go` on every boot, so a hand-installed
#   add-on would have to be re-installed from the sofa after each reboot
#   unless it were declared — which is what this file does.
#
# ── NO DEPENDENCIES, VERIFIED BY READING IT ─────────────────────────────────
#
#   `addon.xml` requires only `xbmc.python` 3.0.0.  Every import across
#   `default.py`, `service.py`, `lib/navidrome_api.py` and `lib/vfs.py` is
#   either standard library (hashlib, json, random, ssl, string, sys, time,
#   urllib.*) or supplied by Kodi (xbmc, xbmcaddon, xbmcgui, xbmcplugin,
#   xbmcvfs).  Nothing wants `requests`.  So there is no
#   `extraRuntimeDependencies` here and none is missing.
#
# ── IT IS A SERVICE AS WELL AS A PLUGIN ─────────────────────────────────────
#
#   `addon.xml` declares two extension points: `xbmc.python.pluginsource`
#   (default.py) and `xbmc.service` (service.py).  The service half is what
#   scrobbles plays back to Navidrome and maintains "now playing"; it starts
#   with Kodi rather than when the add-on is opened.  Nothing to configure
#   here — noted so that a future reader does not mistake a background python
#   process named for this add-on for something that escaped.
#
# ── THE ID IS THE ODD ONE, AND IT IS NOT A TYPO ─────────────────────────────
#
#   `namespace` MUST be `plugin.kodi.navidrome`, which is upstream's `id`,
#   even though the add-on `<provides>audio</provides>` and every add-on in
#   Kodi's own repository that provides audio is called `plugin.audio.*`.
#   Kodi keys the installed directory, the settings file and every
#   `plugin://` URL on the id — and this add-on's own "Clear Offline Cache"
#   button hardcodes `plugin://plugin.kodi.navidrome/?action=clear_cache` in
#   resources/settings.xml.  "Correcting" the namespace to plugin.audio.*
#   would produce an add-on Kodi installs, lists under Music, and cannot
#   launch.
#
# ── CONFIGURATION IS RUNTIME STATE AND CANNOT BE SET HERE ───────────────────
#
#   Kodi keeps add-on settings under ~/.kodi/userdata/addon_data, which
#   `guiSettings` does not reach — that option writes guisettings.xml, which
#   is Kodi's own settings and not any add-on's.  So this is the same shape as
#   `youtube`'s API key, `pvr-hts`'s server address and the Immich add-on's
#   URL: installed and INERT until someone opens its settings.  Three values,
#   in Settings -> Add-ons -> Navidrome:
#
#     server_url   https://navidrome.goclan.org     (default is
#                  http://localhost:4533, which is wrong here and fails
#                  silently-ish rather than loudly)
#     username     a Navidrome account
#     password     THE PASSWORD ITSELF, not a token.  Subsonic builds a fresh
#                  salted token per request from the password, so no client
#                  can hold a token instead — see the guide.
#
#   `verify_ssl` defaults to true and should STAY true: navidrome.goclan.org
#   is a real Traefik certificate, not a self-signed one, so the
#   `ca_cert_path` setting v0.6.0 added has no use here.
#
#   TURN `enable_offline_cache` OFF.  It defaults to ON at 2000 MB, and on
#   this machine it is pure waste: the Kodi client and the Navidrome server
#   are the SAME BOX, so the cache would copy ernst's music onto ernst over
#   its own loopback-shaped path.  Worse, it lands in
#   ~/.kodi/userdata/addon_data, `.kodi` is in `persistenceDirectories`, and
#   /persist is on the mirrored 960 GB zroot — so it is 2 GB of the system
#   pool spent duplicating a library that is already on the bulk pool.  The
#   setting exists for someone taking a laptop off the network; nobody is
#   taking the living room anywhere.
{
  lib,
  buildKodiAddon,
  fetchFromGitHub,
}:

buildKodiAddon rec {
  pname = "navidrome";
  namespace = "plugin.kodi.navidrome";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "colinfredynand";
    repo = "plugin.kodi.navidrome";
    rev = "306096c279dece572b63f6d93a23cd7674748a08"; # tag v0.6.0, dereferenced
    hash = "sha256-V46ftZatH7/AfV8X9tiGFmaZIU+FzUbVA6xQ6hcU2BQ=";
  };

  meta = {
    homepage = "https://github.com/colinfredynand/plugin.kodi.navidrome";
    description = "Browse and play a Navidrome music library from Kodi";
    longDescription = ''
      Unofficial Kodi client for Navidrome over the Subsonic API: artists,
      albums, playlists and search, with scrobbling and "now playing" from a
      background service. Not endorsed by the Navidrome project.
    '';
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}
