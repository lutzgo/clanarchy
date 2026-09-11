# machines/ernst/containers/pkgs/picons.nix
#
# Channel logos for Tvheadend (and therefore for Kodi on the TV, which reads
# them over HTSP).  Upstream's `utf8snp` pack, RENAMED to the exact scheme
# Tvheadend generates — because those two are not the same scheme, and the
# difference is 27 channels.
#
# ── THE SOURCE THE BRIEF NAMED IS GONE ──────────────────────────────────────
#
#   picons.xyz — the site every Tvheadend guide points at — is a PARKED
#   DOMAIN as of 2026-09-11: it 307s to a GoDaddy "for sale" page.  The
#   project itself is alive and is github.com/picons/picons (303 stars, pushed
#   the same day), which publishes DATED RELEASES with stable asset URLs.  So
#   this pins a release asset rather than scraping a website, which it could
#   not have done anyway.
#
# ── `snp` NO LONGER EXISTS EITHER.  IT IS `utf8snp` NOW ─────────────────────
#
#   The project replaced the ASCII-only `snp` scheme with `utf8snp` after an
#   OpenPLi change in April 2024 gave Enigma2 unicode picon names.  Every guide
#   still says "download the snp pack"; there is no snp pack.
#
#   THAT MATTERS BECAUSE TVHEADEND DID NOT FOLLOW.  `svcnamepicons()` in
#   src/channels.c (read at rev 45cbe4a, the rev containers/pkgs/tvheadend.nix
#   pins) is unchanged and brutally ASCII:
#
#       '&' -> "and"    '+' -> "plus"    '*' -> "star"
#       'A'-'Z'         -> lower-cased
#       'a'-'z', '0'-'9'-> kept
#       EVERYTHING ELSE -> DROPPED, one byte at a time
#
#   The last clause is the interesting one: it discards bytes, not characters,
#   so a UTF-8 'ü' does not become 'u' — it vanishes.  `TRT Türk` becomes
#   `trttrk`, `Antenne Düsseldorf` becomes `antennedsseldorf`, and
#   `HOME & GARDEN TV` becomes `homeandgardentv`.
#
# ── SO THE PACK IS RENAMED HERE, AND IT IS WORTH 27 CHANNELS ────────────────
#
#   Measured against the 198 channels ernst's Tvheadend actually carries
#   (`/api/channel/grid` on the running instance, 2026-09-11):
#
#       pack as shipped, matched by name  : 131 / 198   (66%)
#       pack renamed with svcnamepicons   : 158 / 198   (80%)
#
#   …except 158 is WRONG, and finding out why is the reason this file drops
#   empty keys. See below.
#
# ── THE EMPTY-KEY COLLISION, WHICH WOULD HAVE SHIPPED FIVE WRONG LOGOS ──────
#
#   Vodafone's bouquet contains five channels literally named `.`, `..`,
#   `...`, `....` and `.....`.  `svcnamepicons` drops every one of those
#   characters, so all five normalise to the EMPTY STRING.
#
#   And so do twelve files in the pack — `рада.png`, `перший.png`,
#   `κρήτη νέα τηλεόραση.png` and friends, whose names are entirely non-ASCII.
#
#   A naive rename therefore produces `.png`, and Tvheadend would cheerfully
#   serve a Ukrainian or Greek station logo for five junk channels.  Dropping
#   empty keys on both sides is what makes the honest number **153 / 198**
#   rather than 158 — the five "extra" matches were all wrong.
#
#   Broken down, which is the number worth knowing:
#
#       TV channels    104 / 117   (88%)
#       radio           49 /  81   (60%)
#       all            153 / 198   (77%)
#
#   The eight unmatched TV channels are almost all foreign-language — TRT Türk,
#   Halk TV, Tunisie 1, Kanal Avrupa, TVR, 1+1 International, Nederland 2 —
#   plus WDR HD Düsseldorf.  Radio is the weak half and always will be: the
#   pack is built for satellite TV bouquets.
#
# ── COLLISIONS, AND WHY THE TIE-BREAK IS EXPLICIT ──────────────────────────
#
#   Normalising 32,432 names into 23,376 keys means collisions — up to six
#   files per key (`viju tv1000.png`, `vijutv1000русское.png`, … all become
#   `vijutv1000`).  A build that picked whichever `find` happened to yield
#   first would not be reproducible, so the rule is stated and enforced:
#
#     1. a file whose name is ALREADY the normalised form wins (the pack ships
#        both `00s heroes.png` and `00sheroes.png`, and the latter is the one
#        upstream intends for ASCII lookups);
#     2. otherwise the lexicographically smallest name wins.
#
# ── SIZE: 98 MB, AND THE WHOLE SET IS SHIPPED DELIBERATELY ─────────────────
#
#   23,376 logos to serve 153 channels. Filtering to the current lineup would
#   cost under a megabyte — and would silently produce a blank logo the day
#   Vodafone adds a channel, with a rebuild needed before anyone could fix it.
#   Against 55 TB free on zdata, the whole set is the cheaper mistake.
{
  lib,
  stdenvNoCC,
  fetchurl,
  python3,
  xz,
}:

let
  # Dated release tag. Assets under a GitHub release have stable URLs, unlike
  # the "latest" redirect, so this is pinnable.
  release = "2026-09-06--00-52-42";

  # 220x132 rather than 100x60: this is read on a television, from a sofa.
  # light.on.transparent rather than dark: Kodi's Estuary skin is dark, and a
  # dark logo on a dark background is an invisible logo.
  # hardlink rather than symlink: the symlink variant's links can point outside
  # the extracted tree, which is a fetchurl unpacking hazard for no benefit
  # here — this derivation copies the files it keeps anyway.
  variant = "utf8snp-full.220x132-190x102.light.on.transparent";
in
stdenvNoCC.mkDerivation {
  pname = "picons-tvheadend-svcname";
  version = release;

  src = fetchurl {
    url = "https://github.com/picons/picons/releases/download/${release}/${variant}_${release}.hardlink.tar.xz";
    hash = "sha256-QVQNGj4kNMphP7sjL1B9ar37kLqq769k6fSN+bQoShA=";
  };

  nativeBuildInputs = [ python3 xz ];

  dontConfigure = true;
  dontFixup = true;

  # `tar` unpacks into a single versioned directory; the rename pass below
  # walks whatever it finds rather than hard-coding that name, so a future
  # release that changes the layout fails loudly on "no PNGs" instead of
  # silently producing an empty output.
  unpackPhase = ''
    runHook preUnpack
    mkdir -p source
    tar -xJf "$src" -C source
    runHook postUnpack
  '';

  buildPhase = ''
    runHook preBuild
    python3 "$rename" source "$out/picons"
    runHook postBuild
  '';

  installPhase = "true";  # buildPhase writes straight into $out

  # A port of tvheadend's svcnamepicons(), byte for byte. If Tvheadend ever
  # changes that function, THIS IS THE FILE THAT HAS TO CHANGE WITH IT, and
  # the symptom of forgetting would be logos quietly disappearing rather than
  # an error.
  rename = builtins.toFile "picon-rename.py" ''
    import os, sys, pathlib, collections

    def svcnamepicons(s):
        """Exact port of tvheadend src/channels.c:svcnamepicons().

        Operates on BYTES, like the C does: a multi-byte character is dropped
        entirely rather than transliterated. That is why 'Türk' -> 'trk'.
        """
        out = []
        for b in s.encode("utf-8"):
            c = chr(b)
            if   c == '&': out.append("and")
            elif c == '+': out.append("plus")
            elif c == '*': out.append("star")
            elif 'a' <= c <= 'z': out.append(c)
            elif 'A' <= c <= 'Z': out.append(c.lower())
            elif '0' <= c <= '9': out.append(c)
        return "".join(out)

    src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    pngs = sorted(src.rglob("*.png"))
    if not pngs:
        sys.exit("picons: no PNGs under %s — the release layout changed" % src)

    keys = collections.defaultdict(list)
    dropped_empty = 0
    for p in pngs:
        stem = p.name[:-4]
        k = svcnamepicons(stem)
        if not k:
            # Entirely non-ASCII names normalise to nothing. Keeping them would
            # create a single ".png" that Tvheadend serves for every channel
            # whose name is pure punctuation — see this file's header.
            dropped_empty += 1
            continue
        keys[k].append(p)

    dst.mkdir(parents=True, exist_ok=True)
    collisions = 0
    for k, group in sorted(keys.items()):
        if len(group) > 1:
            collisions += 1
        # Tie-break, in order: the file already named exactly the normalised
        # form, else the lexicographically smallest. Deterministic by
        # construction, which a build has to be.
        exact = [p for p in group if p.name[:-4] == k]
        pick = sorted(exact or group, key=lambda p: p.name)[0]
        (dst / (k + ".png")).write_bytes(pick.read_bytes())

    print("picons: %d source files -> %d logos "
          "(%d empty-name dropped, %d keys had collisions)"
          % (len(pngs), len(keys), dropped_empty, collisions))
  '';

  meta = {
    description = "Channel logos renamed to Tvheadend's service-name scheme";
    longDescription = ''
      The picons project's utf8snp pack, with every file renamed through a port
      of tvheadend's own svcnamepicons(). Consumed by
      machines/ernst/containers/tvheadend.nix, which bind-mounts it at the
      stable path /picons inside the container.
    '';
    homepage = "https://github.com/picons/picons";
    # UPSTREAM'S OWN DECLARATION, not an inference. github.com/picons/picons
    # ships a LICENSE file and GitHub reports it as GPL-3.0, so that is what
    # goes here.
    #
    # An earlier draft of this file said `unfree`, reasoning that the artwork
    # is broadcaster trademarks and therefore cannot be freely licensed. That
    # reasoning is not wrong about trademarks — but it is a claim UPSTREAM DOES
    # NOT MAKE, and encoding someone else's licence as stricter than they
    # declare it is as much an error as the reverse. It also broke the build
    # for no reason. The trademark point stands as a fact about the content and
    # is recorded here rather than as a licence attribute: these are channel
    # logos used to identify those same channels on a household TV.
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}
