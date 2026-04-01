# Cheat Sheet

Quick reference for the miralda desktop (Niri + foot + nushell).

---

## Reading output

| Command | Use for |
|---------|---------|
| `bat file.nix` | View file with syntax highlighting and built-in paging |
| `command \| bat` | Pipe output through bat (syntax detect + paging) |
| `command \| less` | Classic scrollable pager (q to quit) |
| `command \| explore` | Nushell native interactive table browser |

`bat` auto-pages when output exceeds the terminal. `explore` is best for nushell tables (supports horizontal scrolling).

---

## Terminal line editing (nushell / reedline)

Nushell uses Emacs-mode keybindings by default.

### Cursor movement

| Key | Action |
|-----|--------|
| `Ctrl+A` | Start of line |
| `Ctrl+E` | End of line |
| `Ctrl+F` | Forward one character |
| `Ctrl+B` | Back one character |
| `Alt+F` | Forward one word |
| `Alt+B` | Back one word |

### Editing

| Key | Action |
|-----|--------|
| `Ctrl+K` | Delete to end of line |
| `Ctrl+U` | Delete to start of line |
| `Ctrl+W` | Delete word backward |
| `Alt+D` | Delete word forward |
| `Ctrl+D` | Delete character forward (or exit if empty) |
| `Ctrl+Y` | Yank (paste last deleted text) |
| `Ctrl+T` | Transpose characters |

### History

| Key | Action |
|-----|--------|
| `Ctrl+R` | Reverse search history |
| `Ctrl+P` / `Up` | Previous history entry |
| `Ctrl+N` / `Down` | Next history entry |

Run `keybindings default` in nushell to see the full list.

---

## Foot terminal shortcuts

| Key | Action |
|-----|--------|
| `Ctrl+Shift+C` | Copy to clipboard |
| `Ctrl+Shift+V` | Paste from clipboard |
| `Ctrl++` / `Ctrl+=` | Increase font size |
| `Ctrl+-` | Decrease font size |
| `Ctrl+0` | Reset font size |
| `Shift+PgUp/PgDn` | Scroll back/forward |
| `Ctrl+Shift+R` | Search scrollback |
| `Ctrl+Shift+O` | Open URL hints |

---

## Niri window management

| Key | Action |
|-----|--------|
| `Mod+Return` | Open terminal (foot) |
| `Mod+Shift+Return` | Floating scratch terminal |
| `Mod+Space` | App launcher (Noctalia) |
| `Mod+Q` | Close window |
| `Mod+H/J/K/L` | Focus left/down/up/right |
| `Mod+Shift+H/J/K/L` | Move window left/down/up/right |
| `Mod+V` | Toggle floating |
| `Mod+M` | Maximize column |
| `Mod+F11` | Fullscreen |
| `Mod+Tab` | Focus previous window |
| `Mod+R` | Cycle column width presets |
| `Mod+Shift+C` | Center column |
| `Mod+[` / `Mod+]` | Consume/expel window |
| `Mod+1-9` | Switch workspace |
| `Mod+Shift+1-9` | Move window to workspace |
| `Mod+E` | Helix (editor) |
| `Mod+F` | Yazi (file manager) |
| `Mod+C` | Clipboard (Noctalia clipper) |
| `Mod+Shift+E` | Quit niri |
| `Mod+Shift+R` | Reload niri config |

---

## Unicode input

| Method | How |
|--------|-----|
| Foot / GTK apps | `Ctrl+Shift+U`, type hex codepoint, `Enter` |
| Script injection | `wtype -k 'U2714'` |

Common symbols: ✓ `2713` · ✔ `2714` · ✅ `2705` · ☑ `2611`

---

## Deploy workflow

```bash
deploy              # nixos-rebuild switch on miralda
deploy boot         # stage boot entry only
push                # git push via gh token
```
