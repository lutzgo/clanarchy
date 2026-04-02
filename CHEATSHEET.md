# Cheat Sheet

Quick reference for the miralda desktop (Niri + foot + nushell).

Keybind layers — each level uses a different modifier to avoid conflicts:

| Layer | Modifier | Unlock |
|-------|----------|--------|
| **Niri** (WM) | `Mod` (Super) | Always active |
| **Zellij** (mux) | `Alt` | `Alt+G` to unlock, `Alt+G` to re-lock |
| **Helix** (editor) | `Ctrl` / vim keys | Normal mode |
| **Nushell** | Emacs keys | Always active |

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

## Niri window management (`Mod`)

### Navigation

| Key | Action |
|-----|--------|
| `Mod+H/J/K/L` | Focus left/down/up/right |
| `Mod+Shift+H/J/K/L` | Move window left/down/up/right |
| `Mod+Ctrl+H/J/K/L` | Focus monitor left/down/up/right |
| `Mod+Ctrl+Shift+H/J/K/L` | Move window to monitor |
| `Mod+1-9` | Switch workspace |
| `Mod+Shift+1-9` | Move window to workspace |
| `Mod+Tab` | Focus previous window |

### Launch

| Key | Action |
|-----|--------|
| `Mod+Return` | Terminal (foot) |
| `Mod+Shift+Return` | Floating scratch terminal |
| `Mod+Space` | App launcher (Noctalia) |
| `Mod+E` | Helix (editor) |
| `Mod+F` | Yazi (file manager) |
| `Mod+C` | Clipboard (Noctalia clipper) |
| `Mod+P` | Toggle KeePassXC (show/hide to tray) |

### Window management

| Key | Action |
|-----|--------|
| `Mod+Q` | Close window |
| `Mod+V` | Toggle floating |
| `Mod+M` | Maximize column |
| `Mod+F11` | Fullscreen |
| `Mod+R` | Cycle column width presets |
| `Mod+Shift+C` | Center column |
| `Mod+[` / `Mod+]` | Consume/expel window |
| `Mod+-` / `Mod+=` | Shrink/grow column width |
| `Mod+Shift+-` / `Mod+Shift+=` | Shrink/grow window height |

### Media / brightness (Noctalia OSD)

| Key | Action |
|-----|--------|
| `XF86AudioRaiseVolume/Lower/Mute` | Volume up/down/mute |
| `XF86AudioPlay/Next/Prev` | Media play-pause/next/prev |
| `XF86MonBrightnessUp/Down` | Brightness up/down |

### Session

| Key | Action |
|-----|--------|
| `Mod+Shift+E` | Quit niri |
| `Mod+Shift+R` | Reload niri config |

---

## Zellij multiplexer (`Alt`)

Starts in **locked mode** — all keys pass through to the terminal.

### Mode switching

| Key | Action |
|-----|--------|
| `Alt+G` | Toggle locked/normal mode |

### Normal mode (after `Alt+G`)

#### Pane management

| Key | Action |
|-----|--------|
| `Alt+H/J/K/L` | Focus pane left/down/up/right |
| `Alt+N` | New pane (right) |
| `Alt+Shift+N` | New pane (down) |
| `Alt+X` | Close pane |
| `Alt+Z` | Toggle pane fullscreen |
| `Alt+Tab` | Focus next pane |
| `Alt+T` | New terminal pane |

#### Tabs

| Key | Action |
|-----|--------|
| `Alt+1-9` | Go to tab 1-9 |
| `Alt+R` | Rename tab |

#### Launch

| Key | Action |
|-----|--------|
| `Alt+E` | Open Helix in new pane |
| `Alt+F` | Open Yazi in new pane |

#### Scroll / search / copy

| Key | Action |
|-----|--------|
| `Alt+S` | Enter scroll mode |

In scroll mode:

| Key | Action |
|-----|--------|
| `j` / `k` | Scroll down/up |
| `d` / `u` | Half-page down/up |
| `/` | Start search |
| `n` / `N` | Next/previous match |
| `Esc` | Back to normal mode |

#### Session

| Key | Action |
|-----|--------|
| `Alt+D` | Detach session |

---

## Helix editor (`Ctrl` / vim)

### Split navigation

| Key | Action |
|-----|--------|
| `Ctrl+H/J/K/L` | Focus split left/down/up/right |

### Space leader

| Key | Action |
|-----|--------|
| `Space+F` | File picker |
| `Space+B` | Buffer picker |
| `Space+/` | Global search |
| `Space+E` | Open Yazi in new foot window |
| `Space+G` | Open Lazygit in new foot window |

---

## Yazi file manager

| Key | Action |
|-----|--------|
| `e` | Open in Helix |
| `s` | Open terminal here |
| `g` | Open Lazygit |
| `A` | Select all |

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

### Zsh (vi mode)

| Key | Action |
|-----|--------|
| `Ctrl+E` | Enter command (vi normal) mode |
| Standard vi keys | Navigation in normal mode |

---

## Foot terminal

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
