#!/usr/bin/env bash
# post-deploy-check.sh <machine> — what to look at after `clan machines update`.
#
# Usage:
#   ./scripts/post-deploy-check.sh ernst
#
# ── WHY THIS EXISTS AS A SCRIPT ─────────────────────────────────────────────
#
# The repo's own rule is one deploy per ROUND of findings, not one per finding
# (M32 cost six). That only works if the whole round is gathered in one pass,
# and a checklist in a document does not get followed the same way twice.
#
# Every check here answers a question that a green `systemctl status` does not:
#
#   - the host's `systemctl --failed` is clean whether or not a unit INSIDE a
#     container died, so each container is asked separately;
#   - `--collect` on the probe is required, or the probe unit itself lingers
#     and fires a false ContainerSystemdUnitFailed alert (four of those on
#     2026-09-27);
#   - a container with no VLAN tag is simply unreachable while every
#     indicator says healthy, so the bridge ports are counted;
#   - and the running generation is compared against the wanted one, because
#     a deploy that silently shipped stale code looks exactly like a deploy
#     that worked.
set -uo pipefail

m="${1:?usage: post-deploy-check.sh <machine>}"
host="${2:-10.0.50.10}"
fail=0

say() { printf '\n── %s\n' "$1"; }
bad() { printf '   !! %s\n' "$1"; fail=1; }
ok()  { printf '   ok %s\n' "$1"; }

# ── REACHABILITY FIRST, AND SAY WHY IF NOT ─────────────────────────────────
#
# Every section below is an ssh round trip. Without this preflight, an
# unreachable host means six sections that each hang for their own timeout and
# then report "could not read" without saying what went wrong — which is how
# this script's first run spent a minute telling me nothing useful.
#
# The failure worth naming is the YubiKey one: a key the agent lists and a card
# gpg can read will still refuse to SIGN when pinentry cannot prompt, and the
# message for that is `agent refused operation`, not anything about the host.
say "reachability"
# `timeout` around the whole call, not just ConnectTimeout: the TCP connect
# succeeds and then AUTH hangs — a YubiKey that cannot sign takes about a
# minute to give up, which ConnectTimeout does not bound at all.
sshout=$(timeout 20 ssh -o ConnectTimeout=8 -o BatchMode=yes -o NumberOfPasswordPrompts=0 "root@${host}" true 2>&1)
rc=$?
hung=0
if [ "$rc" -eq 124 ]; then
  hung=1
  sshout="${sshout}${sshout:+ }timed out after 20s — auth hung, same symptom"
fi
if [ -n "$sshout" ]; then
  bad "cannot ssh to root@${host}:"
  printf '%s\n' "$sshout" | sed 's/^/      /'
  # The hint fires on the explicit message AND on a hang, because a YubiKey
  # that cannot sign usually hangs first and only sometimes gets as far as
  # printing `agent refused operation`.
  case "$sshout$hung" in
    *"agent refused operation"*|*1)
      cat >&2 <<'HINT'

   The YubiKey is not signing. The card itself is usually fine — check with
   `gpg --card-status`, which needs no PIN. If that works, it is the pinentry
   path, and the fix is from a terminal with a TTY:

       export GPG_TTY=$(tty)
       gpgconf --kill gpg-agent && gpg --card-status    # touch/PIN when asked
       ssh root@HOST true

   If `gpg --card-status` ALSO fails, it is the other failure: something else
   holds the CCID interface (yubioath-flutter is the usual culprit). Check
   `journalctl -u pcscd -n 20` for LIBUSB_ERROR_BUSY.
HINT
      ;;
  esac
  echo
  echo "post-deploy-check: host unreachable; nothing else was checked." >&2
  exit 1
fi
ok "ssh works"

say "generation: wanted vs running"
want=$(nix eval --no-update-lock-file --raw \
  ".#nixosConfigurations.${m}.config.system.build.toplevel" 2>/dev/null)
have=$(ssh -o ConnectTimeout=8 "root@${host}" readlink /run/current-system 2>/dev/null)
if [ -z "$want" ] || [ -z "$have" ]; then
  bad "could not read one of the two paths (want='$want' have='$have')"
elif [ "$want" = "$have" ]; then
  ok "$(basename "$have")"
else
  bad "DRIFT — the deploy did not land what this tree evaluates to"
  printf '      want %s\n      have %s\n' "$want" "$have"
fi

say "host units"
hf=$(ssh -o ConnectTimeout=8 "root@${host}" 'systemctl --failed --no-legend' 2>/dev/null)
if [ -z "$hf" ]; then ok "none failed"; else bad "failed on the host:"; printf '%s\n' "$hf"; fi

say "units inside every container"
# `--collect` is not optional: without it the probe unit lingers as a failed
# unit and alerts on itself.
ssh -o ConnectTimeout=20 "root@${host}" '
  for c in $(machinectl list --no-legend | awk "{print \$1}"); do
    out=$(systemd-run --machine="$c" --collect --pipe --quiet \
            systemctl --failed --no-legend 2>&1)
    if [ -n "$out" ]; then printf "   !! %s:\n%s\n" "$c" "$out"; else printf "   ok %s\n" "$c"; fi
  done' 2>/dev/null || bad "could not enumerate containers"

say "podman containers"
ssh -o ConnectTimeout=10 "root@${host}" '
  for u in $(systemctl list-units --no-legend "podman-*.service" | awk "{print \$1}"); do
    s=$(systemctl is-active "$u" 2>/dev/null)
    if [ "$s" = active ]; then printf "   ok %s\n" "$u"; else printf "   !! %s is %s\n" "$u" "$s"; fi
  done' 2>/dev/null || bad "could not enumerate podman units"

say "bridge VLAN tags"
# A vb-* port with no tag is a container that is up and unreachable. br0 has
# DefaultPVID = "none", so a miss is fail-closed and silent.
tagged=$(ssh -o ConnectTimeout=8 "root@${host}" "bridge vlan show | grep -c ' 90 '" 2>/dev/null)
ports=$(ssh -o ConnectTimeout=8 "root@${host}" "bridge vlan show | grep -c '^vb-'" 2>/dev/null)
printf '   %s ports tagged 90, %s vb-* ports present\n' "${tagged:-?}" "${ports:-?}"
[ "${tagged:-0}" -ge "${ports:-1}" ] || bad "fewer tags than ports — check 'bridge vlan show'"

say "the dirs units that guard a dataset"
# These REFUSE rather than create when a mount is wrong, so an inactive one is
# a service whose state would have landed on a filesystem that rolls back.
ssh -o ConnectTimeout=10 "root@${host}" '
  for u in $(systemctl list-units --no-legend "*-dirs.service" | awk "{print \$1}"); do
    s=$(systemctl show -p Result --value "$u" 2>/dev/null)
    if [ "$s" = success ]; then printf "   ok %s\n" "$u"; else printf "   !! %s result=%s\n" "$u" "$s"; fi
  done' 2>/dev/null || bad "could not enumerate dirs units"

printf '\n'
if [ "$fail" -eq 0 ]; then
  echo "post-deploy-check: nothing to report."
else
  echo "post-deploy-check: findings above. Batch them into ONE fix PR —" >&2
  echo "  the repo's rule is one deploy per round, not one per finding." >&2
  exit 1
fi
