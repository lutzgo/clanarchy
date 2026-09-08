# App-API ingress: the services apps talk to

Five hostnames on ernst are reachable from the public internet **without
Authelia in front of them**. This page is why, what compensates, and how to
verify it works.

The mechanism lives in `machines/ernst/containers/ingress-policy.nix`. Read
that file before changing a middleware; this page is the operator's half.

## The one rule

> **Can every client of this hostname render a login page and follow a 302?**

That is the whole test. It is **not** "admin versus household" — Jellyseerr is
a household service and *is* behind Authelia; Audiobookshelf is a household
service and is *not*.

| Answer | Category | What authenticates |
|---|---|---|
| Yes | `protectedHosts` / `householdHosts` | Authelia forward-auth, 2FA, per-user regulation |
| No | `appApiHosts` | the application's own accounts |

Forward-auth is a **redirect protocol**. An app holding a bearer token has no
browser to render the portal, so it reports an opaque network error and the
user concludes the server is broken. If someone reports *"works in the browser,
fails in the app"*, check this first — it is almost always the cause.

### The exempt five

| Host | Clients that force the exemption |
|---|---|
| `jellyfin` | TV apps, Android/iOS, Chromecast senders, DLNA |
| `audiobookshelf` | the ABS mobile and TV apps (bearer token) |
| `komga` | Komelia, Mihon's Komga extension, OPDS v1/v2 readers |
| `navidrome` | every Subsonic client — the credential is a **query parameter**, by protocol definition |
| `cwa` | OPDS (basic auth), Kobo (device token **in the URL path**), KOReader `/kosync` (RFC 7617) |

A Kobo e-reader is the clearest case: there is no browser on the device at all.

## It is enforced, not documented

`withWan` in `traefik.nix` throws at **evaluation** — `nix flake check` and CI
catch it, and it cannot be demoted to a warning. Seven checks; four are new:

| | Catches |
|---|---|
| (a) | a router that omits `entryPoints` (Traefik binds those to *every* entrypoint — measured) |
| (b) | `wanExposed` naming a router that does not exist |
| (c) | a router adding `wan` by hand |
| (d) | a rule whose `Host()` literal cannot be parsed |
| (e) | an `appApiHosts` router carrying `authelia` — **breaks every native client** |
| (f) | a routed hostname in none of the policy lists |
| (g) | a protected router *missing* `authelia` — **the fail-open direction** |

(g) is the dangerous one. Authelia's `default_policy = "deny"` does **not**
save you: the middleware is what consults Authelia at all, so without it the
request goes straight to the backend.

All three new branches were verified to fire by deliberately breaking the
config.

## What compensates for the missing forward-auth

Stated plainly, because these vhosts are genuinely less protected than the
rest:

1. **The service's own accounts.** Now the entire boundary. They must be
   strong — nothing in the repo can enforce this.
2. **`wan-ratelimit` / `wan-inflight`** — 50/s, sized for browsing.
3. **`wan-login-ratelimit`** — 1 per 10s, burst 5, on login paths only, via
   higher-priority `<name>-wan-login` routers. Browsing and authentication have
   opposite shapes; 50/s is 4.3 million password guesses a day.
4. **CrowdSec `clanarchy/app-api-auth-bf`** — 10× 401/403 in 5 minutes → ban at
   the packet layer.
5. **The services' own limiters** — Navidrome ships 5 attempts / 2 min;
   Audiobookshelf has failed-login backoff. **Komga has neither.**

### Residual exposure — the honest list

- **No second factor on any of the five.** Authelia's 2FA and per-user
  regulation do not apply, because Authelia is never consulted.
- **The login rate limiter does not cover Subsonic or Komga's HTTP Basic.**
  Those carry the credential on *every* request, so there is no distinct login
  path. CrowdSec's status-based scenario is the only control there.
- **Komga has no separate admin surface.** Administration is a role on an
  ordinary account at the same origin — no port or path to split off. The
  policy of keeping admin surfaces off public vhosts cannot be honoured here.
- **No geo-restriction.** Asked for, deliberately not implemented: Traefik has
  no native geo filter, and the only route is a Yaegi plugin fetched unpinned
  from `plugins.traefik.io` at Traefik's startup. `traefik.nix` rejects that
  pattern on stronger grounds than the thing it would defend against.
- **First-run windows.** Audiobookshelf's setup wizard hands root to whoever
  loads it first. Create admin accounts **immediately** after first deploy.
- Requests to the bare public IP still complete TLS and get
  `404 CN=TRAEFIK DEFAULT CERT` — existence disclosure, inherited from M18.

## The UDM-Pro checklist

None of this is declarative and Claude cannot apply it.

**Nothing to change for the reachability fix.** The WAN `:443` → `10.0.90.12:8443`
DNAT already exists and is proven working. Do **not** open `:80` — ACME is
DNS-01 and HTTP-01 never runs.

1. **DHCP reservation for CWA.** MAC `02:00:00:90:00:0d` → `10.0.90.21`. This
   is M16's old cloudflared pair, reused. The MAC is unchanged, so if that
   reservation was never deleted it is already correct. **Never** create a
   second reservation for `10.0.90.21` on a different MAC.
2. **Do not add an IPv6 forward.** There is no GUA anywhere on this path and no
   AAAA in the zone. A v6 path would bypass the DNAT and therefore the `wan`
   entrypoint entirely, and the CrowdSec bouncer has `nftables.ipv6.enabled =
   false` — the routes would be reachable *and* unbannable at once.
3. **Verify the reservation is inside the DHCP pool** (`10.0.90.6–.254`).
   UniFi accepts an address from the `.2–.5` range and then silently hands out
   an ordinary pool lease instead.

### `on_boot.d`

**No new entries.** Nothing added here needs one — the DNAT and the DHCP
reservation are both UniFi-managed configuration that survives firmware
upgrades. Only hand-written `iptables`/`ip` commands need `on_boot.d`, and this
change adds none. Recorded so nobody adds one defensively.

## Public DNS

A records only, **DNS-only (grey cloud)**, all → `78.94.91.74`:

```
audiobookshelf   auth   cwa   jellyfin   jellyseerr   komga   navidrome
```

**Never add AAAA.** Nothing on the path has a global IPv6 address. An AAAA
record is the fastest way to reproduce the outage this work started from.

## Post-deploy checklist

Ordered — several steps depend on the one before.

### 1. Immediately after the first deploy

```bash
zfs set com.sun:auto-snapshot=true zdata/state
```

**`zdata/state` currently has no ZFS snapshots at all.** `disko.nix` declares
the property but disko does not apply properties to datasets on an existing
pool; only `zdata/audiobooks` and `zdata/roms` carry it on the live pool. Until
this runs, Navidrome's own SQLite backup is the *only* protection for its
database, not a supplement to one. This affects every service's state on ernst,
not just Navidrome.

Then, **before anything else reaches these hostnames**, create the admin
account on each of Komga, Navidrome and CWA. Their first-run flows are
unauthenticated by construction.

### 2. Navidrome users

```bash
nixos-container run arr -- navidrome user create <name>
```

Or through the web UI as admin: **Settings → Users → Add**. Navidrome has no
declarative user database; accounts are DB rows.

### 3. The Opus 96k mobile profile — a UI step, and it cannot be otherwise

Transcoding profiles are **database rows**, not configuration. A fresh 0.63.2
DB ships four seeded rows (`mp3 192`, `opus 128`, `aac 256`, `flac`), and
`player.transcoding_id` / `player.max_bit_rate` are written when a client first
connects.

1. Connect the phone once (Tempo → log in → play anything). This creates the
   player row.
2. Navidrome → **Settings → Players** → pick the phone.
3. Set **Transcoding** = `opus audio`, **Max bitrate** = `96`.
4. Leave every LAN player untouched — no assignment means no transcoding, which
   is the desired default.

**Since 0.61 transcoding is server-managed.** Clients no longer negotiate
format. If a client-side "audio quality" setting appears to do nothing, this is
why.

### 4. CWA: OIDC on the web UI

CWA has no config file and no OAuth environment variables — verified by
grepping every `os.environ` read in the v4.0.6 source, where the only
OAuth-related variable is `OAUTH_SSL_STRICT`. This is typed in once.

```bash
clan vars get ernst authelia-oidc-cwa/cwa-client-secret
```

Then **Admin → Edit Basic Configuration → OAuth**:

| Field | Value |
|---|---|
| Provider | Generic / OIDC |
| Metadata URL | `https://auth.goclan.org/.well-known/openid-configuration` |
| Client ID | `cwa` |
| Client secret | the value from `clan vars get` |
| OAuth redirect host | `https://cwa.goclan.org` |

**The redirect host is not optional.** Left empty, CWA takes a fallback branch
that omits `redirect_url` and builds the callback from the request, which
behind a proxy produces an `http://` URI Authelia refuses. The expected
callback is `https://cwa.goclan.org/login/generic/authorized`.

A mismatch shows up as `invalid_client` **at the portal**, not as a CWA error.

### 5. CWA: KOReader sync

**Default is off at 4.0.6** — `scripts/cwa_schema.sql` declares
`koreader_sync_enabled SMALLINT DEFAULT 0 NOT NULL`, and the settings helper
reads that column and nothing else, failing closed. The README's "enabled by
default" is stale. There is **no environment variable**; it is a UI toggle.

**CWA Settings → Enable KOReader Sync (CWA Plugin)**

Upstream's own warning, logged when you enable it:

> KOReader sync enabled: checksum backfill runs at startup and may temporarily
> lock `metadata.db`. Disable and restart the container to stop a running
> backfill.

**Enable it now, while the library is empty.** The backfill cost scales with
the library, so doing this before the library fills is nearly free; doing it
afterwards means a slow first start with the web UI blocking on `metadata.db`.

Confirm the plugin page serves:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://cwa.goclan.org/kosync
```

KOReader plugin install path — copy the downloaded `cwasync.koplugin` to:

```
<KOReader>/plugins/cwasync.koplugin/
```

On a Kobo that is `/mnt/onboard/.adds/koreader/plugins/`. Restart KOReader,
then **Tools → CWA Sync** → server `https://cwa.goclan.org`, and log in with
the CWA account.

### 6. Rotating the Navidrome metrics password

Two containers share it. Restarting only one leaves Prometheus scraping with
the old password and the job reporting `up=0` with a 401 — which looks like
Navidrome being down rather than a half-finished rotation.

```bash
clan vars generate ernst
systemctl restart navidrome-secrets container@arr
systemctl restart monitoring-secrets container@monitoring
```

## Verification — from mobile data, WiFi off

The whole point is the external path, so test it externally. Run these on the
FP5 (Termux) or on `miralda` tethered to 5G.

### Per service, both stacks separately

```bash
for h in jellyfin audiobookshelf komga navidrome cwa; do
  echo "== $h"
  dig +short $h.goclan.org @1.1.1.1
  curl -4 -sS -o /dev/null -w '  v4: %{http_code} verify=%{ssl_verify_result} t=%{time_total}\n' \
    https://$h.goclan.org/
  curl -6 -sS -o /dev/null -w '  v6: %{http_code}\n' https://$h.goclan.org/ 2>&1 | tail -1
done
```

- **v4 must return 200 or 302 with `verify=0`.**
- **v6 must fail** — there is no AAAA. A v6 *success* means someone added one;
  remove it.
- `verify=0` is the full-chain check. Mobile apps are stricter than desktop
  browsers, which cache intermediates.

### The negative control — prove `wan` is still fail-closed

```bash
curl -sS -o /dev/null -w 'sonarr from outside: %{http_code}\n' \
  --resolve sonarr.goclan.org:443:78.94.91.74 https://sonarr.goclan.org/
```

**Must be 404**, not 302 and not 200. 404 means Traefik has no router for that
name on `wan` — not there, rather than refused.

`sonarr` replaces `jellyfin`, which M18 used as this control until this change
exposed it. `sonarr` is strictly better: it carries forward-auth, so a leak
would be caught twice.

### Failure-mode key

| Symptom | Cause |
|---|---|
| `NXDOMAIN` | missing public A record |
| connection **refused** | reached the house, no listener — check the DNAT |
| connection **times out** | firewall drop, or PMTUD blackhole |
| TLS **hangs** after ClientHello | MTU/PMTUD — verify ICMPv6 "Packet Too Big" is not dropped |
| `404` with a valid cert | correct for an unexposed name; a bug for an exposed one — check `wanExposed` |
| `302` to `auth.goclan.org` on an app-API host | the forward-auth regression check (e) exists to prevent |

### Native apps

| Service | Android client | Check |
|---|---|---|
| Jellyfin | Jellyfin | login, then a video **plays** |
| Audiobookshelf | Audiobookshelf | login, playback, **progress syncs back** |
| Komga | Komelia | login, library list, a page **renders** |
| Navidrome | **Tempo** | login, a track **plays** |
| CWA | KOReader + `cwasync.koplugin` | login, open a book, progress round-trips |

Also: Mihon → Extensions → Komga; and an OPDS reader against
`https://cwa.goclan.org/opds`.

**Komga per-user access control must survive exposure.** Log in through the
*external* name as a restricted (kids') account and confirm the library list is
short and age filtering still applies. Komga enforces this inside the
application on every API and OPDS path, keyed on the authenticated principal —
not on which vhost the request arrived through — so it should hold. Verify it
anyway; it is the one check that must not be assumed.

### Prove Navidrome is actually transcoding

Not just that it plays — that the mobile profile *bit*.

```bash
# On ernst, watch for the ffmpeg invocation while the phone plays a track:
nixos-container run arr -- journalctl -u navidrome -f | grep -i transcod
```

Expect a line naming the opus profile and `-b:a 96k`. Cross-check in
**Settings → Players** that the phone's row shows the assignment. A LAN client
playing the same track must produce **no** ffmpeg line at all.

## What could not be verified statically

- **The UDM-Pro forward.** `10.0.90.12:8443` is unreachable from a consumer
  VLAN (the ZBF rule permits `:443` only) and hairpin NAT to the public IP
  times out from inside. Relies on M18's 2026-09-07 measurement from 5G.
- **Everything about CWA's runtime.** No instance has ever run here. The
  KOReader and OIDC behaviour above is read from the v4.0.6 source, which is
  better than documentation but is not a running system.
- **Komga and Navidrome have never started on ernst.** In particular the
  `PrivateUsers = true` that both upstream modules set, combined with
  `Group = media`, is expected to work — the unit's primary GID is what gets
  mapped — but it is nested inside an nspawn container and is untested.
  If either fails to read the library, that is the first thing to check:
  `nixos-container run arr -- systemctl status komga navidrome`.
- **The Opus 96k profile end to end.** It cannot exist until a player row does.
- **Whether the served chain includes the LE intermediate.** `curl` verifies
  clean from `miralda`, but that machine may have it cached. The mobile test
  above settles it.
