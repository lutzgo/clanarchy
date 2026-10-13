# Decisions that bite

Things whose reason is not visible from the code, and which someone will
otherwise "fix". Where the reason already lives next to the code, this page is a
pointer rather than a second copy — a duplicated rationale is one that drifts.

## Pointers

| Decision | Where the reasoning lives |
|---|---|
| `~/.gnupg/scdaemon.conf` must contain `disable-ccid`, or scdaemon races pcscd and reports "No such device" with the key present | `modules/users/lgo.nix` |
| `pinentry-qt`, never `pinentry-gnome3` — the latter needs `gnome-keyring-daemon`, absent on Niri, and every PIN prompt then fails silently | `modules/hardware/yubikey.nix` |
| pcscd needs a polkit rule via `security.polkit.extraConfig` (not `extraRules`), because SSH sessions have no "active" logind session | `modules/hardware/zsa.nix`, `modules/hardware/yubikey.nix` |
| greetd/tuigreet: pass `--sessions /run/current-system/sw/share/wayland-sessions`; never `--remember-session` or any cache-writing flag (tuigreet 0.9.1 panics on a stale cache after rollback, and greetd then hits its restart limit); never add TTY systemd overrides to the unit | `modules/desktop/desktop-common.nix` |
| Why birte is btrfs: out-of-tree OpenZFS gates the kernel, and birte tracks unstable plus a Valve kernel | `machines/birte/disko.nix` |
| The niri overlay's `checkPhase = ":"` (an EMFILE sandbox test failure) | `lib/overlays.nix` |
| Do **not** set `gtk.iconTheme` in `home-manager.sharedModules` — it conflicts with Stylix's GTK target and breaks HM activation for the affected user | `modules/icon-theme.nix` |
| Machine composition: what `commonBase` and `commonHeadful` exist for | `lib/mk-machine.nix`, and [modules.md](modules.md) |

## `stylix.polarity` is load-bearing, not cosmetic

It is the single source of truth for which side of the palette the fleet is on,
and three things outside Stylix read it:

- `modules/icon-theme.nix` picks the Papirus source variant from it.
- `modules/desktop/noctalia-hm.nix` derives `colorSchemes.darkMode` from it, and
  Noctalia feeds that to gsettings `color-scheme` — so GTK apps get dark chrome
  on a light desktop if the two disagree.
- `modules/stylix-base.nix` sets it to `lib.mkDefault "dark"` precisely so a
  theme can override it.

A new light theme must set `polarity = "light"` in its `palettes.nix` entry. The
base16 scheme alone will not flip any of the above.

## Impermanence is enforced, not assumed

Both backends roll root **and** home back on boot. The snapshots are **not**
created automatically, and a machine missing them silently is not impermanent at
all — which is what happened to ernst for a month.
`clanarchy-impermanence-check.service` now fails loudly when they are absent. If
a deploy reports it, that machine is accumulating state outside `/persist`.

The shared system-level persist set is in `modules/rootfs.nix`; modules add
their own (e.g. `/var/lib/libvirt`, `/var/lib/private/ollama`,
`/var/lib/clanarchy-session`), and per-user paths are declared in
`modules/users/*.nix`.

**`/var/lib/zerotier-one` is deliberately not persisted**, despite what earlier
revisions of this documentation claimed. clan-core sources each node's identity
from a clan var, so it is redeployed from sops on every boot and survives
rollback without `/var/lib` state. Persisting it would add a second, competing
source of truth for the node ID.

## Game libraries sit outside the rollback path

birte's `@games` subvolume and ernst's `zdata/games` dataset are symlinked into
the gaming user's home by a tmpfiles `L+` rule that re-forces the link after
every rollback. Two reasons they are not mounted straight at
`~/.local/share/Steam`:

- that path is restored as an impermanence bind-mount, which would shadow
  anything mounted underneath it; and
- keeping the library on its own subvolume/dataset lets it carry `nodatacow`
  (CoW badly fragments large, repeatedly-rewritten game files) without imposing
  that on `@home`.

A `d` tmpfiles rule fixes ownership, since a fresh subvolume or dataset is
`root:root`.

## `pkgs-unstable` does not follow clan-core's nixpkgs

That is deliberate — Noctalia and Quickshell need a newer tree. It is injected
as a module arg via `_module.args` (see `mkModuleArgs`), so a module takes
`{ pkgs-unstable, … }` in its signature. Note `nixpkgs.config` cannot be layered
on at the NixOS level for a machine on the unstable channel: anything like
`permittedInsecurePackages` has to live inside the pkgs instance in
`lib/mk-machine.nix`.

## The theme registry

`modules/themes/palettes.nix` is data (one entry per known-good theme:
`scheme`, `polarity`, optional `fontSizes`); `default.nix` is the mechanism. It
replaced one ~75-line file per theme, of which ~65 lines were a byte-identical
copy of the ImageMagick wallpaper generator. Adding a theme is one entry;
switching is one line in a machine's `configuration.nix`; a typo names the valid
alternatives instead of silently defaulting.

## The `lgo` editor option

`clanarchy.users.lgo.editor` selects `"govim"` (default) or `"helix"`. govim is a
flake input built on nvf, wired via `programs.nvf.settings`. The nvf HM option
namespace must be declared at the NixOS level via `home-manager.sharedModules` —
a per-user import cannot bootstrap its own option types. `EDITOR`/`VISUAL`,
Zellij's `Alt+e` and Yazi's `e` all key off the same `editorBin`.

Anything reading this option must tolerate it being absent or set to `helix`:
`roles.opencode` checks it on the NixOS config rather than probing `options`,
because using `options` to decide a module's own attribute structure is infinite
recursion.

## `push`

Reads the gh token at runtime to construct the HTTPS remote URL, which is what
makes pushing work on a machine where `~/.config/git` is a read-only
impermanence bind-mount. Never combine it with `git push -u`: that bakes the
token into `.git/config`.
