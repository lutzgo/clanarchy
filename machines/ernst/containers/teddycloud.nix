# machines/ernst/containers/teddycloud.nix
#
# TeddyCloud: a local server for the household's CC3200 Toniebox, which runs
# the HackiesboxNG bootloader.  The box talks to this instead of Boxine's
# cloud; official Tonies still work because TeddyCloud passes through to
# Boxine and caches what it fetches.
#
# ── TIER: podman ────────────────────────────────────────────────────────────
#
#   Not in nixpkgs (checked 2026-11-11 against ernst's pin: no package, no
#   module).  Upstream ships an OCI image, so this is the escape hatch.
#
# ── TWO DOORS, AND ONLY ONE OF THEM IS TRAEFIK ─────────────────────────────
#
#   :80   web UI.  Browser-only, so it rides Traefik behind forward-auth like
#         every other operator tool (`teddycloud` in ingress-policy.nix).
#   :443  the BOX.  Mutual TLS: the box presents the client certificate from
#         its own flash, and trusts only the CA flashed to /cert/c2.der, which
#         is TeddyCloud's certs/server/ca.der.  Traefik cannot terminate that,
#         so the box reaches this address directly.  That needs a UDM-Pro rule
#         `IoT (20) -> 10.0.90.33:443/tcp`; without it the box shows a red LED
#         and TeddyCloud's log stays silent.
#   :8443 TeddyCloud's own HTTPS web UI.  Not opened; Traefik does TLS.
#
#   The box finds this address by name: the bootloader's altUrl.305 patch
#   rewrites the cloud hostnames to `prod.revvox` and `rtnl.revvox`, which
#   Technitium resolves to 10.0.90.33.  The patch caps the name at 12
#   characters, so a goclan.org name does not fit.
#
# ── IDS ─────────────────────────────────────────────────────────────────────
#
#   The image's entrypoint starts as root, chowns /teddycloud to PUID:PGID and
#   drops privileges with gosu; the binary carries cap_net_bind_service for
#   :80/:443.  So PUID/PGID are set and the module's `uidgid` is NOT — a
#   `--user` would skip the chown and the privilege drop both.
{
  config,
  lib,
  pkgs,
  ...
}: let
  alloc = import ../allocations.nix;
  row = alloc.vlan90.teddycloud;
  uid = alloc.ids.teddycloud.uid;
  gid = alloc.ids.teddycloud.gid;
  webPort = 80;
  boxPort = 443;
  traefikAddr = alloc.vlan90.traefik.ip;
  iotSubnet = "10.0.20.0/24";
  stateDir = "/srv/state/teddycloud";
  # Every directory the image declares as a volume, in stateDir.
  subdirs = ["certs" "config" "content" "library" "custom_img" "firmware" "cache" "plugins"];
  # tc_v0.7.1
  imageDigest = "sha256:870fd1ab0fc5175f72f37a424f3dd3be6da82f90ca1de6fc6b18322963139975";
in {
  users.users.teddycloud = {
    isSystemUser = true;
    inherit uid;
    group = "teddycloud";
    home = stateDir;
  };
  users.groups.teddycloud.gid = gid;

  clanarchy.podmanContainers.teddycloud = {
    enable = true;
    mac = "02:00:00:90:00:${lib.toLower (lib.toHexString row.seq)}";
    interface = row.iface;

    stateDirs =
      [
        {
          path = stateDir;
          owner = uid;
          group = gid;
          mode = "0750";
        }
      ]
      ++ map (d: {
        path = "${stateDir}/${d}";
        owner = uid;
        group = gid;
        mode = "0750";
      })
      subdirs;

    allowFrom = [
      {
        peer = traefikAddr;
        port = webPort;
      }
      {
        peer = iotSubnet;
        port = boxPort;
      }
    ];

    images.teddycloud = {
      image = "ghcr.io/toniebox-reverse-engineering/teddycloud@${imageDigest}";
      environment = {
        TZ = "Europe/Berlin";
        PUID = toString uid;
        PGID = toString gid;
      };
      volumes =
        map (
          d:
            if d == "custom_img" || d == "plugins"
            then "${stateDir}/${d}:/teddycloud/data/www/${d}"
            else if d == "certs" || d == "config"
            then "${stateDir}/${d}:/teddycloud/${d}"
            else "${stateDir}/${d}:/teddycloud/data/${d}"
        )
        subdirs;
      ports = [];
    };
  };

  systemd.services.podman-teddycloud.serviceConfig = {
    Nice = 10;
    CPUWeight = 40;
  };
}
