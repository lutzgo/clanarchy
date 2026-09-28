# HACS integration dependencies

Home Assistant on ernst is built with `--skip-pip`, so a HACS-downloaded integration's Python requirements are **never installed and never checked**. They have to be declared in Nix. This page is how you find out what to declare.

## The one command

```bash
ssh root@10.0.50.10
nixos-container run hass -- hacs-deps-check
```

It reads every `manifest.json` under `custom_components/`, resolves each requirement against **the same interpreter and PYTHONPATH `home-assistant.service` runs under**, and prints a verdict per requirement:

```
hacs-deps-check: 1 declared in Nix, 5 downloaded, 0 with unmet requirements

  DECLARED  hacs  (verified at build time)
  OK        choreops  python-dateutil>=2.9.0 -> python-dateutil 2.9.0.post0
  OK        mail_and_packages  Pillow>=9.0 -> Pillow 12.3.0
  OK        mass_queue  music-assistant-client -> music-assistant-client 1.3.5
  OK        philips_airplus  paho-mqtt>=2.1,<3 -> paho-mqtt 2.1.0

All downloaded integrations have their requirements available.
```

On a miss it exits non-zero and prints a ready-to-paste block. Add it to `machines/ernst/containers/home-assistant.nix` and redeploy:

```nix
services.home-assistant.extraPackages = ps: [
  ps.<name>
];
```

The nixpkgs attribute usually matches the PyPI name — confirm with `nix search nixpkgs python3Packages.<name>`. **A requirement with no nixpkgs packaging is the signal to package the integration under `./pkgs` and drop it from HACS.**

## Why a tool exists for this at all

Requirement checking sits behind the same flag as pip:

```python
# homeassistant/requirements.py:167
if not self.hass.config.skip_pip:
    await self._async_process_integration(integration, done)
```

So Home Assistant does not check, does not raise `RequirementsNotFound`, and logs nothing about pip. The integration loads, does `import pyfoo`, and the first symptom is an `ImportError` from inside someone else's code — which for a lazily-importing integration may not appear until the affected device is first used, days after the download. There is no upstream signal to alert on, so `hacs-deps-check` manufactures one.

You do not have to remember to run it. `hass-hacs-deps.service` runs it on every Home Assistant start (`wantedBy = home-assistant.service`), and a failure becomes `clanarchy_container_systemd_unit_failed` within a minute via ernst's container-unit collector.

## The other kind of dependency

A manifest has **two** dependency fields and only one of them is this tool's business:

| Field | Names | Declared as | Failure mode |
|---|---|---|---|
| `requirements` | Python distributions | `extraPackages` | **silent** — hence this tool |
| `dependencies` | other HA integrations | `extraComponents` | loud — HA names the missing integration |

`hacs-deps-check` deliberately ignores `dependencies`: that failure reports itself clearly, and the tool exists only for the one that doesn't.

!!! warning "`extraComponents` is not free to grow"
    The list is already near a hard ceiling. At 1595 entries the module's colon-separated PYTHONPATH was 162898 bytes, and `execve()` rejects any environment string over 131072 — so Home Assistant did not start **at all**. That took the hub down on 2026-09-25; the fix (PR #233) merges every dependency into one `buildEnv` instead. Before adding components, read the `hassPythonEnv` note in `home-assistant.nix`.

## Checking before you install

`hacs-deps-check` only sees what is already downloaded. To vet an integration first, read its `manifest.json` in the upstream repo — `requirements` is the list you will owe Nix.

## What it skips, and why that is not a gap

Integrations symlinked in from the Nix store are reported as `DECLARED` rather than re-checked. Their requirements were proven at **build** time by `buildHomeAssistantComponent`'s `manifestRequirementsCheckHook`, which fails the derivation on a miss — so re-checking could only ever agree, and a disagreement would mean the store path had been edited underneath us.
