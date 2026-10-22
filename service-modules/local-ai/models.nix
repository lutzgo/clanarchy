##############################################################################
# roles.models — the declarative model set
##############################################################################
{lib, ...}: {
  description = "Models to fetch and declare. Fetched to zdata, hash-verified.";

  interface.options.models = lib.mkOption {
    default = {};
    description = ''
      The models this machine serves, keyed by the name clients request.

      NO IMPERATIVE PULL.  The ollama era of this module had a `models` list
      of registry tags and a `ollama pull` loader, and it failed in the two
      ways that arrangement always fails: a tag that never existed
      (`qwen3-coder:8b`, which sat in a restart loop for months because
      qwen3-coder publishes only 30b and 480b), and a context window that
      moved silently whenever the tag was edited.  Here a model is a URL, a
      hash and a context — all three reviewed together, in one place, and the
      SAME attrset renders both the fetcher and llama-server's preset INI.

      EVERY url AND hash MUST BE VERIFIED BEFORE IT IS WRITTEN DOWN:

        nix store prefetch-file --hash-type sha256 --json <url> | jq -r .hash

      The fetcher verifies again at runtime, so a wrong hash is a failed unit
      rather than a corrupt model — but a wrong URL that happens to resolve
      is not something a hash can catch after the fact.
    '';
    type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
      options = {
        url = lib.mkOption {
          type = lib.types.str;
          description = "Direct download URL for the GGUF. Must be verified before it is committed.";
        };
        hash = lib.mkOption {
          type = lib.types.str;
          example = "sha256-…";
          description = "SRI hash of the file at `url`, from `nix store prefetch-file`.";
        };
        filename = lib.mkOption {
          type = lib.types.str;
          default = baseNameOf name;
          description = "Name the file is stored under in the model directory.";
        };

        subdir = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "checkpoints";
          description = ''
            Directory BELOW the model directory this file is stored in, or ""
            for the model directory itself.

            ADDED BY M21, AND IT EXISTS FOR ONE CONSUMER'S CONVENTIONS.
            llama-server does not care where a GGUF sits — it is handed a
            path.  ComfyUI does: it discovers models by SCANNING category
            directories (`checkpoints`, `loras`, `vae`, …) and offers
            whatever it finds in the matching node's dropdown.

            Pointed at a flat store, that scan is wrong in a way that is
            annoying rather than fatal: `folder_paths.py`'s
            `supported_pt_extensions` includes `.bin`, so Whisper's
            `ggml-large-v3-turbo-q5_0.bin` would be offered as a diffusion
            checkpoint.  (The GGUFs would not — `.gguf` is not in that set —
            which is exactly the kind of half-right that is worse than
            either.)

            So this is a layout option, not a second store.  ONE FETCHER,
            ONE HASH-VERIFIED DIRECTORY TREE, still: `extraFiles` inherit
            this subdirectory, and the inference role's preset INI derives
            its paths from the same value, so the fetcher and the server
            cannot disagree about where a file is.
          '';
        };
        description = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Human-readable label, shown in client model pickers.";
        };

        contextLength = lib.mkOption {
          type = lib.types.ints.positive;
          example = 32768;
          description = ''
            `-c` for this model, and NO DEFAULT ON PURPOSE — every model must
            state its own window.

            This is where standing note SN1 now lives, and the placement is
            the point.  Under ollama the window was derived from the model
            tag and set by one global environment variable, so editing which
            model was served silently changed the context for every client
            with no diff that showed it.  Here it sits on the model, is
            required, and moves only when someone edits this line.

            What overflowing it now does is ALSO different, and better: on
            llama.cpp it is HTTP 400 naming both numbers, where ollama
            returned HTTP 200 with the head of the prompt silently discarded
            and a fabricated answer in place of a refusal.

            Size it against VRAM.  Measured on ernst's 24560 MiB card with
            the 30B: f16 at 32768 is 21799 MiB resident; f16 at 65536 spills.
            "Spills" is the generous failure; see `residentVramMiB` for the
            one that takes the television with it.
          '';
        };

        residentVramMiB = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          example = 22800;
          description = ''
            MEASURED resident VRAM for this model, in MiB.  Never computed,
            never estimated — read off the card with the model loaded and
            every other claimant stopped:

            ```
            systemctl stop display-manager.service
            curl -s -X POST http://127.0.0.1:11434/v1/chat/completions \
              -H 'content-type: application/json' \
              -d '{"model":"<name>","messages":[{"role":"user","content":"hi"}],"max_tokens":1}'
            cat /sys/class/drm/card1/device/mem_info_vram_used
            ```

            Stopping the session first is not fussiness: measured with it up
            you measure the sum, which is the quantity that is supposed to
            be checked against, not the input to the check.

            When this and `inference.vram.totalMiB` are both set, the
            evaluator refuses a model that does not fit under the reserve.
            `null` means unmeasured — allowed, but it warns, because an
            unmeasured model is exactly the one that overruns.
          '';
        };

        kvCacheType = lib.mkOption {
          type = lib.types.enum ["f16" "q8_0" "q4_0"];
          default = "f16";
          description = ''
            `--cache-type-k` and `--cache-type-v` for this model. BOTH, always
            — see below.

            f16 BY DEFAULT, which reverses ernst's ollama-era setting, and
            the reversal is a measurement.  q8_0 was adopted only because f16
            at 65536 spilled to system RAM on ollama.  On llama.cpp f16 at
            32768 — the window ernst actually declares — fits with 2761 MiB
            to spare, and q8_0 costs 14.7% of decode there (94.6 vs 107.5
            tok/s, interleaved, n=5).  So it buys nothing at the declared
            window.

            Take q8_0 when a model genuinely needs a 64k window: that is
            21990 MiB resident at ~95 tok/s, against f16's 24529 MiB which
            does not fit.

            DO NOT QUANTISE ONLY K.  `-ctk q8_0` with V left at f16 costs
            ~45% OF DECODE (57.1 tok/s vs ~100) to save 887 MiB — a measured
            trap, not a middle ground.  This option sets both, which is why
            it is one option and not two.

            The tool-call cost M11 attributed to q8_0 (40% vs f16's 83% at a
            baseline system prompt) is NOT a factor here: with the
            `<tool_call>` reinforcement the opencode role ships, both are
            100% on both servers. The choice is purely speed for context.
          '';
        };

        servedByLlama = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether this entry becomes a section in llama-server's preset INI.

            False for weights that the GPU tier loads but llama-server does
            not — whisper's ggml model is the case that exists.  Such an entry
            is still FETCHED AND HASH-VERIFIED by the same oneshot, which is
            the whole reason it is declared here rather than in the role that
            consumes it: one model store, one verification path, one place to
            look when a file is missing.
          '';
        };

        mmproj = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Filename of the multimodal projector, for vision or audio models.
            It is a SECOND file with its own URL and hash — declare it as its
            own entry in `extraFiles` and name it here.
          '';
        };

        extraFiles = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            options = {
              url = lib.mkOption {
                type = lib.types.str;
                description = "Verified URL.";
              };
              hash = lib.mkOption {
                type = lib.types.str;
                description = "SRI hash.";
              };
            };
          });
          default = {};
          description = ''
            Additional files fetched alongside the model, keyed by filename.
            Projectors for vision models live here — llama.cpp needs the
            projector and the weights as two files.
          '';
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          example = ["--n-cpu-moe 4"];
          description = ''
            Extra llama-server arguments for this model, appended verbatim
            to the command line llama-swap spawns.

            THE DESCRIPTION HERE USED TO SAY "preset INI lines … keys
            without leading dashes", with `temp = 0.7` as the example.  That
            was ollama-era text that outlived its implementation: `llamaCmd`
            has always joined this list into an argv, so an INI line would
            have been passed to llama-server as a positional argument.
            Corrected when the VRAM budget started depending on the option.

            The lever it exists for on an MoE is `--n-cpu-moe N`, which
            keeps the expert tensors of the first N layers in system RAM
            while attention and the KV cache stay on the GPU.  Prefer it
            over `-ngl`: `-ngl 999` is already in the fixed argument list
            above, so overriding it would rest on llama.cpp's parser being
            last-wins, which nobody here has measured.
          '';
        };
      };
    }));
  };

  perInstance = {
    settings,
    roles,
    machine,
    ...
  }: {
    nixosModule = {
      config,
      pkgs,
      lib,
      ...
    }: let
      inf = roles.inference.machines.${machine.name}.settings or null;
      stateDir =
        if inf != null
        then inf.stateDir
        else "/srv/state/local-ai";
      user =
        if inf != null
        then inf.user
        else "llama";
      modelsDir = "${stateDir}/models";

      # Path of a file RELATIVE to the model directory.  Derived in one
      # place and used by every consumer, for the reason `fileOf` in the
      # inference role gives: two names for one path is how the fetcher and
      # the server drift.  extraFiles deliberately inherit the model's
      # subdirectory — a projector lives beside its weights.
      relOf = m: file:
        if m.subdir == ""
        then file
        else "${m.subdir}/${file}";

      # One fetch job per file: the model itself plus anything in
      # extraFiles.  Flattened here so the script below is a plain loop
      # rather than nested shell.
      jobs = lib.flatten (lib.mapAttrsToList (
          name: m:
            [
              {
                file = relOf m m.filename;
                inherit (m) url hash;
              }
            ]
            ++ lib.mapAttrsToList (fn: f: {
              file = relOf m fn;
              inherit (f) url hash;
            })
            m.extraFiles
        )
        settings.models);
    in {
      assertions = [
        {
          assertion = inf != null;
          message = ''
            @clanarchy/local-ai: ${machine.name} holds roles.models but not
            roles.inference.  Fetching models onto a machine that serves none
            is almost certainly a mistake in clan.nix; if it is deliberate,
            say so here rather than removing this assertion.
          '';
        }
      ];

      ##################################################################
      # The fetcher.
      #
      # A ONESHOT, NOT A PACKAGE.  These are 18 GiB blobs and architecture
      # invariant #7 puts them on zdata; a fixed-output derivation would
      # put them in the store on zroot, which is the pool that rolls back
      # and the one with no room for them.  That is the same reasoning
      # M14's hand-rolled derivations record, applied to data rather than
      # to code.
      #
      # Idempotent by hash: a file already present and correct is skipped,
      # so this is cheap on every boot and self-healing after a partial
      # download.  A hash MISMATCH is a hard failure that leaves the old
      # file alone — never a silent overwrite, because the thing on the
      # other side of a wrong model is an agent that sounds fine.
      ##################################################################
      # ── STARTED BY A TIMER, NOT BY multi-user.target ──────────────────
      #
      # See the long note in the inference role: as a `wantedBy` unit this put a
      # 25 GiB download on the activation critical path and made the first
      # deploy look like a hang for thirteen minutes.  A .timer is pulled in
      # by timers.target, and starting a timer completes instantly, so
      # activation returns while the fetch runs behind it.
      #
      # restartIfChanged = false is the other half.  Without it, ADDING a
      # model changes this unit's script, switch-to-configuration restarts
      # it, and the whole download is back on the critical path — the exact
      # defect, reintroduced by the exact edit most likely to trigger it.
      systemd.timers.llama-models-fetch = {
        description = "Fetch declared local-ai models shortly after boot";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "30s";
          AccuracySec = "5s";
          Unit = "llama-models-fetch.service";
        };
      };

      systemd.services.llama-models-fetch = {
        description = "Fetch and verify declared local-ai models";
        after = ["network-online.target"];
        wants = ["network-online.target"];

        # Deliberately NOT wantedBy multi-user.target — the timer above owns
        # starting it.  A deploy that ADDS a model therefore does not fetch
        # it immediately; run `systemctl start llama-models-fetch` (it is
        # idempotent) or wait for the next boot.  That is the documented
        # cost of keeping deploys non-blocking, and it is the right trade:
        # adding a model is rare and deliberate, deploying is neither.
        restartIfChanged = false;
        stopIfChanged = false;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = user;
          Group = user;
          # 18 GiB over a domestic line is not a 90-second job.
          TimeoutStartSec = "6h";
          StateDirectory = "local-ai-fetch";
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [stateDir];
          MemoryDenyWriteExecute = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];

          # Second pass: 7.2 on the first deploy, same two omissions again.
          # This one downloads over TLS and hashes files, so it keeps the
          # internet address families and cannot carry IPAddressDeny — but
          # everything else is free.
          CapabilityBoundingSet = [""];
          AmbientCapabilities = [""];
          SystemCallFilter = ["@system-service" "~@resources" "~@privileged"];
          SystemCallErrorNumber = "EPERM";
          SystemCallArchitectures = "native";
          ProtectProc = "invisible";
          ProcSubset = "pid";
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RemoveIPC = true;
          # 0077 is safe here even though llama-swap and its children read these files:
          # both units run as the same `llama` user, so 0600 is sufficient.
          UMask = "0077";
          # NO IPAddressDeny — this is the one unit that legitimately talks
          # to the internet, and the model hosts are a CDN with no stable
          # address range worth pinning.  The hash check is the control that
          # matters here, not the address.

          # THERE IS DELIBERATELY NO `try-restart llama-swap` HERE, and it is
          # deleted rather than fixed (M29c) because it could never have
          # worked.
          #
          # IT IS NOT PERMITTED.  This unit runs `User=llama` with no ambient
          # capabilities — measured on ernst 2026-09-25 — and an
          # unprivileged user cannot restart a system unit:
          #
          #   Failed to try-restart llama-swap.service: Access denied as
          #   the requested operation requires interactive authentication.
          #
          # AND IT IS NOT NEEDED, which settles it.  The premise was "a model
          # whose file did not exist yet is listed but unusable until
          # llama-swap re-reads", and the case that would have shown it
          # refuted it: on 2026-09-25 the fetcher downloaded a newly-declared
          # 21 GiB model, this restart was DENIED, llama-swap was never
          # restarted, and the first request naming that model loaded and
          # served it.  llama-swap renders each backend's COMMAND at startup
          # and the command contains a PATH; nothing opens that path until a
          # request spawns the child llama-server, so a file that appears
          # later is simply found.  There is nothing to re-read.
          #
          # If a future change makes llama-swap cache something about the
          # files themselves, the fix is a polkit rule scoped to this one
          # unit and action — not a restart the fetcher cannot perform.
        };

        script = ''
          set -euo pipefail
          mkdir -p ${modelsDir}

          fetch() {
            local file="$1" url="$2" want="$3"
            local dest="${modelsDir}/$file"

            # `file` may carry a subdirectory (roles.models' `subdir`), so
            # the parent is created per-file rather than once above.
            mkdir -p "$(${pkgs.coreutils}/bin/dirname "$dest")"

            if [ -f "$dest" ]; then
              local have
              have=$(${pkgs.nix}/bin/nix hash file --type sha256 --sri "$dest")
              if [ "$have" = "$want" ]; then
                echo "ok      $file"
                return 0
              fi
              echo "MISMATCH $file: have $have, want $want" >&2
              echo "         refusing to overwrite; move it aside by hand" >&2
              return 1
            fi

            # RESUMABLE, and it has to be.  Measured on the first deploy:
            # HuggingFace served the first three files at ~29 MB/s and then
            # throttled the 18 GiB one to 2 MB/s — a 77-minute tail.  A
            # download that long WILL be interrupted, by a deploy, a reboot
            # or an operator, and without --continue-at every interruption
            # discarded everything: `fetch` tests for the FINAL name, so a
            # rerun re-opened "$dest.part" and started from zero.  8.8 GiB
            # was nearly thrown away exactly that way.
            #
            # `--continue-at -` resumes from the current .part length. If
            # the server ignores Range, curl fails loudly rather than
            # silently appending to a truncated file — and the hash check
            # below is the backstop for anything subtler.
            if [ -f "$dest.part" ]; then
              echo "resume  $file (from $(${pkgs.coreutils}/bin/stat -c %s "$dest.part") bytes)"
            else
              echo "fetch   $file"
            fi
            ${pkgs.curl}/bin/curl -fSL --retry 5 --retry-delay 10 \
              --continue-at - -o "$dest.part" "$url"
            local got
            got=$(${pkgs.nix}/bin/nix hash file --type sha256 --sri "$dest.part")
            if [ "$got" != "$want" ]; then
              rm -f "$dest.part"
              echo "HASH MISMATCH after download of $file" >&2
              echo "  want $want" >&2
              echo "  got  $got" >&2
              return 1
            fi
            mv -f "$dest.part" "$dest"
            echo "done    $file"
          }

          ${lib.concatMapStringsSep "\n" (
              j: ''fetch ${lib.escapeShellArg j.file} ${lib.escapeShellArg j.url} ${lib.escapeShellArg j.hash}''
            )
            jobs}
        '';
      };
    };
  };
}
