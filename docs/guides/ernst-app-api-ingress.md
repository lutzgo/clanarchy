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

### The exempt six

| Host | Clients that force the exemption |
|---|---|
| `jellyfin` | TV apps, Android/iOS, Chromecast senders, DLNA |
| `audiobookshelf` | the ABS mobile and TV apps (bearer token) |
| `komga` | Komelia, Mihon's Komga extension, OPDS v1/v2 readers |
| `navidrome` | every Subsonic client — the credential is a **query parameter**, by protocol definition |
| `cwa` | OPDS (basic auth), Kobo (device token **in the URL path**), KOReader `/kosync` (RFC 7617) |
| `photos` | the Immich app on two phones (bearer token), the Kodi add-on on the TV (`x-api-key`), **and shared album links** |

A Kobo e-reader is the clearest case: there is no browser on the device at all.

#### `photos` is the sixth, and it breaks the pattern of the other five

Every other name in that table answers only to a **credential**. Immich answers
a **shared album link** to an anonymous caller — that is the feature, and it is
how a family member with no account here sees an album at all. Forward-auth
would not degrade it, it would remove it.

So the usual sentence — *"the application's own accounts are now the entire
boundary"* — is not the whole truth for this one. The accurate version:

- **the library** is bounded by Immich's accounts;
- **anything explicitly shared** is bounded by possession of a URL, from
  anywhere on the internet, until the link is revoked in the UI.

Those links are 128-bit random keys, which is the real control. Immich also
supports a **per-link expiry and password** — use both for anything that is not
meant to be world-readable, because nothing in this repo can set them and no
middleware in front of it can help.

`photos` is also the one name here whose first-run window is closed by a
**mechanism** rather than by speed: `IMMICH_ALLOW_SETUP` is `false` in
`containers/immich.nix`, and the public A record is created only after both
accounts exist. See the post-deploy checklist below.

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

## DNS — BOTH halves, and forgetting either one has now bitten twice

Split horizon means **two** records per service, in two different places, and
neither is created by this repo. They fail in opposite directions:

| Missing | Symptom |
|---|---|
| Public A record at Cloudflare | NXDOMAIN from outside. Service works perfectly on the LAN. *(This is what kept Audiobookshelf unreachable on 5G.)* |
| Internal record in Technitium | the LAN resolver **recurses to the public view**, gets the WAN IP, and the request hairpins at the UDM-Pro — which does not work here, so it **hangs**. Not NXDOMAIN, not refused: a timeout that looks like a dead backend. *(This is what made Navidrome unreachable from the LAN while its router was working fine.)* |

The second is the nastier of the two, because a name that resolves feels like a
name that is configured.

### Internal — Technitium (10.0.5.3), every service

One A record per hostname → **`10.0.90.12`** (Traefik). Every `*.goclan.org`
service name needs one, exposed externally or not. The established shape is a
small **zone per service name** with an `@ A` record, matching the existing
entries.

#### FLUSH BEFORE YOU CONCLUDE ANYTHING

A lookup made *before* the zone existed leaves a cached **NXDOMAIN**, and the
zone's SOA minimum is **900 s** — so a correct record can keep failing for up
to fifteen minutes and look like a broken zone. This has already burned one
debugging round here, and it is the same mechanism `traefik.nix` documents at
length for ACME, where a premature query poisoned a public resolver for thirty
minutes.

Two caches, and clearing one does not clear the other:

```bash
resolvectl flush-caches          # systemd-resolved, on the client
```
```
chrome://net-internals/#dns  →  Clear host cache      # Chrome's own
```

Then verify against Technitium directly before believing anything downstream:

```bash
dig +short @10.0.5.3 <name>.goclan.org     # must answer 10.0.90.12
dig +short <name>.goclan.org               # your resolver, post-flush
```

If the first answers and the second does not, it is cache — not config.

### Public — Cloudflare, only the externally reachable set

A records only, **DNS-only (grey cloud)**, all → `78.94.91.74`:

```
audiobookshelf   auth   cwa   jellyfin   jellyseerr   komga   navidrome   photos
```

Add each one only *after* that service's admin credential is set — see the
credential table above. `photos` is the strictest case of that rule and the
reason it is worth stating as a rule at all: see step 1c.

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

Then, **before a public A record exists for any of these names**, deal with
each service's initial credential. The three are NOT the same shape, and
treating them as one is how the wrong one gets left open:

| Service | Initial state | What "unauthenticated" means |
|---|---|---|
| Komga | no account at all | first visitor is offered **Create the first user**, and it is an admin |
| Navidrome | no account at all | first visitor gets the **create-admin** form; the API advertises `firstTime: true` to anyone who asks |
| **CWA** | **`admin` / `admin123` already exists** | **not a wizard — a DEFAULT CREDENTIAL.** `cps/constants.py:132` sets `DEFAULT_PASSWORD = "admin123"` and `cps/ub.py:1175` creates the account automatically |

CWA is the dangerous one, because there is no window that closes by itself.
Komga and Navidrome are unowned until someone claims them; CWA is owned from
first boot by a password that is in the source code and in every guide on the
internet. **Change it before `cwa.goclan.org` resolves publicly**, not after.

The ordering rule that follows: add the public A record for a service only
*after* its admin credential is set. `komga` and `cwa` deliberately have no
public record yet for exactly this reason.

### 1c. Immich (M22) — a first-run window closed by a flag, not by hurrying

Immich is the fourth shape in that table, and the only one where the repo holds
a switch:

| Service | Initial state | What "unauthenticated" means |
|---|---|---|
| **Immich** | no account, **and signup disabled** | `/auth/admin-sign-up` is **off** until `adminSetupOpen` is flipped, so there is no window to lose a race in |

`containers/immich.nix` ships `adminSetupOpen = false` → `IMMICH_ALLOW_SETUP=false`.
Opening it is a deploy, not a restart. In order:

1. Edit `adminSetupOpen = true` in `machines/ernst/containers/immich.nix`,
   `clan machines update ernst`.
2. On the LAN, open `https://photos.goclan.org` and create the **admin**
   account (lgo). Then create **sgo** from the admin's user-management page —
   Immich's signup endpoint only ever creates the *first* account, so every
   later user is made by an admin and there is no second window.
3. Set `adminSetupOpen = false` again, `clan machines update ernst`. Confirm
   the signup endpoint is gone before continuing.
4. **Only now** add the public `photos` A record.

Steps 3 and 4 are independently sufficient, which is why both are here. Immich
additionally refuses a second signup once an admin exists, so after step 2 all
three controls are redundant — which is exactly when nobody is watching.

**Then set strong passwords on both accounts.** They are about to become
internet-reachable single-factor logins, and unlike the other five names on
that list, this one also serves anonymous shared-album URLs by design.

### 1b. If a Navidrome scan ever fails, it poisons its own scan state

Worth knowing before you need it, because it happened on the first deploy and
the symptom is silence.

A scan that fails **per file** — bad permissions, an unreadable `/tmp`, a
missing codec — still records the folders as processed. The scan "Completes",
the unit stays `active`, the exit status is clean, and every subsequent
incremental scan correctly sees no mtime change and skips everything:

```
Scanner: Starting scan fullScan=false
Scanner: Finished scanning all libraries duration=10.1ms
```

Fixing the underlying cause is **not enough**. Restarting is not enough. The
library stays empty until something forces a full rescan.

The tell is `audioCount` non-zero with `tracksImported=0` on the *original*
failing run. Note that plain `journalctl -u navidrome | grep tracksImported`
replays the whole history and will show you those old lines forever — use
`--since` or you will diagnose a fixed problem:

```bash
nixos-container run arr -- journalctl -u navidrome --since '10 min ago' \
  --no-pager | grep tracksImported
```

Recovery, non-destructive — do **not** delete the database:

```bash
nixos-container run arr -- systemctl stop navidrome

nixos-container run arr -- systemd-run --quiet --wait --collect --pipe \
  -p User=navidrome -p Group=media -p PrivateTmp=yes \
  <navidrome>/bin/navidrome scan --full \
    --configfile <the unit's --configfile path> \
    --datafolder /var/lib/navidrome --nobanner

nixos-container run arr -- systemctl start navidrome
```

Three things about that invocation are load-bearing:

- **`--datafolder /var/lib/navidrome` is required.** `DataFolder` is
  deliberately unset in the Nix config (it defaults to the module's
  WorkingDirectory, which the bind mount puts on zdata). The CLI does not
  inherit that default — it falls back to `.` — so without this flag the scan
  builds a *different, empty* database in the current directory and reports
  success.
- **`-p User=navidrome -p Group=media`.** Running it as root leaves
  root-owned WAL/journal files in a 0700 directory the service cannot then
  write.
- **`-p PrivateTmp=yes`.** The unit has it for the taglib reason above; the
  CLI needs it for the same reason, and does not get it from the unit.

Expect `tracksImported` to equal `audioCount` for every folder.

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

#### Finding the settings — THERE IS NO "OAuth" SECTION

This cost several rounds of looking, so it is written down precisely.

Go to **Admin → Edit Basic Configuration**. The OAuth fields are **not** a
section of their own and are **not** visible when the page loads. They are a
collapsed block under **Feature Configuration**, revealed only by changing one
dropdown:

```
Server Configuration
Logfile Configuration
Feature Configuration
  … uploads, anonymous browsing, public registration
  … Kobo sync, Goodreads, Hardcover
  … Allow Reverse Proxy Authentication
  … Auto-create users from reverse proxy    ← last thing before it
  ▼ Login type            ← SET THIS to "Use OAuth (requires HTTPS)"
  ▼ OAuth provider fields ← appear only once that is selected
External binaries
Security Settings
```

**The decoy:** a panel headed **"OAuth & API Integrations"** exists, contains
one "Hardcover API Token" field, and is *not this*. It lives in
`user_edit.html` — **Admin → Users → edit a user** — and is a per-user metadata
token. Sharing a word with what you want is the whole of its relevance.

If the Login type dropdown is genuinely absent rather than merely scrolled
past, the template gates it on `feature_support['oauth']`, which is set by
`from . import oauth_bb` succeeding — and the failure is logged at **debug**
level, so an INFO-level log shows nothing. Check it directly:

```bash
podman exec cwa sh -c 'cd /app/calibre-web-automated && python3 -c "from cps import oauth_bb"'
```

Silence means the section is there and you have not scrolled far enough.

#### The fields

| Field | Value |
|---|---|
| Login type | **Use OAuth (requires HTTPS)** |
| Metadata URL (auto-discovery) | `https://auth.goclan.org/.well-known/openid-configuration` |
| Use Manual Endpoint URLs | leave **unchecked** — auto-discovery fills the rest |
| Client ID | `cwa` |
| Client secret | the value from `clan vars get` |
| OAuth redirect host | `https://cwa.goclan.org` |
| Admin group name | `admins` |

**"requires HTTPS" is satisfied** even though Traefik speaks plain HTTP to the
container: CWA runs `ProxyFix` with `x_proto` and logs
`ProxyFix configured to trust 1 proxy(ies)` at startup, so `X-Forwarded-Proto`
from Traefik is honoured. Do **not** set `TRUSTED_PROXY_COUNT` — the default of
1 is exactly right, because nothing sits in front of Traefik.

**The admin group name is not optional here.** Security Settings ships with
*"Enable OAuth Group-Based Admin Role Management"* **ticked**, which means the
OIDC group claim decides admin rights on every login. Left empty with that box
ticked, an OIDC login can revoke your own admin. `admins` matches the group
`authelia.nix` puts lgo and go in.

**Leave "Disable Standard Login" OFF** until a full OIDC round-trip has
succeeded. Its own help text says so, and the recovery from getting it wrong is
editing `config_login_type` back to `0` in `/srv/state/cwa/config/app.db` by
hand.

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

### Never test a backend directly — it hangs, and that is correct

```bash
curl http://10.0.90.21:8083/     # CWA   — HANGS
curl http://10.0.90.13:25600/    # Komga — HANGS
```

Every backend's own netns firewall accepts its port from `10.0.90.12`
(Traefik) and nothing else, with policy `DROP` — so a probe from ernst itself
(VLAN 50) or from a laptop times out rather than being refused. That is the
backend-bypass hardening working, not a broken service.

`traefik.nix` states this for the pre-existing backends under "DEBUGGING
CONSEQUENCE"; it applies identically to everything added since. **Always test
through Traefik**:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://cwa.goclan.org/
```

To reach a backend directly for debugging, go in via loopback, which is always
trusted:

```bash
nixos-container run arr -- curl -sS localhost:25600/     # Komga
podman exec cwa curl -sS localhost:8083/                 # CWA
```

### Failure-mode key

| Symptom | Cause |
|---|---|
| `NXDOMAIN` | missing public A record |
| a **backend address** hangs | expected — see above, test through Traefik |
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
