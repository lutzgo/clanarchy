##############################################################################
# roles.speech — whisper.cpp STT
##############################################################################
{lib, ...}: {
  description = "Whisper speech-to-text on an OpenAI-shaped endpoint, arbitrated by llama-swap.";

  interface.options = {
    model = lib.mkOption {
      type = lib.types.str;
      default = "ggml-large-v3-turbo-q5_0.bin";
      description = ''
        Filename of the whisper ggml model inside the model directory.  It is
        declared and fetched by `roles.models` like everything else — the
        filename here must match a key there.
      '';
    };
    language = lib.mkOption {
      type = lib.types.str;
      default = "auto";
      description = ''
        `-l`.  "auto" detects per utterance, which is what a bilingual
        household needs; pinning "de" is faster and wrong the moment somebody
        dictates an English package name.
      '';
    };
    threads = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = ''
        `-t`.  The 9950X has 16 cores; 8 leaves room for the containers that
        share this machine.  Whisper on this card is GPU-bound anyway — this
        matters for the mel spectrogram, not the decode.
      '';
    };
    gpuTarget = lib.mkOption {
      type = lib.types.str;
      default = "gfx1100";
      description = ''
        `rocmGpuTargets` for the whisper-cpp build.  A STRING, unlike
        llama-cpp's list-typed argument of the same name in nixpkgs 26.05 —
        passing a list here fails an `assert lib.isString value` deep in
        cmake option handling that does not mention this option.

        IT DOES NOT CURRENTLY BUY A GPU, and that is measured rather than
        assumed.  `rocmSupport = true` produces a binary that links
        libamdhip64.so.7 and libamd_comgr.so.3 — so the override is genuinely
        in effect, and checking `ldd` alone would tell you it worked — but the
        build emits no loadable `libggml-hip.so`, and ggml discovers backends
        by loading `libggml-<backend>.so` out of its own lib directory.  So at
        runtime:

          load_backend: loaded CPU backend from …/libggml-cpu-zen4.so
          whisper_backend_init_gpu: device 0: CPU (type: 0)
          whisper_backend_init_gpu: no GPU found

        llama-cpp's ROCm build DOES ship libggml-hip.so, which is why the same
        override works there and not here.  The option is kept because the
        build is otherwise correct and this is a packaging gap that may close;
        when it does, whisper becomes a real GPU consumer and MUST then be
        added to the exclusive group in the inference role.  Until then it is
        CPU, ~2.1x realtime on 8 threads, and costs no VRAM.
      '';
    };
  };

  perInstance = {...}: {
    # Deliberately empty.
    #
    # WHY THIS ROLE PRODUCES NO UNITS OF ITS OWN: whisper-server must be
    # SPAWNED BY llama-swap, not run beside it, or it is outside the
    # exclusive group and can hold VRAM while the coder model wants it —
    # which is the exact failure this milestone exists to prevent.  So the
    # role carries settings and the inference role reads them and builds the
    # backend entry.  A unit here would be a second, competing owner.
    #
    # SPEACHES WAS THE BRIEF'S CHOICE AND IS NOT TAKEN.  Two reasons, both
    # checked rather than assumed: it is not in nixpkgs at all (its
    # dependencies are — faster-whisper 1.2.1, ctranslate2 4.7.2, kokoro — but
    # the server is not), and its STT path runs through CTranslate2, whose GPU
    # backend is CUDA.  On a 7900 XTX that is a CPU path with extra steps.
    # pkgs.whisper-cpp builds with rocmSupport for gfx1100 out of the flake's
    # own nixpkgs, and its whisper-server takes --inference-path, so
    # `--inference-path /v1/audio/transcriptions` is OpenAI-shaped with no
    # wrapper and no new input.
    nixosModule = {...}: {};
  };
}
