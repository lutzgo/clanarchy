# Remote unlock: entering the zroot passphrase from miralda

When a headless clan machine (currently only `ernst`) boots, its stage-1
initrd blocks at a `systemd-ask-password` prompt for the zroot
passphrase.  With `clanarchy.initrdSsh.enable = true`, a minimal sshd
runs on port 2222 during that window so you can SSH in from miralda and
answer the prompt — no TV, no serial cable.

`zdata` is a keyfile-on-zroot dataset (see [`feat(ernst): auto-unlock
zdata via keyfile on zroot`](https://github.com/lutzgo/clanarchy/blob/main/machines/ernst/configuration.nix)),
so this procedure only ever needs to unlock zroot.

## One-time host-key generation on ernst

Boot ernst normally (TV / physical console) once, then generate an
ed25519 host key on `/persist` so it survives ZFS rollback:

```bash
ssh root@ernst.skynet.lan
umask 077
mkdir -p /persist/etc/secrets/initrd
ssh-keygen -t ed25519 -N "" -C "ernst initrd" \
  -f /persist/etc/secrets/initrd/ssh_host_ed25519_key
chmod 400 /persist/etc/secrets/initrd/ssh_host_ed25519_key
exit
```

Then deploy so NixOS reads the key at activation and packs it into
the initrd cpio (via `boot.initrd.secrets`):

```bash
clan machines update ernst
ssh root@ernst.skynet.lan systemctl reboot
```

This used to stage with `deploy-ernst boot` and reboot into it.
`clan machines update` activates as well as writing the boot entry, which is
harmless here — the initrd is only exercised on the next boot either way.

## Client-side setup (miralda only, one time)

The `lgo` HM ssh config already includes an `ernst-initrd` alias with
`HostKeyAlias ernst-initrd` — so the initrd host key lives in
`~/.ssh/known_hosts` under a separate name and doesn't clash with the
running-system entry for `ernst.skynet.lan`.

The first time you connect during boot, ssh will prompt to trust the
new key.  Accept it (once):

```
The authenticity of host 'ernst-initrd' can't be established.
ED25519 key fingerprint is SHA256:...
Are you sure you want to continue connecting (yes/no)?  yes
```

Compare the fingerprint to `ssh-keygen -lf /persist/etc/secrets/initrd/
ssh_host_ed25519_key` on ernst to verify.

## Boot-day operator flow

When ernst reboots (planned or unplanned):

The atlantic 10G NIC takes ~10 s to gain link at boot, so poll in a
loop rather than a single try.  Keep the ssh command on one line —
line-wrapping a poll loop across the shell will split `--query` off
into a bogus separate command:

```bash
while ! ssh -tt -o ConnectTimeout=2 ernst-initrd systemd-tty-ask-password-agent --query; do sleep 1; done
```

### The window opens in about a minute, and then stays open

**Measured on ernst, 2026-08-24.** An earlier revision of this section claimed
this machine spends tens of minutes in firmware POST. That was wrong, it was
inferred from a gap in the journal rather than measured, and it is corrected
here because it told the reader to expect exactly the wrong thing.

`systemd-analyze time`, from the boot in question:

```
Startup finished in 36.851s (firmware) + 8.041s (loader) + 1.230s (kernel)
                  + 1min 6.920s (initrd) + 12.408s (userspace) = 2min 5.451s
```

**Firmware POST is 37 seconds.** The whole boot is two minutes, and most of
the initrd minute is the passphrase prompt waiting for a human.

So the real timeline after `systemctl reboot`:

| elapsed | event |
|---|---|
| ~0:40 | shutdown finishes, machine resets |
| ~0:45 | firmware POST (37 s) + systemd-boot (8 s) |
| ~0:50 | kernel + initrd; sshd listens on 2222, `enp13s0` gains carrier |
| **~0:50 onwards** | **the window is open, and stays open** |
| when you answer | zroot imports, initrd hands off, stage-1 sshd is killed |

**The window does not time out.** It closes when *you* answer the prompt, so
there is no race to win — only a minute to wait.

**Therefore: if the loop has not connected within about two minutes, something
is actually wrong.** Do not sit through a long silence assuming POST, which is
what the previous version of this text invited.

### What the 2026-08-24 reboot actually did

The machine was power-cycled at the TV after ~35 minutes, on the belief that it
had not come back. It had. `zpool history` keeps the receipt, because a boot
that never reaches stage 2 leaves no journal but still imports the pool:

```
2026-08-24.13:11:06  zpool import ... zroot     → zdata 13:16:02   (normal boot)
2026-08-24.18:33:23  zpool import ... zroot     → zdata NEVER      ← the lost boot
2026-08-24.19:09:20  zpool import ... zroot     → zdata 19:10:24   (after power-cycle)
```

Shutdown completed at 18:32:33 and stage 1 imported zroot at **18:33:23** —
fifty seconds later. ernst then sat at the passphrase prompt, reachable, for
thirty-five minutes.

**`zpool history` is the tool for this in general**: an interrupted boot leaves
no journal, but the pool import is timestamped, so a zroot import with no
matching zdata import is a boot that stopped in stage 1.

### Reading the errors correctly

- **`Connection timed out`** is what a **running** ernst gives on 2222 — the
  host firewall drops the packet (verified against the live machine). So this
  is the expected error for the first ~40 seconds, while the old system is
  still shutting down.
- **`Connection refused`** would mean the address answered with a RST, i.e.
  something is up but nothing is listening on 2222. If that persists past the
  first minute it is worth investigating rather than waiting out.
- **`No route to host`** means the machine is down or mid-POST. Normal, briefly.

**Remote unlock has still never been completed on ernst.** The channel has been
observed to come up correctly — sshd listening, interface configured — but no
reboot has yet been unlocked through it, and the 2026-08-24 attempt failed from
the client side while stage-1 sshd sat there logging nothing.

### Diagnosing the next attempt — both ends at once

The 2026-08-24 attempt could not be diagnosed afterwards because **neither end
recorded anything usable**: stage-1 sshd logged two lines for the whole boot
("Server listening", "Received signal 15"), and the client's error was
remembered rather than captured. Both halves are now instrumented.

**Server side — opt in for one boot, then turn it off.** Set

```nix
clanarchy.initrdSsh.debug = true;   # machines/ernst/configuration.nix
```

deploy, and reboot. That adds `LogLevel VERBOSE` to the initrd sshd — so any
accepted TCP connection logs `Connection from <ip> port <n>` *before*
authentication — plus a `clanarchy-initrd-netdebug` oneshot that dumps
`ip -br address`, `ip route` and `ip neigh` into the stage-1 journal. Read it
after the boot:

```bash
ssh root@ernst.skynet.lan 'journalctl -b 0 | grep -iE "sshd|clanarchy-initrd-netdebug"'
```

Then set it back to `false`. It is scaffolding: off by default because
scaffolding left up stops being read, and because VERBOSE logs every
connection attempt to a port that exists for recovery. With `debug = false`
the option is a true no-op — the built system's derivation hash is unchanged
by its presence.

**Client side** — run the poll loop verbose and *keep the output*:

```bash
while ! ssh -vvv -tt -o ConnectTimeout=2 ernst-initrd systemd-tty-ask-password-agent --query; do sleep 1; done 2>&1 | tee /tmp/unlock.log
```

`-vvv` distinguishes the cases that all look like "it didn't work":

| what `-vvv` shows | meaning |
|---|---|
| stops at `Connecting to ... port 2222` then times out | packets are not arriving — addressing, VLAN or ARP |
| `Connection refused` | something answered with a RST; the address is live but nothing is on 2222 |
| gets to `Remote protocol version` then fails | the network is fine; the problem is the host key or authentication |
| `Host key verification failed` | expected once; accept the initrd key, see above |

**Read the two together.** `Connection from` on the server plus a client-side
auth failure is a completely different bug from silence on both ends, and
until 2026-08-24 there was no way to tell them apart.

### One known asymmetry worth checking first

**ernst answers on a different MAC in stage 1 than in stage 2**, for the same
IP address. Stage 2 holds `10.0.50.10` on `br0`, whose MAC is pinned to
`b2:8b:e1:f2:1e:7c` in `machines/ernst/networking.nix`. Stage 1 has no bridge
and speaks from the NIC's hardware address, `a0:ad:9f:1c:9d:74` — visible in
the journal as the link-local `fe80::a2ad:9fff:fe1c:9d74`.

Anything upstream holding a neighbour entry for `10.0.50.10` therefore has the
*wrong* link-layer address during stage 1 until it revalidates. This is a
candidate explanation and **not** a confirmed cause — `ip neigh` from the
netdebug unit, plus whether the client's `-vvv` output ever leaves
`Connecting to`, is what will confirm or kill it.

- `-tt` (double `t`) forces ssh to allocate a pty even when stdin
  isn't one (as inside a `while` loop).
  `systemd-tty-ask-password-agent` reads from `/dev/tty`; no pty →
  silent hang.
- On success it prints `Password: ` — type the zroot passphrase and
  press Enter; the command exits and ernst continues booting.
- Stage-1 sshd is killed automatically when the initrd hands off to
  stage 2.

Once ernst is up, verify:

```bash
ssh root@ernst.skynet.lan zpool status         # zroot + zdata both ONLINE
```

If you get "REMOTE HOST IDENTIFICATION HAS CHANGED" for `ernst-initrd`,
someone regenerated the initrd host key — remove the old entry from
`~/.ssh/known_hosts` and re-verify the fingerprint.

### When the alias does not resolve

The `ernst-initrd` alias uses `HostName ernst.skynet.lan`, so it depends
on DNS — and DNS is one of the things a bad network change can break,
which is exactly when you need this channel most.  ernst's stage-1
address is static, so fall back to the IP literal:

```bash
ssh -tt -p 2222 -o HostKeyAlias=ernst-initrd -o ConnectTimeout=2 root@10.0.50.10 systemd-tty-ask-password-agent --query
```

`HostKeyAlias` is what keeps this pointing at the same known-hosts entry
as the alias, instead of prompting for a new one.

### The switch port must keep VLAN 50 untagged

Stage 1 brings up the **raw** `enp13s0`, not the `br0` bridge that
stage 2 uses — see the file header in `machines/ernst/networking.nix`.
The raw NIC speaks untagged, so ernst's SFP+ port on the UDM-Pro must
keep `Servers (50)` as its **native/untagged** VLAN.  Converting that
port to a pure tagged trunk kills this unlock channel and makes every
future boot a trip to the Comet KVM.  See
[the VLAN bridge cutover runbook](../runbooks/ernst-vlan-bridge-cutover.md).

## Rollback / disabling

Set `clanarchy.initrdSsh.enable = false;` in `machines/ernst/
networking.nix` and redeploy.  Next boot returns to console-only
passphrase entry.
