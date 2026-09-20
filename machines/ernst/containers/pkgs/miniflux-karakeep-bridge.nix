# machines/ernst/containers/pkgs/miniflux-karakeep-bridge.nix
#
# karakeep-miniflux-webhook — M28.  A 375-line Go HTTP server that receives
# Miniflux's webhook and creates Karakeep bookmarks from it.  It is what makes
# "subscribe in Miniflux, consume in Karakeep" an actual pipeline rather than a
# pair of tabs.
#
# ── WHY THIS EXISTS AT ALL, WHICH IS NOT OBVIOUS ────────────────────────────
#
#   Karakeep subscribes to RSS natively (User Settings → RSS Subscriptions),
#   so for most people this bridge would be redundant — and M27's guide says
#   exactly that.  The thing Karakeep's own feed ingestion CANNOT do is FILTER:
#   its subscriptions take a name, a URL, an enabled flag and a tag-import
#   toggle, and nothing else.  No rules, no keyword blocking, no regex.
#
#   Miniflux can.  Per-feed block/keep rules, rewrite rules, and scraper rules
#   for feeds that publish excerpts.  So the pipeline is: Miniflux polls and
#   DECIDES, this bridge forwards what survives, Karakeep crawls, archives,
#   tags and is where a human actually reads.
#
#   THE TRACKING-PARAMETER POINT IS THE SECOND HALF OF THE ARGUMENT, and it is
#   the one that matters for duplicates.  Karakeep deduplicates on the EXACT
#   url — verified in its own source, `attemptToDedupLink` in
#   packages/trpc/routers/bookmarks.ts — so `?utm_source=...` produces a second
#   bookmark for the same page.  Miniflux's rewrite rules can strip those
#   before the URL is ever forwarded, which no amount of work on Karakeep's
#   side could do.
#
# ── NOT THE podman TIER, DESPITE UPSTREAM SHIPPING A Dockerfile ─────────────
#
#   Invariant #1's escape hatch is for upstreams that ship ONLY an OCI image.
#   This upstream ships Go SOURCE — one main.go, a go.mod with a single
#   dependency, and a Dockerfile as a convenience.  `buildGoModule` builds it
#   in a dozen lines, so it is an ordinary systemd unit inside an existing
#   container and takes no MAC, no address and no netns.
#
#   There is also no published image to pin: the repository has NO RELEASES
#   and no registry package (checked 2026-09-20).  The podman tier's
#   digest-pinning discipline would have nothing to bite on, which is a second
#   and independent reason not to use it.
#
# ── PINNED TO A REVISION, AND THE REPOSITORY IS QUIET ───────────────────────
#
#   Last commit 7c81f23f, 2025-05-18 — the rename from "hoarder" to
#   "karakeep".  Sixteen months without a commit.  That is stated rather than
#   hidden because it is the main risk this file carries: if Karakeep's API or
#   Miniflux's webhook payload changes shape, nobody upstream is watching.
#
#   What makes that acceptable is size.  The whole program is 375 lines doing
#   one thing: verify an HMAC, unmarshal a payload, POST to
#   /api/v1/bookmarks.  If it breaks, it is readable in an afternoon and
#   replaceable in a day — which is a very different bet from an unmaintained
#   application.
#
# ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────
#
#   No duplicate detection of its own, and it needs none: Karakeep's API
#   dedupes on URL and, per an explicit guard in that source, re-submitting an
#   already-ARCHIVED bookmark stays a no-op rather than unarchiving it.  So a
#   feed re-announcing an old entry cannot resurrect something already read and
#   filed.  Upstream Karakeep notes the dedup is not race-proof; at one
#   webhook delivery at a time that is not a shape this deployment can hit.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "miniflux-karakeep-bridge";

  # No upstream version exists — no tags, no releases — so the date of the
  # pinned revision IS the version.  Inventing a "1.0.0" here would imply a
  # release that never happened.
  version = "0-unstable-2025-05-18";

  src = fetchFromGitHub {
    owner = "mathpn";
    repo  = "karakeep-miniflux-webhook";
    rev   = "7c81f23f45409de80de84e5a2b2afa6fbaf0bec0";
    hash  = "sha256-RpifUa8EN+AOMp6kRl2KRdYplRo5DVgKLGvSqUg1JpM=";
  };

  vendorHash = "sha256-NHTKwUSIbNCUco88JbHOo3gt6S37ggee+LWNbHaRGEs=";

  # The module is literally named `main`, so the built binary would be called
  # `main` and land in the container's PATH as that.  Renamed here rather than
  # worked around in the unit, because a binary called `main` on a system PATH
  # is a trap for whoever greps for it next.
  postInstall = ''
    mv "$out/bin/main" "$out/bin/miniflux-karakeep-bridge"
  '';

  meta = with lib; {
    description = "Webhook bridge that saves Miniflux entries to Karakeep";
    homepage    = "https://github.com/mathpn/karakeep-miniflux-webhook";
    license     = licenses.agpl3Only;
    mainProgram = "miniflux-karakeep-bridge";
    platforms   = platforms.linux;
  };
}
