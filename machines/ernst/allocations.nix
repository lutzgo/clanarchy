# The allocation registry for ernst: one row per thing that takes a MAC, an
# address, a veth name or a numeric id on this host.
#
# ── WHY THIS IS DATA AND NOT A COMMENT ──────────────────────────────────────
#
# It was four comment tables in machines/ernst/networking.nix, ~1500 lines, and
# nothing checked any of it.  The tables had already drifted: three different
# "NEXT FREE IN THE 3000 BLOCK" sentences disagreed (3038, 3044, "remains
# 3038"), and a mistyped MAC or a duplicated address would have evaluated
# cleanly and failed on the machine — a DHCP reservation keyed on a MAC that no
# container claims is a service that silently takes a pool lease instead.
#
# Now the rows are read by assertions in networking.nix, which cross-check them
# against `config.containers` rather than against each other.  `nextFree` is
# computed; no sentence has to be kept in step by hand.
#
# A plain attrset rather than a module option, for the reason
# containers/ingress-policy.nix gives: each `containers.<n>.config` is its own
# NixOS evaluation with no access to the host's option tree, so a plain import
# crosses that boundary and an option would have to be threaded through by hand.
#
# ── THE RULES ───────────────────────────────────────────────────────────────
#
#   VLAN 90  MAC is 02:00:00:90:00:<seq>, and the address is 10.0.90.<8 + seq>.
#            That correspondence is the only thing that makes a mistyped
#            reservation visible by inspection, so it is asserted.
#   VLAN 20  MAC is 02:00:00:20:00:<seq>.  THE 8 + seq RULE DOES NOT APPLY —
#            these addresses mirror the host's VLAN-90 last octet instead, as a
#            mnemonic.  Do not derive a VLAN-20 address from its seq.
#   uids     The 3000 block is ours.  Anything outside it is an upstream static
#            id and is recorded with `upstream = true` so it cannot be
#            renumbered into the block by someone tidying up — that mistake is
#            an eval conflict, which is how M24 met `hass` = 286.
#   names    An NSPAWN container name must be <= 12 characters: nspawn derives
#            the host veth as `vb-<name>`, and 15 is IFNAMSIZ.  This passes
#            eval and fails at container START, which is why it is asserted.
#            SCOPED TO `kind = "nspawn"` ON PURPOSE — `wg-qbittorrent` is 14
#            characters and perfectly fine, because it is a microvm whose
#            interface is `tap-qbt` and is named explicitly.  An unscoped
#            check flags it, which is how this scoping was found.
{
  # ── VLAN 90 — the services VLAN ───────────────────────────────────────────
  #
  # Addresses are DHCP reservations on the UDM-Pro keyed on the MAC, so the
  # value that matters in Nix is the MAC; the address is recorded so the
  # correspondence can be checked and so peers can be named from one place.
  # Every reservation must be INSIDE the pool (10.0.90.6–.254) — UniFi accepts
  # an address from the .2–.5 range the cutover runbook set aside and then
  # silently hands out a pool lease instead.
  vlan90 = {
    jellyfin       = { seq = 2; ip = "10.0.90.10"; kind = "nspawn"; };
    wg-qbittorrent = { seq = 3; ip = "10.0.90.11"; kind = "microvm"; iface = "tap-qbt"; };
    traefik        = { seq = 4; ip = "10.0.90.12"; kind = "nspawn"; };
    arr            = { seq = 5; ip = "10.0.90.13"; kind = "nspawn"; };
    monitoring     = { seq = 6; ip = "10.0.90.14"; kind = "nspawn"; };
    authelia       = { seq = 7; ip = "10.0.90.15"; kind = "nspawn"; };
    tvheadend      = { seq = 10; ip = "10.0.90.18"; kind = "nspawn"; };
    tubesync       = { seq = 11; ip = "10.0.90.19"; kind = "podman"; iface = "eth0"; };
    storyteller    = { seq = 12; ip = "10.0.90.20"; kind = "podman"; iface = "st0"; };
    cwa            = { seq = 13; ip = "10.0.90.21"; kind = "podman"; iface = "cw0";
                       note = "reuses M16's freed cloudflared pair — the UDM-Pro reservation was RE-POINTED, not added alongside"; };
    romm           = { seq = 14; ip = "10.0.90.22"; kind = "podman"; iface = "rm0"; };
    openwebui      = { seq = 15; ip = "10.0.90.23"; kind = "nspawn"; };
    searxng        = { seq = 16; ip = "10.0.90.24"; kind = "nspawn"; };
    immich         = { seq = 17; ip = "10.0.90.25"; kind = "nspawn"; };
    nextcloud      = { seq = 18; ip = "10.0.90.26"; kind = "nspawn"; };
    hass           = { seq = 19; ip = "10.0.90.27"; kind = "nspawn"; };
    miniflux       = { seq = 20; ip = "10.0.90.28"; kind = "nspawn"; };
    karakeep       = { seq = 21; ip = "10.0.90.29"; kind = "nspawn"; };
    mass           = { seq = 22; ip = "10.0.90.30"; kind = "nspawn"; };
    mail           = { seq = 23; ip = "10.0.90.31"; kind = "nspawn"; };
    paperless      = { seq = 24; ip = "10.0.90.32"; kind = "nspawn"; };
  };

  # 08 and 09 lapsed and were never reclaimed; 0d was taken back by CWA. There
  # is no free gap below the high-water mark.
  vlan90Lapsed = [ 8 9 ];

  # ── VLAN 20 — IoT, for the two services that need link-local discovery ────
  #
  # mDNS and SSDP are link-local and this repo refuses to relay them across a
  # firewall boundary, so a service that must discover wifi devices gets a
  # second leg rather than a relay.
  vlan20 = {
    hass = { seq = 1; ip = "10.0.20.27"; veth = "iot0"; };
    mass = { seq = 2; ip = "10.0.20.30"; veth = "iot1"; };
  };

  # ── Point-to-point ULA legs ───────────────────────────────────────────────
  #
  # llama-swap and the other loopback-bound producers stay on 127.0.0.1; each
  # consumer gets its own /128 pair, a socket-activated proxy on the host end
  # and one firewall accept on the container end.  Nothing on any VLAN.
  #
  # THE VETH NAME IS A HOST-GLOBAL ALLOCATION, not a per-container one.  M19
  # and M27 both chose `ai0`; the name is used for both ends, so only one
  # container could hold it and Open WebUI silently had no second interface for
  # five days.  Names now track the peer's ULA nibble — fe91 -> ai1 — and
  # uniqueness is asserted.  `mon0` predates the rule and keeps its name.
  ula = {
    monitoring = { veth = "mon0";  prefix = "fdca:fe90::"; consumer = "monitoring"; purpose = "Prometheus, and llama-swap's /metrics"; };
    openwebui  = { veth = "ai1";   prefix = "fdca:fe91::"; consumer = "openwebui";  purpose = "chat and STT"; };
    karakeep   = { veth = "ai2";   prefix = "fdca:fe92::"; consumer = "karakeep";   purpose = "auto-tagging"; };
    hass       = { veth = "ai3";   prefix = "fdca:fe93::"; consumer = "hass";       purpose = "the conversation agent, STT and TTS"; };
    searxng    = { veth = "web0";  prefix = "fdca:fe94::"; consumer = "searxng";    purpose = "web search for the agent — points INWARD"; };
    paperless  = { veth = "doc0";  prefix = "fdca:fe95::"; consumer = "paperless";  purpose = "document search for the agent — points INWARD"; };
    kodi       = { veth = "kodi0"; prefix = "fdca:fe96::"; consumer = "hass";       purpose = "Home Assistant -> Kodi's HTTP control"; };
  };

  # ── Numeric ids ───────────────────────────────────────────────────────────
  #
  # virtiofs and nspawn both pass uids and gids through UNMAPPED, so a number
  # chosen inside a guest is a number on zdata.  That is the whole reason this
  # table exists.
  #
  # `upstream = true` means the id is a well-known NixOS static one. It is
  # recorded so nobody renumbers it into the 3000 block — doing so is an option
  # conflict at eval (`conflicting definition values: 286 / 3038`).
  #
  # `reserved = true` means a milestone claimed it and shipped without it. The
  # number is NOT reused: the row says why, so a reader can tell "recorded as
  # declining" from "somebody forgot".
  ids = {
    media          = { gid = 3000; where = "containers/jellyfin.nix"; note = "the shared read/write group"; };
    jellyfin       = { uid = 964;  upstream = true; where = "containers/jellyfin.nix"; };
    qbittorrent    = { uid = 3001; where = "microvms/wg-qbittorrent.nix"; };
    sonarr         = { uid = 3002; where = "containers/arr/common.nix"; groups = [ "media" ]; };
    radarr         = { uid = 3003; where = "containers/arr/common.nix"; groups = [ "media" ]; };
    prowlarr       = { uid = 3004; gid = 3004; where = "containers/arr/common.nix"; };
    traefik        = { uid = 3005; gid = 3005; where = "containers/traefik.nix"; };
    prometheus     = { uid = 3006; gid = 3006; where = "service-modules/monitoring.nix"; };
    grafana        = { uid = 3007; gid = 3007; where = "service-modules/monitoring.nix"; };
    authelia-main  = { uid = 3008; gid = 3008; where = "containers/authelia.nix"; };
    bazarr         = { uid = 3009; where = "containers/arr/common.nix"; groups = [ "media" ]; };
    umlautadaptarr = { uid = 3010; gid = 3010; reserved = true; where = "containers/arr/common.nix";
                       note = "shipped under DynamicUser instead; the number stays claimed"; };
    cleanuparr     = { uid = 3011; where = "containers/arr/common.nix"; groups = [ "media" ]; };
    mediathekarr   = { uid = 3012; where = "containers/arr/common.nix"; groups = [ "media" ]; };
    unpackerr      = { uid = 3013; reserved = true; where = "containers/arr/common.nix"; note = "M12 made it conditional and it never shipped"; };
    jellyseerr     = { uid = 3014; gid = 3014; where = "containers/arr/common.nix"; };
    janitorr       = { uid = 3015; where = "containers/arr/common.nix"; groups = [ "media" ]; };
    scraparr       = { uid = 3016; gid = 3016; where = "containers/arr/common.nix"; };
    lidarr         = { uid = 3017; where = "containers/arr/common.nix"; groups = [ "media" ]; };
    soularr        = { uid = 3018; where = "containers/arr/common.nix"; groups = [ "media" ]; };
    kapowarr       = { uid = 3019; where = "containers/arr/common.nix"; groups = [ "media" ]; };
    questarr       = { uid = 3020; gid = 3020; where = "containers/arr/common.nix"; };
    audiobookshelf = { uid = 3021; where = "containers/arr/common.nix"; groups = [ "media" ]; };
    storyteller    = { uid = 3022; where = "containers/storyteller.nix"; groups = [ "media" ]; };
    tdarr          = { uid = 3023; reserved = true; where = "—"; note = "M15 closed 2026-08-29; nothing shipped"; };
    slskd          = { uid = 3024; where = "microvms/wg-qbittorrent.nix"; groups = [ "media" ]; };
    wizarr         = { uid = 3025; gid = 3025; reserved = true; where = "—"; note = "M16 evaluated it and declined"; };
    tvheadend      = { uid = 3026; gid = 3026; where = "containers/tvheadend.nix"; };
    tubesync       = { uid = 3027; where = "containers/tubesync.nix"; groups = [ "media" ]; };
    bindery        = { uid = 3028; where = "containers/arr/common.nix"; groups = [ "media" ]; };
    romm           = { uid = 3029; where = "containers/romm.nix"; };
    crowdsec       = { uid = 3030; gid = 3030; where = "containers/crowdsec.nix"; };
    komga          = { uid = 3031; where = "containers/arr/common.nix"; groups = [ "media" ]; note = "read-only"; };
    navidrome      = { uid = 3032; where = "containers/arr/common.nix"; groups = [ "media" ]; note = "read-only"; };
    cwa            = { uid = 3033; gid = 3033; where = "containers/cwa.nix"; };
    open-webui     = { uid = 3034; gid = 3034; where = "service-modules/local-ai.nix"; };
    searx          = { uid = 3035; gid = 3035; where = "service-modules/local-ai.nix"; };
    immich         = { uid = 3036; gid = 3036; where = "containers/immich.nix"; };
    nextcloud      = { uid = 3037; gid = 3037; where = "containers/nextcloud.nix"; };
    karakeep       = { uid = 3038; gid = 3038; where = "containers/karakeep.nix"; };
    mneme          = { uid = 3039; where = "service-modules/local-ai.nix"; };
    music-assistant = { uid = 3040; gid = 3040; where = "containers/music-assistant.nix";
                        note = "upstream's DynamicUser is forced OFF: StateDirectory + DynamicUser migrates the bind mount"; };
    virtualMail    = { uid = 3041; where = "containers/mail.nix"; };
    docsin         = { gid = 3042; where = "containers/paperless.nix"; note = "M32's shared ingest group — the one id M32 took from the block"; };
    redis-rspamd   = { uid = 3043; where = "containers/mail.nix"; note = "the Bayes store; 3043 not 3042 because docsin took that"; };

    # Upstream-static, recorded so they are never renumbered into the block.
    hass           = { uid = 286; gid = 286; upstream = true; where = "containers/home-assistant.nix"; };
    paperless      = { uid = 315; upstream = true; where = "containers/paperless.nix";
                       note = "ids.uids.paperless is assigned unconditionally by the module; pinning 3042 on top is the hass=286 conflict"; };
    postgres       = { uid = 71;  upstream = true; where = "miniflux / nextcloud / immich / paperless"; };
    postfix        = { uid = 13;  upstream = true; where = "containers/mail.nix"; };
    postdrop       = { gid = 14;  upstream = true; where = "containers/mail.nix"; };
    dovecot2       = { uid = 46;  upstream = true; where = "containers/mail.nix"; };
    rspamd         = { uid = 225; upstream = true; where = "containers/mail.nix"; };
  };
}
