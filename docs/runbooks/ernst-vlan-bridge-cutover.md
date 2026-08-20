# ernst — cutting over to the VLAN bridge

Converting ernst from a plain static address on `enp13s0` to a VLAN-filtering
bridge `br0`, with `enp13s0` as a tagged trunk port.

**This is the high-risk change in the ernst buildout.** ernst is reachable only
over the network being reconfigured, and `clan machines update` applies it
*live* — there is no stage-for-next-boot mode, so `switch-to-configuration boot`
**and** `switch` both run and networkd reconfigures mid-session.

Read the whole runbook before starting. §2 happens on the UDM-Pro *before*
anything is deployed, and is verified with ernst still untouched.

## What changes

| | Before | After |
|---|---|---|
| Host address | on `enp13s0` | on `br0` |
| `enp13s0` | static `10.0.50.10/24` | trunk port, no L3 |
| VLANs on the wire | untagged only | 50 untagged (PVID) + 1, 5, 20, 90 tagged |
| DNS routing | `Domains = "~. skynet.lan"` on `enp13s0` | same, on `br0` |
| Stage-1 initrd SSH | raw `enp13s0` | **unchanged** — raw `enp13s0` |

The host's L2 identity does not change: with exactly one port, the kernel gives
`br0` the burned-in MAC of `enp13s0`.

## 1. Prerequisites

Do not skip any of these. Each one is a channel you may need.

1. **A console you have actually tested.** Two heads exist and they are not
   interchangeable:

   | Head | DRM | PCI | Watched by |
   |---|---|---|---|
   | iGPU | `card0-HDMI-A-2` | `0000:7b:00.0` | GL.iNet Comet KVM |
   | dGPU (7900 XTX) | `card1-HDMI-A-1` | `0000:03:00.0` | the living-room TV |

   The KVM is the *documented* console, but it is not the essential one — and
   as of 2026-08-19 it was dead (black screen, no video and no input) while
   `card0-HDMI-A-2` still reported `connected`, i.e. the fault was on the KVM
   side, not a missing signal.

   **The TV plus a keyboard is a sufficient substitute, and in one way a
   better one:** it gives a full recovery shell without depending on firmware
   video at all. `logind` runs with the default `NAutoVTs=6`, so **Ctrl+Alt+F2**
   drops from the HTPC session to a getty.

   **Test this before you change anything, not after:**

   - At the TV, press **Ctrl+Alt+F2** — you should get a login prompt.
   - Log in as **`admin`** (uid 1000). `root` is locked and `go` is
     deliberately not in `wheel`, so `admin` is the only local account that
     can fix anything.
   - Run `sudo -v` to confirm the password works and sudo is available
     (`%wheel ALL=(ALL:ALL)` is set).
   - **Ctrl+Alt+F1** returns to the couch session.

   If `admin` cannot log in there, stop — you have no recovery path and the
   cutover must wait until either the KVM or that login is fixed.

   Note the boot menu is a separate question: systemd-boot renders on whichever
   head the UEFI treats as primary, which is very likely the iGPU (that is why
   the KVM watches it). With the KVM dead you should assume **the boot menu is
   not visible**, and use the live rollback in §5 instead — it does not need it.
2. **Second out-of-band path.** ZeroTier survives a VLAN-50 mistake that would
   leave the KVM as the only option:

   ```
   ssh ernst-zt true
   ```

3. **Rollback target exists.** Confirm the previous generation is selectable in
   the systemd-boot menu — over the KVM, not just `bootctl list` output.
4. **Record the current state** for comparison, and for the MAC that M2b will
   need to pin:

   ```
   ip -br link show enp13s0        # ← save this MAC
   ip -br addr
   ip route
   resolvectl status
   nmcli device status
   bridge link show                # expect empty
   ```

   Baseline captured 2026-08-19, before the cutover:

   | | Value |
   |---|---|
   | `enp13s0` MAC | `a0:ad:9f:1c:9d:74` — **this is the value to pin on `br0` before M2b** |
   | Address | `10.0.50.10/24` on `enp13s0` |
   | Default route | `via 10.0.50.1 dev enp13s0` |
   | `bridge link show` | empty |
   | `nmcli` on `enp13s0` | **`connected (externally)`** |
   | resolved on `enp13s0` | DNS `10.0.5.3`, domain `skynet.lan ~.` |

   Note the NetworkManager row. `connected (externally)` means NM *sees* the
   uplink and considers it managed-but-configured-elsewhere — it is not hands
   off today. That is precisely why `machines/ernst/networking.nix` names
   `br0` and the physical NICs in `networking.networkmanager.unmanaged`
   rather than trusting udev's `ID_NET_MANAGED_BY` tagging. After the cutover
   these must read `unmanaged`, not `connected (externally)`.

5. **Deploy target.** clan's configured `targetHost` is DNS-dependent. Use the
   IP literal for the cutover so name resolution is off the critical path:

   ```
   clan machines update ernst --target-host root@10.0.50.10
   ```

## 2. UDM-Pro — done FIRST, verified on its own

Making the port a trunk **does not change untagged handling**, so this step is a
no-op for the running host and can be verified independently. Doing it after the
deploy would stack two unverified changes on top of each other.

### 2.1 Create the Services network

Settings → Networks → **Create New Network**.

| Field | Value |
|---|---|
| Name | `Services` |
| VLAN ID | `90` |
| Gateway / Host Address | `10.0.90.1/24` |
| DHCP | Server on. UniFi fixes the range at **`10.0.90.6`–`10.0.90.254`** and does not allow narrowing it |
| Domain Name | `skynet.lan` |
| DNS Server | **Manual → `10.0.5.3`** so containers inherit Technitium like the host |
| Device Isolation | **off** — Traefik must reach Jellyfin in M5 |

**On addressing for M2b/M5.** The pool covers almost the whole subnet, so there
is no "static range" to hold back. Give containers **DHCP reservations against
their pinned MACs** — UniFi assigns a fixed IP inside the pool quite happily, and
that keeps the network's source of truth on the UDM-Pro, which is what M2b wanted
anyway. Only `10.0.90.2`–`.5` sit outside the pool, so reserve those for anything
that genuinely must be hard-coded.

### 2.2 Firewall zone

**A new network lands in the `Internal` zone by default.** On this UDM-Pro
`Internal` already holds LAN, IoT, HA, DNS-Container, Servers and Matter, and the
matrix has `Internal → Internal: Allow All`. Leaving `Services` there means it
shares a zone — and therefore a blanket allow — with the host it is supposed to
be separable from, and architecture invariant #3 has nothing to bite on.

Zone-Based Firewall → **Create Zone** → name it `Services` → assign the
`Services` network to it. A network belongs to exactly one zone, so this removes
it from `Internal` automatically. Confirm afterwards that the `Internal` row no
longer lists `Services`.

No policies yet — M2b and M5 add them. But know what that implies: once
`Services` is its own zone it is **isolated by default**, so when M2b puts
Jellyfin there it will need at minimum `Services → DNS-Container` (Technitium at
10.0.5.3, or nothing resolves) and `Services → External` (metadata and plugin
downloads). Those belong to M2b, not here — they are noted so their absence
later reads as expected rather than as a bug.

Leave the existing interim rules alone. `Allow Jellyfin from LAN to Servers`
(`10.0.50.10/32:8096`, ledger row **L1**) stays pointed at the host address —
Jellyfin is still on host networking until M2b.

No rules yet — M2b and M5 add them. Leave interim ledger rows **L1** (Family →
`ernst:8096`) and **L2** (IoT → `ernst:8096`) pointing at `10.0.50.10`; Jellyfin
is still on host networking after this change.

### 2.3 Port profile on ernst's switch port

**ernst is on `USW Pro 24 PoE` port 6, not on a UDM-Pro SFP+ port.** Verified
2026-08-19 from the UniFi client list. The topology is:

```
UDM-Pro SFP+2 ══ 10 GbE ══ USW Pro 24 PoE ── port 6 (GbE) ── ernst enp13s0
```

So there are two links to think about, not one: the access port carrying ernst,
and the switch's uplink to the UDM-Pro. UniFi normally propagates every network
across inter-switch uplinks automatically — verify rather than assume, but the
uplink is not usually where this goes wrong.

Note ernst's own port runs at **1 GbE**: the AQC113CS is 10GBASE-T, but port 6
is a GbE port. Nothing here depends on the speed; it is recorded so nobody
"fixes" a link that was never 10G.

Settings → Profiles → Ethernet Port Profiles.

- **Native VLAN / Network: `Servers (50)` — do not change, do not blank.**
  This is what keeps stage-1 initrd SSH alive. In stage 1 the raw NIC speaks
  untagged; a pure tagged trunk kills the unlock channel and makes every future
  boot a KVM trip.
- **Tagged VLAN Management: Custom** → `LAN (1)`, `DNS-Container (5)`,
  `IoT (20)`, `Services (90)`.
  Not "Allow All" — that would put HA (30), Guest (40) and Matter (60) on the
  trunk, against the decision that a VLAN not on the trunk cannot be reached by
  a typo in a future container unit.

Apply to `USW Pro 24 PoE` **port 6** only — do not edit the shared "All" profile
in place unless it is used by that port alone, or every other port inherits the
trunk.

### 2.4 Prove the trunk before touching ernst's config

Do not take the switch UI's word for it. These probes create VLAN sub-interfaces
on the *running* `enp13s0`, prove what the trunk actually delivers, and remove
themselves — the host's own untagged config is never touched.

**Are tagged frames arriving at all?** Passive, no addressing, no firewall
involvement:

```bash
for v in 1 5 20 90; do ip link add link enp13s0 name vl$v type vlan id $v; ip link set vl$v up; done
sleep 25
for v in 1 5 20 90; do echo "VLAN $v: $(cat /sys/class/net/vl$v/statistics/rx_packets) pkts"; done
for v in 1 5 20 90; do ip link del vl$v; done
```

Busy VLANs (LAN, IoT) should show thousands; quiet ones (DNS-Container,
Services) may show only a couple of LLDP/STP frames — **any non-zero count means
the tag is being delivered.** Zero on a busy VLAN means the port profile did not
apply.

**Is the VLAN routed?** Tagging and routing are different things, and this is the
trap that cost time on 2026-08-19:

```bash
ip link add link enp13s0 name vl90 type vlan id 90
ip addr add 10.0.90.250/24 dev vl90; ip link set vl90 up; sleep 4
ping -c1 -W2 -I vl90 10.0.90.1 >/dev/null 2>&1; ip neigh show dev vl90
ip link del vl90
```

`lladdr … REACHABLE` means a gateway SVI exists. `INCOMPLETE` or `FAILED` means
**nothing is routing that VLAN**, even though the tag is being delivered.
Confirm with a DHCP probe that configures nothing:

```bash
nix shell nixpkgs#dhcpcd -c dhcpcd -1 -T vl90
```

Falling back to a `169.254.x` IPv4LL address means no DHCP server answered.

Use a VLAN you know is routed as the control — VLAN 5 should ARP-resolve
`10.0.5.1` and ping Technitium at `10.0.5.3`. If the control works and the new
VLAN does not, the fault is that network's configuration, not the trunk.

!!! danger "Resolved 2026-08-20 — Services moved to VLAN 90 / `10.0.90.0/24`"

    **This is history, kept because the failure mode is worth recognising.** The
    Services network was originally VLAN 80 on `10.0.80.0/24`, and its gateway
    never answered. The fix was to renumber, not to repair anything: the subnet
    was already taken.

    `wg show` on the UDM-Pro identified the claimant as a live site-to-site
    peer, not a stale entry — `allowed ips: 10.0.70.2/32, 10.0.80.0/24`, with
    16.02 GiB received / 55.78 GiB sent. Reclaiming the subnet would have broken
    that tunnel's routing, so Services moved instead. `10.0.90.0/24` was verified
    free first (`ip route show | grep -E '^10\.0\.'`), and `10.0.80.0/24` is the
    only subnet routed to `wgsrv1`.

    **`10.0.80.0/24` was claimed by the `skynet-travel` WireGuard
    config**, so the UDM-Pro carried two routes for it and the wrong one won:

    ```
    10.0.80.0/24 dev wgsrv1 proto VPN scope link          ← wins
    10.0.80.0/24 dev br80   proto kernel scope link src 10.0.80.1

    ip route get 10.0.80.250 → dev wgsrv1 src 10.0.70.1   ❌
    ip route get 10.0.20.250 → dev br20   src 10.0.20.1   ✅
    ```

    The UDM-Pro sets `arp_filter = 1` on its bridges, which answers an ARP
    request **only if the kernel would route back to the sender out of that same
    interface**. It would have routed to `10.0.80.250` via `wgsrv1`, so it
    silently declined to reply on `br80` — no filter, no log, no error.

    This is why every component tested correct in isolation: interfaces `UP`,
    `eth10.80`/`switch0.80` properly enslaved to `br80`, address present,
    requests visibly arriving (`tcpdump -i br80 -n -e arp` showed ernst's
    `a0:ad:9f:1c:9d:74`), sysctls identical to the working `br20`, and ebtables
    empty. The fault was one routing-table row.

    **Diagnostic sequence that found it** — reuse this shape for any "VLAN is
    tagged but the gateway is silent" case:

    1. `ip link show master br<N>` — are the VLAN subinterfaces enslaved?
    2. `tcpdump -i br<N> -n -e arp` — do the requests actually arrive?
    3. `sysctl …arp_ignore …arp_filter …rp_filter` — diff against a *working*
       bridge, not against expectations.
    4. **`ip route get <sender-ip>`** — the decisive one. With `arp_filter = 1`,
       an ARP reply is a routing decision.

    Wrong hypotheses discarded on the way: "VLAN Only" network (settings
    disproved it), provisioning lag (persisted for hours), and the UDM↔USW
    uplink not trunking VLAN 80 (frames demonstrably arrived).

    **Lesson for future VLANs: check the subnet against `ip route show` on the
    UDM-Pro before creating the network.** A free VLAN ID does not imply a free
    subnet — VPN peers, WireGuard `AllowedIPs` and site-to-site tunnels all
    install routes that shadow a connected network.

    **This never blocked M2** — the bridge cutover needs only VLAN 50 untagged
    for the host. It gates **M2b**, where Jellyfin first needs an address on the
    services VLAN.

### 2.5 Verify with ernst unchanged

From miralda:

```
ping -c3 10.0.50.10
ssh root@10.0.50.10 true
```

Expect a brief port bounce while the profile is pushed. **If this fails, stop
and revert the port profile.** ernst's configuration is still untouched at this
point, so the switch is the only thing that can be wrong.

## 3. Deploy

The SSH transport may drop at the moment the address migrates from `enp13s0` to
`br0`. Plan for it rather than being surprised by it.

- Run from miralda inside `zellij`, so a dropped connection does not kill the run.
- Keep the KVM console visible throughout.

```
clan machines update ernst --target-host root@10.0.50.10
```

If the connection drops, **do not retry blind** — look at the KVM console first,
then re-run. The update is idempotent.

## 4. Verification, in order

On ernst, over restored SSH or the KVM:

```
networkctl list                 # br0 routable/configured, enp13s0 enslaved/configured
networkctl status br0 enp13s0
bridge -d vlan show             # ← the decisive one
bridge -d link show             # enp13s0 master br0, state forwarding
ip -br addr                     # 10.0.50.10/24 on br0, nothing on enp13s0
ip route                        # default via 10.0.50.1 dev br0
resolvectl status br0           # DNS Servers: 10.0.5.3 ; DNS Domain: ~. skynet.lan
nmcli device status             # br0 and enp13s0 both unmanaged
```

`nmcli` is a real check, not a formality: before the cutover `enp13s0` reads
`connected (externally)`. If it still does afterwards — or if `br0` appears as
anything other than `unmanaged` — NetworkManager did not take the hands-off
setting, and it can still pull the rug out from under networkd.

`bridge vlan show` must show exactly this:

```
port      vlan-id
enp13s0   1
          5
          20
          50 PVID Egress Untagged
          90
br0       50 PVID Egress Untagged     ← the "self" entry
```

**If the `br0` line is missing, the host is deaf** — it holds an address and
cannot emit a frame. See §5 for the one-line live fix.

### Reachability matrix

| From | Check | Proves |
|---|---|---|
| ernst | `ping -c3 10.0.50.1` | untagged egress on VLAN 50 |
| ernst | `ping -c3 10.0.5.3` | Technitium reachable |
| ernst | `resolvectl query ernst.skynet.lan` | the `~.` routing domain is live |
| ernst | `curl -sSo /dev/null -w '%{http_code}\n' https://cache.nixos.org/nix-cache-info` | DNS + egress, i.e. the *next* deploy will work |
| miralda | `ssh root@10.0.50.10 true` | inbound on the server VLAN |
| miralda | `avahi-resolve -n ernst.local` | mDNS survived the move to `br0` |
| miralda | `ssh ernst-zt true` | the out-of-band channel survived |
| a LAN/Family host | `curl -sSI http://10.0.50.10:8096/health` | ledger row **L1** still holds |
| an IoT TV | Jellyfin app plays a title | ledger row **L2** still holds |

### Reboot test

This is the **only** thing that proves initrd SSH survived the trunk change. Do
it with the KVM open, before considering the cutover done.

```
while ! ssh -tt -o ConnectTimeout=2 ernst-initrd systemd-tty-ask-password-agent --query; do sleep 1; done
```

The poll loop is deliberate: the atlantic 10G NIC takes ~10 s to gain link at
boot. If the alias does not answer, try the IP-literal form in §5 before
concluding the channel is dead.

## 5. Recovery

**Host is deaf — `bridge vlan show` has no `br0` self entry.** One line from the
KVM restores it immediately:

```
bridge vlan add dev br0 vid 50 pvid untagged self
```

Then fix the unit and redeploy. This is the most likely failure and the cheapest
to recover from.

**Anything worse — roll back live from the TTY, no reboot.** This is the
preferred path, and it works even when the boot menu is invisible. At the TV:
Ctrl+Alt+F2, log in as `admin`, then

```bash
ls -1 /nix/var/nix/profiles/ | grep system- | sort -V | tail -3   # pick the previous one
sudo /nix/var/nix/profiles/system-23-link/bin/switch-to-configuration switch
```

substituting the generation number *below* the current one. That restores the
plain `50-enp13s0` networking immediately, without a reboot, without the boot
menu, and without needing zroot to be unlocked again.

**Boot-menu rollback** — reboot and select the previous generation at
systemd-boot, then unlock zroot. Only if the live path above is unavailable, and
note it needs the boot menu to be *visible*: with the Comet KVM dead, assume it
is not. Prefer the TTY.

**`ernst-initrd` does not resolve.** That alias uses `HostName ernst.skynet.lan`
— DNS-dependent, and DNS is exactly what a bad cutover can break. The address is
static, so use it directly:

```
ssh -tt -p 2222 -o HostKeyAlias=ernst-initrd -o ConnectTimeout=2 \
    root@10.0.50.10 systemd-tty-ask-password-agent --query
```

**What initrd SSH can and cannot do.** It unlocks zroot so the machine finishes
booting. It is **not** a stage-2 rescue shell: it cannot fix networkd, and it
cannot reach you at all if the port lost its untagged VLAN 50 or if VLAN 50
itself is broken.

**Last resort.** Physical access, previous generation from the boot menu.

## 5b. Expected after the cutover — not faults

Observed on the real cutover, 2026-08-20. Both look alarming and neither is a
problem with the bridge.

**ZeroTier goes `OFFLINE` and needs a restart.** The daemon does not survive its
host interface being replaced: `zerotier-cli info` reports `OFFLINE` even though
the node still holds its address and general internet works (`curl
https://cache.nixos.org/nix-cache-info` → 200). `ssh ernst-zt` times out, which
is alarming precisely because it is the backup channel. One restart fixes it:

```bash
systemctl restart zerotierone
sleep 20 && zerotier-cli info      # expect ONLINE
```

**Do this as the last verification step**, and confirm `ssh ernst-zt true`
succeeds — otherwise the second out-of-band path is silently gone.

**`ssh ernst.skynet.lan` fails, `ssh root@ernst.skynet.lan` works.** This is *not*
caused by the cutover. The `lgo` HM ssh config matches `Host ernst ernst.local
ernst.skynet.lan …` but sets no `User`, so it defaults to `lgo` — and **`lgo` does
not exist on ernst**, which only has `admin` (uid 1000) and `go` (uid 1001). Always
use `root@`. Worth confirming before a cutover so it is not mistaken for lockout
mid-deploy.

**`ernst.local` not resolving is also not a regression.** mDNS is link-local, and
miralda (LAN, VLAN 1) is on a different VLAN from ernst (Servers, VLAN 50), so it
depends on the UDM-Pro's mDNS repeater rather than on ernst. Control test:
`avahi-resolve -n biene.local` fails the same way from miralda, and biene was
never touched. If `.local` names matter, that is a UDM-Pro repeater question.

## 6. After the cutover

- Pin `br0`'s MAC in `machines/ernst/networking.nix` using the value captured in
  §1.4 — **required before M2b**, because a Linux bridge adopts the numerically
  lowest port MAC and the second port would otherwise be able to move the host's
  identity.
- M2b, M3 and M5 copy the commented worked examples in that file. Note there are
  two of them: a tap for microvm guests, a `vb-*` veth for nspawn containers.
  They are not interchangeable.
