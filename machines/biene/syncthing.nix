# Syncthing user override.
# The clan syncthing service defaults to the system 'syncthing' user, which
# cannot write into /home/sabine/Public.  Running as sabine lets syncthing
# read and write the shared folder without any ACL gymnastics.
{ ... }:
{
  services.syncthing.user = "sabine";
}
