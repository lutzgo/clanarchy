# ernst — bringing up the VPN microvm

Deploying M3: `wg-qbittorrent`, a microvm on ernst running qBittorrent behind an
IVPN WireGuard tunnel with a guest-side nftables killswitch. Code is
[PR #83](https://github.com/lutzgo/clanarchy/pull/83); this runbook is the other
half.

Read it end to end before starting. Nothing here is a one-way door — unlike
[enabling impermanence](ernst-enable-impermanence.md), every step is reversible
by deploying `main` again — but two steps are ordering-sensitive and one of them
costs a rebuild if you get it wrong.

**Time:** about an hour, most of it waiting for a build.

## What you need in front of you

- **The YubiKey**, plugged in. Not for the vars generation — that only encrypts,
  to public recipients — but for `ssh root@ernst` and for reaching the guest
  afterwards. The guest authorises exactly one key: `machines/miralda/yubikey_ed25519.pub`.
- **IVPN's WireGuard config**, from the Client Area. Generate the key pair
  locally and register only the public half:

  ```bash
  wg genkey | tee >(wg pubkey >&2)   # private → stdout, public → stderr
  ```

  Six of the seven prompts come straight out of the resulting config file.
- **UDM-Pro access**, for one DHCP reservation and one firewall rule.
- **The branch checked out and the tree clean.** `clan vars generate` commits
  into whatever branch you are on:

  ```bash
  git switch feat/ernst-vpn-microvm && git status -sb
  ```

## Order, and why it is not negotiable

1. **Vars before deploy.** clan-core cannot know a sops secret's path until the
   secret exists — until then `files.<n>.path` evaluates to the literal
   `/no-such-path`, and that string is baked into the staging unit. Deploy first
   and you get a system whose `microvm-secrets-wg-qbittorrent.service` can never
   succeed. It fails closed (the VM never starts) but the fix is another build,
   not a restart.
2. **DHCP reservation before deploy.** Not fatal to get wrong — the guest takes a
   pool lease and works — but then every address in this runbook is wrong and
   the firewall rule points at nothing.
3. **Firewall rule before you try to reach it.** Until it exists the guest is
   only reachable at L2, from within VLAN 90. Step 4 does exactly that, on
   purpose, so that "unreachable" can be attributed before it is diagnosed.

---

## 1. Generate the vars

```bash
clan vars generate ernst
```

Only the new `wg-qbittorrent` generator should prompt; the existing ernst
generators are already satisfied and are skipped. **clan asks in alphabetical
order of prompt name**, not the order they are declared:

| Prompt | From IVPN's config | Notes |
|---|---|---|
| `address` | `[Interface] Address` | keep the `/32`. IVPN assigns from `172.16.0.0/12` |
| `dns` | `[Interface] DNS` | `172.16.0.1`, or `10.0.254.2` / `10.0.254.3` for AntiTracker |
| `endpoint` | `[Peer] Endpoint` | **IP literal**, `IP:PORT`. Rejected otherwise — see below |
| `mtu` | `[Interface] MTU` | **`1412` for IVPN.** Empty = wg-quick's 1420, which is too high here |
| `peer-public-key` | `[Peer] PublicKey` | the server's |
| `private-key` | `[Interface] PrivateKey` | yours; the one whose public half you registered |
| `webui-password` | — | qBittorrent WebUI, user `admin` |

**The endpoint must be an IP address.** The generator rejects a hostname on
purpose: wg-quick resolves the endpoint using the guest's resolver, which is
in-tunnel, which does not exist until the handshake that needs the endpoint. If
the Client Area gave you `de1.wg.ivpn.net`, resolve it yourself:

```bash
dig +short de1.wg.ivpn.net
```

That pins the tunnel to one specific server. If IVPN later retires or renumbers
it, re-run this step and restart the two units (see [Rotating the
tunnel](#rotating-the-tunnel-later)).

**There is no preshared key and no username/password.** IVPN authenticates the
registered key; the generator has no prompt for either, and that is correct
rather than an omission.

### Check

```bash
git log --oneline -1        # expect: vars: update via generator wg-qbittorrent
git status -sb              # expect: clean — clan commits for you
ls vars/per-machine/ernst/wg-qbittorrent/
# expect: endpoint-ip  endpoint-port  ssh-host-key  ssh-host-key.pub
#         webui-password-pbkdf2  wg0.conf
```

Six entries, each a directory containing an encrypted `secret` — except
`ssh-host-key.pub`, which is public by design so it can go in `known_hosts`.

Nothing is decrypted into the working tree, and nothing needs `git add`: clan
committed it. If that commit is missing, check `git config commit.gpgsign` —
clan's commit is unsigned and will fail if signing is forced on.

---

## 2. DHCP reservation on the UDM-Pro

Services network (VLAN 90), MAC `02:00:00:90:00:03` → **`10.0.90.11`**.

**It must be inside the DHCP pool** (`10.0.90.6`–`.254`). UniFi accepts an
address from the `.2`–`.5` range the cutover runbook set aside and then silently
hands out an ordinary pool lease instead — that range is for addresses hard-coded
on the client, not for reservations. This cost M2b a round of debugging; do not
repeat it.

---

## 3. Deploy

From the branch, per the pre-merge check in
[accepting-pull-requests.md](../guides/accepting-pull-requests.md):

```bash
clan machines update ernst
```

This is the first build of a second NixOS closure (the guest), so expect it to
take noticeably longer than a normal ernst deploy.

The deploy activates immediately — there is no stage-only mode. It does not
touch the bootloader, disko or impermanence, so the risk of losing the machine
is low; but ernst's only management address rides `br0`, and this deploy adds a
port to that bridge. Have the [Comet KVM](../guides/remote-unlock.md) reachable
before you run it, as usual.

---

## 4. Verify at L2, before the firewall is in the way

The guest is on VLAN 90 and ernst holds no address there, so everything from
your desk still has to cross the UDM-Pro — and the rule for that does not exist
yet. Rather than guess, borrow M2b's probe: a veth on `br0` tagged into VLAN 90,
in its own netns, is *inside* the same broadcast domain as the guest. Traffic
between them is switched, never routed, so the firewall is not involved at all.

First, host-side, no network needed:

```bash
ssh root@10.0.50.10
systemctl status microvm@wg-qbittorrent            # active (running)
systemctl status microvm-secrets-wg-qbittorrent    # active (exited)
bridge vlan show dev tap-vpn                       # 90 PVID Egress Untagged
ip -br link show master br0                        # enp13s0 + vb-jellyfin + tap-vpn
journalctl -u microvm@wg-qbittorrent -n 40         # the guest's console log
```

That last one is the guest's serial console: qemu wires it to the service's
stdout, so a full boot log lands in ernst's journal. It is one-way — there is no
console to type into, which is why the guest runs sshd.

Then, from inside VLAN 90:

**Two differences from M2b's version of this probe, both learned the hard way
on the first run.** ernst has no `dhcpcd` — `roles/server.nix` zeroes
`environment.defaultPackages` — so the probe takes a static address from the
`.2`–`.5` range the cutover runbook set aside for exactly that. And unlike
Jellyfin, **this guest firewalls by source address**, so almost everything the
probe tries is *supposed* to fail. Read the ARP table, not the ping.

```bash
ip netns add p90
ip link add vb-p90 type veth peer name eth0p
ip link set eth0p netns p90
ip link set vb-p90 master br0 up
bridge vlan add dev vb-p90 vid 90 pvid untagged
ip netns exec p90 ip link set eth0p address 02:00:00:90:00:99
ip netns exec p90 ip addr add 10.0.90.5/24 dev eth0p
ip netns exec p90 ip link set eth0p up
sleep 2

ip netns exec p90 ping -c2 -W2 10.0.90.11        # expect: 100% loss — correct
ip netns exec p90 ip neigh                       # THIS is the check

ip link del vb-p90; ip netns del p90             # leaves nothing behind
```

The line that matters:

```
10.0.90.11 dev eth0p lladdr 02:00:00:90:00:03 REACHABLE
```

That single line proves three things at once: the DHCP reservation took (the
guest holds `.11`), the guest is alive and answering at L2, and the reservation
is bound to the right MAC. ARP is answered because `arp` is a separate netfilter
family that `table inet killswitch` does not touch.

**Everything else failing is the correct result.** `10.0.90.5` is not in
`mgmt_nets`, so the guest's input chain drops the ICMP, the WebUI and SSH — which
is exactly what should happen to a stranger on the Services VLAN. A probe that
*could* reach port 8080 from here would mean the firewall was wrong.

To watch the tunnel itself, sniff the host side of the tap — no login required:

```bash
timeout 20 tcpdump -ni tap-vpn -c 8 'udp port <endpoint-port>'
```

A healthy tunnel shows a 148-byte handshake initiation out, a 92-byte response
back, a 32-byte keepalive, and then transport traffic in both directions. If you
see only outbound packets, the handshake is failing — check the keys and the
endpoint.

If the ARP entry is absent, stay on ernst: the problem is in
`journalctl -u microvm@wg-qbittorrent`, not in the firewall.

---

## 5. The firewall rule

One **permanent** rule — architecture invariant #4 makes the qBittorrent WebUI a
deliberate, permanent bypass of the "everything behind Traefik" rule. It is in
the ledger as a `—` row so no later milestone tries to retire it.

- **Source:** the zone your management networks are in. LAN (1) at minimum;
  Servers (50) too if you want to reach the guest from ernst itself.
- **Destination:** Services, `10.0.90.11`, `tcp 8080` and `tcp 22`.
- **TICK `Auto Allow Return Traffic`.**

That checkbox is the one that costs an afternoon. Without it the SYN is
forwarded and the SYN-ACK is dropped, which presents exactly as a dead service
and logs nothing. The tell is a rule with a **non-zero hit count** and a
connection that still hangs. Connection State `All` is fine and is *not* a
substitute — see [M2b's
table](../roadmap.md#the-udm-pro-half-cost-more-than-the-nix-half).

**Whether Servers (50) → Services needs its own rule is not established.** LAN
and Servers are both in the `Internal` zone, so a rule whose source is the zone
covers both; a rule whose source is the LAN *network* does not. Jellyfin has only
ever been reached from LAN and IoT, so this has never been tested. Set the source
to cover both, or find out with the probe above re-tagged into VLAN 50 rather
than assuming.

---

## 6. Verify for real

From miralda, with the YubiKey in.

```bash
ssh-keygen -F 10.0.90.11    # nothing yet; the host key is the one clan generated
ssh root@10.0.90.11
```

The host key fingerprint should match `vars/per-machine/ernst/wg-qbittorrent/ssh-host-key.pub/value`
— it is public precisely so you can check it instead of clicking through.

### The tunnel is up and traffic actually uses it

```bash
# In the guest:
wg show                                    # a recent handshake, non-zero transfer
curl -s https://ifconfig.co                # IVPN's exit address
getent hosts example.com                   # resolves — via the in-tunnel DNS

# From miralda, for comparison:
curl -s https://ifconfig.co                # your WAN address — MUST differ
```

If `wg show` is healthy but nothing resolves, the in-tunnel DNS is being routed
the wrong way. Check `resolvectl status` / `/etc/resolv.conf` in the guest, and
re-read the `routingPolicyRules` comment in the module — the management-network
carve-out is deliberately per-subnet rather than a `10.0.0.0/16` supernet
precisely because IVPN's AntiTracker resolvers live at `10.0.254.2`/`.3`.

### The killswitch actually holds

Stop the tunnel and watch the host-side tap. This is the test the milestone
exists for.

```bash
# On ernst, in one window:
tcpdump -ni tap-vpn 'not arp and not (udp port 67 or udp port 68)'

# In the guest, in another:
systemctl stop wg-quick-wg0
curl -m5 https://ifconfig.co     # must FAIL — not fall back to the WAN
getent hosts example.com         # must FAIL — no name leak either
```

tcpdump must show **nothing but** traffic to the IVPN endpoint (and it will stop
even that once wg0 is down). Any packet to any other address is a leak and the
milestone has failed. A DNS query leaving here would be the classic failure: the
packets are held but the names escape.

```bash
systemctl start wg-quick-wg0     # and re-check `wg show`
```

### The hardlink chain — the reason M4 can work

This is the part worth being fussy about, because a false pass here is invisible
until M4 has silently filled the array twice over.

Create the file **as qBittorrent does** — its uid, its umask — not as root:

```bash
# In the guest:
runuser -u qbittorrent -- sh -c 'umask 0002; : > /srv/media/torrents/complete/probe'
```

Then, on ernst, link it **as a non-root process in group media** — root would
bypass the very check we are testing:

```bash
ls -l /srv/media/torrents/complete/probe
# expect:  -rw-rw-r-- 1 3001 media   ← 3001 because the host has no name for it

setpriv --reuid 3002 --regid 3000 --clear-groups --groups 3000 \
  ln /srv/media/torrents/complete/probe /srv/media/library/movies/probe

stat -c '%i %h %U:%G %a' /srv/media/torrents/complete/probe \
                         /srv/media/library/movies/probe
# expect: identical inode, link count 2, on both lines
```

Uid 3002 is a stand-in for M4's arr: a different uid, in group media, exactly as
the arr will be.

**Now prove the control**, so you know the test can fail:

```bash
rm /srv/media/library/movies/probe
chmod 0644 /srv/media/torrents/complete/probe
setpriv --reuid 3002 --regid 3000 --clear-groups --groups 3000 \
  ln /srv/media/torrents/complete/probe /srv/media/library/movies/probe
# expect: "Operation not permitted"
```

That is `fs.protected_hardlinks` refusing a link to a file the caller neither
owns nor can write. It is why `UMask=0002` is on the qBittorrent unit, and why a
tidy-minded future edit removing it would break M4 without breaking anything
visible at the time.

```bash
rm -f /srv/media/torrents/complete/probe /srv/media/library/movies/probe
```

### The WebUI

```bash
xdg-open http://10.0.90.11:8080/     # user: admin, password: what you set in step 1
```

In the UI, confirm **Tools → Preferences → Advanced → Network Interface** shows
`wg0`. That binding is the second line of defence; nftables is the guarantee.

---

## 7. The reboot

Not optional. Architecture invariant #7 names M3 as one of three milestones
carrying state that has never met a real rollback — ernst only became genuinely
impermanent on 2026-08-18.

```bash
systemctl reboot     # then wait for the zroot passphrase prompt on the TV/KVM
```

Afterwards:

| Check | Expect |
|---|---|
| `systemctl status clanarchy-impermanence-check` | success — both `@blank` snapshots present |
| `ls -l /var/lib/microvms/wg-qbittorrent/` | `current` + `toplevel` symlinks, rebuilt from the store |
| `systemctl status microvm@wg-qbittorrent` | running |
| `bridge vlan show dev tap-vpn` | `90 PVID Egress Untagged` — created from config this time |
| guest `ls /var/lib/qBittorrent/qBittorrent/` | the session survived, on zdata |
| guest `wg show` | handshake re-established without intervention |

`/var/lib/microvms` is deliberately **not** in `/persist`:
`install-microvm-wg-qbittorrent.service` rewrites it from the store on every
boot, so persisting it would only freeze a stale `current` symlink across a
redeploy. The reboot is what proves that claim.

---

## 8. Merge

```bash
gh pr merge 83 --squash --delete-branch
git switch main && git fetch origin && git merge --ff-only origin/main
```

Then update the roadmap status row from **code landed — deploy pending** to
**done — deployed \<date\>**, and write up anything this runbook got wrong. M2b's
write-up is the model: what was measured, not what was expected.

---

## Expected — not faults

- **A duplicate-tmpfiles warning for `/srv/media/torrents`.** microvm.nix emits
  its own rule for every share source in `10-microvm.conf`; ours is in
  `00-nixos.conf`, sorts first and wins. The warning is systemd noting it
  ignored the second.
- **`systemd-networkd-wait-online` failing inside the guest** if DHCP is slow.
  The timeout is capped at 20 s on purpose; `network-online.target` is reached
  regardless and the services start. One failed unit, everything else running,
  is the diagnosable shape.
- **qBittorrent reporting no incoming connections.** IVPN removed port
  forwarding in September 2023. Outgoing peer connections work; incoming ones
  cannot. The guest's inbound rule for the torrent port is inert by design.
- **`microvm-virtiofsd@` restarting once at boot.** `Restart=always` with a 5 s
  delay; it settles.

## When it does not work

| Symptom | Look at |
|---|---|
| `microvm@` will not start | `systemctl status microvm-secrets-wg-qbittorrent` — if its script references `/no-such-path`, the vars were generated after the build. Re-deploy. |
| Guest boots, tunnel never comes up | `nft list set inet killswitch vpn_endpoint` in the guest. Empty means `vpn-killswitch-endpoint.service` did not run — the handshake is blocked, fail-closed, by design. |
| Tunnel up, nothing resolves | The DNS server is being routed out `eth0` and dropped. See the AntiTracker note in step 6. |
| Handshake fine, transfers stall | MTU. IVPN wants 1412; if you left the prompt empty you have 1420. Re-run step 1. |
| Reachable from ernst, not from miralda | `Auto Allow Return Traffic` on the ZBF rule, and the zone-vs-network source question in step 5. |
| Everything unreachable, guest healthy at L2 | The rule is missing or points at the wrong address. Re-check the DHCP reservation actually took (step 2). |

## Rotating the tunnel later

New IVPN key, or a server that moved:

```bash
clan vars generate ernst      # re-prompts only what changed
clan machines update ernst
```

If only the secret's *contents* changed and no path did, nix sees no difference
and the staging unit will not re-run on its own:

```bash
ssh root@10.0.50.10 systemctl restart \
  microvm-secrets-wg-qbittorrent microvm@wg-qbittorrent
```

## Backing out

Nothing here is one-way. Deploy `main` and the guest, its tap and its units all
disappear; `/srv/state/qbittorrent` and anything downloaded stay on zdata,
because they were never on the rolled-back pool to begin with.

```bash
git switch main && clan machines update ernst
```
