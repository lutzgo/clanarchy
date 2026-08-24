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

### START THE LOOP AND LEAVE IT.  READ THIS BEFORE DECIDING IT IS BROKEN

**Every failure the loop prints until the unlock window opens is expected**,
and on this machine that is a long time.  `Connection refused`,
`No route to host` and `Connection timed out` all mean "ernst is not up yet",
not "remote unlock is broken".  The loop exists precisely to absorb them.

**ernst's POST is measured in tens of minutes, not seconds.**  From the
2026-08-24 reboot, out of the journal:

| time | event |
|---|---|
| 18:32:33 | shutdown finishes, machine powers off |
| **19:09:16** | kernel starts — **36 minutes of firmware POST** |
| 19:09:19 | `sshd: Server listening on 0.0.0.0 port 2222` |
| 19:09:25 | `enp13s0: Gained carrier` — **the window opens here** |
| 19:10:21 | zroot imported, `sshd: Received signal 15` — window closes |

That reboot was unlocked at the TV, and the reason was not a fault in any of
this: sshd came up correctly, the interface was configured correctly, and the
window was open for 56 seconds.  It opened **36 minutes** after the reboot
command, by which time the operator had reasonably concluded the channel was
dead and walked to the television.

So the failure mode to guard against is human, and the guard is: start the
loop, put the terminal somewhere visible, and do not interpret errors during
POST as a verdict.  The window closes when *you* answer the prompt, so it is
never too short — it is only ever late.

**The 36 minutes is itself worth attention** and is not something this guide
can fix: it is firmware, before Linux runs, with an HBA enumerating eight SAS
devices.  `zpool status` is clean, so it is not a failing pool member. If it
grows, suspect the HBA or a marginal device (see
`docs/incidents/ernst-slot12-drop-2026-08-11.md`) before suspecting this
setup.

**How to know the window is open rather than guessing:** the loop succeeding
*is* the signal — it prints `Password: `. Until then there is nothing to see.
If you would rather not watch a terminal, ping the address first and start the
loop once anything answers:

```bash
while ! ping -c1 -W1 10.0.50.10 >/dev/null 2>&1; do sleep 5; done; echo "ernst is answering — starting unlock loop"
```

Note `ping` answers in stage 1 *and* in a fully booted system, so it tells you
ernst is reachable, not that it is waiting for a passphrase.

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
