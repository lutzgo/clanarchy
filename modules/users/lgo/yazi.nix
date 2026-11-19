# ============================================================
# YAZI — modules/users/lgo/yazi.nix
# ============================================================
#
# Home Manager module, imported by modules/users/lgo.nix, so it applies to
# every machine carrying lgo (miralda and jens). The gvfs daemon the `gvfs`
# plugin talks to is a SYSTEM service and is enabled next to the import, in
# lgo.nix; yazi.nvim is enabled in the nvf block there too.
#
# Through programs.yazi, never a bare package: Stylix's yazi target only sets
# `programs.yazi.theme`, and Home Manager writes nothing from it otherwise.
#
# ── PLUGINS AND WHERE TO FIND THEM ──────────────────────────────────────
#
#   ouch          archive previews; `C` compresses; extracting (yazi's own
#                 "extract" opener on an archive) goes through ouch too
#   gvfs          one `M` menu for everything mountable: MTP phones, PTP
#                 cameras, USB drives (encrypted too), and saved URIs for
#                 WebDAV (davs://), SMB, SFTP, FTP, NFS. Saved URIs live in
#                 ~/.config/yazi/gvfs.private (persisted); passwords go to
#                 gnome-keyring, never into that file.
#   mediainfo     audio/video/image: thumbnail + metadata (replaces the
#                 built-in image/video previewers, which it uses underneath)
#   piper+glow    rendered Markdown (the glow plugin itself is broken on
#                 yazi 26.9 — see the previewer rule)
#   tables        CSV/TSV/Parquet as a duckdb table   } piper + yazi-doc-preview;
#   office docs   docx/xlsx/odt/pptx… as text via      } both plugins are broken
#                 LibreOffice                          } on yazi 26.9
#   git           status signs per file; works in jj repos (colocated .git)
#   wl-clipboard  `<C-y>` copies the selected FILES to the Wayland clipboard
#   drag          `<A-d>` drags them into another app (ripdrag).
#                 NOT <C-d> as its README suggests: that is half-page down.
#   chmod         `c m`; sudo: the `R` menu (paste, rename, create, trash,
#                 delete, chmod as root)
#   full-border, smart-enter (`l` enters a directory OR opens a file)
#
# Keymap search needs no plugin: `~` (or F1) opens the help, and typing
# there filters it.
#
# ── TWO KEYS MOVED, ON PURPOSE ──────────────────────────────────────────
#
# lazyjj was on a bare `g`. A single-key prepend shadows every built-in `g`
# chord — `gg` (top), `gh`/`gc`/`gd` (jump home/config/downloads), `gf` — so
# those were dead. It is now `g j`. DuckDB's README also asks for H/L, which
# are yazi's history back/forward; they are not bound.
#
# ── ZELLIJ ───────────────────────────────────────────────────────────────
#
# Zellij already opens yazi (Alt f). The reverse: inside zellij, `s` and
# `g j` open a zellij pane instead of a separate foot window. yazi runs
# `shell` through sh, so this is POSIX sh, and $PWD is yazi's directory.
{
  osConfig,
  pkgs,
  ...
}: let
  editor = osConfig.clanarchy.users.lgo.editor or "govim";
  editorBin =
    if editor == "govim"
    then "nvim"
    else "hx";
  editorDesc =
    if editor == "govim"
    then "Neovim"
    else "Helix";

  # One list, used for both preloaders and previewers: they must match, or a
  # file is preloaded by one plugin and previewed by another.
  mediaRules = [
    {
      mime = "{audio,video,image}/*";
      run = "mediainfo";
    }
    {
      mime = "application/{subrip,postscript,illustrator,vnd.adobe.illustrator,eps}";
      run = "mediainfo";
    }
  ];
  # Tables and office documents, through piper and this one script — NOT the
  # duckdb and office plugins. Both packaged versions (2025-05, 2025-09) call
  # plugin APIs yazi 26.9 removed and fail on every file ("attempt to
  # concatenate a nil value"; "attempt to call a nil value (field
  # 'preview_widgets')"), seen rendering them on 2026-11-19.
  #
  # LibreOffice runs on its OWN profile, so a preview never collides with a
  # LibreOffice already open. `--cat` handles only text documents, hence the
  # CSV and PDF detours for spreadsheets and slides. The path reaches duckdb
  # via getenv, not spliced into SQL, so a quote in a file name is harmless.
  docPreview = pkgs.writeShellApplication {
    name = "yazi-doc-preview";
    runtimeInputs = with pkgs; [libreoffice duckdb poppler-utils];
    text = ''
      f=$1
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      lo() {
        soffice "-env:UserInstallation=file://''${XDG_RUNTIME_DIR:-/tmp}/yazi-doc-preview-lo" \
          --headless "$@" 2>/dev/null
      }
      table() {
        F=$1 duckdb -c "SELECT * FROM read_csv_auto(getenv('F')) LIMIT 200"
      }
      case "''${f,,}" in
        *.csv | *.tsv) table "$f" ;;
        *.parquet) F=$f duckdb -c "SELECT * FROM read_parquet(getenv('F')) LIMIT 200" ;;
        *.xlsx | *.xls | *.ods)
          lo --convert-to csv --outdir "$tmp" "$f" >/dev/null
          table "$tmp"/*.csv
          ;;
        *.pptx | *.ppt | *.odp)
          lo --convert-to pdf --outdir "$tmp" "$f" >/dev/null
          pdftotext -layout "$tmp"/*.pdf -
          ;;
        # --cat starts with a UTF-8 byte-order mark, which garbles the
        # first word of the preview; strip it.
        *) lo --cat "$f" | sed '1s/^\xEF\xBB\xBF//' ;;
      esac
    '';
  };
  docRun = ''piper -- yazi-doc-preview "$1"'';

  key = on: run: desc: {inherit on run desc;};
in {
  programs.yazi = {
    enable = true;

    # Explicit, to settle the stateVersion warning: `y` is the shell wrapper
    # that cd's into the directory yazi was left in (nushell included).
    shellWrapperName = "y";

    plugins = {
      inherit
        (pkgs.yaziPlugins)
        ouch
        gvfs
        mediainfo
        piper
        git
        wl-clipboard
        drag
        chmod
        sudo
        full-border
        smart-enter
        ;
    };

    # Put on yazi's PATH only (the wrapper), not into home.packages.
    extraPackages = with pkgs; [
      ouch
      _7zz # yazi's built-in archive listing
      mediainfo
      imagemagick
      ffmpeg
      poppler-utils # PDF previews
      resvg # SVG previews
      glow
      docPreview # brings libreoffice (the same attribute as
      # apps/desktop-tools.nix, so no second copy) and duckdb
      nushell # the sudo plugin runs its file operations as a nu script
      ripdrag
      wl-clipboard
      glib # `gio`, which the gvfs plugin drives
      libsecret # `secret-tool`, for gvfs passwords in gnome-keyring
      jq
      fd
      ripgrep
      fzf
      zoxide
      file
    ];

    initLua = ''
      require("full-border"):setup()
      require("git"):setup()
      require("smart-enter"):setup({ open_multi = true })
      require("gvfs"):setup({
        password_vault = "keyring",
        save_password_autoconfirm = true,
      })
    '';

    settings = {
      plugin = {
        prepend_fetchers = [
          {
            url = "*";
            run = "git";
            group = "git";
          }
          {
            url = "*/";
            run = "git";
            group = "git";
          }
        ];
        # Media only. yazi caps preloaders at 16 IN TOTAL, its own 8
        # included, and rejects a config over the cap WHOLE ("Preloaders
        # exceed the limit of 16") — falling back to preset settings with
        # every plugin previewer gone. piper rules need no preloader.
        prepend_preloaders = mediaRules;
        prepend_previewers =
          [
            {
              mime = "application/{*zip,tar,bzip2,7z*,rar,xz,zstd,java-archive}";
              run = "ouch";
            }
            # glow THROUGH PIPER, not the glow plugin: that one (2025-06)
            # calls a plugin API yazi 26.9 removed — "attempt to call a nil
            # value (method 'args')" on every Markdown file.
            {
              url = "*.md";
              run = ''piper -- CLICOLOR_FORCE=1 glow -w=$w -s=dark "$1"'';
            }
            {
              url = "*.{csv,tsv,parquet}";
              run = docRun;
            }
            # yazi strips `vnd.` from MIME types, hence `ms-excel` for
            # application/vnd.ms-excel. Listed rather than `ms-*`, which also
            # catches application/ms-opentype — fonts, sent to LibreOffice.
            {
              mime = "application/{openxmlformats-officedocument.*,oasis.opendocument.*,msword,ms-excel,ms-powerpoint}";
              run = docRun;
            }
          ]
          ++ mediaRules;
      };

      opener.extract = [
        {
          run = ''ouch d -y "$@"'';
          desc = "Extract here with ouch";
          for = "unix";
        }
      ];
    };

    keymap.mgr.prepend_keymap = [
      (key ["e"] "open --with ${editorBin}" "Open in ${editorDesc}")
      (key ["s"]
        ''shell 'if [ -n "$ZELLIJ" ]; then zellij action new-pane --cwd "$PWD"; else foot --working-directory "$PWD"; fi' ''
        "Open terminal here (zellij pane inside zellij)")
      (key ["g" "j"]
        ''shell 'if [ -n "$ZELLIJ" ]; then zellij run --floating --close-on-exit --cwd "$PWD" -- lazyjj; else foot -T lazyjj -e lazyjj; fi' ''
        "Lazyjj")
      (key ["A"] "select_all" "Select all")
      (key ["l"] "plugin smart-enter" "Enter directory or open file")

      # Archives
      (key ["C"] "plugin ouch" "Compress selection with ouch")

      # Mounts (gvfs)
      (key ["M" "m"] "plugin gvfs -- select-then-mount --jump" "Mount a device or saved URI, then jump there")
      (key ["M" "u"] "plugin gvfs -- select-then-unmount" "Unmount")
      (key ["M" "U"] "plugin gvfs -- select-then-unmount --eject" "Eject a drive")
      (key ["M" "a"] "plugin gvfs -- add-mount" "Add a mount URI (davs://, smb://, sftp://…)")
      (key ["M" "e"] "plugin gvfs -- edit-mount" "Edit a mount URI")
      (key ["M" "r"] "plugin gvfs -- remove-mount" "Remove a mount URI")
      (key ["g" "m"] "plugin gvfs -- jump-to-device" "Jump to a mounted device")
      (key ["`" "`"] "plugin gvfs -- jump-back-prev-cwd" "Jump back from a device")

      # Clipboard, drag, permissions
      (key ["<C-y>"] "plugin wl-clipboard" "Copy files to the system clipboard")
      (key ["<A-d>"] "plugin drag" "Drag files into another app")
      (key ["c" "m"] "plugin chmod" "chmod selection")

      # As root (sudo)
      (key ["R" "p" "p"] "plugin sudo -- paste" "sudo paste")
      (key ["R" "P"] "plugin sudo -- paste --force" "sudo paste (overwrite)")
      (key ["R" "r"] "plugin sudo -- rename" "sudo rename")
      (key ["R" "a"] "plugin sudo -- create" "sudo create")
      (key ["R" "d"] "plugin sudo -- remove" "sudo trash")
      (key ["R" "D"] "plugin sudo -- remove --permanently" "sudo delete")
      (key ["R" "m"] "plugin sudo -- chmod" "sudo chmod")
    ];
  };
}
