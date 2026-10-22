##############################################################################
# roles.voice — Wyoming STT and TTS for Home Assistant's Assist pipeline (M29)
#
# ── THIS CLOSES local-ai.md's TTS NOTE ON ITS OWN TERMS ───────────────────
#
# M19 recorded "nothing in nixpkgs serves an OpenAI-shaped /v1/audio/speech …
# revisit if a packaged Kokoro or Piper HTTP server appears".  The premise
# was right and the search space was too narrow: Home Assistant does not want
# an OpenAI-shaped endpoint for voice, it wants WYOMING, and nixpkgs 26.05
# ships `services.wyoming.piper` (2.2.2), `services.wyoming.faster-whisper`
# (3.1.0) and `services.wyoming.openwakeword` (2.1.0).  Verified against this
# flake's own nixpkgs, not against the option search.
#
# ── THERE ARE NOW TWO SPEECH-TO-TEXT ENGINES ON THIS MACHINE ──────────────
#
# That is deliberate and is stated here so the next reader does not find two
# transcribers and assume one is an accident:
#
#   roles.speech   whisper.cpp   ggml weights    OpenAI /v1/audio/…  Open WebUI
#   roles.voice    faster-whisper CTranslate2    Wyoming             Assist
#
# Neither can serve the other's protocol and neither can load the other's
# weights — a ggml .bin and a CTranslate2 model directory are different
# formats for different runtimes.  Collapsing them would mean writing a
# Wyoming-to-OpenAI shim for a saving of about 1.6 GiB of disk, on a machine
# with 92 TB of it.  Both run on the CPU, so neither costs VRAM and they do
# not contend for the card.
#
# ── THE WEIGHTS ARE PULLED AT RUNTIME, WHICH BREAKS THIS MODULE'S RULE ────
#
# `roles.models` exists so that a model cannot be downloaded but undeclared,
# and every GGUF on this machine is hash-verified.  These two are not, and
# the reason is structural rather than laziness:
#
#   * both servers take a model DIRECTORY whose layout is chosen by the
#     library version (faster-whisper wants model.bin + config.json +
#     tokenizer.json + vocabulary.txt; piper wants <voice>.onnx +
#     <voice>.onnx.json), and roles.models fetches FILES;
#   * both nixpkgs units are `DynamicUser` with a `StateDirectory`, so
#     pointing them at a store owned by the `llama` user would mean granting
#     a systemd-ALLOCATED identity read access to the hash-verified tree —
#     the shape M27 refused for Meilisearch and the reason the uid table in
#     machines/ernst/networking.nix exists.
#
# What makes that acceptable here and not for a GGUF: these artifacts are
# RE-ACQUIRABLE and carry no state.  Losing them costs a download, not data.
# The persist entry below is therefore a bandwidth optimisation — without it
# ernst re-fetches ~1.6 GiB on every boot, because root rolls back.
##############################################################################
{
  lib,
  mkBridges,
}: {
  description = "Wyoming speech-to-text and text-to-speech for Home Assistant Assist.";

  interface.options = {
    stt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run wyoming-faster-whisper.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 10300;
        description = "Loopback port. 10300 is Wyoming's conventional STT port.";
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = "turbo";
        description = ''
          faster-whisper model name.  "turbo" is large-v3-turbo — the same
          weights roles.speech runs, in the other format — and is the largest
          one that stays comfortably realtime on this CPU.
        '';
      };
      language = lib.mkOption {
        type = lib.types.str;
        default = "de";
        description = ''
          PINNED, unlike roles.speech's "auto", and the difference is the
          workload rather than an inconsistency.  roles.speech transcribes
          dictated prose where a mispinned language mangles English package
          names.  Assist transcribes short commands, where "auto" spends its
          detection budget on two seconds of audio and mis-detects often
          enough to matter.  Home Assistant's pipeline also carries its own
          language, and the two disagreeing is a confusing failure.
        '';
      };
      beamSize = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 1;
        description = ''
          1, not the module's default of 5.  A voice command is short and
          latency is the whole experience; beam search buys accuracy on long
          prose, which is not what this endpoint transcribes.
        '';
      };
    };

    tts = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run wyoming-piper.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 10200;
        description = "Loopback port. 10200 is Wyoming's conventional TTS port.";
      };
      voice = lib.mkOption {
        type = lib.types.str;
        default = "de_DE-thorsten-medium";
        description = ''
          Piper voice.  `-medium` rather than `-high`: on a CPU the high
          variant is several times slower to synthesise and the difference is
          inaudible through a phone speaker, which is what will play it.
        '';
      };
    };

    exposeOn = lib.mkOption {
      default = [];
      description = ''
        Containers that may reach the voice servers.  Same shape and same
        three-part hazard as everywhere else in this module; see the header.

        Each entry opens BOTH ports on its address — a pipeline needs STT and
        TTS together, and splitting them would be two lists that can
        disagree.
      '';
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            example = "hass";
          };
          address = lib.mkOption {
            type = lib.types.str;
            example = "fdca:fe93::1";
          };
          allowedSource = lib.mkOption {
            type = lib.types.str;
            example = "fdca:fe93::2";
          };
        };
      });
    };
  };

  perInstance = {settings, ...}: {
    nixosModule = {
      pkgs,
      lib,
      ...
    }:
      lib.mkMerge [
        {
          services.wyoming.faster-whisper.servers.assist = lib.mkIf settings.stt.enable {
            enable = true;
            uri = "tcp://127.0.0.1:${toString settings.stt.port}";
            inherit (settings.stt) model language beamSize;
            device = "cpu";

            # OFF, and not for tidiness.  The module defaults it on, which
            # would advertise this server over mDNS on every interface the
            # host has — including br0 and therefore VLAN 50.  Home Assistant
            # is configured here by address, over a point-to-point link that
            # carries no multicast, so discovery would advertise a service
            # nothing can reach to a segment that should not see it.
            zeroconf.enable = false;
          };

          services.wyoming.piper.servers.assist = lib.mkIf settings.tts.enable {
            enable = true;
            uri = "tcp://127.0.0.1:${toString settings.tts.port}";
            inherit (settings.tts) voice;
            zeroconf.enable = false;
          };

          # ── STATIC USERS, NOT DynamicUser — AND THIS WAS PAID FOR ───────
          #
          # Both nixpkgs modules ship `DynamicUser = true` with a
          # `StateDirectory`, which puts their state under /var/lib/private.
          # M29's first deploy failed there, at every start of both units:
          #
          #   Directory "/var/lib/private" already exists, but has mode 0755
          #   that is too permissive (0700 was requested), refusing.
          #   status=238/STATE_DIRECTORY
          #
          # The proximate cause is fixed fleet-wide in modules/rootfs.nix —
          # impermanence creates the parents of a persist entry with the
          # default 0755, and systemd demands 0700 for that path.  This
          # override is the SEPARATE half, and it is the one this module
          # already had an opinion about: the `user` option on roles.inference
          # says DynamicUser + impermanence is a trap "written in blood in the
          # ollama era of this file", and these two units are the same shape.
          #
          # The second cost is the one the error message never mentions.  A
          # dynamic uid is re-allocated per boot, so systemd re-chowns the
          # state directory to match — and that directory is a 1.6 GiB model
          # tree on the persist pool.  A static owner makes the ownership a
          # fact instead of a per-boot reconciliation.
          #
          # No uid is pinned, and that is deliberate: this lands on zroot, not
          # on zdata, so the numbering rules in machines/ernst/networking.nix
          # do not apply.  /var/lib/nixos is persisted, so the allocation is
          # stable across boots anyway.
          users.users.wyoming-faster-whisper = lib.mkIf settings.stt.enable {
            isSystemUser = true;
            group = "wyoming";
            description = "Wyoming speech-to-text";
          };
          users.users.wyoming-piper = lib.mkIf settings.tts.enable {
            isSystemUser = true;
            group = "wyoming";
            description = "Wyoming text-to-speech";
          };
          users.groups.wyoming = {};

          systemd.services.wyoming-faster-whisper-assist = lib.mkIf settings.stt.enable {
            serviceConfig = {
              DynamicUser = lib.mkForce false;
              Group = "wyoming";
            };
          };
          systemd.services.wyoming-piper-assist = lib.mkIf settings.tts.enable {
            serviceConfig = {
              DynamicUser = lib.mkForce false;
              Group = "wyoming";
            };
          };

          # See the role header: re-acquirable, not hash-verified, and worth
          # persisting only so a reboot is not a 1.6 GiB download.  Now that
          # neither unit is DynamicUser this is the plain /var/lib/wyoming
          # rather than the /var/lib/private indirection; systemd creates the
          # per-service subdirectory under it and owns it to the right user.
          environment.persistence."/persist".directories = [
            {
              directory = "/var/lib/wyoming";
              user = "root";
              group = "root";
              mode = "0755";
            }
          ];
        }

        (mkBridges {
          inherit pkgs;
          unit = "wyoming-stt-bridge";
          what = "wyoming-faster-whisper";
          targetPort = settings.stt.port;
          bridges = lib.optionals settings.stt.enable settings.exposeOn;
          extraAfter = ["wyoming-faster-whisper-assist.service"];
        })

        (mkBridges {
          inherit pkgs;
          unit = "wyoming-tts-bridge";
          what = "wyoming-piper";
          targetPort = settings.tts.port;
          bridges = lib.optionals settings.tts.enable settings.exposeOn;
          extraAfter = ["wyoming-piper-assist.service"];
        })
      ];
  };
}
