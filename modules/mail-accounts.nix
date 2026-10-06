# modules/mail-accounts.nix
#
# The @goclan.org mailbox passwords (M31), as one SHARED clan-vars generator.
#
# ── WHY THIS IS NOT IN machines/ernst/containers/mail.nix WITH EVERYTHING ──
#    ELSE ABOUT MAIL
#
#   Because two different machines have to read it, and a clan var is only
#   deployed to a machine whose configuration DECLARES the generator.  ernst
#   needs every mailbox's password hash to hand to Dovecot; miralda and jens
#   need lutz's plaintext for aerc's `passwordCommand`, because IMAP and SMTP
#   AUTH send the password itself and there is no other shape that works.
#
#   Declaring the generator twice — once in the container file, once beside
#   lgo — is not an option: `script` and `prompts` are unique options, so two
#   definitions are an evaluation conflict.  And splitting it into two
#   generators is worse than it looks, because each would carry its OWN prompt
#   for lutz's password and nothing would keep the two answers equal.  A
#   silently diverged pair means aerc authenticating with a password the
#   server has never heard of, and the only symptom is a login failure that
#   looks like a typo.
#
#   So: one module, one generator, imported by both consumers.  Nix dedupes
#   `imports` by path, so importing it from mail.nix and from users/lgo.nix is
#   one declaration, not two.
#
# ── IT IS NOT IN commonBase, AND THAT IS THE POINT ─────────────────────────
#
#   The fleet-wide-import-plus-inert-option pattern (modules/hardware/
#   convertible.nix) is right for a feature.  It is wrong for the household's
#   mail passwords: every machine that declares this generator has the secret
#   decryptable on disk, and biene and birte have no use for it.  This module
#   is imported by exactly the three machines that do.
#
# ── ONLY lutz's PLAINTEXT IS EMITTED ───────────────────────────────────────
#
#   The other four exist only as hashes.  admin is used from a terminal on
#   ernst; Sarinah, Max and the couch account each type theirs into a client
#   once and the client keeps it.  None needs a machine-readable copy, so none
#   gets one — the exposure is the part that is cheap to avoid.
#
#   lutz's plaintext DOES land on ernst as well, because clan deploys every
#   file of a declared generator to every machine declaring it and there is no
#   per-machine file subset.  That is a real cost, and a small one in this
#   case specifically: ernst is the machine holding every message in the
#   mailbox the password protects.
{ config, lib, pkgs, ... }:

let
  cfg = config.clanarchy.mail.accounts;

  # ── THE MAILBOXES, AS DATA ────────────────────────────────────────────────
  #
  #   `key` is the prompt and file name; `address` is the mailbox it hashes a
  #   password for.  They differ for everyone except `admin` and `go`, because
  #   the fleet identifies people by a three-letter username and addresses them
  #   by their first name — see containers/mail.nix for the alias table that
  #   makes both forms deliver.
  #
  #   THE KEY IS NOT THE ADDRESS ON PURPOSE.  A clan-vars file name ends up in
  #   a sops path, a staging script and a systemd unit; keeping `@` and dots out
  #   of it means none of those have to quote anything.
  #
  #   `plaintext` means "also emit the password in the clear, not just its
  #   hash".  Exactly one mailbox sets it: aerc on miralda and jens
  #   authenticates with `passwordCommand`, and IMAP and SMTP AUTH send the
  #   password itself, so there is no hash-only shape that works.  Everyone
  #   else types theirs into a client once and the client keeps it.
  mailboxes = [
    { key = "admin";   address = "admin@goclan.org";   plaintext = false;
      note = "also postmaster@/abuse@/hostmaster@/dmarc@"; }
    { key = "lutz";    address = "lutz@goclan.org";    plaintext = true;
      note = "aerc on miralda and jens reads this"; }
    { key = "sarinah"; address = "sarinah@goclan.org"; plaintext = false;
      note = "Sarinah types this into K-9"; }
    { key = "max";     address = "max@goclan.org";     plaintext = false;
      note = "Max's mailbox"; }
    { key = "go";      address = "go@goclan.org";      plaintext = false;
      note = "the couch/admin account"; }
  ];
in
{
  options.clanarchy.mail.accounts = {
    enable = lib.mkEnableOption "the shared @goclan.org mailbox password generator";

    plaintextOwner = lib.mkOption {
      type    = lib.types.str;
      default = "root";
      example = "lgo";
      description = ''
        Unix user that owns `lutz.plain` on this machine.

        aerc runs as `lgo` and reads this file through `passwordCommand`, so
        on miralda and jens it must be `lgo`; the file is 0400 and root
        ownership would mean aerc could not read it.  On ernst there is no
        `lgo` and nothing reads the plaintext, so it stays `root` — naming a
        user that does not exist on the machine is a sops-nix activation
        failure, not an eval error, which is the sort that surfaces during a
        deploy rather than during a build.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    ############################################################################
    # The three mailbox passwords.
    #
    # ITS OWN GENERATOR, NOT MORE PROMPTS ON AN EXISTING ONE.  clan treats a
    # generator as satisfied when every file it DECLARES exists; prompts are
    # inputs and only files are state, so adding a prompt to a satisfied
    # generator asks for NOTHING at the next `clan vars generate`.  That is
    # what happened to `homepage-tokens` on 2026-09-19.
    #
    # `share = true` for the reason in this file's header — one password per
    # mailbox across the fleet, not one per machine.
    #
    # ── IT IS PROMPTED, SO IT BLOCKS EVERY DEPLOY UNTIL IT IS GENERATED ─────
    #
    #   `clan vars generate` runs generators for ALL machines, and
    #   `clan machines update` refuses to proceed with a prompt outstanding —
    #   in a non-interactive shell that surfaces as a `termios.error` rather
    #   than as "you owe me a password".  Generate this once, in a real
    #   terminal, before the first deploy of ANY machine after this lands.
    ############################################################################
    clan.core.vars.generators.mail-accounts = {
      share = true;

      # One `<key>.hash` per mailbox, plus `lutz.plain`.  Built from the
      # `mailboxes` list above rather than written out five times, so adding a
      # sixth mailbox is one line in one place and cannot half-land.
      files = lib.listToAttrs (
        (map (m: lib.nameValuePair "${m.key}.hash" {
          secret       = true;
          restartUnits = [ "mail-secrets.service" "container@mail.service" ];
        }) mailboxes)
        ++
        # Consumed by aerc on miralda and jens — see
        # machines/miralda/home-modules/console-desktop.nix.  No restartUnits:
        # nothing on ernst reads it, and aerc re-runs passwordCommand on every
        # start, so there is no daemon to poke.
        (map (m: lib.nameValuePair "${m.key}.plain" {
          secret = true;
          owner  = cfg.plaintextOwner;
          mode   = "0400";
        }) (lib.filter (m: m.plaintext) mailboxes))
      );

      prompts = lib.listToAttrs (map (m: lib.nameValuePair m.key {
        description = "Password for ${m.address} — ${m.note} (min 12 chars)";
        type        = "hidden";
      }) mailboxes);

      runtimeInputs = [ pkgs.mkpasswd pkgs.coreutils ];

      # `mkpasswd -s` reads the password on stdin and picks libxcrypt's
      # strongest available scheme (yescrypt at this pin).  Dovecot verifies
      # it through {CRYPT}, so the writer and the verifier agree without
      # either being told which scheme was used — the same property
      # containers/authelia.nix gets by hashing with Authelia's own binary.
      #
      # THE 12-CHARACTER FLOOR IS ENFORCED, NOT DOCUMENTED, and it is more
      # load-bearing than Authelia's: :465 and :993 answer the whole internet,
      # and the only thing between a guessed password and the household's mail
      # is fail2ban's five tries an hour.
      #
      # A BLANK ANSWER IS NOT AN OPTIONAL CREDENTIAL.  It stores nothing,
      # `.path` becomes the literal /no-such-path, and every later deploy
      # re-prompts — fatal without a TTY.  The length check catches that as a
      # side effect and says so in words rather than in a stack trace.
      # The loop is generated from the same `mailboxes` list the files and
      # prompts come from, so the three can never disagree about which
      # mailboxes exist — a hand-written `for a in …` is exactly the line
      # somebody forgets to extend.
      script = ''
        set -euo pipefail

        hash_one() {
          key="$1"; addr="$2"
          pw=$(cat "$prompts/$key")
          if [ "''${#pw}" -lt 12 ]; then
            echo "  ✗ $addr: password is ''${#pw} characters, minimum is 12." >&2
            echo "    :465 and :993 are reachable from the internet; this is not a formality." >&2
            exit 1
          fi
          printf '%s' "$pw" | mkpasswd -s > "$out/$key.hash"
          if [ ! -s "$out/$key.hash" ]; then
            echo "  ✗ $addr: mkpasswd produced nothing." >&2
            exit 1
          fi
        }

        ${lib.concatMapStringsSep "\n" (m: ''hash_one ${m.key} ${m.address}'') mailboxes}

        ${lib.concatMapStringsSep "\n"
            (m: ''printf '%s' "$(cat "$prompts/${m.key}")" > "$out/${m.key}.plain"'')
            (lib.filter (m: m.plaintext) mailboxes)}
      '';
    };
  };
}
