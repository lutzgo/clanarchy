# machines/ernst/containers/pkgs/questarr.nix
#
# Questarr — M14.  An *arr-shaped manager for GAMES: it discovers titles
# through IGDB, tracks a library, and grabs releases through Prowlarr's
# Torznab/Newznab indexers.
#
# Not in nixpkgs — no package and no module, surveyed against ernst's own pin
# on the session date (2026-08-28, nixpkgs fcb8fcd).
#
# ── THIS IS THE ONLY DERIVATION IN M14 THAT IS A REAL BUILD ───────────────
#
#   docs/roadmap.md's packaging rule is "take the upstream release artifact
#   when there is one".  Here there is NOT one: v1.4.2 (2026-08-11) publishes
#   an EMPTY assets array — the only distribution channel is an OCI image.
#   Checked against the releases API on 2026-08-28, not inferred from the
#   README.
#
#   So this builds from source, and the build is genuine: a Vite/React/Tailwind
#   frontend bundle plus a `tsc` pass over an Express server, exactly the step
#   docs/roadmap.md's Storyteller note says Docker performs invisibly and a
#   from-source install has to perform by hand.
#
#   It stops well short of Storyteller, though, and the difference is why this
#   one is packaged and that one is not: Questarr's build is plain npm with a
#   committed package-lock.json and ONE native module.  Storyteller needs yarn
#   workspaces, whisper.cpp binaries and a Readium binary lifted out of a
#   separate container image.  See containers/storyteller.nix.
#
# ── THE ROADMAP'S "SQLite-BACKED" PREMISE SURVIVED CHECKING.  ITS SOURCE ───
#   DID NOT ────────────────────────────────────────────────────────────────
#
#   Worth recording because the public write-ups disagree with upstream: a
#   widely-syndicated review of Questarr describes it as PostgreSQL-backed, and
#   docs/roadmap.md says SQLite.  The roadmap is right and the review is stale —
#   upstream removed PostgreSQL in favour of SQLite's zero-configuration setup,
#   and v1.4.2's dependency list carries `better-sqlite3` and `drizzle-orm` with
#   no pg driver at all.
#
#   That matters beyond trivia: a Postgres requirement would have needed a
#   database server in the arr container, which is a thing this repo has
#   deliberately never added (it is why M13 deferred Jellystat).
#
# ── better-sqlite3 IS A NATIVE MODULE AND MUST BE BUILT, NOT DOWNLOADED ───
#
#   Its install script normally fetches a prebuilt binary through
#   `prebuild-install`.  There is no network in a Nix build sandbox, so that
#   path cannot work; `npm_config_build_from_source` makes it compile with
#   node-gyp instead, which is why python3 and node-gyp are build inputs.
#
#   Leaving it to the fallback would "work" — prebuild-install fails soft and
#   node-gyp runs anyway — but only by accident, and a soft failure that
#   happens to reach the right outcome is the kind of thing that changes
#   silently on a dependency bump.
#
# ── node-7z NEEDS A 7z BINARY ON PATH AT RUN TIME ─────────────────────────
#
#   `node-7z` is a wrapper around the 7-Zip EXECUTABLE, not a decompressor in
#   its own right; Questarr uses it to unpack multi-part game archives.  npm
#   cannot express that dependency, so nothing in the build fails without it —
#   the failure appears at the first extraction, in a service that has by then
#   already downloaded the file.  The wrapper below puts p7zip on PATH.
#
# ── THE UNIT MUST SUPPLY A WRITABLE WorkingDirectory.  THIS IS NOT OPTIONAL ─
#
#   READ THIS BEFORE CHANGING THE WRAPPER.  Questarr resolves TWO things from
#   `process.cwd()`, and they pull in opposite directions:
#
#     dist/server/migrate.js:148   path.resolve(process.cwd(), "migrations")
#     dist/server/logger.js:33     destination: "./server.log"   (mkdir: true)
#     dist/server/routes.js:274    path.resolve(process.cwd(), "server.log")
#
#   So the working directory has to CONTAIN the migrations AND be WRITABLE.
#   Neither a `--chdir` into the store nor a bare state directory satisfies
#   both, and both failures are real and were measured here:
#
#     --chdir into $out          "EROFS: read-only file system, open
#                                './server.log'" — after the migrations had
#                                already run and seeded 21 rows, so it dies
#                                half-initialised.
#     no migrations in cwd       "Migrations journal not found at:
#                                <cwd>/migrations/meta/_journal.json".
#
#   The wrapper therefore sets NO working directory at all, deliberately.
#   containers/arr.nix supplies `WorkingDirectory=/var/lib/questarr` and a
#   tmpfiles `L+` rule symlinking `migrations` from this store path into it —
#   the same shape the game-library symlinks use, and `L+` because the store
#   path changes on every upgrade and the link has to be re-forced.
#
#   There is no environment variable for either path; upstream assumes the
#   Docker image's `/app` working directory, which is writable and contains the
#   migrations because the image copies both into one layer.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  node-gyp,
  python3,
  makeWrapper,
  p7zip,
}:

buildNpmPackage rec {
  pname = "questarr";
  version = "1.4.2";

  src = fetchFromGitHub {
    owner = "Doezer";
    repo = "Questarr";
    tag = "v${version}";
    hash = "sha256-w2/2qdoLSwO4uE65yEBEtUY4o/UUzk13bxQwaQcSbK4=";
  };

  npmDepsHash = "sha256-sYHojPg+XUvIWjzahAc+FhhNqYDDrrzhhm0OZVpnuQo=";

  nativeBuildInputs = [
    makeWrapper
    node-gyp
    python3
  ];

  # See the header.  Forces better-sqlite3 down the node-gyp path instead of
  # the prebuild-install one, which cannot work without network.
  env.npm_config_build_from_source = "true";

  # `npm run build` = `vite build && tsc -p tsconfig.build.json`: the first
  # emits the client bundle, the second the server JS.  Both land under dist/.
  npmBuildScript = "build";

  # The default install hook expects a package that installs itself through
  # npm.  This one is an application: it is started as
  # `node dist/server/index.js` with its node_modules beside it, so the tree is
  # placed by hand.
  #
  # `npm prune --omit=dev` first — the dev tree is Vite, TypeScript, Vitest and
  # Playwright, none of which a running server imports.  It is the difference
  # between shipping the build system and shipping the build.
  installPhase = ''
    runHook preInstall

    npm prune --omit=dev $npmPruneFlags

    mkdir -p $out/lib/questarr

    # `migrations/` is NOT optional and NOT compiled in.  The server runs the
    # Drizzle migrations on every start, reading them off disk RELATIVE TO ITS
    # WORKING DIRECTORY — which is why the wrapper below sets --chdir.
    #
    # It is copied unconditionally, with no `if [ -d ... ]` guard, deliberately:
    # if upstream renames this directory the build must fail here rather than
    # produce a package that starts and then dies with "Migrations journal not
    # found at: <store path>/migrations/meta/_journal.json".  That was the
    # actual first failure of this derivation — a guarded copy of the WRONG
    # name (`drizzle/`, which is what the config file is called) succeeded
    # silently and moved the error to run time.
    cp -r dist node_modules package.json migrations $out/lib/questarr/

    # NO --chdir.  See the WorkingDirectory section of the header: the process
    # needs a cwd that is both writable and holds `migrations/`, and only the
    # unit can provide that.
    makeWrapper ${lib.getExe nodejs} $out/bin/questarr \
      --add-flags "$out/lib/questarr/dist/server/index.js" \
      --set NODE_ENV production \
      --prefix PATH : ${lib.makeBinPath [ p7zip ]}

    runHook postInstall
  '';

  meta = {
    description = "Game library manager and downloader for the *arr suite";
    homepage = "https://github.com/Doezer/Questarr";
    license = lib.licenses.gpl3Only;
    mainProgram = "questarr";
    platforms = lib.platforms.linux;
  };
}
