# Authelia second factors

Enrolling a second factor on [`auth.goclan.org`](https://auth.goclan.org) — a TOTP app, a YubiKey, or a phone fingerprint. All three go through the same gate, and that gate is where every attempt so far has gone wrong.

Config: [`machines/ernst/containers/authelia.nix`](https://github.com/lutzgo/clanarchy/blob/main/machines/ernst/containers/authelia.nix). Its header carries the full reasoning; this page is the procedure.

## The gate: a one-time code from a file

Authelia 4.39 will not let an already-authenticated session register a 2FA device. It first demands a **session elevation**: an eight-character one-time code, sent through the notifier. Our notifier is a **file on ernst**, so "check your email" means reading `/srv/state/authelia/notification.txt`.

Start the watcher on ernst *before* clicking anything in the browser:

```bash
ssh root@10.0.50.10
authelia-code --wait
```

It blocks until a new notification lands, then prints the code with its age.

!!! warning "Do not click ADD twice"
    Code generation is rate-limited in stacked buckets: 35 s, then 545 s, then **1745 s (29 minutes)**. The UI reports this as "Failed to generate the One-Time Code. Please try again later", which reads like a broken notifier and is not. While limited, no new notification is written, so the file keeps showing the previous expired code — which reads like a broken helper and is also not.

    ```bash
    nixos-container run authelia -- journalctl -u authelia-main | grep "Rate Limit"
    ```

    The limiter is in-memory. `machinectl restart authelia` clears it instantly, at the cost of every active session.

Codes expire in **5 minutes**. Both "the code didn't match any recorded code challenges" and "the code challenge has expired" mean the same thing: what you typed is not the code that is currently valid. Re-read the file — not your scrollback.

## Fingerprint (Android + Google Password Manager)

No deploy is needed. `authelia.nix` sets no `webauthn:` block, so Authelia runs upstream defaults, and those are already what a Google Password Manager passkey requires:

| Default | Why it matters |
|---|---|
| `selection_criteria.discoverability: preferred` | GPM only stores discoverable credentials |
| `selection_criteria.user_verification: preferred` | this is what triggers the fingerprint prompt |
| `filtering.prohibit_backup_eligibility: false` | GPM passkeys are synced, so `true` would **reject** them |
| `metadata.enabled: false` | no MDS trust check to trip over |

`auth` is in `wanExposed` with a public A record and the Let's Encrypt wildcard, so this works on mobile data as well as on the LAN.

Use **Chrome**. Firefox on Android will not route to Google Password Manager.

1. `authelia-code --wait` running on ernst.
2. On the phone: log in to `https://auth.goclan.org` with password + current TOTP.
3. Settings → Two-Factor Authentication → **Security Key / WebAuthn** → ADD.
4. Type the code ernst just printed.
5. Chrome's passkey sheet → **this device** → touch the sensor. Name it (`fp5`).

### Two things to know afterwards

**It is not bound to the phone.** The credential lives in Google Password Manager and syncs to the Google account; any device signed into that account can use it behind its own screen lock. The fingerprint unlocks GPM — it does not tie the key to FP5 hardware. A device-bound credential is a YubiKey, not this.

**Never set `filtering.prohibit_backup_eligibility = true`**, and do not enable `metadata` validation without checking, for the same reason: both reject synced passkeys, and this credential is one.

## TOTP

Identical, except step 3 is **One-Time Password → ADD** and step 5 is scanning the QR.

## Login still defaults to TOTP

`default_2fa_method = "totp"` in `authelia.nix`, so a newly enrolled account lands on the code box. Click **METHODS** and pick Security Key. Authelia remembers the per-user preference after that, so this bites once.

The inverse trap also exists and looks worse: the 2FA page can land on Security Key with nothing registered, showing only "Register device" and no code box. That is not a broken login — click METHODS.

Three optional one-line changes in `authelia.nix`, none currently made:

- `default_2fa_method = "webauthn"` — fingerprint first, fleet-wide
- `webauthn.enable_passkey_login = true` — fingerprint *instead of* the password, not after it
- `webauthn.display_name` — cosmetic; it is what GPM shows in its save prompt instead of "Authelia"
