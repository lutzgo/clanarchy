# History

One row per milestone. The code refers to milestones by number — roughly 1,400
`M<n>` tokens across the `.nix` tree — so this index exists to make every one of
them resolvable: what it was, whether it landed, and which PRs to read.

**The per-milestone journals that used to live here are gone.** They ran to
~15,000 lines, held a third copy of explanations that already exist in the code
and in the guides, and had begun to contradict both. What they recorded that is
still load-bearing was moved rather than deleted:

- properties a change must design around → [invariants](invariants.md)
- hazards in files somebody will edit for another reason → [standing notes](standing-notes.md)
- temporary firewall / DNS / routing shims → [ledger](ledger.md)
- incidents worth their own write-up → [`docs/incidents/`](incidents/ernst-card1-vram-starvation-2026-10-09.md)
- everything else → the PRs linked below, and `git log`

Two numbers appear in the code with no row here: **M22b** and **M25**, both
referenced as future work that was never written up ("idle until M25").

Comments throughout the tree refer to "the roadmap" — its briefs, its prompts,
its packaging rule, its backlog. They mean this file and the PRs it links. The
prose was left as written rather than rewritten in ~30 places, because the
rename is not what those sentences are about.

Statuses were verified against the repo on 2026-08-25 for the rows up to M21,
and updated in place for each milestone since.

| Milestone / work | Status | PRs |
|---|---|---|
| zdata datasets + server-role hardening | **done** | [#18](https://github.com/lutzgo/clanarchy/pull/18) |
| `/srv/media` as one hardlink domain | **done** | [#20](https://github.com/lutzgo/clanarchy/pull/20) |
| Datasets for the rescued Arch data | **done** | [#66](https://github.com/lutzgo/clanarchy/pull/66) |
| `modules/gaming-common.nix` extraction | **done** | [#19](https://github.com/lutzgo/clanarchy/pull/19) |
| Jellyfin in an nspawn container | **done** | [#20](https://github.com/lutzgo/clanarchy/pull/20), [#45](https://github.com/lutzgo/clanarchy/pull/45), [#46](https://github.com/lutzgo/clanarchy/pull/46) |
| Jellyfin VAAPI transcoding | **done** | [#49](https://github.com/lutzgo/clanarchy/pull/49), [#50](https://github.com/lutzgo/clanarchy/pull/50), [#51](https://github.com/lutzgo/clanarchy/pull/51) |
| Container journals persisted | **done** | [#54](https://github.com/lutzgo/clanarchy/pull/54) |
| HTPC role (gamescope + Plasma switching) | **done** | [#39](https://github.com/lutzgo/clanarchy/pull/39), [#53](https://github.com/lutzgo/clanarchy/pull/53), [#57](https://github.com/lutzgo/clanarchy/pull/57) |
| Wireless Xbox controller support | **done** | [#65](https://github.com/lutzgo/clanarchy/pull/65) |
| TV session survives a dark TV | **done** | [#68](https://github.com/lutzgo/clanarchy/pull/68) |
| Headless opt-in gaming | **superseded** | — |
| Plasma Bigscreen in a container | **parked** | [#48](https://github.com/lutzgo/clanarchy/pull/48), [#60](https://github.com/lutzgo/clanarchy/pull/60), [#62](https://github.com/lutzgo/clanarchy/pull/62), [#63](https://github.com/lutzgo/clanarchy/pull/63), **revert [#64](https://github.com/lutzgo/clanarchy/pull/64)** |
| Ollama on ernst | **done** | [#39](https://github.com/lutzgo/clanarchy/pull/39), [#47](https://github.com/lutzgo/clanarchy/pull/47), [#52](https://github.com/lutzgo/clanarchy/pull/52), [#55](https://github.com/lutzgo/clanarchy/pull/55), [#61](https://github.com/lutzgo/clanarchy/pull/61) |
| ZFS → ntfy alerting | **done** | [#33](https://github.com/lutzgo/clanarchy/pull/33), [#35](https://github.com/lutzgo/clanarchy/pull/35), [#40](https://github.com/lutzgo/clanarchy/pull/40) |
| `fwupd-refresh` failure tolerance | **done** | — |
| Deploy interface = clan CLI | **done** | [#59](https://github.com/lutzgo/clanarchy/pull/59) |
| CI eval check on PRs | **done** | — |
| ernst `@blank` snapshots | **done — executed 2026-08-18** | — |
| M1 — Kvantum linkGeneration drift | **closed — did not reproduce** | — |
| M2 — ernst VLAN bridge | **done — deployed 2026-08-20** | [#73](https://github.com/lutzgo/clanarchy/pull/73) |
| M2b — Jellyfin on its own veth | **done — deployed 2026-08-20** | [#82](https://github.com/lutzgo/clanarchy/pull/82) |
| M3 — VPN microvm + qBittorrent | **done — deployed 2026-08-20** | [#83](https://github.com/lutzgo/clanarchy/pull/83) |
| M4 — arr stack | **done — deployed, proven, and survived an unplanned power cut 2026-08-21** | [#85](https://github.com/lutzgo/clanarchy/pull/85) |
| M5 — Traefik | **done — deployed 2026-08-23, proven 2026-08-24** | [#86](https://github.com/lutzgo/clanarchy/pull/86) |
| M6 — monitoring | **done — deployed, alerting proven end to end, and survived a real reboot 2026-08-24; biene/birte pending** | [#87](https://github.com/lutzgo/clanarchy/pull/87) |
| M7 — Authelia | **done — deployed 2026-08-24; both accounts enrolled on TOTP + WebAuthn; L5 retired in code and in the device; Grafana OIDC and the reboot still pending** | [#90](https://github.com/lutzgo/clanarchy/pull/90) |
| M8 — Tvheadend / SAT>IP live TV | **done — deployed and playing 2026-08-27; Phase 0 cleared the same day with live evidence** | — |
| M9 — TubeSync | **done — deployed 2026-08-27, first source added** | — |
| M10 — Kodi + IR remote | **dropped — 2026-08-20** | — |
| M11 — fleet-local coding agent | **open — Parts 2/3/4 done 2026-08-26; Part 1 outstanding** | — |
| M12 — arr helpers | **done — deployed and merged 2026-08-26 (#100); (a) Byparr split out as M12b** | — |
| M12c — library profile reassignment | **open — requested 2026-08-26** | — |
| M13 — media lifecycle | **done — deployed via [#102](https://github.com/lutzgo/clanarchy/pull/102), operator-confirmed 2026-08-27** | [#102](https://github.com/lutzgo/clanarchy/pull/102) |
| M14 — libraries | **done — deployed and merged 2026-08-29 ([#108](https://github.com/lutzgo/clanarchy/pull/108)); ONE VERIFICATION STILL OWED** | — |
| M15 — Tdarr / space reclamation | **closed 2026-08-29 — measured, and NOTHING SHIPS: neither Muxarr nor Tdarr** | — |
| M16 — external ingress | **superseded 2026-09-03 by M18** — the tunnel is deleted; the two externally reachable hostnames and the auth posture are unchanged, only the mechanism | — |
| M17 — ebook acquisition | **done — deployed and operator-confirmed 2026-08-31; both owed verifications PASSED** | — |
| M18 — WAN ingress, direct | **built 2026-09-03 — the deploy, the UDM-Pro forward, the public A records, the reboot and the off-net negative controls are lgo's** | — |
| M19 — llama.cpp on ernst | **DEPLOYED AND FULLY VERIFIED 2026-09-09** | — |
| M20 — SearXNG / web search | **done — deployed and fully verified 2026-09-10, end to end; TWO DEFECTS found after the first deploy, both fixed and confirmed live** | [#171](https://github.com/lutzgo/clanarchy/pull/171) |
| M21 — image generation | **done — verified working 2026-09-10; BUILT not pinned, and SIX defects surfaced after "shipped"** | — |
| M22 — Immich | **DONE — deployed, both libraries imported, and 5G upload confirmed 2026-09-11** | [#177](https://github.com/lutzgo/clanarchy/pull/177) [#179](https://github.com/lutzgo/clanarchy/pull/179) [#180](https://github.com/lutzgo/clanarchy/pull/180) |
| M23 — Nextcloud | **deployed 2026-09-15**; OIDC end to end after two defects found by using it | — |
| M24 — Home Assistant | **deployed 2026-09-16**, first try; two defects found by deploying. HACS followed as M24b | [#196](https://github.com/lutzgo/clanarchy/pull/196) |
| M24b — HACS | **DEPLOYED AND FULLY VERIFIED 2026-09-18. TWO DEFECTS FOUND BY TESTING RATHER THAN BY READING, and the second one would have made the alerting worse than useless** | [#200](https://github.com/lutzgo/clanarchy/pull/200) |
| M26 — the service index | **DEPLOYED AND FULLY VERIFIED 2026-09-17, same day. It came up on the first try. TWO DEFECTS FOUND BY DEPLOYING, and the first one REMOVED a firewall rule rather than adding one** | [#197](https://github.com/lutzgo/clanarchy/pull/197) |
| M27 — the reading stack | **deployed 2026-09-19**; four defects found by deploying, two of them silent | [#201](https://github.com/lutzgo/clanarchy/pull/201) |
| M28 — the reading pipeline | **deployed 2026-09-20** and structurally verified, then found not to work in practice — both true | [#204](https://github.com/lutzgo/clanarchy/pull/204) |
| M29 — Home Assistant on the local AI tier | **deployed 2026-09-24**; carries the fix for the five-day Open WebUI outage. One defect found by deploying | [#219](https://github.com/lutzgo/clanarchy/pull/219), [#220](https://github.com/lutzgo/clanarchy/pull/220) |
| M29b — the agent's memory, web search and images | **BUILT 2026-09-25; not yet deployed.** `mneme` gains a git-versioned wiki it reads and writes, a `web_search` tool over SearXNG, and a `generate_image` tool over ComfyUI | — |
| M29c — Qwen3.6 on ernst | **MEASURED AND SWITCHED 2026-09-25.** `qwen3.6-35b-a3b` replaces BOTH `qwen3-coder-30b` and `qwen2.5-vl-7b`; the vision entry is deleted | — |
| M30 — Music Assistant | **deployed 2026-09-27**, verified end to end including playback; six defects, four of them ours | [#236](https://github.com/lutzgo/clanarchy/pull/236) |
| M31 — mail for @goclan.org | row says **built, not yet deployed** (2026-10-06) — **STALE**: `docs/guides/mail.md` documents it live, with deliverability fixed. The guide is authoritative | — |
| M32 — Paperless-ngx | **deployed 2026-10-06**, verified end to end; five defects, four of them a PR comment asserting something false | — |
