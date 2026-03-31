# Syncthing user override.
# The clan syncthing service defaults to the system 'syncthing' user, which
# cannot write into /home/lgo/Public.  Running as lgo lets syncthing read and
# write the shared folder without any ACL gymnastics.
{ ... }:
{
  services.syncthing.user = "lgo";
}
