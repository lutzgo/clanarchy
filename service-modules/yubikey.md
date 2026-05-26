# @clanarchy/yubikey

Enables full YubiKey support on a machine:

- **pcscd** — PC/SC daemon started eagerly at boot (avoids `No such device` race)
- **GnuPG agent** — SSH support enabled; uses `pinentry-qt` with a Wayland wrapper that injects `WAYLAND_DISPLAY` and `QT_QPA_PLATFORM=wayland` so PIN prompts work over SSH and in UWSM sessions
- **udev rules** — `yubikey-personalization` rules for non-root card access
- **polkit rule** — grants unconditional PCSC access so `ykman` and scdaemon work over SSH (no active logind session required)
- **known_hosts** — pins clan machine host keys system-wide (plain ed25519)

## Usage

```nix
# clan.nix — inventory.instances
yubikey = {
  module.input = "self";
  module.name  = "@clanarchy/yubikey";
  roles.default.machines.miralda = { };
};
```

## Notes

`pinentry-gnome3` is explicitly avoided: it requires `gnome-keyring-daemon` via D-Bus (`org.gnome.keyring.SystemPrompter`), which is absent on Niri. Without it, every PIN prompt fails silently and gpg-agent returns "agent refused operation".
