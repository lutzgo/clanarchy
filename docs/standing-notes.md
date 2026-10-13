# Standing notes

Not invariants — an invariant is a property of the **system** that a milestone
must design around. These are properties of the **ground** a milestone stands
on: hazards that live in a file somebody will edit for an unrelated reason, and
decisions the fleet owes itself but has not made. They are here rather than
inside the change that discovered them precisely because the person who trips
over them will not be reading that change.

## SN1 — The model tag silently sets the context window

**Ollama derives `num_ctx` from the model when it is not set explicitly.**
Measured on 2026-08-25: `qwen3-coder:30b` on ernst → **32768**;
`qwen2.5-coder:7b` on miralda → **4096**. So editing the `models` list in
`clan.nix` — which is what `service-modules/local-ai.nix`'s `models` option
invites — **changes the context window fleet-wide, with no diff that shows it.**
A one-word edit that reads as "use the smaller model" is actually "quarter the
context and break tool calling", and nothing in the review says so.

The consequence is not degraded output, which is what makes it dangerous.
Measured at `num_ctx = 8192`: a **17,083-token** file (`containers/arr.nix`) was
silently truncated to **4,098** tokens. HTTP 200, no flag, no warning anywhere in
the response. Truncation **keeps the tail and drops the head** at roughly
`num_ctx/2` — and the system message and tool definitions live at the front, so
**tool calling went to 0/6**. Asked for a fact from the dropped head, the model
did not decline: it **invented a plausible, placeholder-shaped MAC address**
(`00:11:22:33:44:55` in place of `02:00:00:90:00:05`) — precisely the kind of
value that survives a skim of a diff.

**So `num_ctx` must be set explicitly wherever the model is declared, and the
two must be reviewed together.** A model-tag change is a context change until
proven otherwise.

**CLOSED 2026-08-26 at the place the hazard lives.** `roles.ollama` now carries
a `contextLength` setting and both machines set it explicitly — ernst 32768,
miralda 4096. The window no longer moves when `models` is edited, and the two
now sit adjacent in `clan.nix` so a review sees both. The hazard is recorded
rather than deleted because it returns the moment a **new** machine joins
`roles.ollama` without setting it: the option defaults to `null`, which restores
exactly the model-derived behaviour above. **Adding a machine to that role means
setting its context.**

A second hazard of the same shape was found while closing this one and is worth
reading together with it: `kvCacheType = "q8_0"` roughly **halves tool-call
reliability** (83% → 38%) unless the client's system prompt explicitly demands
the `<tool_call>` wrapper — a server-side VRAM optimisation whose cost lands in
a different component and appears in no readback. Measured, interleaved, n=30
per arm. Both are documented in `service-modules/local-ai.md`.

Cross-referenced from M11 (which measured
it) and M15 (whose entire VRAM budget depends on it).

**WHERE THE CONTEXT LIVES NOW — updated 2026-09-09 by
M19, and the hazard is now SPLIT.**

On **ernst**, both halves of this note are closed, at the mechanism rather than
by documentation:

- **The window lives on the model.** `roles.models` declares each model as
  `{ url, hash, contextLength, kvCacheType }`, and **`contextLength` has no
  default** — a model cannot be declared without someone stating its window. The
  same attrset renders both the fetcher and llama-server's preset INI, so there
  is no second place for it to disagree with itself. Editing which model is
  served can no longer move the context of another one, because there is no
  longer a global `OLLAMA_CONTEXT_LENGTH` for them to share.
- **Exceeding it is now LOUD.** llama-server answers an over-long prompt with
  **HTTP 400 `request (16694 tokens) exceeds the available context size (8192
  tokens)`**. The silent-truncation behaviour this note exists to warn about is
  an ollama property, not a general one.

On **miralda** the note stands **completely unchanged**, and that is the reason
it is not being deleted. miralda still runs `roles.ollama` — deliberately; M19
scoped itself to the discrete-card case and an iGPU running out of shared system
RAM is a different question. So the HTTP 200, the tail-kept/head-dropped
truncation and the fabricated answer are all still live there. Re-measured
2026-09-08 on ollama 0.32.3: a 16,694-token prompt became **4,098** tokens and
the model invented `00:00:00:00:00:00` for a fact from the discarded head — a
*different* fabrication from M11's `00:11:22:33:44:55`, which is itself the
point. It is not a memorised wrong answer; it is a fresh invention each time.

**So: adding a machine to `roles.ollama` still means setting its context.
Adding one to `roles.models` cannot fail to.**

The `q8_0` half of this note is also superseded on ernst and only there. It cost
tool-call reliability under ollama at a baseline system prompt; with the
`<tool_call>` reinforcement in place it costs nothing on either server, so the
KV choice is now purely speed-for-context — and at ernst's declared 32768 window
`f16` fits with 2761 MiB to spare, so **the fleet default reverted to `f16`**.

## SN2 — IPv6 is off, and that is now a decision

**ernst's connection is a static full IP stack** — static public IPv4 *and*
native IPv6, no CGNAT, no DS-Lite. Confirmed by lgo, 2026-08. Every milestone to
date was written as if the fleet were v4-only, and until now nothing forced the
question.

**What the repo does today.** Every container sets `IPv6AcceptRA = false` and
takes DHCPv4 only — `containers/jellyfin.nix`, `arr.nix`, `traefik.nix`,
`authelia.nix`, the monitoring container, and the microvm guest, which disables
v6 outright (M3 records that wg-quick aborts under `set -e` on a dual-stack
`Address` line). VLAN 90 carries no GUA. The one v6 in the fleet is M6's `mon0`,
a point-to-point ULA veth to the host — deliberate, scoped, and not what this
note is about.

**That uniformity is an accident, not a decision.** It propagated by copying
M2b's working pattern into every subsequent container. No milestone argued for
it, and no milestone has ever tested it.

**The hazard, precisely.** The v4 security model rests on UDM-Pro ZBF policies
and — implicitly, unexamined — on RFC1918 plus NAT as a backstop. That backstop
is why a ZBF mistake has so far cost reachability *from another VLAN* rather than
*from the internet*: M5 lost a round to `Servers` missing from a source list and
the failure was a timeout, not an exposure. **IPv6 has no NAT and no equivalent
backstop.** If RAs ever reach VLAN 90, every container becomes globally
addressable the moment it accepts one, and the only thing between the internet
and the arr container's `8989` is the UDM-Pro's **IPv6** firewall — a *different*
rule set from the v4 policies this repo has maintained and corrected since M2,
and one **no milestone has ever audited**. The failure would be silent: nothing
in the fleet monitors for an unexpected GUA.

**Measured 2026-08-25, on ernst and in every container** — the baseline this note
exists to be checked against:

```
ip -6 addr show                                  # on ernst
  br0            fe80::b08b:e1ff:fef2:1e7c/64          link-local only
  mon0           fdca:fe90::1/128                      M6's ULA, host end
  ztzavl64zk     fdda:106a:123a:d561:…:711f/88         ZeroTier rfc4193
  enp13s0        (no inet6 at all — bridge port)

nixos-container run <c> -- ip -6 addr show eth0
  jellyfin       fe80::ff:fe90:2/64                    link-local only
  traefik        fe80::ff:fe90:4/64                    link-local only
  arr            fe80::ff:fe90:5/64                    link-local only
  monitoring     fe80::ff:fe90:6/64                    link-local only
  authelia       fe80::ff:fe90:7/64                    link-local only
```

**Link-local only, everywhere. No GUA anywhere on VLAN 90, and none on the host
either** — ernst holds no ISP-delegated v6 address at all today. So the native-v6
half of the connection is, at the fleet's edge, entirely unused. That is the safe
state and it is the *current* state; it is not a state anything defends.

**A GUA anywhere on VLAN 90 makes this an incident, not a note.** Re-run the
block above before believing otherwise.

**The decision owed, either answer acceptable:**

- **(a) VLAN 90 is v4-only, deliberately and permanently.** `IPv6AcceptRA = false`
  is promoted from a copied line to an invariant with a stated reason, and the
  next container that omits it is a review comment rather than an accident.
- **(b) IPv6 is supported**, in which case the UDM-Pro's v6 ruleset is audited,
  proven default-deny inbound, and maintained in parallel from then on — a
  standing cost, not a one-time one.

### DECIDED 2026-09-03 by M18: (a), and now with a mechanism

**The trigger this note named fired.** It said the decision was forced by "M16
choosing the port forward"; M16 chose the tunnel and deferred it, and **M18
un-deferred it** by dropping the tunnel and opening a real WAN port. That ends
the exemption the tunnel bought: with inbound ingress on the box, an unaudited
v6 path is a *second* way in that bypasses the `wan` entrypoint — and therefore
bypasses the entire fail-closed argument M18 is built on.

**The answer is (a): the WAN-facing path is IPv4-only BY CONSTRUCTION.**

**What was measured, on ernst and in every container, 2026-09-03** — the
baseline above, re-run as this note requires:

```
ip -6 addr show                       # on ernst
  br0         fe80::b08b:e1ff:fef2:1e7c/64     link-local only
  mon0        fdca:fe90::1/128                 M6's ULA, host end
  ztzavl64zk  fdda:106a:…:711f/88              ZeroTier rfc4193
  (no ISP-delegated address anywhere)

ip -6 route show default              → nothing.  No RA has ever been accepted.
cat /proc/sys/net/ipv6/conf/br0/accept_ra → 0

nixos-container run <c> -- ip -6 addr show eth0
  jellyfin fe80::ff:fe90:2   traefik fe80::ff:fe90:4   arr        fe80::ff:fe90:5
  monitoring fe80::ff:fe90:6 authelia fe80::ff:fe90:7  tvheadend  fe80::ff:fe90:a
ip netns exec <ns> ip -6 addr show    # the podman tier
  tubesync fe80::ff:fe90:b  storyteller fe80::ff:fe90:c  romm fe80::ff:fe90:e
```

**Link-local only, everywhere. Still no GUA anywhere on VLAN 90, and ernst still
holds no ISP-delegated v6 address at all.** The 2026-08-25 baseline reproduced
exactly, eight days and four milestones later.

**What CHANGED is that this is now enforced rather than observed.** The note's
own complaint was that `IPv6AcceptRA = false` "propagated by copying" and that
nothing defends the safe state. M18 adds three mechanisms, all greppable:

> **CORRECTION 2026-09-07, ON DEPLOY DAY.** The first of the three mechanisms
> below was **wrong**, and it was wrong in the direction that matters: it
> claimed a control that did not exist. It read *"every Traefik entryPoint binds
> `0.0.0.0:` and not `:` … the bind is the defence rather than the absence of a
> GUA."* Measured against the deployed config on 2026-09-07, with every
> entryPoint already written `0.0.0.0:`:
>
> ```
> ss -ltnH -f inet   ->  127.0.0.1:8080  127.0.0.54:53  0.0.0.0:5355
> ss -ltnH -f inet6  ->  *:80  *:443  *:8443  *:8082  *:6060
> ```
>
> **All four entryPoints, plus CrowdSec's metrics port, were accepting IPv6.**
> Go treats `0.0.0.0` as *unspecified* and opens an AF_INET6 socket with
> `IPV6_V6ONLY=0` for any wildcard listen, so the bind convention did nothing
> whatsoever. Not an exposure — link-local only, no GUA, no v6 route, no v6
> forward — but a claim of this shape is worse than no claim, because it reads
> like a control in review. **The lesson is the milestone's own: a mechanism
> that was reasoned about rather than measured is a description.** The list
> below is the corrected one.

- **No IPv6 address exists in the Traefik netns** — `LinkLocalAddressing = "no"`
  on its `10-eth0` network unit. Nothing there needs v6: ACME reaches Let's Encrypt
  over v4 and Technitium is v4-only. **The proof is `ip -6 addr show dev eth0`
  returning nothing, plus an empty `ip -6 route show`.** Not a bare
  `ip -6 addr show`: `lo` keeps `::1/128 scope host`, which is loopback, is
  unreachable from outside the netns, and is supposed to be there. That bare
  form was accurate only while the deleted sysctl block existed, since `all = 1`
  covered `lo` as well.

  > **THIRD CORRECTION, 2026-09-07.** This mechanism was stated wrong three
  > times in one day. All three are left on the record rather than quietly
  > fixed, because the pattern is the point.
  >
  > 1. *"Every entryPoint binds `0.0.0.0:`, so nothing listens on v6."* False —
  >    Go treats `0.0.0.0` as unspecified and opens AF_INET6 with
  >    `IPV6_V6ONLY=0` for any wildcard listen.
  > 2. *"`disable_ipv6` makes Go fall back to `AF_INET`, so `ss -f inet6` comes
  >    back empty."* False — the socket family is available whenever the module
  >    is loaded, independent of addressing.
  > 3. *"`all` + `default` + `eth0` disable_ipv6 removes the address."* False,
  >    and deployed twice before being caught: systemd-sysctl runs **before**
  >    `eth0` exists in the netns so the per-interface key is silently skipped,
  >    **and** systemd-networkd writes `disable_ipv6 = 0` on every link it
  >    configures. Either reason is fatal alone.
  >
  > **What works is `LinkLocalAddressing = "no"`, and the repo already had the
  > idiom** — `machines/ernst/networking.nix` and the `br0` port in
  > `containers/traefik.nix` both carry `LinkLocalAddressing` + `IPv6AcceptRA`
  > together. The container's `10-eth0` had only the second, which is why it
  > alone on VLAN 90 kept a link-local address. **It was an omission, not a
  > decision, and three novel mechanisms were invented before anyone looked at
  > what the neighbouring units already did.**
  >
  > Verified live: with `LinkLocalAddressing=no`, `ip -6 addr show` returns
  > nothing while `net.ipv6.conf.eth0.disable_ipv6` still reads **0** — proof
  > the sysctl was never the mechanism. `10.0.90.12` intact, Traefik serving.
  >
  > ---
  >
  > *Superseded detail from the second correction, kept for the record:*
  > It said `disable_ipv6` would make Go fall back to `AF_INET` so that
  > `ss -ltnH -f inet6` came back empty. **It does not.** Measured on the
  > deployed container with every v6 address gone:
  >
  > ```
  > ip -6 addr show    ->  (nothing)
  > ss -ltnH -f inet6  ->  *:80  *:443  *:8443  *:8082  *:6060
  > ```
  >
  > The AF_INET6 socket family is available whenever the ipv6 module is loaded,
  > independent of addressing. **The listeners are dual-stack and stay
  > dual-stack**; what changed is that they have nothing to be reached on, and
  > no delegated prefix can ever be accepted on `eth0` — which is the thing SN2
  > actually cares about.
  >
  > **`all` alone was deployed and was not enough**: eth0 kept
  > `fe80::ff:fe90:4/64`. nspawn creates the veth and moves it into the netns
  > *before* the container's init runs, so the interface already exists when
  > systemd-sysctl fires; `default` governs interfaces created later and does
  > not apply retroactively. **`eth0` is the key that does the work.** That was
  > established by setting the keys live and watching the address disappear,
  > not by reading kernel documentation.
  >
  > **Two wrong mechanisms in a row, both from reasoning instead of running the
  > command, is the durable lesson** — and a future reader running
  > `ss -f inet6`, finding listeners, and reporting a regression would be the
  > third instance of it;
- **the WAN forward on the UDM-Pro is IPv4 only, and no v6 forward is created** —
  it is in M18's manual steps as an explicit "do not";
- **CrowdSec's remediation declares `nftables.ipv6.enabled = false`**, so there
  is no `crowdsec6` table (`nft list table ip6 crowdsec` → `No such file or
  directory`, confirmed on the deployed system). A v6 ban chain that nothing can
  ever match is the kind of rule that later reads as enforcement. **Note the
  sharper reading this correction forces**: while those sockets *were* dual
  stack, "reachable over v6" and "unbannable over v6" were true at the same
  time. Mechanism one is what makes the pair impossible, not merely unlikely.

**WHAT IS STILL NOT AUDITED, AND MUST NOT BE READ AS AUDITED.** The UDM-Pro's
**IPv6 ruleset** was *not* inspected — Claude does not touch the UDM-Pro, and
lgo's manual steps for M18 do not include it because the design was made not to
need it. That is the honest scope of this decision: **(a) does not require the
v6 ruleset to be correct; it requires there to be nothing listening on v6.** The
two are different claims and only the second is made here.

**The residual risk, stated plainly — and re-stated after the correction above.**
The bind convention narrowed nothing, so the honest version is simpler than the
one it replaces: **everything rests on mechanism one holding, per netns.** The
Traefik netns has it. Any *future* service in another netns that must be reached
from outside would need it too, and would not get it by copying a `0.0.0.0:`
address into its config.

The line about "nothing in the fleet monitors for an unexpected GUA" was the
weakest part of this, and **it is now false**: `exporters.ipv6Guard` on ernst
emits `clanarchy_ipv6_global_addresses` every five minutes and
**`UnexpectedIPv6GlobalAddress`** fires on any non-ULA global address — or on
the collector going silent, so it cannot fail closed-mouthed. The filter is
proven in both directions: ernst's two real global-scope addresses (ZeroTier
`fdda:`, M6's `mon0` `fdca:`) are ULA and yield **0**, while the same filter
over a synthetic `2001:db8::` yields **1**.

**ernst only, deliberately.** The four laptops roam, and a café network handing
out a v6 prefix is routine there; the alert would fire constantly and correctly
on those machines and be ignored within a week — which would teach everyone to
ignore it on ernst too. ernst never leaves VLAN 90, so on ernst a global address
means the **line** changed, which is exactly the event this watches for.

**Triggers that re-open it**, now that it is decided: `UnexpectedIPv6GlobalAddress`
firing (a GUA on VLAN 90 is an incident, not a note — this trigger used to say
"re-run the block above", which is precisely the hand-measurement the alert
replaces); `ss -ltnH -f inet6` in the Traefik netns returning anything at all;
any milestone setting `IPv6AcceptRA = true` on VLAN 90;
any UDM-Pro change enabling RAs or DHCPv6 on the Services network; any service
that must be reachable over v6 from outside, which would force the (b) branch
and the standing cost that comes with it.

Cross-referenced from M16,
M18 and
the backlog.

## SN3 — A broken instrument is indistinguishable from a bad result

M11's session very nearly recorded a tool-calling score of **0/10** for
`qwen3-coder:30b` and wrote the conclusion that follows from it. The true score
was **28/40**. The difference was a `jq` scoping bug in the session's *own*
grader (`$a|has(.)` rebinds `.` to `$a`) — a defect in the measuring apparatus,
producing a damning number about the thing being measured.

That is the same epistemics as SN1's truncation finding, seen from the other
side. There, a silently truncated context is indistinguishable from a stupid
model. Here, a silently broken grader is indistinguishable from a stupid model.
In both cases the observation is confident, internally consistent, and about the
wrong subject.

**This repo already knows the answer and has paid for it twice.** M3's synthetic
hardlink proof carries a **negative control** — the same file at `0644`, which
*must* fail with `EPERM` — for exactly this reason: without it, the test cannot
distinguish a working chain from root bypassing the check, which is what an
earlier revision of M3's own plan did. M6 found a zedlet that had never once
delivered a notification, because it discarded curl's stderr and therefore could
not report its own failure.

**The rule: check the instrument before believing a number, and especially
before believing a number that confirms what you expected.** A measurement that
agrees with the prediction gets less scrutiny than one that contradicts it, which
is precisely backwards — the confirming result is the one whose harness nobody
re-reads. In practice this means: a negative control wherever one is possible
(M14 owes one and its prompt says so), and a sanity path wherever one is not.

**Why this is a standing note and not a tenth invariant.** The nine invariants
are each a property of the *system* with a *mechanism* behind it — a dataset
boundary, a firewall rule, a tier, a directory. A milestone respects them in its
**design**. This is a rule about **method**, it binds every milestone's test plan
rather than any milestone's architecture, and it has no mechanism to point at.
Filing it as invariant #10 would dilute a list whose value is that every entry
names something concrete you can go and check.

## SN4 — A failed oneshot on a timer is silent

**Found by M14, the expensive way.** Soularr ran every 15 minutes for a day and
failed every single time:

```
cat: /run/arr-api-keys/lidarr-api-key: Permission denied
```

Roughly ninety consecutive failures, and **nothing anywhere said so**. The
service was `active (waiting)` because that is the *timer's* state; the unit
itself was `inactive (dead)` with a stale `Result=exit-code` that no dashboard
looks at. `systemctl list-units --failed` was **empty** — a oneshot that failed
and was then re-triggered does not stay in the failed set. The symptom reached
a human only as "nothing has downloaded", days later, with no obvious place to
look.

**The rule: a timer-driven unit needs an alert, or it does not need to exist.**
A long-running service that dies is loud — the port stops answering, the
container restart-loops, someone notices within minutes. A oneshot has none of
that: its whole lifecycle is "start, exit, disappear", and a failing exit looks
identical to a successful one from every angle except its journal.

**Concretely, for this fleet:** anything on a timer needs either a Prometheus
alert on `node_systemd_unit_state{state="failed"}` for that unit, or an
`OnFailure=` handler that reaches ntfy. M6 already scrapes systemd unit state on
every machine, so the exporter half exists and only the alert rule is missing.
This is owed by `soularr`, `recyclarr` and every future timer.

**Why this is a standing note and not an invariant**, on SN3's own test: it is a
rule about *method* — how a milestone must make its work observable — not a
property of the system with a mechanism to point at. It binds every milestone
that adds a timer, and no milestone's architecture.

---

## SN5 — A prompted clan var blocks EVERY deploy in the fleet, not just its own machine

**Measured 2026-09-11**, on the first `clan machines update ernst` of M22. The
command stopped before it built anything, prompting for a var belonging to
**jens**:

```
Prompting value for immich-api-key/api-key for machines: jens
Immich API key for lgo on https://photos.goclan.org … (hidden):
termios.error: (25, 'Inappropriate ioctl for device')
```

It is not a quirk of that var. It is what the command does:

```python
all_machines = list(flake.list_machines_full().values())
…
run_generators(all_machines, full_closure=False)
```
— `clan_cli/machines/update.py`

**`clan machines update <machine>` runs the generators for every machine in the
flake**, then updates the one named. So an unanswered prompt anywhere — on a
laptop that is switched off, on a machine nobody has deployed in a month —
stops a deploy of an unrelated machine, before it evaluates anything.

**Two consequences, and the second is the one that bites.**

*It needs a TTY.* Any deploy driven by a script, a CI job or an agent dies at
`termios.tcgetattr` rather than failing cleanly, and the error names neither the
machine nor the var in its message.

*A prompted var whose value cannot exist yet is a DEADLOCK, not an ordering
hazard.* This is the real trap and it is easy to build by accident. The rule
this repo had was `traefik-acme`'s — **GENERATE BEFORE YOU DEPLOY** — and it is
correct *there*, because a Cloudflare API token exists independently of this
fleet and can be minted at any time. It does not generalise. A credential
**issued by a service this clan hosts** cannot be generated before that service
is deployed, and declaring a prompt for it blocks the very deploy that would
make it obtainable — plus every other deploy until someone breaks the cycle.

M22 built exactly that and had to be changed on deploy day: the laptop uploader
now ships `clanarchy.immich.upload.enable = false`, so the generator is not
declared at all, and enabling it is a deliberate second step after the accounts
exist. See `modules/immich-upload.nix`.

**The test to apply before adding a prompted generator.** Ask: *can this value
be obtained right now, with the fleet in whatever state it is in?*

- **Yes** — an external credential (Cloudflare, IVPN, an indexer API key, a
  password the operator chooses). Prompt away; `traefik-acme`'s rule applies.
- **No** — it is issued by something this clan runs. Then **the consumer must
  ship disabled**, so the generator is not declared until the value exists.
  Gating on an option is the mechanism; `lib.mkIf cfg.enable` around the
  generator is all it takes.

**What must NOT be done instead**, because both are worse and both look
tempting at the prompt: answering blank (it stores nothing, `.path` becomes
`/no-such-path`, and every later deploy re-prompts — this took RomM down on
2026-09-07), and answering with a placeholder (the service authenticates with
garbage and fails at runtime instead of at deploy time, which is the direction
this repo spends its effort avoiding).

**Why this is a standing note and not an invariant**, on SN3's own test: it is a
property of the *ground* — a hazard living in `clan_cli`, which nobody edits and
everybody stands on — rather than a property of this system's architecture. It
binds every future milestone that adds a secret, and no milestone's design.

**Worth reporting upstream**, alongside the `Domains=skynet.lan` item in the
backlog: running every machine's generators for a single-machine update is at
best surprising, and the TTY failure mode has no non-interactive escape hatch
(`--no-check` is unrelated; there is no `--no-vars`).

---

