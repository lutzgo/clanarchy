# Mail on ernst — @goclan.org

The operator's half of M31. The declarative half is
[`machines/ernst/containers/mail.nix`](../../machines/ernst/containers/mail.nix)
and [`modules/mail-accounts.nix`](../../modules/mail-accounts.nix); everything
here is a step somebody has to take at Cloudflare, on the UDM-Pro, in
Technitium, or on a phone.

Five mailboxes, one domain. Webmail is the Nextcloud **Mail** app at
`cloud.goclan.org` — see [Nextcloud Mail](#nextcloud-mail--webmail-at-cloudgoclanorg):

| Mailbox | Also receives | Used from |
|---|---|---|
| `admin@goclan.org` | `postmaster@` `abuse@` `hostmaster@` `dmarc@` | a terminal on ernst |
| `lutz@goclan.org` | `lgo@` | aerc on miralda and jens |
| `sarinah@goclan.org` | `sgo@` | K-9 on Sarinah's phone |
| `max@goclan.org` | `mgo@` | K-9 on Max's phone |
| `go@goclan.org` | — | the couch/admin account |

**Everyone is reachable under both names.** The fleet identifies people by a
three-letter username (`lgo`, `sgo`, `mgo`) and addresses them by their first
name, so each mailbox carries its username form as an alias — mail to `lgo@`
lands in `lutz@`. That is routing, not a second account: an alias costs no
mailbox, no password and no Maildir. `go@` needs none, because there the
username and the local part are already the same word.

`sabine@goclan.org` does **not** exist. It was an alias in an earlier draft,
back when Authelia's account for Sarinah was called `sabine`; PR #278 renamed
it to `sarinah` and #280 renamed it again to `sgo`, so the address now names
nobody — and it never received mail, because this server did not exist. Her
Unix username on biene is still `sabine` and that is untouched and unrelated.

---

## Read this before anything else

**This milestone was planned on the assumption that outbound mail would mostly
fail, and that assumption no longer holds.** Both problems were real, both were
measured, and both were fixed by work outside this repo. Keeping the before
column matters, because the design below was chosen while the "now" column did
not exist.

| | 2026-09-29 (planning) | 2026-10-06 (now) |
|---|---|---|
| Public IPv4 | `78.94.91.74` | unchanged |
| PTR | `…um19.pools.vodafone-ip.de` | **`mail.goclan.org`** — Vodafone set it on request |
| Forward-confirmed rDNS | n/a | **confirmed**, both directions agree |
| Outbound `:25` | open — reached Gmail's and iCloud's MX directly | unchanged |
| `b.barracudacentral.org` | **listed** (`127.0.0.2`) | **delisted** |
| Spamhaus, SpamCop, UCEPROTECT, PSBL, SORBS | not listed | not listed |

So direct sending is now genuinely viable here. **It is viable because of two
specific external facts, not because sending direct from a residential line is
generally fine.** It is not. If the PTR is ever lost — a tariff change, a pool
renumbering, a support ticket handled by somebody else — the symptom is mail
quietly landing in junk, and the answer is
[the smarthost escape hatch](#the-smarthost-escape-hatch), which is one option
block and changes no mailbox, no key and no client.

Step 7 of the rollout is still a **gate**. It is now expected to pass.

---

## Phase 0 — reputation ✅ DONE 2026-10-06

Kept as a record, because this is the work that made the rest viable and it is
the work to repeat if deliverability ever degrades. None of it is in the repo
and none of it can be.

1. **Barracuda removal** — <https://www.barracudacentral.org/rbl/removal-request>.
   Free, self-service, same-day. ✅ Delisted.
2. **Spamhaus** — check <https://check.spamhaus.org/ip/78.94.91.74> in a
   browser. ✅ Not listed. Do **not** try to check this with `dig`: Spamhaus
   refuses queries arriving via a public or shared resolver and answers
   `127.255.255.254`, which is easy to misread as "not listed".
3. **Microsoft** — enrolled in [SNDS](https://sendersupport.olc.protection.outlook.com/snds/),
   mitigation requested at <https://sender.office.com/>. ✅
4. **Vodafone set the PTR to `mail.goclan.org`** on request — the single change
   that mattered most, and the one that was expected to be refused on a
   consumer tariff. It was not.

### These are now monitored, so do not re-check them by hand

This section originally said *"re-check 1, 2 and 4 quarterly"*. That was the
same mistake `ipv6Guard` was written to fix — **a property re-measured by hand
is not monitored** — with a longer interval. Both facts can be lost on somebody
else's schedule, and the symptom is identical and silent: mail stops being
accepted, with nothing wrong on this host.

A textfile collector on ernst now checks them **twice a day** and alerts
through the usual ntfy path:

| Alert | Fires when | What to do |
|---|---|---|
| `MailReverseDnsBroken` | PTR and forward A disagree, for 6h | Get the PTR restored, or enable [the smarthost escape hatch](#the-smarthost-escape-hatch) |
| `MailIpBlocklisted` | listed on any checked DNSBL, for 6h | Use that list's removal form — the links are above |
| `MailDnsblCheckUnusable` | a list fails its own test points, for 24h | The *check* is broken, not the reputation |

**Why the third alert exists.** Measured on ernst: asking the host resolver
gives `127.255.255.254`, which is Spamhaus **refusing** the query — they refuse
anything arriving via a large public resolver, and Technitium forwards. A naive
check reads that as "no answer, so not listed" and goes green permanently, in
exactly the case it was built for. So the queries go through the mail
container's kresd, and every run first asks each list about `127.0.0.2` (must
be listed) and `127.0.0.1` (must be clean). A list that fails its own control
gets `usable 0` and **no** `listed` verdict at all.

To check by hand anyway — after an alert, or when curious — use the container's
resolver, not the host's:

```bash
ssh root@10.0.50.10 '
  nixos-container run mail -- dig +short -x 78.94.91.74
  nixos-container run mail -- dig +short A mail.goclan.org
  nixos-container run mail -- dig +short 74.91.94.78.zen.spamhaus.org
  nixos-container run mail -- dig +short 2.0.0.127.zen.spamhaus.org   # control: must be 127.0.0.x
'
```

The first two must agree — that pair is forward-confirmed reverse DNS, and it
is what receivers actually test. The third must be empty. **If the fourth is
empty too, the other answers mean nothing.**

Steps 1–3 above (the removal forms and SNDS) still have no automation and
cannot have any; they are web forms. The monitoring tells you *when* to go and
fill one in.

---

## DNS

### Cloudflare — public, and **grey cloud (DNS-only) on every record**

Never orange-cloud any of these. Cloudflare's proxy cannot carry SMTP or IMAP
at all, and a proxied `A` record breaks the MX outright.

| Type | Name | Value |
|---|---|---|
| A | `mail` | `78.94.91.74` |
| MX | `@` | `10 mail.goclan.org.` |
| TXT | `@` | `v=spf1 mx -all` |
| TXT | `mail._domainkey` | the contents of `clan vars get ernst mail-dkim/dkim.txt` |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:dmarc@goclan.org; ruf=mailto:dmarc@goclan.org; fo=1` |

`clan vars get ernst mail-dkim/dkim.txt` emits the record in BIND zone-file
form. Cloudflare's editor wants only the quoted value, and the key is long
enough to be split across several quoted strings — paste all of them, keeping
the quotes, into the single content field.

**DMARC starts at `p=none` and stays there for two weeks.** Reports land in
`admin@` via the `dmarc@` alias. Going straight to `p=quarantine` on an IP with
this reputation makes a genuine misconfiguration indistinguishable from the
junking you already expect, and you lose the only two weeks in which the
difference is cheap to find out.

**No AAAA record, ever** — standing note SN2. A v6 path would reach `:25`
without passing the UDM-Pro DNAT, so it would carry no port forward to remove,
and the container's fail2ban jails are v4 chains. Reachable and unbannable at
once is exactly what SN2 exists to prevent.

### Not yet: MTA-STS and TLS-RPT

`_mta-sts` and `_smtp._tls` are **deliberately absent from the table above**,
and publishing them now would make things worse rather than better: MTA-STS
requires a policy file served over HTTPS at
`https://mta-sts.goclan.org/.well-known/mta-sts.txt`, and a `_mta-sts` record
pointing at a 404 is a broken policy rather than no policy.

That policy file is HTTP, so unlike everything else about mail it **does** ride
Traefik: a small static-file router on the existing `*.goclan.org` wildcard,
`mta-sts` added to `appApiHosts` (its clients are remote MTAs, which cannot
follow a 302) and to `wanExposed`, plus a public A record and its own ledger
row. It is the one piece of mail that touches `containers/ingress-policy.nix`,
which is why it is a separate change and not part of M31 — it edits a
fail-open-direction guard, and that does not belong in the same diff as a large
new container.

Until it lands, inbound TLS is opportunistic. That is the same posture every
other small mail server has and is not a reason to delay the rest.

### Technitium (`10.0.5.3`) — internal

One `A` record, `mail.goclan.org` → `10.0.90.31`, in its own small zone, the
same way every other service name is handled.

**Do not skip this.** Without it, LAN clients resolve `mail.goclan.org` to the
public address, then hairpin at a UDM-Pro that does not hairpin — which
presents as aerc **hanging** rather than failing, and sends you looking at the
mail server.

---

## UDM-Pro

### DHCP reservation

`10.0.90.31` for MAC `02:00:00:90:00:17`, which is the **container-side** MAC.
It must be inside the `10.0.90.6–.254` pool; UniFi silently hands out an
ordinary pool lease for anything in `.2–.5`.

If this is missed, the container leases some other address, the monitoring
accept rule stops matching, and nothing says so — M30 lost a verification row
to exactly this.

### Port forwards — four, and they are the first that do not end at Traefik

Before M31 this fleet had exactly one port forward, `WAN :443 →
10.0.90.12:8443`, and "one forward" was load-bearing in several arguments
elsewhere. It is now five.

| WAN | Destination | Ledger |
|---|---|---|
| `:25` | `10.0.90.31:25` | L19 |
| `:465` | `10.0.90.31:465` | L20 |
| `:993` | `10.0.90.31:993` | L20 |
| `:4190` | `10.0.90.31:4190` | L20 |

**DNAT, not SNAT** — `Auto Allow Return Traffic` ticked, no source NAT. The
container's fail2ban jails ban by client address, so a rewritten source would
either ban nothing or ban the gateway. This is the same property
`containers/crowdsec.nix` measured for Traefik, and it matters here for the
same reason.

**Ports go in the Destination card.** The editor has a Port section in both
zone cards and the source one is the one you see first; filling that one
matches traffic *from* port 25, i.e. never.

### No VLAN 50 → 90 rule

Same as M22, M23, M24, M27 and M30: nothing on the Servers VLAN needs to reach
this container. Remember that `nc -vz 10.0.90.31 25` **from ernst** succeeds
anyway, because the mail ports accept from everywhere — see the inverted
negative control below.

---

## Rollout

Ordered so a failure stops before anyone is given an address.

### 1. Build

```bash
jj st                      # snapshot first: Nix cannot read an untracked path
nix build --dry-run .#nixosConfigurations.ernst.config.system.build.toplevel
```

### 2. Generate the secrets — **in a real terminal**

Two generators, and they behave differently. Run both:

```bash
clan vars generate ernst
clan vars generate ernst --generator authelia-users --regenerate
```

**The first** prompts for all five mailbox passwords, minimum 12 characters,
enforced by the generator. It re-prompts even for mailboxes that already had a
password, because clan treats a generator as satisfied only when *every* file
it declares exists — and `max.hash` and `go.hash` are new. Nothing is deployed
yet, so no password is in use; re-entering the old ones or choosing new ones
are equally fine. It is a **shared** generator, so this also satisfies miralda
and jens, and because it is prompted, **every deploy of every machine blocks
until it has run once**. In a non-interactive shell that surfaces as a
`termios.error`, not as "you owe me a password".

**The second is the one that is easy to skip, and skipping it is silent.**
Adding `mgo` to `autheliaUsers` adds a *prompt* but no new *file* —
`authelia-users` emits a single `users_database.yml`, which already exists — so
a plain `clan vars generate` asks for nothing and Max never reaches the
database. `--regenerate` forces it. The cost is that it re-prompts **lgo, go
and sgo as well**, because that generator is atomic.

> ⚠️ **Enter the existing three passwords unchanged** unless you mean to change
> them. These are the accounts that reach every admin UI in the house. TOTP
> enrolments are unaffected — they live in Authelia's own storage, keyed by
> username, and no username changes here.

Then check the secrets actually landed in the tree:

```bash
jj diff --from main --to @ -- vars/
```

`clan vars generate` commits as a jj **sibling**. An empty diff here means the
new secrets are not in your change and the deploy will ship without them.

### 3. Publish DKIM before deploying

```bash
clan vars get ernst mail-dkim/dkim.txt
```

Put it in Cloudflare now, along with the rest of the [DNS table](#dns). DNS
propagation and first delivery then stop racing each other.

### 4. Deploy

```bash
clan machines update ernst
bridge vlan show dev vb-mail      # must show 90 PVID untagged
nixos-container run mail -- systemctl --failed
```

### 5. Inbound `:25` — the gate that decides whether M31 works at all

**Vodafone may block inbound 25 and nothing in this repo can tell you.** From
off-LAN — phone tethering, not the house wifi:

```bash
nc -vz 78.94.91.74 25
swaks --to admin@goclan.org --server 78.94.91.74
```

If this fails, the milestone is dead in its current form. The fallback is the
VPS-relay design that was considered and set aside during planning: a small
box with a static IP and a settable PTR, relaying both directions to ernst over
ZeroTier. Do not hand out addresses before this passes.

### 6. Outbound authentication and alignment

```bash
# from aerc, or:
nixos-container run mail -- swaks --from lutz@goclan.org \
  --to check-auth@verifier.port25.com --server localhost
```

Require `SPF=pass`, `DKIM=pass`, `DMARC=pass` in the reply. Then send to a fresh
address from <https://www.mail-tester.com/>. With the PTR set and the
blocklists clear this should now score close to 10/10 — if it does not, read
which check failed rather than assuming it is reputation, because the two
reputation problems this guide was written around are both gone.

### 7. Real-world delivery — the honest test

Send to a **Gmail**, a **GMX** and an **Outlook.com** address, and check **where
each landed**, not whether it was accepted. Then reply from each and confirm
inbound.

This is still the gate, but it is now **expected to pass** — Outlook's usual
reason for rejecting a residential sender is generic rDNS, and the PTR is
`mail.goclan.org` with forward confirmation. If mail still lands in junk,
that is new information rather than the predicted outcome: re-run the two
`dig` checks in Phase 0 first, and only then consider
[the escape hatch](#the-smarthost-escape-hatch).

### 8. Clients

See [Client setup](#client-setup). Test K-9 **over mobile data, not wifi** —
on wifi it takes the LAN path and proves nothing about the port forwards. Then
do one ManageSieve round-trip to exercise `:4190`.

### 9. Protection

```bash
# three bad IMAP logins from off-LAN, then:
nixos-container run mail -- fail2ban-client status dovecot
nixos-container run mail -- rspamc stat          # Rspamd is scoring
nixos-container run mail -- rspamadm configtest
```

### 10. Monitoring and snapshots

`up{job="mail"} == 1` in Grafana, and the `postfix_showq_*` series non-null.
Stop dovecot and confirm `ContainerSystemdUnitFailed` reaches the ntfy topic.

```bash
zfs list -t snapshot zdata/state | tail
```

**Those snapshots are the only backup that exists.** There is no borg, no
restic and no replication anywhere in this repo. For media that was a shrug;
mail is not re-acquirable.

---

## Client setup

Same settings everywhere. **Mail is implicit TLS; ManageSieve is STARTTLS** —
see the warning under the table, which has already cost one round.

| | |
|---|---|
| IMAP | `mail.goclan.org` : `993`, **SSL/TLS** |
| SMTP | `mail.goclan.org` : `465`, **SSL/TLS** |
| ManageSieve | `mail.goclan.org` : `4190`, **STARTTLS** |
| Username | the **full address** — `lutz@goclan.org`, not `lutz` |

> ⚠️ **ManageSieve does not take implicit TLS, and `:4190` is not a typo for a
> wrapper-mode port.** `143` and `587` are switched off on this server per RFC
> 8314, so "implicit TLS everywhere, STARTTLS nowhere" is the right instinct for
> *mail* — and it is wrong for Sieve. There is no implicit-TLS ManageSieve port
> in common use: Dovecot's Pigeonhole listens plaintext on 4190 and advertises
> `STARTTLS`, which is the standard. Measured on the running server:
>
> ```
> $ exec 3<>/dev/tcp/10.0.90.31/4190; cat <&3
> "IMPLEMENTATION" "Dovecot Pigeonhole"
> "SASL" ""
> "STARTTLS"
> ```
>
> The empty `SASL` list is `ssl = required` working correctly — Dovecot offers
> no authentication mechanism at all until TLS is up. A client configured for
> SSL/TLS sends a TLS ClientHello into a plaintext greeting and the handshake
> fails; **Nextcloud Mail reports this as `Request failed with status code
> 500`**, which names neither TLS nor the port and sends you looking at
> credentials.

### aerc (miralda, jens)

Already configured, in
[`machines/miralda/home-modules/console-desktop.nix`](../../machines/miralda/home-modules/console-desktop.nix)
— shared through `modules/users/lgo.nix`, so one edit covers both laptops.
The password comes from the shared clan var, so there is nothing to type.

If aerc prompts for a password, the clan var did not reach the machine: check
that `modules/users/lgo.nix` still imports `modules/mail-accounts.nix`, and
that `/run/secrets/vars/mail-accounts/lutz.plain` exists and is owned by `lgo`.

### K-9 / Thunderbird for Android (Sarinah's and Max's phones)

Add the account manually rather than letting autodiscovery try — there is no
autoconfig endpoint published. Server `mail.goclan.org` for both incoming and
outgoing, ports as above, username `sarinah@goclan.org` / `max@goclan.org`.

**The password is the one you typed at `clan vars generate` time, and it is not
recoverable from the repo.** `clan vars get ernst mail-accounts/sarinah.hash`
returns a *hash*, not a password — that is the whole point of it. If it has
been lost, the reset path is:

```bash
clan vars generate ernst --generator mail-accounts --regenerate
```

which re-prompts every mailbox password, not just the lost one, because the
generator is atomic. Then redeploy ernst.

### Thunderbird (biene)

Installed, not configured. Same settings; Thunderbird's autoconfig will fail
and offer manual entry, which is the expected path.

### Nextcloud Mail — webmail at `cloud.goclan.org`

The **Mail** app is installed declaratively
([`machines/ernst/containers/nextcloud.nix`](../../machines/ernst/containers/nextcloud.nix),
`extraApps`). It is a per-user IMAP client, so each person adds their own
account **once**, in the app's UI — there is nothing to deploy per person.

Settings are the same four as every other client:

| Field | Value |
|---|---|
| Mail address | the full address, e.g. `sarinah@goclan.org` |
| IMAP | `mail.goclan.org` : `993`, **SSL/TLS** |
| SMTP | `mail.goclan.org` : `465`, **SSL/TLS** |
| Password | the one from `clan vars generate` — the same one K-9 uses |

Use the **hostname, not the IP**. Nextcloud's container resolves
`mail.goclan.org` to `10.0.90.31` through Technitium, so the Let's Encrypt
certificate validates; pointed at the bare address, TLS fails on a name
mismatch. No firewall change is needed in either container — the mail ports
accept from everywhere.

**Then, under Account settings:**

- **Aliases → Add alias** — add the username form (`lgo@`, `sgo@`, `mgo@`).
  The server permits it: `:465` enforces `reject_sender_login_mismatch` against
  `vaccounts`, which maps each alias to its owning login. Without the alias here
  you can receive at both addresses but only *send* as the canonical one.
- **Sieve server → Enable sieve filter**, host `mail.goclan.org`, port `4190`,
  **STARTTLS** — not SSL/TLS, see the warning above — with *IMAP credentials*.
  This puts filters on the server, so they apply to K-9 and aerc too.

**Folders are a server setting, not a client one.** Trash and Archive did not
exist at first: simple-nixos-mailserver ships `Trash` as `auto = "no"` —
declared so clients know its name, but never created — and no `Archive` at all.
Both are now `auto = "subscribe"` in `mailserver.mailboxes`, so every client
gets them without configuring anything. If you ever add a folder there, **list
all five**: the option is a freeform attrset, so naming one replaces the whole
default and would silently delete Drafts, Sent and Junk.

**Avatars are off by design.** Turning off *Avatars from Gravatar and favicons*
in Mail settings is what removes them — Gravatar lookups send a hash of your
correspondent's address to a third party, and favicon fetches hit the sender's
domain when you open a message. The local alternative costs nothing and leaks
nothing: a contact in Nextcloud **Contacts** with a photo shows that photo in
Mail. Same picture, no third party.

> **Accounts are deliberately not auto-provisioned, and cannot be.** Nextcloud
> Mail's default provisioning logs into IMAP with the user's *Nextcloud login
> password*, and logins here go through Authelia over OIDC, so Nextcloud never
> has one. Its master-password mode — built for exactly this situation — needs
> Dovecot **master users**, which simple-nixos-mailserver exposes no option
> for. The container file carries the full argument. Typing three passwords
> once is the cheaper side of that trade.

**Nextcloud's own outbound mail is still unconfigured** and is a separate gap:
`mail_smtphost` is the stock `127.0.0.1` default, so `sharebymail` and
password-reset mail cannot send. That needs either a mailbox credential for
Nextcloud or a Postfix `mynetworks` exemption for `10.0.90.26` — its own
decision, its own change.

---

## The smarthost escape hatch

**Not enabled.** This is what to do if step 7 shows mail is not arriving.

Outbound moves to a relay with a real reputation and a real PTR. Nothing else
changes — not the mailboxes, not the DKIM key, not SPF alignment, not a single
client — because Rspamd signs the message **before** Postfix hands it off, so
the signature and the `From:` domain still align on the far side.

In the container config:

```nix
services.postfix.settings.main = {
  relayhost                  = [ "[smtp.relay.example]:587" ];
  smtp_sasl_auth_enable      = true;
  smtp_sasl_password_maps    = "texthash:/run/mail-secrets/relay.passwd";
  smtp_sasl_security_options = "noanonymous";
  smtp_tls_security_level    = "encrypt";
};
```

Note `services.postfix.relayHost` was **removed** in nixpkgs 26.05 in favour of
`settings.main.relayhost`, which takes a **list**.

Then:

- add the relay's credentials as a new prompted clan-vars generator and stage
  `relay.passwd` alongside the other secrets in `mail-secrets`;
- add the relay to SPF: `v=spf1 mx include:spf.relay.example -all`.

Candidates, EU-hosted and free at household volume: Mailjet (200/day), Brevo
(300/day). Amazon SES `eu-central-1` is €0.10/1000 and has the best
deliverability of the cheap options. All three allow a custom `From:` domain,
which is the requirement — a mailbox provider's SMTP will not do, because those
only let you send as an address you hold with them.

---

## Things that will look wrong and are not

**`nc -vz 10.0.90.31 25` from ernst succeeds.** Every other container on this
host refuses connections from ernst by design, and each of their files says so.
Mail is the exception: `:25`, `:465`, `:993` and `:4190` accept from everywhere,
because they have to. The negative control still holds for the exporter —
`curl http://10.0.90.31:9154/metrics` from ernst **is** refused, and only
`10.0.90.14` gets through.

**CrowdSec shows no mail decisions, ever.** It acquires only Traefik's journal
and lives in Traefik's netns. Mail is covered by fail2ban inside its own
container; `cscli decisions list` is the wrong tool and will always look empty.

**The container cannot resolve `*.skynet.lan`.** It runs kresd and does its own
recursion instead of pointing at Technitium, because DNSBL operators refuse
queries arriving via a shared resolver — a Technitium-pointed Rspamd would read
every blocklist as empty and say nothing. There is nothing on the LAN this
container needs by name.

**`up{job="mail"}` is the boring metric.** The job exists for
`postfix_showq_message_age_seconds` and the queue-size series. A mail server
that has silently stopped delivering is `active (running)` the whole time, and
every unit-state signal reads green.

**DMARC and TLS report sending is ON, and was not always.** Those options make
*this* server mail daily reports to strangers about their SPF/DKIM failures and
TLS negotiations. They shipped **off**, because the IP was Barracuda-listed
behind a generic pool PTR and unsolicited volume to parties with no
relationship to us was the last thing it needed. Both halves of that premise
expired — the delisting took, Vodafone set the PTR, and the delivery gate
passed — so they were turned on in a **separate** change from the one that
proved delivery, deliberately, rather than putting two untested things in one
deploy.

**If deliverability ever degrades, switch these back off first** — before the
smarthost, before anything else. They are the only outbound traffic this server
generates that nobody asked for, so they are the cheapest thing to stop.

**Receiving** reports was never affected: that is a property of our own
`_dmarc` record and has worked since the day it was published. Note that
`_smtp._tls` is still unpublished (it waits on MTA-STS), so nothing is asking
us for TLS reports about ourselves yet either.
