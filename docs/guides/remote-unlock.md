# Remote unlock: entering the zroot passphrase from miralda

When a headless clan machine (currently only `ernst`) boots, its stage-1
initrd blocks at a `systemd-ask-password` prompt for the zroot
passphrase.  With `clanarchy.initrdSsh.enable = true`, a minimal sshd
runs on port 2222 during that window so you can SSH in from miralda and
answer the prompt — no TV, no serial cable.

`zdata` is a keyfile-on-zroot dataset (see [`feat(ernst): auto-unlock
zdata via keyfile on zroot`](../../machines/ernst/configuration.nix)),
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
deploy-ernst boot
ssh root@ernst.skynet.lan systemctl reboot
```

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

```bash
# Wait a few seconds for the NIC to come up and sshd to start.
# Then answer the pending zroot passphrase prompt in one command:
ssh ernst-initrd systemd-tty-ask-password-agent --query
# Passphrase for zroot:
#   <type it>
# (Ctrl-D to exit.  Stage-1 sshd is killed automatically when the
#  initrd hands off to stage 2.)

# Once ernst is up, verify:
ssh root@ernst.skynet.lan zpool status         # zroot + zdata both ONLINE
```

If you get "REMOTE HOST IDENTIFICATION HAS CHANGED" for `ernst-initrd`,
someone regenerated the initrd host key — remove the old entry from
`~/.ssh/known_hosts` and re-verify the fingerprint.

## Rollback / disabling

Set `clanarchy.initrdSsh.enable = false;` in `machines/ernst/
networking.nix` and redeploy.  Next boot returns to console-only
passphrase entry.
