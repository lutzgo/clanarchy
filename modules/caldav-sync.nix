# CalDAV sync for user lgo: org → VTODO → Nextcloud (push-only, phase 1).
#
# Pipeline:
#   org-to-ics  parses todo.org / habits.org and writes .ics VTODO files
#               into a local vdir collection directory.
#   vdirsyncer  pushes that vdir to the Nextcloud CalDAV server.
#               conflict_resolution = "a wins" makes org the source of truth.
#
# Entries appear in Nextcloud's Tasks app (VTODO), not in the calendar grid.
# A VEVENT / two-way phase can be added later.
#
# First-time setup after deploying:
#   clan vars generate miralda     # prompts for the Nextcloud app password
#
# The app password is created in Nextcloud:
#   Settings → Security → App passwords → Add new app password
#
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.caldavSync;

  # ── org-to-ics Python script ───────────────────────────────────────────
  #
  # Reads org files, extracts TODO headings with SCHEDULED/DEADLINE timestamps,
  # and writes one .ics VTODO file per entry into the output vdir directory.
  #
  # UIDs are derived from sha256(filepath:heading) so re-runs update existing
  # entries instead of creating duplicates.  Stale entries (headings removed
  # from org) are deleted.  The "@org-to-ics" suffix in UIDs distinguishes
  # script-generated entries from externally created ones.
  orgToIcsSrc = pkgs.writeText "org-to-ics.py" ''
    import argparse, hashlib, sys, re
    from pathlib import Path
    from datetime import datetime, date, timezone
    import orgparse
    from icalendar import Calendar, Todo, Journal

    def uid_todo(path, heading):
        return hashlib.sha256(f"{path}:{heading}".encode()).hexdigest()[:32] + "@org-to-ics-t"

    def uid_journal(path):
        return hashlib.sha256(str(path).encode()).hexdigest()[:32] + "@org-to-ics-j"

    def to_dt(orgdate):
        if orgdate is None:
            return None
        try:
            return orgdate.start
        except Exception:
            return None

    def make_vtodo(node, src):
        if not hasattr(node, 'todo') or not node.todo or not node.heading:
            return None
        t = Todo()
        t.add("uid",     uid_todo(src, node.heading))
        t.add("summary", node.heading)
        t.add("dtstamp", datetime.now(tz=timezone.utc))
        state = node.todo.upper()
        if state == "DONE":
            t.add("status", "COMPLETED")
        elif state == "CANCELLED":
            t.add("status", "CANCELLED")
        else:
            t.add("status", "NEEDS-ACTION")
        if node.scheduled:
            dt = to_dt(node.scheduled)
            if dt: t.add("dtstart", dt)
        if node.deadline:
            dt = to_dt(node.deadline)
            if dt: t.add("due", dt)
        if node.tags:
            t.add("categories", list(node.tags))
        if node.priority:
            t.add("priority", {"A": 1, "B": 5, "C": 9}.get(node.priority, 5))
        return t

    def parse_date_from_stem(stem):
        """Parse YYYYMMDD or YYYY-MM-DD from org-roam daily filename stem."""
        m = re.fullmatch(r'(\d{4})-?(\d{2})-?(\d{2})', stem)
        if m:
            try:
                return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            except ValueError:
                pass
        return None

    def make_vjournal(filepath):
        dt = parse_date_from_stem(filepath.stem)
        if dt is None:
            return None
        content = filepath.read_text(encoding="utf-8", errors="replace")
        j = Journal()
        j.add("uid",         uid_journal(filepath.resolve()))
        j.add("dtstart",     dt)
        j.add("dtstamp",     datetime.now(tz=timezone.utc))
        j.add("summary",     dt.isoformat())
        j.add("description", content)
        return j

    def process_todos(org_file, out_dir):
        src = str(org_file.resolve())
        try:
            org = orgparse.load(src)
        except Exception as e:
            print(f"error loading {src}: {e}", file=sys.stderr)
            return set()
        written = set()
        for node in org:
            t = make_vtodo(node, src)
            if t is None:
                continue
            u = str(t.get("uid"))
            cal = Calendar()
            cal.add("prodid", "-//org-to-ics//EN")
            cal.add("version", "2.0")
            cal.add_component(t)
            (out_dir / f"{u}.ics").write_bytes(cal.to_ical())
            written.add(u)
        return written

    def process_journals(journal_dir, out_dir):
        written = set()
        for f in sorted(journal_dir.glob("*.org")):
            j = make_vjournal(f)
            if j is None:
                continue
            u = str(j.get("uid"))
            cal = Calendar()
            cal.add("prodid", "-//org-to-ics//EN")
            cal.add("version", "2.0")
            cal.add_component(j)
            (out_dir / f"{u}.ics").write_bytes(cal.to_ical())
            written.add(u)
        return written

    p = argparse.ArgumentParser(description="Convert org TODOs/dailies to iCalendar")
    p.add_argument("files", nargs="+", type=Path)
    p.add_argument("--output-dir", "-o", type=Path, required=True)
    p.add_argument("--journal-dir", "-j", type=Path, default=None)
    args = p.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    written = set()
    for f in args.files:
        if f.exists():
            written |= process_todos(f, args.output_dir)
        else:
            print(f"warning: {f} not found", file=sys.stderr)
    if args.journal_dir and args.journal_dir.is_dir():
        written |= process_journals(args.journal_dir, args.output_dir)

    # Remove stale entries generated by this script (all suffix variants)
    for f in args.output_dir.glob("*@org-to-ics*.ics"):
        if f.stem not in written:
            f.unlink()
  '';

  pythonEnv = pkgs.python3.withPackages (ps: [ ps.orgparse ps.icalendar ]);

  org-to-ics = pkgs.writeShellScriptBin "org-to-ics" ''
    exec ${pythonEnv}/bin/python3 ${orgToIcsSrc} "$@"
  '';

  # ── Derived paths ──────────────────────────────────────────────────────
  vdirBase  = "/home/${cfg.username}/.local/share/vdirsyncer";
  orgVdir   = "${vdirBase}/org";
  statusDir = "${vdirBase}/status";
  orgOutDir = "${orgVdir}/${cfg.calendarName}";

  orgFilePaths = map (f: "/home/${cfg.username}/${cfg.orgNoteDir}/${f}") cfg.syncFiles;

  # CalDAV password file path — resolved from the clan var at Nix eval time.
  # The file is written by `clan vars generate miralda` and encrypted with
  # the YubiKey age key; it lives outside the Nix store.
  passwordPath = config.clan.core.vars.generators.caldav-app-password.files."password".path;

in
{
  options.clanarchy.caldavSync = {
    enable = lib.mkEnableOption "CalDAV org-push sync via vdirsyncer";

    nextcloudHost = lib.mkOption {
      type        = lib.types.str;
      default     = "citizengo.io";
      description = "Nextcloud hostname (without scheme, e.g. citizengo.io).";
    };

    username = lib.mkOption {
      type        = lib.types.str;
      default     = "lgo";
      description = "Nextcloud username.";
    };

    calendarName = lib.mkOption {
      type        = lib.types.str;
      default     = "lgo";
      description = "CalDAV calendar slug (collection name in Nextcloud).";
    };

    orgNoteDir = lib.mkOption {
      type        = lib.types.str;
      default     = "citizengo/note";
      description = "Path to the org notes directory, relative to home.";
    };

    syncFiles = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [ "todo.org" "habits.org" ];
      description = "Org files to convert and push (relative to orgNoteDir).";
    };

    journalDir = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      description = "Path to org-roam dailies directory (relative to home) for VJOURNAL export. Set to null to disable.";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Clan var: Nextcloud app password ─────────────────────────────────
    clan.core.vars.generators.caldav-app-password = {
      files."password"  = { secret = true; neededFor = "users"; };
      prompts."password" = {
        description = "Nextcloud app password for CalDAV (Settings → Security → App passwords)";
        type        = "hidden";
      };
      runtimeInputs = [ pkgs.coreutils ];
      script = ''${pkgs.coreutils}/bin/cat "$prompts/password" > "$out/password"'';
    };

    # sops-install-secrets places every clan var as 0400 root:root with no
    # per-file owner option exposed.  Run a chown after setupSecretsForUsers
    # so the user service can read the password without sudo.
    system.activationScripts.caldav-secret-perms = {
      deps = [ "setupSecretsForUsers" ];
      text = ''
        if [ -f /run/secrets-for-users/vars/caldav-app-password/password ]; then
          chown ${cfg.username} /run/secrets-for-users/vars/caldav-app-password/password
        fi
      '';
    };

    # ── Home Manager config for lgo ───────────────────────────────────────
    home-manager.users.${cfg.username} = { ... }: {

      # vdirsyncer config — rendered at build time with all options resolved.
      # The password is read at runtime from the clan vars file path.
      xdg.configFile."vdirsyncer/config".text = ''
        [general]
        status_path = "${statusDir}"

        [pair org_push]
        a = "org_local"
        b = "caldav_remote"
        collections = ["${cfg.calendarName}"]
        conflict_resolution = "a wins"

        [storage org_local]
        type    = "filesystem"
        path    = "${orgVdir}"
        fileext = ".ics"

        [storage caldav_remote]
        type     = "caldav"
        url      = "https://${cfg.nextcloudHost}/remote.php/dav/calendars/${cfg.username}/"
        username = "${cfg.username}"
        password.fetch = ["command", "cat", "${passwordPath}"]
      '';

      # khal config — points at the same vdir org collection.
      xdg.configFile."khal/config".text = ''
        [calendars]
        [[org]]
        path   = ${orgOutDir}/
        type   = discover

        [sqlite]
        path = ${vdirBase}/khal.db

        [locale]
        timeformat     = %H:%M
        dateformat     = %Y-%m-%d
        datetimeformat = %Y-%m-%dT%H:%M
        timezone       = Europe/Berlin
      '';

      home.packages = [ pkgs.khal org-to-ics ];

      # ── org-to-ics: convert org files on every save ───────────────────
      systemd.user.services.org-to-ics = {
        Unit.Description = "Convert org TODO/habit entries to VTODO iCalendar";
        Service = {
          Type      = "oneshot";
          ExecStart = "${org-to-ics}/bin/org-to-ics ${lib.concatStringsSep " " orgFilePaths} --output-dir ${orgOutDir}"
            + lib.optionalString (cfg.journalDir != null) " --journal-dir /home/${cfg.username}/${cfg.journalDir}";
        };
      };

      # Path unit watches the org files; fires org-to-ics on every write.
      systemd.user.paths.org-to-ics = {
        Unit.Description  = "Watch org files for changes, trigger org-to-ics";
        Path = {
          PathModified = orgFilePaths;
          Unit         = "org-to-ics.service";
        };
        Install.WantedBy = [ "default.target" ];
      };

      # ── vdirsyncer: push vdir to Nextcloud CalDAV ─────────────────────
      systemd.user.services.vdirsyncer = {
        Unit = {
          Description = "Push org iCalendar entries to Nextcloud CalDAV";
          After       = [ "network.target" ];
        };
        Service = {
          Type = "oneshot";
          # Ensure the vdir collection and status dirs exist before syncing.
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${orgOutDir} ${statusDir}";
          ExecStart    = "${pkgs.vdirsyncer}/bin/vdirsyncer sync org_push";
        };
      };

      systemd.user.timers.vdirsyncer = {
        Unit.Description = "Run vdirsyncer CalDAV push every 15 minutes";
        Timer = {
          OnBootSec       = "2min";
          OnUnitActiveSec = "15min";
          Unit            = "vdirsyncer.service";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
  };
}
