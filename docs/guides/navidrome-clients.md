# Navidrome clients

Navidrome runs inside the `arr` container on ernst (port 4533) and answers at
[`navidrome.goclan.org`](https://navidrome.goclan.org). Two clients are deployed, split by machine.

| Machine | Client | Kind |
|---|---|---|
| miralda, jens | `sonic-tui` | terminal (mpv-backed) |
| birte, biene | Supersonic | desktop (Go/Fyne) |

## Credentials are Navidrome's, not Authelia's

`navidrome` is in `appApiHosts`, so forward-auth is permanently off it — the Subsonic API authenticates with a salted token in query parameters and cannot follow a 302 to a login portal. It is also in `wanExposed`, so every client below works on the LAN and off it with no VPN.

Accounts live in Navidrome itself. **The password cannot be replaced with a token**: Subsonic builds a fresh salted token per request from the password, so the client needs the password.

## sonic-tui (miralda, jens)

Installed via `modules/users/lgo.nix` from a flake input — it is not in nixpkgs. The config is deliberately **not** managed by Nix, because it holds that password. Write it once:

```yaml title="~/.config/sonic-tui/config.yaml"
server:
  url: "https://navidrome.goclan.org"
  username: "lgo"
  password: "…"
  # Or, keeping it out of the file:
  # password_command: "secret-tool lookup service navidrome"

audio:
  volume: 100
  gapless: true

ui:
  show_cover_art: true      # foot speaks sixel, so covers render inline
  show_visualizer: true
  page_size: 100
```

`chmod 600` it. `~/.config` is in lgo's persist set, so it survives rollback.

Then just `sonic-tui`. Keys: `?` help · `/` search · `space` play/pause · `hjkl` navigate · `:` command palette · `q` quit. MPRIS is supported, so media keys and `playerctl` work.

!!! note "Why a flake input and not nixpkgs"
    The Subsonic TUI niche has churned badly. `stmp` and its fork `stmps` were the standard answer for years; `stmps` is now titled "[unmaintained]" by its own author. The `mopidy-subidy` + `rmpc` bridge route is stale too (last push March 2024) and Mopidy's MPD frontend doesn't implement `albumart`, which would cost rmpc its best feature. `termsonic` *is* in nixpkgs but is a Jan 2025 snapshot off a personal cgit instance.

    sonic-tui is developed on NixOS and ships `packages.default` as a plain `rustPlatform.buildRustPackage`, so there is no derivation to maintain here. It follows `nixpkgs-unstable` rather than clan-core's 26.05, for the same reason govim does — see the comment on the input in `flake.nix`.

## Supersonic (birte, biene)

`clanarchy.apps.subsonic.enable = true`. Chosen over feishin and aonsoku because it is a native Go/Fyne binary rather than Electron or Tauri, and both consumers are constrained — birte is a battery-powered handheld, biene is a 1366×768 laptop.

**The attribute name differs by channel.** Verified against the real machine pkgs sets:

| | `supersonic` | `supersonic-wayland` |
|---|---|---|
| biene (stable) | 0.21.1 | 0.21.1 |
| birte (unstable) | 0.22.0 | **removed** — folded into `supersonic` |

birte takes the module default; biene overrides `clanarchy.apps.subsonic.package` to `pkgs.supersonic-wayland`, because plain `supersonic` on stable is the X11 build and would run through XWayland under labwc. Do **not** copy that override to a machine on `clanarchy.channel = "unstable"` — the attribute does not exist there and it fails at eval.
