# Cheat Sheet

Quick reference for the miralda desktop (Niri + foot + nushell).

Keybind layers — each level uses a different modifier to avoid conflicts:

| Layer | Modifier | Unlock |
|-------|----------|--------|
| **Niri** (WM) | `Mod` (Super) | Always active |
| **Zellij** (mux) | `Alt` | Autolock (auto); `Alt+G` lock/unlock; `Alt+Z` disable autolock |
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

Starts in **locked mode** — all keys pass through to the terminal. The **autolock** plugin automatically switches to locked mode when helix, fzf, yazi, git, or zoxide are running, and back to normal when they exit. The **zjstatus** bar shows mode (colored pill), session name, tabs (bubble style), and time.

### Mode switching

| Key | From | Action |
|-----|------|--------|
| `Alt+G` | Normal | Disable autolock + switch to locked (manual passthrough) |
| `Alt+G` | Locked | Re-enable autolock + switch to normal |
| `Alt+Z` | Locked | Disable autolock + switch to normal (stay unlocked regardless of triggers) |

### Normal mode (after `Alt+G`)

#### Pane management

| Key | Action |
|-----|--------|
| `Alt+H/J/K/L` | Focus pane left/down/up/right |
| `Alt+N` | New pane (right) |
| `Alt+Shift+N` | New pane (down) |
| `Alt+X` | Close pane |
| `Alt+Shift+Z` | Toggle pane fullscreen |
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
| `e` | Edit scrollback in Helix (vim select + yank to copy) |
| `Esc` | Back to normal mode |

In search mode (after `/` + type + `Enter`):

| Key | Action |
|-----|--------|
| `n` / `p` | Next/previous match |
| `j` / `k` | Scroll down/up |
| `Esc` | Back to scroll mode |

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
| `Space+G` | Open Lazyjj (jj TUI) in new foot window |

---

## Yazi file manager

| Key | Action |
|-----|--------|
| `e` | Open in Helix |
| `s` | Open terminal here |
| `g` | Open Lazyjj (jj TUI) |
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

## Version control (jj)

The repo is driven with jj, colocated with git — `.git` stays authoritative, `gh` and CI
are unaffected. Full guide: `docs/guides/jj-workflow.md`.

### The loop

```bash
jj bookmark track main --remote=origin   # ONCE per clone, or `main` never moves
jj git fetch                             # `main` advances on its own
jj new main -m "<message>"               # start the change (no bookmark name yet)
# ...edit files. No `add`, no `commit` — edits land in @ as you go.
jj bookmark set <type>/<slug> -r @       # name it
jj git push --bookmark <type>/<slug>     # first push and every later one
gh pr create
```

After the PR merges: `jj git fetch && jj bookmark forget <type>/<slug>`.

**New files:** run `jj st` before `nix eval` / `clan machines update`. jj snapshots when a
jj command runs, not when the file appears, and Nix cannot read a path git does not track
yet (`Path '…' is not tracked by Git`). This is the only thing `git add` used to cover that
jj does not cover for free.

### Looking around

| Command | Action |
|---------|--------|
| `jj st` | What is in the working-copy revision (replaces `git status`) |
| `jj diff` | Diff of `@` |
| `jj log` | History (replaces `git log --oneline --graph`) |
| `jj show <rev>` | One revision in full |
| `lazyjj` | TUI — `Space+G` in Helix, `g` in Yazi |

### Changing things

| Command | Action |
|---------|--------|
| `jj describe -m "..."` | Set or revise the message of `@` |
| `jj new <rev>` | Start a new change on top of `<rev>` |
| `jj edit <rev>` | Move the working copy onto an existing revision |
| `jj split` | Cut `@` into two revisions |
| `jj squash` | Fold `@` into its parent |
| `jj absorb` | Auto-distribute edits into the revisions that introduced those lines |
| `jj rebase -d main` | Move a change onto current `main` |
| `jj abandon` | Throw the revision away |

### Getting out of trouble

| Command | Action |
|---------|--------|
| `jj undo` | Reverse the last operation |
| `jj op log` | Every operation, including working-copy snapshots |
| `jj op restore <op>` | Go back to a previous state — the `git reflog` replacement |
| `jj bookmark set main -r main@origin` | Put a stray `main` back |

There is no index, no `--amend` and no `--force-with-lease`: editing files *is* amending,
and jj refuses an unsafe overwrite on its own.

---

## Deploy workflow

```bash
clan machines update miralda    # build + activate
clan vars generate miralda      # (re)generate secrets first, if they changed

jj git push --bookmark <slug>   # push the change (uses the gh credential helper)
push                            # git escape hatch — same helper, via git
```
