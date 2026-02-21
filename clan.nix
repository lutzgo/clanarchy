{ ... }:
{
  clan = {
    meta.name = "clanarchy";
    meta.domain = "goclan.org";

    inventory.machines = {
      miralda = { };
    };

    inventory.instances = {
      # SSH baseline (recommended in official guide flow)
      sshd = {
        roles.server.tags.all = { };
        roles.server.settings.authorizedKeys = {
          "admin-machine-1" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPo4uZn6hVFTnJ0K7eagj1XL0jVn9t6sSU8RAejhWBy+ clanarchy_admin";
        };
      };

      # Zerotier scaffold (inactive until you choose a controller and deploy it)
      zerotier = {
        roles.controller.machines."miralda" = { };
        roles.peer.tags.all = { };
      };
    };

    machines = { };
  };
}
