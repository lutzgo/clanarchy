# machines/ernst/containers/pkgs/janitorr.nix
#
# Janitorr — M13.  Not in nixpkgs (surveyed against ernst's own pin on the
# session date, 2026-08-26: no `janitorr` attribute, no `services.janitorr`
# module).
#
# ── THIS ONE IS BUILT FROM SOURCE, AND THAT IS NOT A PREFERENCE ──────────────
#
#   Every other hand-rolled derivation in this directory fetches a RELEASE
#   ARTIFACT — umlautadaptarr.nix and cleanuparr.nix both take a published
#   linux-amd64 zip, and the argument for preferring that over a source build
#   is written out once in umlautadaptarr.nix.
#
#   Janitorr cannot do that, because UPSTREAM PUBLISHES NO ARTIFACT.  Its
#   GitHub releases carry zero assets — checked against the v2.2.0 release API
#   on 2026-08-26 — and the only distribution channel is an OCI image on
#   ghcr.io, produced by `./gradlew bootBuildImage --publishImage` in
#   .github/workflows/jvm-image.yml.  There is no jar on Maven Central, no jar
#   on GitHub Packages, and no jar attached to the tag.
#
#   The image is also not a jar wearing a container: BootBuildImage uses the
#   Paketo buildpacks (`paketobuildpacks/ubuntu-noble-builder-buildpackless`
#   plus the adoptium and java buildpacks), so what is inside is an EXPLODED,
#   layered Spring Boot application with a buildpack launcher and an AOT cache
#   — not something to unpick with `dockerTools.pullImage` and a `cp`.
#
#   And the container route is closed anyway: `virtualisation.oci-containers`
#   inside an nspawn container is REJECTED for this repo — see the packaging
#   section of docs/roadmap.md.  So source build it is.
#
# ── THE FOUR THINGS THAT MAKE THE SOURCE BUILD NON-OBVIOUS ───────────────────
#
#   1. THE JDK VENDOR IS PINNED, and that is the trap that costs the most time.
#
#      build.gradle.kts declares
#
#        kotlin { jvmToolchain {
#          languageVersion.set(JavaLanguageVersion.of(25))
#          vendor.set(JvmVendorSpec.ADOPTIUM)
#        } }
#
#      A Gradle toolchain spec with a VENDOR is matched against the vendor
#      string of each discovered JDK.  `pkgs.jdk25` is an OpenJDK build and
#      does NOT report as Adoptium, so it fails the match — and the failure
#      mode is not "no JDK found", it is that the foojay-resolver-convention
#      plugin in settings.gradle.kts tries to DOWNLOAD a matching JDK from
#      api.foojay.io.  In the Nix sandbox that is a network call, so the build
#      fails on something that reads like a connectivity problem and is really
#      a vendor mismatch.
#
#      Fixed twice over, deliberately, because one of the two is a guess about
#      a matcher we do not control:
#
#        - `temurin-bin-25` is used rather than `jdk25`.  Temurin IS Adoptium's
#          build, so it satisfies the spec as written.
#        - the `vendor.set(...)` line is patched out anyway (see postPatch),
#          and auto-download is disabled explicitly, so that a future change to
#          how Gradle reads the vendor of a Nix-built JDK cannot silently
#          reintroduce a network fetch.
#
#      auto-download=false is the load-bearing half: with it, a toolchain miss
#      FAILS LOUDLY at configure time instead of hanging on a download.
#
#   2. THE WRAPPER WANTS GRADLE 9.7.1; THE PIN HAS 9.4.1.
#
#      gradle/wrapper/gradle-wrapper.properties names 9.7.1.  ernst's nixpkgs
#      has gradle_9 = 9.4.1 (and the unsuffixed `gradle` is 8.14.4, which is
#      too old for Spring Boot 4).  nixpkgs' gradle setup-hook ignores the
#      wrapper and runs the nixpkgs gradle, so the version actually used is
#      9.4.1.
#
#      That is a REAL divergence from what upstream tests, not a formality, and
#      it is called out here so the next person reading a strange Gradle error
#      checks it first.  gradle_9 is named explicitly below rather than
#      inherited from the default `gradle`, so a nixpkgs bump of the default
#      cannot silently move this build onto Gradle 8.
#
#   3. THE VERSIONING PLUGIN READS GIT, AND THERE IS NO GIT HERE.
#
#      `net.nemerosa.versioning` derives branch and commit from a git
#      repository.  fetchFromGitHub produces a source tree with no .git, so
#      `versioning.info.commit` is empty and `.take(8)` on it yields an empty
#      string rather than throwing.  The values only feed build-info.properties
#      and the (unused) BootBuildImage tags, so an empty commit is cosmetic.
#
#      It is recorded because "why does the About page say build revision
#      nothing" has exactly one answer and it is this line.
#
#   4. FOUR MAVEN REPOSITORIES, TWO OF THEM SNAPSHOT REPOS.
#
#      settings.gradle.kts and build.gradle.kts between them name
#      gradlePluginPortal, mavenCentral, repo.spring.io/milestone and
#      repo.spring.io/snapshot.  The mitm-cache deps lock below covers all of
#      them; the snapshot repos are why the lock has to be regenerated on every
#      version bump rather than merely extended.
#
# ── UPDATING THE DEPS LOCK ───────────────────────────────────────────────────
#
#   `janitorr-deps.json` is generated, not written.  After changing `version`
#   (or anything that moves a dependency), regenerate it — the update script
#   needs network access and is therefore never part of a build:
#
#     nix run .#janitorr.mitmCache.updateScript
#
#   A stale lock presents as a build failure naming one missing artifact, which
#   is the right failure: it is loud, and it names the thing that moved.
{
  lib,
  stdenv,
  fetchFromGitHub,
  gradle_9,
  temurin-bin-25,
  temurin-jre-bin-25,
  makeWrapper,
}:

# ── DO NOT ADD A `jre_headless` ARGUMENT HERE ────────────────────────────────
#
#   The first version of this file took `jre_headless ? temurin-bin-25`, on the
#   reasoning that the `?` default documents the requirement while letting a
#   caller substitute.  It does not work, and the failure is silent at build
#   time:
#
#     callPackage supplies EVERY argument it can find in pkgs, and `jre_headless`
#     exists in nixpkgs — it is Java 21.  A `?` default is only consulted when
#     the attribute is ABSENT from pkgs, so the default was never used and the
#     wrapper was built against a JRE eight versions too old.
#
#   The derivation still built cleanly.  It failed only when the jar was RUN:
#
#     UnsupportedClassVersionError: ... has been compiled by a more recent
#     version of the Java Runtime (class file version 69.0), this version of
#     the Java Runtime only recognizes class file versions up to 65.0
#
#   Measured 2026-08-26 by running the built wrapper, which is the only thing
#   that would have caught it — `nix build` succeeding proves nothing about the
#   runtime here.  Both JVMs are now named as ordinary (defaultless) arguments,
#   so a missing one is an evaluation error rather than a wrong-version runtime.
let
  jdk = temurin-bin-25;
  jre = temurin-jre-bin-25;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "janitorr";
  version = "2.2.0";

  src = fetchFromGitHub {
    owner = "Schaka";
    repo = "janitorr";
    tag = "v${finalAttrs.version}";
    hash = "sha256-zAb2fs/+DyFOMZ+uAHlxvMUjbfkfJQ4Q9VcFz60oyNM=";
  };

  # See header item 1.  The vendor pin is removed so that toolchain resolution
  # cannot fall through to a foojay download; `temurin-bin-25` would satisfy it
  # anyway, and having both is deliberate.
  postPatch = ''
    substituteInPlace build.gradle.kts \
      --replace-fail 'vendor.set(JvmVendorSpec.ADOPTIUM)' ""
  '';

  nativeBuildInputs = [
    gradle_9
    makeWrapper
  ];

  mitmCache = gradle_9.fetchDeps {
    pkg = finalAttrs.finalPackage;
    data = ./janitorr-deps.json;
  };

  # Point Gradle at the Nix JDK and forbid it from fetching another one.  See
  # header item 1: auto-download=false is what turns a toolchain miss into a
  # loud configure-time failure instead of a sandbox network hang.
  gradleFlags = [
    "-Dorg.gradle.java.home=${jdk}"
    "-Dorg.gradle.java.installations.auto-download=false"
    "-Dorg.gradle.java.installations.paths=${jdk}"
  ];

  # bootJar, not build: `tasks.named<Jar>("jar") { enabled = false }` means the
  # plain jar task produces nothing, and `build` would additionally run the
  # test suite, which upstream's CI runs against testcontainers (i.e. Docker).
  gradleBuildTask = "bootJar";

  doCheck = false;

  installPhase = ''
    runHook preInstall

    # Found rather than globbed by name.  gradle.properties pins `version=1.0.0`
    # regardless of the release tag (see the version note in the header), and
    # BootJar sets an empty archiveClassifier — so the produced filename tracks
    # a number this derivation deliberately does NOT use.  Matching *.jar and
    # asserting there is exactly one is stable across both.
    echo "build/libs contains:" && ls -l build/libs
    jars=(build/libs/*.jar)
    [ "''${#jars[@]}" -eq 1 ] || { echo "expected exactly one jar, got ''${jars[*]}" >&2; exit 1; }

    mkdir -p $out/share/janitorr
    install -Dm644 "''${jars[0]}" $out/share/janitorr/janitorr.jar

    makeWrapper ${lib.getExe' jre "java"} $out/bin/janitorr \
      --add-flags "-jar $out/share/janitorr/janitorr.jar"

    runHook postInstall
  '';

  meta = {
    description = "Cleans up your media library based on available disk space";
    homepage = "https://github.com/Schaka/janitorr";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "janitorr";
  };
})
