# A synthetic machine that declares one container of each tier, so the modules
# in modules/containers/ are exercised by `nix flake check` rather than only by
# the day somebody migrates a real service onto them.
#
# WHY THIS EXISTS. The modules ship with no consumers — every real container
# still has its skeleton written by hand — so without this they would be
# "evaluates clean" and nothing more. This is what makes the generated units
# readable, diffable against the hand-written ones, and regression-checked.
#
# It is NOT a machine anybody deploys. It is evaluated, its units are compared,
# and that is all.
{ lib, nixpkgs }:
let
  system = "x86_64-linux";
in
(nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ../modules/containers/nspawn.nix
    ../modules/containers/podman-netns.nix
    ../modules/containers/assertions.nix
    ({ config, ... }: {
      boot.loader.grub.enable = false;
      fileSystems."/" = { device = "/dev/null"; fsType = "ext4"; };
      system.stateVersion = "26.05";
      nixpkgs.hostPlatform = system;

      clanarchy.containerDefaults = {
        bridge       = "br0";
        vlan         = 90;
        resolver     = "10.0.5.3";
        searchDomain = "skynet.lan";
        stateMount   = "/srv/state";
        stateSource  = "zdata/state";
      };

      # The plain shape: state on the guarded mount, one peer allowed in.
      clanarchy.containers.widget = {
        enable = true;
        mac = "02:00:00:90:00:63";
        uid = 3099;
        gid = 3099;
        user = "widget";
        stateDirs = [
          { path = "/srv/state/widget"; owner = 3099; group = 3099; mode = "0700"; }
        ];
        allowFrom = [ { peer = "10.0.90.12"; port = 8080; } ];
        config = { ... }: { services.nginx.enable = false; };
      };

      # The harder shape: a point-to-point ULA leg, a second guarded mount,
      # and a staged secret.
      clanarchy.containers.gadget = {
        enable = true;
        mac = "02:00:00:90:00:64";
        extraGuardedMounts = [ "/srv/photos" ];
        stateDirs = [
          { path = "/srv/state/gadget"; owner = 71; group = 71; mode = "0700"; }
        ];
        secrets."oidc.env" = { OAUTH_CLIENT_SECRET = "/run/secrets/vars/gadget/secret"; };
        ula = [
          { veth = "ai9"; hostAddress6 = "fdca:fe99::1"; localAddress6 = "fdca:fe99::2"; }
        ];
        allowFrom = [
          { peer = "10.0.90.12"; port = 3000; }
          { peer = "10.0.90.14"; port = 3000; }
        ];
      };

      # The podman tier, two images in one namespace — the shape that keeps a
      # database on loopback and structurally unaddressable.
      clanarchy.podmanContainers.doohickey = {
        enable = true;
        mac = "02:00:00:90:00:65";
        interface = "dh0";
        uidgid = "3098:3098";
        stateDirs = [
          { path = "/srv/state/doohickey"; owner = 3098; group = 3098; mode = "0700"; }
        ];
        allowFrom = [ { peer = "10.0.90.12"; port = 8080; } ];
        healthcheck.enable = true;
        images = {
          doohickey    = { image = "example.invalid/doohickey:1"; };
          doohickey-db = { image = "example.invalid/mariadb:11"; };
        };
      };
    })
  ];
}).config
