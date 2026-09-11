# Apps

!!! warning "Auto-generated"
    Do not edit by hand — regenerate with `gendocs` in the devShell.

Optional application bundles, and the per-machine service options that go with them. Enable the sets that apply to a machine.

| Option | Type | Description |
|--------|------|-------------|
| `clanarchy.apps.communication.enable` | `boolean` | Whether to enable communication and connectivity apps (Signal, Anytype, Valent/KDE Connect). |
| `clanarchy.apps.containers.enable` | `boolean` | Whether to enable container runtime (Podman with Docker compatibility + docker-compose). |
| `clanarchy.apps.desktopTools.enable` | `boolean` | Whether to enable desktop utility apps (terminal, fastfetch, document tools, color calibration, LibreOffice). |
| `clanarchy.apps.emulation.switch.enable` | `boolean` | Whether to enable Nintendo Switch emulation (Eden). |
| `clanarchy.apps.flatpak.enable` | `boolean` | Whether to enable Flatpak sandbox with Flathub remote. |
| `clanarchy.apps.gnomeCoreApps.enable` | `boolean` | Whether to enable GNOME core apps (text editor, calculator, software center). |
| `clanarchy.apps.graphics.power.enable` | `boolean` | Whether to enable professional graphics tools (darktable, Krita, color calibration). |
| `clanarchy.apps.graphics.simple.enable` | `boolean` | Whether to enable image editing (GIMP, Inkscape, image viewer). |
| `clanarchy.apps.media.enable` | `boolean` | Whether to enable media apps (OBS Studio, VLC, calibre). |
| `clanarchy.immich.upload.enable` | `boolean` | Whether to enable pushing darktable exports to Immich on a timer. |
| `clanarchy.immich.upload.extensions` | `list of string` | Extensions considered for upload, case-insensitively.  NO RAW FORMATS, and that is a decision rather than an oversight: this is the finished-export path, so the ILCE's ARWs stay in darktable's own archive. (The ~6.1k DNGs already on the old server ARE imported, by `photo-import` on ernst, because they are the only copy of those shots. The distinction is between an archive and a workflow.) Adding `.arw` here would reverse that silently.  |
| `clanarchy.immich.upload.inboxDir` | `string` | Where darktable exports to. Set this as the export module's target directory once; nothing else about darktable has to change.  It is an ordinary directory rather than anything clever precisely so that dropping a file into it by hand does the same thing.  |
| `clanarchy.immich.upload.interval` | `string` | `OnUnitActiveSec` for the timer. Latency, not throughput: an export session produces a batch, and fifteen minutes later it is on the server. A shorter interval would mostly wake a laptop up to find an empty directory.  |
| `clanarchy.immich.upload.server` | `string` | The Immich server, as a plain origin.  No `/api` suffix: immich-cli 2.7.5 fetches `.well-known/immich` from this URL and takes the API endpoint from the answer, falling back to the URL as given. Verified by reading the shipped CLI, because the older `https://host/api` form is what most documentation still shows and both appear to work until the day the fallback is the one running.  |
| `clanarchy.immich.upload.settleMinutes` | `signed integer` | How long a file must have been unmodified before it is eligible.  This is the whole reason the pipeline is a timer rather than `immich upload --watch`: a darktable export that is still being written will upload as a truncated image with a perfectly valid checksum, which no retry can detect afterwards.  |
| `clanarchy.immich.upload.uploadedDir` | `string` | Where files go after a successful upload, in dated subdirectories.  MOVED ASIDE RATHER THAN DELETED, deliberately, even though immich-cli has a `--delete` flag. The server is the copy that matters, but a local copy that survives the week costs nothing and is the only thing standing between a misconfigured run and a lost export.  Pruning this is a human decision and there is no timer for it.  |
| `clanarchy.immich.upload.user` | `string` | The account whose inbox is watched, and the user the upload runs as.  NOT the Immich account — that is decided by the API key, which belongs to whoever minted it. The two happen to both be lgo today; they are different things and a future second consumer would have to set both.  |
