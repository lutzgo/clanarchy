##############################################################################
# roles.webui — Open WebUI in an nspawn container on the Services VLAN
##############################################################################
{lib, ...}: {
  description = "Open WebUI on VLAN 90 behind Traefik + Authelia, talking only to llama-swap.";

  interface.options = {
    mac = lib.mkOption {
      type = lib.types.str;
      example = "02:00:00:90:00:0f";
      description = ''
        Container eth0 MAC, allocated in
        machines/ernst/allocations.nix.  The UDM-Pro DHCP reservation keys on
        this; a reservation outside the 10.0.90.6–.254 pool is accepted by
        UniFi and then silently ignored, which M2b, M5 and M6 each lost a
        round to.
      '';
    };
    uid = lib.mkOption {
      type = lib.types.int;
      description = "Static uid/gid, allocated in machines/ernst/allocations.nix.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Open WebUI's listener inside the container.";
    };
    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/state/open-webui";
      description = "Bind-mounted to /var/lib/open-webui. On zdata, invariant #7.";
    };
    hostName = lib.mkOption {
      type = lib.types.str;
      example = "chat.goclan.org";
      description = ''
        Public hostname.  MUST have a Technitium record BEFORE this is
        deployed and before the name is typed anywhere — M17's NXDOMAIN
        lesson: a browser that gets NXDOMAIN once caches it, and the fix then
        looks like a broken deploy.

        Must also appear in `protectedHosts` in
        machines/ernst/containers/ingress-policy.nix, or Authelia's
        default_policy = "deny" returns 403 to a user who has just logged in
        successfully — the RomM failure that file exists to prevent.
      '';
    };
    proxyAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.0.90.12";
      description = ''
        Traefik's address.  The container firewall permits this and only
        this, so a backend-bypass attempt from anywhere else on VLAN 90 —
        including the qBittorrent microvm one layer-2 hop away — times out
        rather than reaching the app.
      '';
    };
    inferenceAddress = lib.mkOption {
      type = lib.types.str;
      example = "fdca:fe91::1";
      description = ''
        Host end of THIS container's veth to ernst, where llama-swap is
        reachable.  Open WebUI talks to the inference stack and to nothing
        else on the host.

        Same shape as M6's mon0 and for the same reason: llama-swap is bound
        to the host's loopback and a container cannot reach that, so the link
        is an explicit point-to-point ULA rather than opening the port.
      '';
    };
    oidc = {
      enable = lib.mkEnableOption "OIDC login against Authelia";
      issuerUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://auth.goclan.org";
        description = "Authelia's issuer. `/.well-known/openid-configuration` is derived from it.";
      };
      clientId = lib.mkOption {
        type = lib.types.str;
        default = "open-webui";
        description = "Must match the client_id in machines/ernst/containers/authelia.nix.";
      };
    };
    speechUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "OpenAI-shaped STT base URL, normally llama-swap. Null disables voice input.";
    };

    ##########################################################################
    # Web search (M20) — and the decision the milestone asked to be argued
    # rather than assumed lives here, because it is expressed entirely in
    # which of these env vars are set.
    ##########################################################################
    searchUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "http://10.0.90.24:8888/search";
      description = ''
        SearXNG's `/search` endpoint — `SEARXNG_QUERY_URL`.  Null disables
        web search entirely.

        MUST INCLUDE THE `/search` PATH.  Open WebUI passes this string
        straight to `session.get()` with the query as parameters
        (retrieval/web/searxng.py); it appends nothing.  A base URL without
        the path gets SearXNG's landing page, which is HTML, and the JSON
        decode fails with an error that names neither.

        The `<query>` placeholder some upstream docs show is legacy — 0.11.0
        strips everything from `?` onward if it sees one — so do not write it.
      '';
    };

    searchResultCount = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = ''
        `WEB_SEARCH_RESULT_COUNT` — how many results are put in front of the
        model.  Upstream's default is 3.

        This is a CONTEXT BUDGET, and on this machine the budget is real and
        enforced: the coder model runs a 32768-token window and llama.cpp
        answers an over-long prompt with HTTP 400 rather than silently
        truncating it the way ollama did (see the header of this file).  Five
        snippets is a few hundred tokens and leaves the window to the
        conversation; it is raisable, but raise it knowing what it spends.
      '';
    };

    searchFetchesPages = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether OPEN WEBUI itself fetches the full text of each result page,
        rather than passing SearXNG's snippets to the model.

        FALSE, AND THIS IS THE EGRESS DECISION M20 OWES AN ANSWER TO.

        The roadmap frames the milestone as "SearXNG must reach the internet;
        nothing else in the M19 stack does".  That is only achievable at
        false.  Open WebUI's default is the opposite — `BYPASS_WEB_SEARCH_WEB_LOADER`
        defaults to False (config.py:1145), meaning the web loader runs — and
        at that default the container holding the household's conversation
        history, its OIDC client secret and the only veth to llama-swap also
        acquires arbitrary outbound HTTP to whatever hosts the results name.
        SearXNG, by contrast, holds nothing.  Two internet-facing services
        where the milestone intended one, and the wrong one gained it.

        THE HONEST COUNTERWEIGHT, because the case is not one-sided: Open
        WebUI 0.11.0 does defend that path.  `validate_url` rejects non-global
        addresses unless `ENABLE_LOCAL_WEB_FETCH` (default False), blocks the
        cloud metadata endpoints, rejects parser-confusing characters, and
        `_SSRFSafeResolver`/`_SSRFSafeAdapter` re-check the IP at connect time
        to close DNS rebinding and redirect-based pivots
        (retrieval/web/utils.py).  This is not the unguarded fetcher it might
        have been, and the argument below does not rest on pretending it is.

        It rests on two things that hold anyway:

          1. SCOPE.  Snippets-only means exactly one process in this stack
             makes outbound connections, and its reachable set is the
             declared engine list.  That is a boundary that can be stated in
             one sentence and checked with one command, which is worth more
             than a defended-but-unbounded one.
          2. CONTEXT.  Full page text for five results routinely exceeds the
             32768-token window.  M19 made that failure loud rather than
             silent (HTTP 400 naming both numbers), so the symptom would be
             searches that fail outright once the pages happen to be long —
             an intermittent, content-dependent break.

        WHAT IT COSTS, stated plainly rather than buried: the model sees
        title, URL and SearXNG's snippet per result — not the page.  For
        "rate your sources", which is the question that opened this
        milestone, that is enough to judge and cite a source and NOT enough
        to have read it.  If answers turn out to need the page text, this is
        the one option to flip, and flipping it is a deliberate widening of
        egress rather than a tuning change.
      '';
    };

    searchEmbedsResults = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether search results go through the embedding/vector-DB path
        instead of straight into the model's context.

        FALSE, and unlike `searchFetchesPages` this one is barely a trade.

        At Open WebUI's default (`BYPASS_WEB_SEARCH_EMBEDDING_AND_RETRIEVAL`
        = False) the results are embedded into a per-query vector collection
        first.  That needs an embedding model, and the default one is
        `sentence-transformers/all-MiniLM-L6-v2` with
        `RAG_EMBEDDING_MODEL_AUTO_UPDATE` defaulting to True
        (config.py:990-996) — i.e. an UNPINNED, UN-HASH-VERIFIED DOWNLOAD
        FROM HUGGINGFACE, fetched at runtime, into a container, on first use.

        This repo has a mechanism for exactly that problem and it is
        `roles.models`: every weight the GPU tier loads is a URL and a hash,
        verified at fetch and again at boot, because "a model reference that
        was merely plausible" has cost this project twice.  Turning this on
        would reintroduce the failure mode that role exists to make
        unrepresentable — and it would do it for a 90 MB model whose only job
        is to rank five snippets that are already ranked by relevance score.

        At false there is no embedding model, no vector collection, and no
        startup dependency on HuggingFace being reachable.
      '';
    };
    imageUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        ComfyUI base URL. Null disables image generation.

        For llama-swap this must carry the `/upstream/<model>` prefix —
        Open WebUI speaks ComfyUI's own API, which has no model name in it
        for llama-swap to dispatch on.
      '';
    };

    # ── THE THREE SETTINGS M21 SHIPPED WITHOUT, AND WHY THEY MATTER ──────
    #
    # M21 set ENABLE_IMAGE_GENERATION, IMAGE_GENERATION_ENGINE and
    # COMFYUI_BASE_URL and stopped there, on the roadmap's claim that Open
    # WebUI's side is "three env vars".  It is not, and the missing ones do
    # not fail loudly:
    #
    #   IMAGE_GENERATION_MODEL  defaults to ''  (config.py:1314)
    #   IMAGE_SIZE              defaults to '512x512'
    #   IMAGE_STEPS             defaults to 50
    #
    # Open WebUI's built-in ComfyUI workflow is a CheckpointLoaderSimple
    # whose `ckpt_name` is the placeholder "model.safetensors", substituted
    # with IMAGE_GENERATION_MODEL.  Empty, ComfyUI is asked for a checkpoint
    # that does not exist.
    #
    # AND THEY CANNOT BE SET IN THE UI, which is the part that makes them
    # belong here.  This container runs ENABLE_PERSISTENT_CONFIG = "False"
    # deliberately (see the note on it below), so the environment is
    # authoritative on every boot: a value typed into Admin Panel -> Images
    # works until the next restart and is then silently reverted.  That is
    # the setting working as intended, and the reason these are options.
    imageModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "sd_xl_base_1.0.safetensors";
      description = ''
        `IMAGE_GENERATION_MODEL` — the checkpoint filename ComfyUI loads,
        as it appears in ComfyUI's `checkpoints` category.

        Required when `imageUrl` is set, and ASSERTED against the model set:
        it must name a `roles.models` entry declared with
        `subdir = "checkpoints"` on this machine.  A name that is merely
        plausible is the failure mode this module has paid for twice —
        `qwen3-coder:8b` sat in a restart loop for months — and here it
        would present as an image request that fails inside ComfyUI, three
        layers from the typo.
      '';
    };

    imageSize = lib.mkOption {
      type = lib.types.str;
      default = "1024x1024";
      description = ''
        `IMAGE_SIZE`, substituted into the workflow's EmptyLatentImage.

        1024x1024, NOT Open WebUI's 512x512 default, and this is a property
        of the checkpoint rather than a preference: SDXL is trained at
        1024x1024 and is known to degrade at 512.  Left at the default it
        would have produced working-but-poor images — worse than a clean
        failure, because nothing would say anything was wrong.

        A non-SDXL checkpoint may well want a different value; it belongs
        next to whatever `imageModel` names.
      '';
    };

    imageWorkflowNodes = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      description = ''
        `COMFYUI_WORKFLOW_NODES` — which node of the ComfyUI workflow each
        generation parameter is written into.

        ── WITHOUT THIS, NOTHING IS SUBSTITUTED AND THE REQUEST IS A 400 ──

        Open WebUI does not inspect the workflow.  `_apply_workflow_nodes()`
        (utils/images/comfyui.py:147) iterates THIS LIST and writes each
        value into the node id it names; the list defaults to an EMPTY
        STRING, which `json.loads` turns into `[]` (config.py:1456), and an
        empty list means the loop body never runs.

        So the bundled workflow is POSTed with its placeholders intact —
        `ckpt_name: "model.safetensors"`, 512x512, and the literal prompt
        text `"Prompt"` — and ComfyUI rejects the unknown checkpoint:

          POST /upstream/comfyui/prompt -> 400 Bad Request

        Open WebUI surfaces that as "An error occurred while generating an
        image" and logs only `ClientResponseError: 400`, never the body,
        so the reason is invisible from its side.  Measured on ernst
        2026-09-10: replaying the SAME workflow with the substitutions
        applied by hand was accepted (`{"prompt_id": …, "node_errors": {}}`),
        which is what isolated it to this list rather than to the workflow,
        the checkpoint, the bridge or llama-swap — all four of which were
        working.

        The node ids below are those of Open WebUI's own bundled workflow
        (`COMFYUI_DEFAULT_WORKFLOW`, config.py):

          3  KSampler                5  EmptyLatentImage   7  CLIPTextEncode (neg)
          4  CheckpointLoaderSimple  6  CLIPTextEncode     8  VAEDecode / 9 SaveImage

        This role does NOT override `COMFYUI_WORKFLOW`, so these ids refer to
        the workflow Open WebUI ships.  **Anything that replaces that
        workflow has to replace this list in the same change** — the ids are
        positional references into one specific document, and a workflow
        whose ids differ silently writes parameters into the wrong nodes, or
        into nodes that do not exist.
      '';
      default = [
        {
          type = "model";
          key = "ckpt_name";
          node_ids = ["4"];
        }
        {
          type = "prompt";
          key = "text";
          node_ids = ["6"];
        }
        {
          type = "negative_prompt";
          key = "text";
          node_ids = ["7"];
        }
        {
          type = "width";
          key = "width";
          node_ids = ["5"];
        }
        {
          type = "height";
          key = "height";
          node_ids = ["5"];
        }
        {
          type = "n";
          key = "batch_size";
          node_ids = ["5"];
        }
        {
          type = "steps";
          key = "steps";
          node_ids = ["3"];
        }
        # `seed` has no fallback key in _apply_workflow_nodes — unlike the
        # others it is indexed with `node.key` directly, so omitting the key
        # here is a KeyError rather than a default.
        {
          type = "seed";
          key = "seed";
          node_ids = ["3"];
        }
      ];
    };

    imageSteps = lib.mkOption {
      type = lib.types.ints.positive;
      default = 20;
      description = ''
        `IMAGE_STEPS`, substituted into the workflow's KSampler.

        20 matches the value in Open WebUI's own bundled workflow; the env
        default of 50 overrides that with 2.5x the sampling work. Which is
        actually better on this card and this checkpoint is a question for a
        measurement rather than for this description — 20 is the
        conservative starting point, not a claim.
      '';
    };

    ##########################################################################
    # Image EDITING (img2img) — a separate subsystem in Open WebUI, with its
    # own engine, model, base URL, workflow and node map.  Enabling image
    # GENERATION does not enable it.
    ##########################################################################
    imageEditEnable = lib.mkEnableOption ''
      image editing (img2img): upload a picture with a prompt and transform it

      Points at the SAME ComfyUI as generation, over the same bridge — no new
      listener and no new firewall rule.  Open WebUI uploads the source image
      to ComfyUI's `/api/upload/image` and passes back the filename it is
      given, which the workflow's LoadImage node consumes
    '';

    imageEditWorkflow = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      description = ''
        The img2img workflow, as a ComfyUI prompt graph.

        UNLIKE GENERATION, OPEN WEBUI SHIPS NO DEFAULT HERE.
        `IMAGES_EDIT_COMFYUI_WORKFLOW` defaults to the empty string
        (config.py:1506), so an edit request against an unset workflow posts
        nothing usable.  The graph below therefore has to exist in this repo
        rather than being a couple of env vars over an upstream default.

        It is the generation graph with the latent source swapped: instead of
        an `EmptyLatentImage`, a `LoadImage` (10) feeds a `VAEEncode` (11)
        which feeds the sampler's `latent_image`.  That is the whole of
        img2img.

        `denoise` is the parameter that matters and it is baked in at 0.75:
        1.0 ignores the input entirely (it is then plain generation), and low
        values return the input barely touched.  0.75 transforms the subject
        while keeping composition, lighting and shadows — verified on ernst
        2026-09-10 by editing a photo of a red apple with "turn the cat
        bright orange, oil painting style" and getting the same object, same
        table, same shadow, different subject.

        NO `EmptyLatentImage` MEANS NO width/height, deliberately: the output
        size comes from the input image, which is what img2img should do.
        `IMAGE_EDIT_SIZE` is left unset for the same reason.
      '';
      default = {
        "3" = {
          inputs = {
            seed = 0;
            steps = 20;
            cfg = 7;
            sampler_name = "dpmpp_2m";
            scheduler = "karras";
            # See the option description. This is the img2img knob.
            denoise = 0.75;
            model = ["4" 0];
            positive = ["6" 0];
            negative = ["7" 0];
            # The one edge that differs from the generation graph.
            latent_image = ["11" 0];
          };
          class_type = "KSampler";
        };
        "4" = {
          # Overwritten from `imageEditModel` via the node map below.
          inputs.ckpt_name = "model.safetensors";
          class_type = "CheckpointLoaderSimple";
        };
        "6" = {
          inputs = {
            text = "Prompt";
            clip = ["4" 1];
          };
          class_type = "CLIPTextEncode";
        };
        "7" = {
          inputs = {
            text = "";
            clip = ["4" 1];
          };
          class_type = "CLIPTextEncode";
        };
        "8" = {
          inputs = {
            samples = ["3" 0];
            vae = ["4" 2];
          };
          class_type = "VAEDecode";
        };
        "9" = {
          inputs = {
            filename_prefix = "ComfyUI";
            images = ["8" 0];
          };
          class_type = "SaveImage";
        };
        "10" = {
          # Overwritten with the uploaded filename via the node map.
          inputs.image = "example.png";
          class_type = "LoadImage";
        };
        # ── THE NODE WITHOUT WHICH A PHONE PHOTO OOMs THE CARD ──────────
        #
        # img2img has no EmptyLatentImage, so the latent is whatever the
        # UPLOAD dictates — and a phone camera uploads 3024x4032. That is a
        # 378x504 latent, and SDXL's attention over it asks for 42 GiB on a
        # 24 GiB card.  Measured on ernst 2026-09-10, at the KSampler:
        #
        #   exception_type: torch.OutOfMemoryError
        #   "CUDA out of memory. Tried to allocate 42.25 GiB. GPU 0 has a
        #    total capacity of 23.98 GiB"
        #   executed: ["10","4","6","7","11"]   <- everything BUT the sampler
        #
        # AND THE FAILURE IS COMPLETELY SILENT AT THE FRONT DOOR, which is
        # why this needs a node rather than a note.  ComfyUI reports it only
        # in its history status; `_ws_get_images` returns an empty list; Open
        # WebUI logs nothing at all, still emits its "Image created" status,
        # and the model happily narrates an image that does not exist.  The
        # only visible symptom is a reply with no picture in it.
        #
        # 1.0 megapixel is SDXL's native training scale, so this is not only
        # a memory fix — an SDXL latent far from ~1 MP degrades anyway.
        # `resolution_steps = 64` keeps both sides a multiple of 64, which
        # the 8x VAE downsample and the UNet's own strides want; lanczos
        # because this is always a downscale and it is the sharpest of the
        # offered filters.
        #
        # Verified with the same 3024x4032 JPEG that produced the OOM above:
        # `status_str: success`, image written.
        "12" = {
          inputs = {
            image = ["10" 0];
            upscale_method = "lanczos";
            megapixels = 1.0;
            resolution_steps = 64;
          };
          class_type = "ImageScaleToTotalPixels";
        };
        "11" = {
          # pixels comes from the RESCALE (12), never straight from
          # LoadImage (10) — that edge is the entire fix.
          inputs = {
            pixels = ["12" 0];
            vae = ["4" 2];
          };
          class_type = "VAEEncode";
        };
      };
    };

    imageEditWorkflowNodes = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      description = ''
        `IMAGES_EDIT_COMFYUI_WORKFLOW_NODES` — the same substitution
        mechanism generation uses, and the same consequence if it is empty:
        nothing is substituted and the placeholders are posted verbatim.

        ── IT IS DELIBERATELY SHORTER THAN THE GENERATION MAP ────────────

        `steps` IS OMITTED ON PURPOSE, and this is not tidiness.  The edit
        caller builds its payload without one (routers/images.py: only
        `image`, `prompt` and optionally `width`/`height`/`n`), so
        `payload.steps` is None — and `_apply_workflow_nodes` writes whatever
        it finds:

          workflow[node_id]['inputs']['steps'] = payload.steps   # -> null

        A `steps` entry here would therefore put JSON `null` into the
        KSampler on every edit and ComfyUI would reject the graph.  `seed` is
        safe by contrast, because that branch substitutes a random value when
        the payload has none.

        `width`/`height` are omitted for a different reason: there is no
        `EmptyLatentImage` in an img2img graph, so there is nothing for them
        to set — the size comes from the uploaded image.

        `image` carries the filename ComfyUI returned from its own upload
        endpoint, and the payload is a LIST, so `node_ids` is indexed
        positionally against it (`payload.image[idx]`).  One LoadImage, one
        entry.
      '';
      default = [
        {
          type = "model";
          key = "ckpt_name";
          node_ids = ["4"];
        }
        {
          type = "prompt";
          key = "text";
          node_ids = ["6"];
        }
        {
          type = "image";
          key = "image";
          node_ids = ["10"];
        }
        {
          type = "seed";
          key = "seed";
          node_ids = ["3"];
        }
      ];
    };
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
      oidcGen = config.clan.core.vars.generators.authelia-oidc-openwebui;

      # DERIVED, NOT RESTATED. modules/containers/nspawn.nix builds this
      # from the CONTAINER name, which is `openwebui` — not the service
      # name `open-webui`. Writing the path out by hand here meant the
      # module bound /run/openwebui-secrets while the service below read
      # /run/open-webui-secrets/oidc.env, which is a missing
      # EnvironmentFile and a unit that will not start. Nothing persists
      # under /run, so the rename costs nothing.
      secretsDir = "${config.clanarchy.containerDefaults.secretsRoot}/openwebui-secrets";
      vethName = "vb-openwebui";
      # ── THIS NAME IS HOST-GLOBAL, AND IT WAS `ai0` UNTIL M29 ──────────
      #
      # `extraVeths.<name>` renders to nspawn's `--network-veth-extra=<name>`
      # with a SINGLE name, which nspawn uses for BOTH ends — so the name
      # appears on the host as well as in the container, and the host has
      # one flat interface namespace.  monitoring.nix:182-184 already wrote
      # that down for `mon0`; what nobody drew from it is that the name must
      # therefore be UNIQUE ACROSS EVERY CONTAINER ON THE MACHINE.
      #
      # M27 gave karakeep `extraVeths.ai0` as well, and from its deploy on
      # 2026-09-19 THIS CONTAINER HAD NO SECOND LEG AT ALL.  Measured on
      # ernst 2026-09-24, sixteen days into the same boot:
      #
      #   openwebui: ip -6 -br addr  ->  lo, eth0.  No ai0.
      #   karakeep : ai0@if126  fdca:fe92::2/128
      #   host     : exactly one ai0, peered into karakeep
      #   openwebui -> [fdca:fe91::1]:11434  ->  curl (7), could not connect
      #   karakeep  -> [fdca:fe92::1]:11434  ->  200          (the control)
      #
      # NOTHING REPORTED IT, and the reason is worth keeping: the host end
      # binds regardless.  `ss -ltn` shows [fdca:fe91::1]:11434 LISTENing,
      # llama-bridge-webui.socket and .service are both active/running, and
      # the only symptom is "No models available" in the chat UI — three
      # layers from the cause, which is the exact failure the `exposeOn`
      # note above claims this mechanism was built to prevent.  It was
      # prevented for the half that lives in this file and not for the half
      # that lives in nspawn's argv.
      #
      # There is a second edge on the same fact: nixos-containers.nix:245
      # runs `ip link del dev <name>` on container STOP, so stopping this
      # container would have taken karakeep's leg down with it.
      #
      # The names now carry the ULA index they belong to — fe91 -> ai1,
      # fe92 -> ai2, fe93 -> ai3 — so a collision requires typing the same
      # number twice, and machines/ernst/networking.nix asserts that no two
      # containers claim one name.
      aiVeth = "ai1";
      aiHost = settings.inferenceAddress;
      aiCont = "fdca:fe91::2";
      swapUrl = "http://[${aiHost}]:11434";

      # Checkpoints this machine actually declares, read out of the SAME
      # attrset the fetcher and ComfyUI's extra_model_paths.yaml are built
      # from — so "is that file on disk" and "does Open WebUI name it"
      # cannot answer differently.
      #
      # `subdir = "checkpoints"` is part of the test, not a detail: ComfyUI
      # resolves `ckpt_name` inside its `checkpoints` category, so a model
      # declared with any other subdir is fetched and hash-verified and
      # still invisible to the loader.
      declaredCheckpoints =
        lib.mapAttrsToList (_: m: m.filename)
        (lib.filterAttrs (_: m: m.subdir == "checkpoints")
          (roles.models.machines.${machine.name}.settings.models or {}));
    in {
      assertions = lib.optionals (settings.imageUrl != null) [
        {
          assertion = settings.imageModel != null;
          message = ''
            @clanarchy/local-ai: ${machine.name} sets roles.webui…imageUrl
            but not imageModel.

            Open WebUI's IMAGE_GENERATION_MODEL defaults to the EMPTY
            STRING, and its bundled ComfyUI workflow substitutes that into
            a CheckpointLoaderSimple.  So image generation would appear
            enabled in the UI and fail inside ComfyUI on every request,
            with nothing on the Open WebUI side saying why.

            Set it to a checkpoint declared in roles.models with
            `subdir = "checkpoints"`, e.g. "sd_xl_base_1.0.safetensors".
          '';
        }
        {
          assertion =
            settings.imageModel
            == null
            || lib.elem settings.imageModel declaredCheckpoints;
          message = ''
            @clanarchy/local-ai: ${machine.name} sets
            roles.webui…imageModel = "${toString settings.imageModel}",
            which is not a checkpoint this machine declares.

            Declared with `subdir = "checkpoints"` in roles.models:
              ${
              if declaredCheckpoints == []
              then "(none — declare one before enabling image generation)"
              else lib.concatStringsSep "\n  " declaredCheckpoints
            }

            A model is fetched, hash-verified and offered to ComfyUI from
            ONE attrset; naming something else here is the same class of
            mistake as an ollama tag that never existed, which sat in a
            restart loop for months.  Caught at build time rather than as
            a failed image request three layers away.
          '';
        }
      ];

      ##################################################################
      # The OIDC client secret. ITS OWN GENERATOR.
      #
      # containers/authelia.nix states the rule and the reason: a clan vars
      # generator is ATOMIC, so adding a file to an existing one re-runs the
      # whole script and hands every other relying party a new secret as a
      # side effect. Grafana and CWA each have their own; so does this.
      #
      # The pair WITHIN this generator is still atomic, which is the part
      # that matters — Authelia stores a PBKDF2 digest and the client sends
      # the plaintext, so the two must come out of one `rand` call.
      ##################################################################
      clan.core.vars.generators.authelia-oidc-openwebui = {
        files."openwebui-client-secret".secret = true;
        files."openwebui-client-secret-digest".secret = true;
        files."openwebui-client-secret-digest".restartUnits = ["authelia-secrets.service" "container@authelia.service"];
        # `openwebui-secrets`, not `open-webui-secrets`: the module names
        # the staging unit after the CONTAINER, and a restartUnits entry
        # naming a unit that does not exist is silent — the secret
        # rotates, nothing restarts, and the container keeps serving the
        # old value. The generator-name gate cannot catch this, because
        # this is a value inside a generator rather than its name.
        files."openwebui-client-secret".restartUnits = ["openwebui-secrets.service" "container@openwebui.service"];

        runtimeInputs = [pkgs.authelia pkgs.gnused pkgs.coreutils];
        script = ''
          set -euo pipefail
          secret=$(authelia crypto rand --length 72 --charset alphanumeric \
                     | sed -n 's/^Random Value: //p' | tr -d '\n')
          [ -n "$secret" ] || { echo "  ✗ no client secret produced" >&2; exit 1; }
          printf '%s' "$secret" > "$out/openwebui-client-secret"

          digest=$(authelia crypto hash generate pbkdf2 --variant sha512 --password "$secret" \
                     | sed -n 's/^Digest: //p')
          [ -n "$digest" ] || { echo "  ✗ no digest produced" >&2; exit 1; }
          printf '%s' "$digest" > "$out/openwebui-client-secret-digest"
        '';
      };

      ##################################################################
      # The container.
      ##################################################################
      #
      # Declared through modules/containers/nspawn.nix, which generates
      # the staging unit, the state directory, the host-side veth
      # network, the VLAN backstop, the container preamble, the
      # in-container networking and the firewall — taking bridge, VLAN,
      # resolver and search domain from the HOST's
      # `clanarchy.containerDefaults` rather than from this role.
      clanarchy.containers.openwebui = {
        enable = true;
        mac = settings.mac;

        # NO uid/gid PIN: the in-container `users.users.open-webui` block
        # declares the user in full.

        # AN ORDERED UNIT RATHER THAN A tmpfiles RULE. This path is bound
        # into the container, and a tmpfiles rule for a bound path races
        # the container's own start — immich measured that. It also gains
        # the /srv/state mount guard, so state cannot land on a
        # filesystem that rolls back.
        stateDirs = [
          {
            path = settings.stateDir;
            owner = settings.uid;
            group = settings.uid;
            mode = "0750";
          }
        ];

        # `required`, preserving this unit's existing behaviour: it used a
        # bare `cat` under `set -euo pipefail`, so a missing var already
        # failed the unit and stopped the container. An empty OIDC client
        # secret is every login broken, so failing closed is right here —
        # unlike a password the application can refuse and log.
        secrets."oidc.env".OAUTH_CLIENT_SECRET = {
          file = oidcGen.files."openwebui-client-secret".path;
          required = true;
        };

        # The inference leg, point-to-point and inward.
        ula = [
          {
            veth = aiVeth;
            hostAddress6 = aiHost;
            localAddress6 = aiCont;
          }
        ];

        bindMounts = {
          "/var/lib/open-webui" = {
            hostPath = settings.stateDir;
            isReadOnly = false;
          };
        };

        # Only the proxy. Nothing else on the services VLAN reaches it.
        allowFrom = [
          {
            peer = settings.proxyAddress;
            port = settings.port;
          }
        ];

        config = {
          config,
          lib,
          ...
        }: {
          # ── OPEN WEBUI IS UNFREE, AND THE ALLOWANCE STAYS IN HERE ─────
          #
          # nixpkgs marks open-webui unfree because of the branding clause
          # in its licence (below), so without an allowance evaluation
          # fails with:
          #
          #   error: Refusing to evaluate package 'open-webui-0.11.0'
          #          because it has an unfree license
          #
          # ernst does NOT set `allowUnfree`.  It carries a narrow
          # `allowUnfreePredicate` from modules/roles/htpc.nix listing the
          # Steam packages, and that file says explicitly why: "this role is
          # expected to land on otherwise-headless boxes (ernst fronts the
          # NAS array), and 'we needed Steam' shouldn't quietly open the
          # whole machine to unfree packages."  Adding open-webui to a list
          # about Steam would be the wrong file, and widening the host to
          # blanket allowUnfree would be exactly what that comment forbids.
          #
          # A container is its own nixosSystem with its own nixpkgs, so the
          # allowance is scoped to the one evaluation that needs it and the
          # host's predicate is untouched.  The cost is a second nixpkgs
          # instantiation and no lib/overlays.nix in here — the overlays are
          # a niri sandbox fix and chromium privacy flags, neither of which
          # this container has any use for.
          #
          # THE LICENCE, recorded so nobody has to rediscover it: Open WebUI
          # is BSD-3-clause plus a fourth clause forbidding removal or
          # alteration of "Open WebUI" branding — EXCEPT where the total
          # number of end users does not exceed FIFTY in any rolling 30-day
          # period.  This household is comfortably under that, so the
          # exemption applies and the branding may be left alone anyway.
          # If this is ever exposed to more than fifty people, that changes.
          nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) ["open-webui"];

          # Matches the host, for the reason arr/ and monitoring.nix
          # both give: every timestamp a human reads is local time, and a
          # container that defaults to UTC makes each of them a two-hour
          # question.
          time.timeZone = "Europe/Berlin";
          users.users.open-webui = {
            isSystemUser = true;
            group = "open-webui";
            uid = settings.uid;
          };
          users.groups.open-webui.gid = settings.uid;

          # ── DynamicUser OFF.  THE SAME TRAP THIS MODULE ALREADY ────────
          #    DOCUMENTED FOR OLLAMA, IN A SECOND FORM.
          #
          # nixpkgs' open-webui module ships `DynamicUser = true` with
          # `StateDirectory = "open-webui"`.  That combination is
          # incompatible with a bind-mounted state directory, and it fails
          # in a way that names neither:
          #
          #   Found pre-existing public StateDirectory= directory
          #     /var/lib/open-webui, migrating to /var/lib/private/open-webui.
          #   Apparently, service previously had DynamicUser= turned off,
          #     and has now turned it on.
          #   Failed to set up special execution directory in /var/lib:
          #     Device or resource busy
          #   status=238/STATE_DIRECTORY
          #
          # systemd wants to MOVE /var/lib/open-webui under /var/lib/private
          # so the per-boot dynamic uid can own it.  It is a bind mount, so
          # the move is EBUSY and the unit never starts — which presents at
          # the front door as Traefik's "Bad Gateway", three layers away.
          #
          # The `ollama` role in this same file carries the other half of
          # this lesson: DynamicUser + a persisted directory means the
          # per-boot uid cannot write to a root-owned 0700 path. Same root
          # cause, different symptom. A STATIC uid is the answer in both
          # cases — here it also has to match the ownership the host-side
          # tmpfiles rule sets on ${settings.stateDir}.
          systemd.services.open-webui.serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = "open-webui";
            Group = "open-webui";
          };

          services.open-webui = {
            enable = true;
            host = "0.0.0.0";
            port = settings.port;
            stateDir = "/var/lib/open-webui";
            environmentFile = "${secretsDir}/oidc.env";

            environment =
              {
                # ── The one setting that makes this declarative ──────────
                #
                # Open WebUI's "PersistentConfig" writes most of the settings
                # below into its own database ON FIRST LAUNCH and thereafter
                # the DATABASE WINS — so a changed env var deploys green and
                # does nothing, which is the exact failure shape this repo
                # keeps rediscovering (the recyclarr duplicate instance, the
                # opencode config that never parsed, SN1's silent truncation).
                # False makes the environment authoritative on every boot,
                # which is the only way a Nix-rendered config means anything.
                ENABLE_PERSISTENT_CONFIG = "False";

                ANONYMIZED_TELEMETRY = "False";
                DO_NOT_TRACK = "True";
                SCARF_NO_ANALYTICS = "True";

                WEBUI_URL = "https://${settings.hostName}";

                # ── The model backend ───────────────────────────────────
                # llama-swap, over the point-to-point veth. Its /v1 surface
                # is OpenAI-compatible; there is no ollama API here any more.
                ENABLE_OPENAI_API = "True";
                ENABLE_OLLAMA_API = "False";
                OPENAI_API_BASE_URL = "${swapUrl}/v1";
                # llama-swap requires no key. A placeholder rather than empty
                # because the OpenAI client library refuses to send a request
                # with no Authorization header at all.
                OPENAI_API_KEY = "sk-no-key-required";

                # ── Auth ────────────────────────────────────────────────
                WEBUI_AUTH = "True";
              }
              // lib.optionalAttrs settings.oidc.enable {
                ENABLE_OAUTH_SIGNUP = "True";
                OAUTH_MERGE_ACCOUNTS_BY_EMAIL = "True";
                OAUTH_CLIENT_ID = settings.oidc.clientId;
                OPENID_PROVIDER_URL = "${settings.oidc.issuerUrl}/.well-known/openid-configuration";
                # DERIVED FROM THE 0.11.0 SOURCE, not from a docs page — the
                # same discipline containers/authelia.nix applied to CWA.
                # main.py registers TWO routes for this callback:
                #
                #   @app.get('/oauth/{provider}/login/callback')   <- current
                #   @app.get('/oauth/{provider}/callback')         <- "Legacy"
                #
                # and the SSO provider is registered under the literal key
                # `oidc` (config.py: OAUTH_PROVIDERS['oidc'] = …), so the
                # provider segment is `oidc` and not OAUTH_PROVIDER_NAME,
                # which is only the label on the button.
                #
                # The current path is used here and BOTH are registered on the
                # Authelia side, so an upstream removal of the legacy route
                # cannot break login. Do not confuse either with
                # `/oauth/clients/<id>/callback`, which is a different feature
                # (Open WebUI acting as an OAuth client to MCP servers).
                OPENID_REDIRECT_URI = "https://${settings.hostName}/oauth/oidc/login/callback";
                OAUTH_PROVIDER_NAME = "Authelia";
                OAUTH_SCOPES = "openid email profile groups";

                # ── PKCE, AND IT IS NOT OPTIONAL HERE ──────────────────────
                #
                # The Authelia client block for this app sets
                # `require_pkce: true` (copied from Grafana's, which works
                # because Grafana sends PKCE by default). Open WebUI's authlib
                # client does NOT send a code_challenge unless told to, so the
                # first login attempt failed with Authelia refusing the
                # authorize request:
                #
                #   invalid_request: Clients must include a 'code_challenge'
                #   when performing the authorize code flow, but it is missing
                #
                # Open WebUI surfaces that as "The email or password provided
                # is incorrect", which is its generic OAuth failure message
                # and says nothing about the actual cause — the real error is
                # only in the container's journal, under a Python traceback.
                #
                # This sets client_kwargs['code_challenge_method'] = 'S256'
                # (config.py). Fixed on the app side rather than by dropping
                # require_pkce on the issuer: PKCE is worth keeping, and the
                # asymmetry was ours, not Authelia's.
                OAUTH_CODE_CHALLENGE_METHOD = "S256";
                # The local password form STAYS, and it is break-glass, not
                # laziness: monitoring.nix makes the same call for Grafana.
                # If Authelia is down, every admin UI in the house is down,
                # and this is the one that can still be reached over an SSH
                # forward to debug it.
                ENABLE_LOGIN_FORM = "True";
              }
              // lib.optionalAttrs (settings.speechUrl != null) {
                AUDIO_STT_ENGINE = "openai";
                AUDIO_STT_OPENAI_API_BASE_URL = "${settings.speechUrl}/v1";
                AUDIO_STT_OPENAI_API_KEY = "sk-no-key-required";
                AUDIO_STT_MODEL = "whisper";
                # TTS is the BROWSER's, deliberately — see the role header in
                # local-ai.md. Nothing in nixpkgs serves an OpenAI-shaped
                # /v1/audio/speech, and the Web Speech API costs no VRAM on a
                # card this milestone is already arbitrating.
                AUDIO_TTS_ENGINE = "";
              }
              // lib.optionalAttrs (settings.searchUrl != null) {
                # ── M20: web search, via SearXNG and nothing else ─────────
                #
                # THE LLM DOES NOT GET A TOOL, AND THAT IS A DECISION.
                #
                # Open WebUI 0.11.0 supports both shapes and picks between
                # them on one value: with native function calling it registers
                # `search_web` as a builtin tool and the model chooses when to
                # search; with `function_calling == 'legacy'` it runs the
                # search itself and injects the results
                # (utils/middleware.py:2552, utils/tools.py:672).
                #
                # The injection path is taken here, for three reasons in
                # descending order of weight:
                #
                #   1. THE TOOL PATH FORCES THE EGRESS THIS MILESTONE IS
                #      TRYING TO CONTAIN.  `search_web` is not registered
                #      alone — `builtin_functions.extend([search_web,
                #      fetch_url])` adds both under ONE category flag, and
                #      `fetch_url` retrieves a model-supplied URL.  There is
                #      no configuration that takes the first without the
                #      second, so choosing the tool path means Open WebUI gets
                #      arbitrary outbound HTTP no matter what
                #      `searchFetchesPages` says.
                #
                #   2. M19's 20/20 TOOL-CALLING RESULT DOES NOT TRANSFER, and
                #      the roadmap's own note that it is "evidence the tool
                #      path would work, not that it should be taken" is
                #      understated.  That 20/20 was measured WITH the
                #      `<tool_call>` reinforcement, and that reinforcement is
                #      injected by the opencode role — `instructions =
                #      [ "${"\${toolCallRule}"}" ]` in this same file, into
                #      opencode's config.json.  Open WebUI ships nothing of
                #      the kind.  Without it the measured baseline on this
                #      model is 4/30 to 21/30 depending on the phrasing.
                #
                #   3. IT REMOVES THE FAILURE THAT OPENED THE MILESTONE.
                #      M20 exists because the model answered from weights and
                #      cited nothing.  On the tool path "the model chose not
                #      to search" stays a possible outcome, and at a 13-70%
                #      call rate a likely one.  Here the toggle means the
                #      search happened.
                ENABLE_WEB_SEARCH = "True";
                WEB_SEARCH_ENGINE = "searxng";
                SEARXNG_QUERY_URL = settings.searchUrl;
                WEB_SEARCH_RESULT_COUNT = toString settings.searchResultCount;

                # See the two options for the full argument. In short:
                # snippets only, so SearXNG is the one process here that
                # talks to the internet; and no embedding, so nothing
                # downloads an unpinned model from HuggingFace at runtime.
                BYPASS_WEB_SEARCH_WEB_LOADER =
                  if settings.searchFetchesPages
                  then "False"
                  else "True";
                BYPASS_WEB_SEARCH_EMBEDDING_AND_RETRIEVAL =
                  if settings.searchEmbedsResults
                  then "False"
                  else "True";

                # Belt and braces on the SSRF guard rather than a load-bearing
                # control: at `searchFetchesPages = false` nothing in this
                # path fetches a URL at all, so this only matters if that flag
                # is ever flipped. False is also upstream's default; it is
                # stated explicitly because it is the setting that decides
                # whether a fetch may reach 10.0.90.0/24, and a default that
                # important should not be invisible.
                ENABLE_LOCAL_WEB_FETCH = "False";
              }
              // lib.optionalAttrs (settings.imageUrl != null) {
                ENABLE_IMAGE_GENERATION = "True";
                IMAGE_GENERATION_ENGINE = "comfyui";
                COMFYUI_BASE_URL = settings.imageUrl;

                # The three that M21 left at their defaults.  See the options
                # for why each one is not optional; in short, the model name
                # defaults to EMPTY and the size defaults to a resolution
                # SDXL degrades at, and neither can be fixed in the UI while
                # ENABLE_PERSISTENT_CONFIG is False.
                IMAGE_GENERATION_MODEL = settings.imageModel;
                IMAGE_SIZE = settings.imageSize;
                IMAGE_STEPS = toString settings.imageSteps;

                # The one that makes the other three reach the workflow at
                # all.  Empty, Open WebUI substitutes NOTHING and posts the
                # bundled workflow with `ckpt_name: "model.safetensors"`
                # still in it — a 400 from ComfyUI that Open WebUI reports
                # only as "An error occurred while generating an image".
                COMFYUI_WORKFLOW_NODES =
                  builtins.toJSON settings.imageWorkflowNodes;
              }
              // lib.optionalAttrs
              (settings.imageUrl != null && settings.imageEditEnable) {
                # ── img2img: SAME ComfyUI, SAME bridge, separate subsystem ─
                #
                # Open WebUI keeps editing entirely apart from generation —
                # its own enable flag, engine, model and workflow — and
                # `ENABLE_IMAGE_EDIT` defaults to false, so turning on
                # generation does not turn this on.
                #
                # It points at `imageUrl`, i.e. the same `/upstream/comfyui`
                # path on the same veth. VERIFIED that the upload endpoint
                # survives that prefix (ernst, 2026-09-10):
                #
                #   POST …/upstream/comfyui/api/upload/image
                #     -> {"name": "testupload.png", "subfolder": "",
                #         "type": "input"}
                #
                # which matters because it is a multipart POST to a path
                # llama-swap only forwards, and it was the one part of this
                # feature that could not be established by reading.
                ENABLE_IMAGE_EDIT = "True";
                IMAGE_EDIT_ENGINE = "comfyui";
                IMAGE_EDIT_MODEL = settings.imageModel;
                IMAGES_EDIT_COMFYUI_BASE_URL = settings.imageUrl;

                # A JSON STRING, not an object: Open WebUI types this field
                # as `workflow: str` and calls json.loads on it itself
                # (ComfyUIWorkflow in utils/images/comfyui.py).
                IMAGES_EDIT_COMFYUI_WORKFLOW =
                  builtins.toJSON settings.imageEditWorkflow;
                IMAGES_EDIT_COMFYUI_WORKFLOW_NODES =
                  builtins.toJSON settings.imageEditWorkflowNodes;

                # IMAGE_EDIT_SIZE is deliberately left unset — see
                # imageEditWorkflow. An img2img graph has no
                # EmptyLatentImage, so the output size is the input's.
              };
          };
        };
      };
    };
  };
}
