# The document store

`docs.goclan.org` — Paperless-ngx on ernst (M32). Scan paper with a phone,
upload it, and have it OCR'd, filed and full-text searchable from anywhere.

Declared in `machines/ernst/containers/paperless.nix`, with a second ingest
door wired into `machines/ernst/containers/nextcloud.nix`.

## The two ways in, and which one to use

**FairScan does not upload anything.** It is deliberately account-free and
cloud-free: it produces a multi-page PDF and then either shares it to another
app or saves it into a folder a storage app provides. So the question is never
"how does FairScan reach ernst" — it is "which app does FairScan hand the PDF
to". Both answers are configured.

| Door | Use it for | How |
|---|---|---|
| **Paperless Mobile** | The everyday case. Tag and name the document at upload time, and search the whole archive from the phone. | Scan → Share → Paperless Mobile |
| **The Nextcloud folder** | When you want to scan now and sort later, or when the other person's phone does not have the app. | Scan → Share → Nextcloud → `Scan Inbox`, or Save directly into that folder |

Both end in the same place. The Nextcloud folder **is** paperless's consumption
directory — `/srv/state/paperless/inbox`, mounted into Nextcloud as writable
external storage — so a file dropped there is picked up within a minute and
becomes a document with no further action.

### Expect the file to disappear from `Scan Inbox`

That is correct and is the sign it worked. Paperless consumes a scan and
unlinks it. Nextcloud is configured to notice (`filesystem_check_changes = 1`
on that mount), so the folder empties itself the next time you open it.

If scans **pile up** in `Scan Inbox` instead, paperless is not consuming — see
[Troubleshooting](#troubleshooting).

## Phone setup

Install **Paperless Mobile** from F-Droid
(`de.astubenbord.paperless_mobile`), add a server:

- Server URL: `https://docs.goclan.org`
- Username / password: the account created for you (see below)

There is a lighter alternative if the full client is more than you want:
**Paperless-NGX Android Uploader**, which adds nothing but a share target.

Both work from mobile data as well as the home wifi — that is the point of the
public hostname, and it is why the app's token exchange is exempt from
forward-auth (`docs` is an `appApiHosts` name; see
[ernst app-API ingress](ernst-app-api-ingress.md)).

## Accounts

| Who | How they log in |
|---|---|
| `admin` | A local paperless password, generated. **The recovery path** — it still works when Authelia, the OIDC registration or Traefik is what is broken. Read it with `clan vars get ernst paperless-admin/admin-pass`. |
| `lgo`, `sgo` | "Sign in with Authelia" in the browser. Those are the Authelia usernames — first initial plus surname, so Sarinah is `sgo`; she can also log in with `sarinah@goclan.org`. The account materialises on first login (`PAPERLESS_SOCIAL_AUTO_SIGNUP`) and lands in the `household` group, so there is no row in this repo to add and nothing to grant by hand. |
| `mneme` | Not a human. A read-only API token for the agent — four `view_*` permissions, no password, provisioned by `paperless-provision.service`. |

Self-registration is off and pinned off. Nobody can create an account against
the public hostname.

### What an auto-created account can do

`paperless-provision.service` creates a `household` group holding every
permission in the `documents` app — view, add, change and delete on documents,
tags, correspondents, document types, storage paths, saved views, notes, custom
fields, share links and workflows. The archive is treated as shared household
property, the way Immich and Nextcloud already are.

It deliberately holds **no** `auth` permissions: nobody in it can add users,
change group membership or grant access. That stays with the two superusers.

> **Anyone who passes Authelia's 2FA lands in this group.** `docs` is an
> `appApiHosts` name, so Authelia has no `access_control` rule for it — what
> gates the OIDC client is its own `two_factor` policy. That includes `go`, the
> couch account that autologins on the television without a password. It is a
> two-person household archive and that was the deliberate trade; the narrower
> shape, if it is ever wanted, is the same group with `delete_*` filtered out.
> **Removing the default group is not the narrower shape** — an account with no
> permissions is the 403 below, not a safe default.

**Enable paperless's own TOTP on `admin`** (Settings → account). That account is
the recovery path, and the recovery path is the one credential the portal
cannot protect.

## The Settings-once list

Things that live in paperless's database rather than in this repo, and
therefore have to be done by hand the first time.

- **Create Sarinah's account** by having her log in with Authelia once. That is
  the whole step — she lands in the `household` group automatically and there is
  nothing to grant by hand. (This item used to say otherwise, and the gap it
  described is what produced the 403 in Troubleshooting below.)
- **TOTP on `admin`**, as above.
- **Mail rules — none.** There is deliberately no IMAP consumption; see the
  "what is deliberately not here" block in `containers/paperless.nix`.
- **Let the classifier learn.** 2.20.15 has no LLM. What it has is a
  scikit-learn classifier that suggests tags, correspondents and document types
  from *your own corrections* — so the first few dozen documents are worth
  filing properly by hand. It retrains on a schedule after that.
- **Storage paths**: not needed. `PAPERLESS_FILENAME_FORMAT` already files the
  archive as `{created_year}/{correspondent}/{title}`, which is what makes a
  ZFS snapshot restorable with `cp` and without paperless.

## Office files

`.docx`, `.odt`, `.xlsx` and friends work: `configureTika = true` brings up
Tika (text extraction) and Gotenberg (LibreOffice → PDF) on the container's own
loopback. They get a PDF preview and searchable text like anything else.

Both listen on `127.0.0.1` **inside the container** and neither is reachable
from VLAN 90.

## OCR language

`deu+eng`, German first, because tesseract tries them in order. A PDF that
already has a text layer is left alone rather than re-OCR'd
(`PAPERLESS_OCR_MODE = "skip"`), which covers most downloaded invoices.

**Changing the language is a rebuild, not a restart.** The nixpkgs module
derives tesseract's `enableLanguages` from this string by splitting on `+`, so
the separator is load-bearing — a comma builds a tesseract containing one
language called `deu,eng`.

> ### Do not change OCR settings in the web UI
>
> paperless keeps an `ApplicationConfiguration` row in its database that **wins
> over the environment**, and opening Settings in the browser and pressing Save
> writes *every* form field into it. A value declared in Nix stops applying the
> moment somebody looks at that page, and nothing says so.
>
> That happened on the first real scan: the row held `deu,eng` and `redo`,
> shadowing `deu+eng` and `skip`. The failure surfaced as
> `MissingDependencyError: OCR engine does not have language data` — which
> points at the package, not at the setting, and the package was fine.
>
> `paperless-provision.service` now resets **`language` and `mode`** to NULL on
> every deploy, so Nix owns exactly the two settings it declares. Everything
> else on that page — deskew, rotate, unpaper, output type, the barcode
> switches — is left alone and the UI keeps it.
>
> So: change OCR language or mode in `containers/paperless.nix`. Changing them
> in the UI lasts until the next deploy.

## Asking the AI about a document

mneme has two tools over the `doc0` leg, so the archive is answerable from
anywhere Assist is — the voice satellites, the Home Assistant app, and any
client pointed at mneme's Ollama endpoint.

| Tool | What it does |
|---|---|
| `document_search` | Full-text search. Returns titles and the *matching lines*, not whole documents |
| `document_read` | The text of one document by id, in numbered parts |

The split is deliberate: search is cheap and read is not, so the model finds
first and reads only what it needs. A long document comes back in parts and the
reply says how many remain — without that, the model would answer from page one
while believing it had read the whole thing.

**Ask with words that are on the paper**, not with a question. It is a
full-text index over OCR'd text, so *"Versicherung Beitrag"* finds things that
*"what does my insurance cost"* does not. The model is told this in the tool's
own description, but phrasing still helps.

### What it cannot do

**Read-only, by construction rather than by the model behaving.** The token
belongs to a non-superuser account holding four `view_*` permissions; `DELETE`,
`PATCH` and the upload endpoint were each measured answering **403** to it. The
worst a confused model can do is read the household's own paper back to it.

**It never leaves the house.** Unlike `web_search`, nothing goes to SearXNG or
the internet. Unlike `generate_image`, it evicts no model — it is a database
query against a container that is already running, so it costs nothing.

### Dates are not trustworthy, and the tool says so

Paperless guesses a document's date out of its OCR text and gets it wrong — the
first scan through this pipeline came back filed under **1983**. So
`document_search` labels the date *"auto-detected, may be wrong"* and there are
deliberately **no date filters**: a filter built on that field would silently
exclude the documents it was meant to find. The date that matters is the one
written on the paper, and that is in the text `document_read` returns.

### If it stops working

`document_search` returning *"the document archive refused mneme's token"* means
`paperless-provision.service` has failed — the staged token never reached the
database. See the troubleshooting entry below.

## Backups

Two layers, and neither is off-box:

- **ZFS snapshots** of `zdata/docs` — `com.sun:auto-snapshot=true`, frequent
  15 min / hourly 24 / daily 7 / weekly 4 / monthly 1.
- **The paperless exporter**, nightly at 02:30 into `/srv/docs/export`:
  originals plus a metadata JSON that restores *without* paperless. It stops
  the paperless services while it runs, which is why the hour is what it is.

> **There is still no off-box backup of any of this**, and this is the library
> where that matters most: the point of scanning a document is to throw the
> paper away, so unlike photographs on a phone or files on a laptop there is no
> second copy anywhere. Both layers above live on the same pool as the data.
> `zdata/backup` is reserved and deliberately uncreated.

Verify the snapshot property is actually set — `disko` applies it at creation
and never reconciles:

```bash
zfs get -r com.sun:auto-snapshot zdata
```

## Troubleshooting

**Scans pile up in `Scan Inbox` and never become documents.**
Check the consumer and the directory's mode:

```bash
systemctl status paperless-inbox
machinectl shell paperless /run/current-system/sw/bin/systemctl status paperless-consumer
stat -c '%A %U:%G' /srv/state/paperless/inbox     # want: drwxrws--- 315:3042
```

A mode other than `2770 315:3042` means Nextcloud's file landed in a group
paperless cannot read. The setgid bit is the part that usually went missing.

**Scans stay visible in `Scan Inbox` after being filed.**
The mount's change-detection option is unset. `files_external:create` — the
non-GUI path — omits it and falls back to the global default of `0` (Never):

```bash
machinectl shell nextcloud /run/current-system/sw/bin/nextcloud-occ \
  files_external:list --output=json
# then, for the Scan Inbox mount id:
machinectl shell nextcloud /run/current-system/sw/bin/nextcloud-occ \
  files_external:option <id> filesystem_check_changes 1
```

`nextcloud-provision.service` sets this on every deploy, so if it keeps
reverting, that unit is failing.

**Logged in fine, but the dashboard shows `Error loading settings — 403 — You
do not have permission to perform this action` on `/api/ui_settings/`.**

The account exists but has no permissions, which means it is not in the
`household` group. Normally that cannot happen — `PAPERLESS_SOCIAL_ACCOUNT_DEFAULT_GROUPS`
puts every new social account there — so check that the group exists at all:

```bash
machinectl shell paperless /run/current-system/sw/bin/paperless-manage shell -c "
from django.contrib.auth.models import Group, User
print([(g.name, g.permissions.count()) for g in Group.objects.all()])
print([(u.username, [g.name for g in u.groups.all()]) for u in User.objects.all()])
"
```

If the group is missing, `paperless-provision.service` has not succeeded. If it
exists and the user is simply not in it — which is the case for any account
created *before* the default group was wired — add them once in Settings →
Users & Groups, or from the shell above with `u.groups.add(g)`.

**The login page shows no "Sign in with Authelia" button.**
The OIDC provider config did not reach the container. It is staged by
`paperless-secrets.service` into an `EnvironmentFile`, not set in the Nix store,
so:

```bash
systemctl status paperless-secrets
systemctl restart paperless-secrets container@paperless
```

**Login fails at the callback with `invalid_client`.**
Authelia's problem to report, paperless's to cause. See the long note in the
Paperless client block in `containers/authelia.nix` — it names the one setting
(`token_endpoint_auth_method`) and the two-arm control that proves it before
changing anything.

**`document_search` says the archive refused mneme's token.**
`paperless-provision.service` has failed, so the staged token never reached the
database. Nothing a human uses is affected, which is why it goes unnoticed —
the only client is the agent:

```bash
machinectl shell paperless /run/current-system/sw/bin/systemctl status paperless-provision
```

**The container will not start at all.**
Almost always the dataset. `paperless-dirs` refuses rather than creating the
archive on zroot, and prints the exact `zfs create` line:

```bash
systemctl status paperless-dirs
```

See [ernst zdata datasets](ernst-zdata-datasets.md).
