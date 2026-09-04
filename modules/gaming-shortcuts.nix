# Declarative non-Steam shortcuts ("Add a Non-Steam Game", done from Nix).
#
# ── Why this exists ───────────────────────────────────────────────────────
# A couch machine's only UI is Steam Big Picture, and Big Picture can launch
# exactly one thing: entries in the Steam library.  Anything else on the box
# — a media client, an emulator front-end — is unreachable from the sofa
# unless it has been added as a non-Steam shortcut.  Installing the package
# is therefore only half the job; without an entry here it exists only in
# Plasma's launcher, which is the mode you switched away from.
#
# ── Why it is not just a file in the Nix store ────────────────────────────
# Steam keeps those entries in `shortcuts.vdf`: a *binary* VDF blob, one per
# Steam account, under `userdata/<steamid>/config/`.  Three properties rule
# out the usual approaches:
#
#   * The steamid is not known at build time — it appears only after someone
#     logs into Steam on the machine — so the path cannot be written down in
#     a NixOS module.  The directory is discovered at runtime instead.
#   * Steam rewrites the file itself (every shortcut edit, and again on
#     exit), so it cannot be a symlink into the store or a read-only file;
#     it has to stay a writable regular file that we *merge into*.
#   * It also holds state we have no business discarding — shortcuts added
#     by hand, per-entry controller layouts, LastPlayTime.
#
# So the mechanism is parse / merge / write back, run once before the display
# manager starts, matching declared entries by AppName.  Entries we do not
# know about are left exactly as they were; declared ones are created if
# missing and corrected if their target moved.  Running before the display
# manager is what makes the merge safe: Steam reads the file at startup and
# rewrites it wholesale at exit, so touching it while Steam is live would be
# a lost update.  The tool refuses to run in that case rather than racing.
#
# The result is idempotent and survives impermanence rollback for free — it
# re-runs on every boot, so even a wiped Steam config comes back with the
# declared entries as soon as the account is logged in again.
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.gaming;

  userHome = config.users.users.${cfg.user}.home;

  shortcutType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = ''
          Name shown in the Steam library. This is also the *identity* of the
          entry: the merge matches on it, so renaming a shortcut here leaves
          the old one behind rather than renaming it in place.
        '';
        example = "Jellyfin";
      };

      exe = lib.mkOption {
        type = lib.types.str;
        description = ''
          Executable to launch. Prefer a stable path such as
          `/run/current-system/sw/bin/<name>` over a `''${pkg}/bin/<name>`
          store path: Steam derives a shortcut's app id from the exe string,
          and a store path that changes on every rebuild makes Steam treat
          the entry as a different game each time — losing its artwork,
          controller layout and play time.
        '';
        example = "/run/current-system/sw/bin/jellyfin-desktop";
      };

      arguments = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Launch options passed to `exe`.";
        example = "--fullscreen --tv";
      };

      startDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        defaultText = lib.literalExpression "dirname exe";
        description = "Working directory. Defaults to the directory holding `exe`.";
      };

      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Small icon for the library list. PNG — Steam's image loader does
          not read SVG, so render one at build time rather than pointing at
          an app's `hicolor/scalable` asset directly.
        '';
      };

      coverArt = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Portrait cover (600×900 PNG) for the library grid — the tile you
          actually see in Big Picture. Without it the entry is a grey box
          with the name written on it, which on a TV is the difference
          between a launcher and a bug report.

          Installed as `userdata/<id>/config/grid/<appid>p.png`, the same
          place SteamGridDB tooling writes to, so hand-picked art set later
          from within Steam simply overwrites it.
        '';
      };

      tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Steam library categories to file the entry under.";
        example = [ "Media" ];
      };
    };
  };

  # What the runtime tool consumes. Kept as JSON rather than baked into the
  # script so the two halves stay readable: Nix decides *what* the entries
  # are, the tool only knows how to merge them into a binary blob.
  #
  # Store paths inside this file are scanned as references, so the generated
  # artwork is a dependency of the unit and cannot be garbage-collected out
  # from under a shortcut that points at it.
  spec = pkgs.writeText "clanarchy-steam-shortcuts.json" (
    builtins.toJSON (
      map (s: {
        inherit (s) name arguments tags;
        exe = s.exe;
        startDir = if s.startDir != null then s.startDir else builtins.dirOf s.exe;
        icon = s.icon;
        coverArt = s.coverArt;
      }) cfg.shortcuts
    )
  );

  writer = pkgs.writers.writePython3Bin "clanarchy-steam-shortcuts" { flakeIgnore = [ "E501" ]; } ''
    """Merge declared non-Steam shortcuts into Steam's binary shortcuts.vdf."""

    import json
    import os
    import shutil
    import struct
    import sys
    import zlib

    SPEC = "${spec}"
    HOME = "${userHome}"

    # Binary VDF: a tag byte, a NUL-terminated key, then the value.
    #   0x00  nested map, terminated by 0x08
    #   0x01  NUL-terminated UTF-8 string
    #   0x02  little-endian signed int32
    #   0x08  end of map
    MAP, STR, INT, END = 0x00, 0x01, 0x02, 0x08


    def read_map(buf, pos):
        out = {}
        while True:
            tag = buf[pos]
            pos += 1
            if tag == END:
                return out, pos
            end = buf.index(b"\0", pos)
            key = buf[pos:end].decode("utf-8", "replace")
            pos = end + 1
            if tag == MAP:
                val, pos = read_map(buf, pos)
            elif tag == STR:
                end = buf.index(b"\0", pos)
                val = buf[pos:end].decode("utf-8", "replace")
                pos = end + 1
            elif tag == INT:
                val = struct.unpack("<i", buf[pos:pos + 4])[0]
                pos += 4
            else:
                raise ValueError("unknown VDF tag 0x%02x at offset %d" % (tag, pos - 1))
            out[key] = val


    def write_map(node):
        out = bytearray()
        for key, val in node.items():
            enc = key.encode("utf-8") + b"\0"
            if isinstance(val, dict):
                out += bytes([MAP]) + enc + write_map(val)
            elif isinstance(val, int):
                out += bytes([INT]) + enc + struct.pack("<i", val)
            else:
                out += bytes([STR]) + enc + val.encode("utf-8") + b"\0"
        out += bytes([END])
        return bytes(out)


    def app_id(exe, name):
        """Steam's own id for a non-Steam shortcut: crc32 of exe+name, high bit set.

        Reproducing it rather than leaving the field at 0 keeps artwork
        filenames predictable, and keeps the id stable if the entry is ever
        removed and recreated.
        """
        return zlib.crc32((exe + name).encode("utf-8")) | 0x80000000


    def signed(u32):
        return struct.unpack("<i", struct.pack("<I", u32))[0]


    def unsigned(i32):
        return struct.unpack("<I", struct.pack("<i", i32))[0]


    def steam_is_running():
        """True if any process looks like a running Steam client.

        Steam holds shortcuts.vdf in memory and writes it back on exit, so a
        merge underneath a live client would simply be overwritten. Checked by
        reading /proc directly to avoid pulling procps into the closure.
        """
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            try:
                with open("/proc/%s/comm" % entry) as handle:
                    comm = handle.read().strip()
            except OSError:
                continue
            if comm in ("steam", "steamwebhelper", "steam-runtime"):
                return True
        return False


    def steam_config_dirs():
        """Every logged-in Steam account's config dir, deduplicated by real path.

        Both well-known Steam roots are probed: ~/.steam/steam is the classic
        one, ~/.local/share/Steam is where the machines in this fleet actually
        keep it (often as a symlink onto a bulk pool).
        """
        seen, dirs = set(), []
        for root in (".steam/steam", ".steam/root", ".local/share/Steam"):
            userdata = os.path.join(HOME, root, "userdata")
            if not os.path.isdir(userdata):
                continue
            for account in sorted(os.listdir(userdata)):
                cfg = os.path.realpath(os.path.join(userdata, account, "config"))
                if account == "0" or not os.path.isdir(cfg) or cfg in seen:
                    continue
                seen.add(cfg)
                dirs.append(cfg)
        return dirs


    def new_entry(want, exe, start_dir):
        entry = {
            "appid": signed(app_id(exe, want["name"])),
            "AppName": want["name"],
            "Exe": exe,
            "StartDir": start_dir,
            "icon": want["icon"] or "",
            "ShortcutPath": "",
            "LaunchOptions": want["arguments"],
            "IsHidden": 0,
            "AllowDesktopConfig": 1,
            "AllowOverlay": 1,
            "OpenVR": 0,
            "Devkit": 0,
            "DevkitGameID": "",
            "DevkitOverrideAppID": 0,
            "LastPlayTime": 0,
            "FlatpakAppID": "",
            "tags": {str(i): t for i, t in enumerate(want["tags"])},
        }
        return entry


    def install_cover(config_dir, entry, source):
        """Drop portrait art where Steam looks for a shortcut's grid tile."""
        appid = unsigned(entry.get("appid", 0))
        if not appid:
            return False
        grid = os.path.join(config_dir, "grid")
        os.makedirs(grid, exist_ok=True)
        target = os.path.join(grid, "%dp.png" % appid)
        if os.path.exists(target) and os.path.getsize(target) == os.path.getsize(source):
            return False
        shutil.copyfile(source, target)
        os.chmod(target, 0o644)
        return True


    def merge(config_dir, wanted):
        path = os.path.join(config_dir, "shortcuts.vdf")
        doc = {"shortcuts": {}}
        if os.path.exists(path):
            with open(path, "rb") as handle:
                raw = handle.read()
            try:
                doc, _ = read_map(raw, 0)
            except (IndexError, ValueError, struct.error) as err:
                # Refuse to guess at a file we cannot read: keep the original
                # next to it so a bad parse is recoverable, and start clean
                # rather than leaving the couch user with no launcher at all.
                print("warning: %s is unreadable (%s); starting a fresh one" % (path, err), file=sys.stderr)
                shutil.copyfile(path, path + ".corrupt")
                doc = {"shortcuts": {}}

        entries = list(doc.get("shortcuts", {}).values())
        changed = False

        for want in wanted:
            # Steam stores both of these quoted, and derives the app id from
            # the quoted form — so quote before hashing, not after.
            exe = '"%s"' % want["exe"]
            start_dir = '"%s"' % want["startDir"]

            entry = next((e for e in entries if e.get("AppName") == want["name"]), None)
            if entry is None:
                entry = new_entry(want, exe, start_dir)
                entries.append(entry)
                changed = True
                print("added shortcut %r in %s" % (want["name"], config_dir))
            else:
                # Only the fields we own. Anything Steam or the user set on
                # the entry — controller layout, artwork, play time — stays.
                for key, value in (
                    ("Exe", exe),
                    ("StartDir", start_dir),
                    ("LaunchOptions", want["arguments"]),
                    ("icon", want["icon"] or ""),
                ):
                    if entry.get(key) != value:
                        entry[key] = value
                        changed = True

            if want["coverArt"]:
                changed |= install_cover(config_dir, entry, want["coverArt"])

        if not changed:
            return False

        doc["shortcuts"] = {str(i): e for i, e in enumerate(entries)}
        tmp = path + ".new"
        with open(tmp, "wb") as handle:
            handle.write(write_map(doc))
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
        return True


    def main():
        with open(SPEC) as handle:
            wanted = json.load(handle)
        if not wanted:
            return 0

        if steam_is_running():
            print("Steam is running; leaving shortcuts.vdf alone", file=sys.stderr)
            return 0

        dirs = steam_config_dirs()
        if not dirs:
            # Entirely normal before anyone has signed into Steam on this
            # machine. The unit runs again on the next boot.
            print("no Steam account data under %s yet; nothing to do" % HOME)
            return 0

        for config_dir in dirs:
            merge(config_dir, wanted)
        return 0


    if __name__ == "__main__":
        sys.exit(main())
  '';
in
{
  options.clanarchy.gaming.shortcuts = lib.mkOption {
    type = lib.types.listOf shortcutType;
    default = [ ];
    description = ''
      Non-Steam applications to add to the gaming user's Steam library, so
      they are launchable from Big Picture without a keyboard.

      Merged into Steam's `shortcuts.vdf` on every boot, before the display
      manager starts. Entries are matched by `name`; anything not listed here
      — including shortcuts added by hand from within Steam — is left alone,
      and removing an entry from this list does *not* remove it from Steam.
    '';
    example = lib.literalExpression ''
      [
        {
          name = "Jellyfin";
          exe = "/run/current-system/sw/bin/jellyfin-desktop";
          arguments = "--fullscreen --tv";
        }
      ]
    '';
  };

  config = lib.mkIf (cfg.enable && cfg.shortcuts != [ ]) {
    # Also on PATH: re-running it by hand after signing into Steam for the
    # first time beats rebooting to get the entries.
    environment.systemPackages = [ writer ];

    systemd.services.clanarchy-steam-shortcuts = {
      description = "Merge declared non-Steam shortcuts into Steam's library";
      wantedBy = [ "multi-user.target" ];

      # Before the display manager, because that is what starts the session
      # that starts Steam — see the lost-update note at the top of this file.
      before = [ "display-manager.service" ];

      # tmpfiles, not just local-fs: on ernst the Steam directory is an `L+`
      # rule symlinking ~/.local/share/Steam onto the bulk pool (see
      # machines/ernst/htpc.nix), so starting before that rule has run means
      # looking for userdata in a directory that does not exist yet — which
      # this tool would report as "no Steam account data" and skip.
      after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # As the gaming user, so the files land with the right ownership and
        # the unit cannot write anywhere that user could not already.
        User = cfg.user;
        Group = config.users.users.${cfg.user}.group;
        ExecStart = "${writer}/bin/clanarchy-steam-shortcuts";
      };
    };
  };
}
