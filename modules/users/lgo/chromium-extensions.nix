# lgo's ungoogled-chromium extensions: ONE list, read by both mechanisms.
#
#   modules/users/lgo/browsers.nix   the chromium-crx user service, which
#                                    downloads each CRX and points Chromium
#                                    at the local file (the one that works)
#   modules/users/lgo.nix            chromiumFirstRunTabs, the first-run
#                                    install prompts
#
# These two used to carry separate lists and had drifted (SideTab Pro was in
# one only).  A new entry goes here and nowhere else.
#
# `crx` overrides where the file comes from; the default is the Web Store's
# update endpoint, which redirects to the current CRX.
{
  # `version` is the browser's: the Web Store picks the newest CRX whose
  # minimum_chrome_version it satisfies.
  webStore = version: id:
    "https://clients2.google.com/service/update2/crx"
    + "?response=redirect&acceptformat=crx2,crx3"
    + "&prodversion=${version}"
    + "&x=id%3D${id}%26uc";

  list = [
    {
      # Restores the Web Store's install button in ungoogled-chromium, and
      # updates every installed extension.  Not on the Web Store itself.
      # The ID is the one its CRX's key produces.  This list used to carry
      # cinhimbnkkaeohfgghhklpknlkffjgod, which Chromium rejects: "Expected
      # ID cinhimbnk…, but ID was ocaahdebb…" (measured 2026-11-13).
      id = "ocaahdebbfolfmndjeplogmgcagdmblk";
      name = "chromium-web-store";
      crx = "https://github.com/NeverDecaf/chromium-web-store/releases/latest/download/Chromium.Web.Store.crx";
    }
    {
      # uBlock Origin LITE, not uBlock Origin.  Measured 2026-11-13: the Web
      # Store answers uBlock Origin (cjpalhdlnbpafiamejdnhcphjbkeiagm) with
      # HTTP 204 for every prodversion.  It is Manifest V2 and has been
      # delisted, so there is no CRX left to download.  Lite is the same
      # author's MV3 build.
      id = "ddkjiahejlhfcafbddmgiahcphecmpfh";
      name = "uBlock Origin Lite";
    }
    {
      id = "oboonakemofpalcgghocfoadofidjkkk";
      name = "KeePassXC-Browser";
    }
    {
      id = "dbepggeogbaibhgnhhndojpepiihcmeb";
      name = "Vimium";
    }
    {
      # Spec-provided ID; the Web Store does serve a CRX for it (302,
      # 2026-11-13), so it exists.
      id = "fehfojhhnbfbclgpffmffigfgngbpnmj";
      name = "SideTab Pro";
    }
    {
      # Vertical Tabs (nicedoc.io), FOSS.  Toggle: Alt+V
      # (chrome://extensions/shortcuts).
      id = "efobhjmgoddhfdhaflheioeagkcknoji";
      name = "Vertical Tabs";
    }
    {
      # M27's reading stack: saves the page to karakeep.goclan.org.
      id = "kgcjekpmcjjogibpjebkhaanilehneje";
      name = "Karakeep";
    }
    {
      # M27: syncs this browser's bookmark tree into the same Karakeep.
      id = "fnaicdffflnofjppbagibeoednhnbjhg";
      name = "floccus";
    }
  ];
}
