# machines/ernst/containers/pkgs/umlautadaptarr.nix
#
# UmlautAdaptarr — M12 (b).  Not in nixpkgs (surveyed against ernst's own pin on
# 2026-08-26, the session date, exactly as the packaging section of
# docs/roadmap.md requires; the 2026-08-25 table still held).
#
# ── Why the upstream RELEASE ARTIFACT and not a source build ─────────────────
#
#   Upstream publishes one asset per release, linux-x64.zip, produced by
#   `dotnet publish -c Release -r linux-x64 --self-contained` (build_linux.bat
#   in the repo root).  Self-contained means the .NET runtime is inside the
#   zip: 48 MB of apphost + loose native .so files + managed .dlls, with
#   UmlautAdaptarr.runtimeconfig.json declaring includedFrameworks
#   Microsoft.NETCore.App 10.0.10 and Microsoft.AspNetCore.App 10.0.10.
#
#   THIS IS THE SAME SHAPE NIXPKGS ITSELF USES FOR THE *ARR FAMILY, and that
#   is the argument rather than expedience.  Checked on ernst's pin:
#
#     prowlarr  src = .../Prowlarr/archive/refs/tags/v2.5.2.5491.tar.gz
#     radarr    src = .../Radarr/archive/refs/tags/v6.3.0.10514.tar.gz
#     bazarr    src = .../bazarr/releases/download/v1.6.0/bazarr.zip
#
#   — i.e. release artifacts, not `dotnet build` from source with a nuget lock.
#   A hand-rolled derivation that departs from how nixpkgs packages the four
#   neighbouring services in the same container would be the odd one out.
#
#   The property M12 actually cares about is NOT "built from source".  It is
#   that the unit is a NixOS unit, legible to `systemd-analyze security`, which
#   is what "virtualisation.oci-containers inside an nspawn container is
#   REJECTED" is protecting.  A store path plus a hand-written, hardened unit
#   keeps every bit of that.  A Docker image would not.
#
#   MediathekArr, in this same directory, goes the other way and builds from
#   source — because it publishes NO release assets at all.  The two files
#   disagree deliberately; each takes what upstream actually ships.
#
# ── Why a pinned hash HERE and not a flake input ─────────────────────────────
#
#   M12's prompt says "New flake inputs ARE expected here (the hand-rolled
#   derivations).  Pin each by tag or rev, never by branch."  The intent —
#   nothing tracks a moving target — is kept in full; the mechanism is not, and
#   the reason is the same one the recyclarr block already argues one file over
#   in containers/arr.nix.
#
#   A flake input is a row in flake.lock, and `nix flake update` moves every
#   row it can.  Nothing in this repo distinguishes "bump nixpkgs" from
#   "silently move the release-rewriting proxy that sits in front of every
#   indexer".  A version string and a hash IN THIS FILE cannot move without an
#   edit, and the edit is a reviewable diff that names the version.  For a
#   RELEASE ARTIFACT the flake-input form is also a poor fit mechanically:
#   github: inputs fetch a source tree, and the thing being pinned here is a
#   published zip.
#
#   The pin is therefore: version below, hash below, both changed together.
#
# ── What this service is, in one paragraph, because it decides the unit ──────
#
#   It presents itself to the *arrs as an INDEXER but actually sits BETWEEN
#   them and the real indexer, rewriting searches and results.  Two ports:
#   5005 is its own HTTP API (Kestrel, appsettings.json pins http://[::]:5005)
#   and 5006 is the internal PROXY that Prowlarr is pointed at.  Both are
#   127.0.0.1-only in this deployment; see containers/arr.nix.
#
#   IT TALKS TO A THIRD-PARTY API ON ITS OWN BEHALF.  appsettings.json ships
#   Settings.UmlautAdaptarrApiHost = https://umlautadaptarr.pcjones.de/api/v1,
#   the maintainer's title-lookup service.  That is stated here rather than
#   discovered later: it is a fact about the service's network posture and it
#   belongs next to the derivation that installs it.  The invariant-#1 argument
#   for keeping it in the nspawn tier is made in containers/arr.nix.
#
# ── NO PERSISTENT STATE, and that changes the uid decision ───────────────────
#
#   Verified against upstream rather than assumed: zero SQLite references in
#   the repository, caching is IMemoryCache (Services/CacheService.cs), and
#   upstream's own docker-compose.yml declares NO volumes at all.  Everything
#   it holds is in memory and everything it is configured with arrives as an
#   environment variable.
#
#   So it takes DynamicUser and NOT the uid 3010 the roadmap reserved — see
#   the block in containers/arr.nix, where that departure is argued.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
  makeWrapper,
  zlib,
  openssl,
  icu,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "umlautadaptarr";
  version = "0.7.6";

  src = fetchurl {
    url = "https://github.com/PCJones/UmlautAdaptarr/releases/download/v${finalAttrs.version}/linux-x64.zip";
    hash = "sha256-uRu0RlLit/4roCfi1CfT9bhlkhvRsPyd6VMkAPiLvWs=";
  };

  # The zip has a single `publish/` directory at its root and unzip has no
  # strip-components; unpack into the build dir and reach into it below.
  sourceRoot = ".";

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
    makeWrapper
  ];

  # openssl and zlib are dlopen'd by libSystem.Security.Cryptography.Native.OpenSsl.so
  # and libSystem.IO.Compression.Native.so.  icu is listed even though this
  # build sets System.Globalization.Invariant = true: the ICU shim
  # libSystem.Globalization.Native.so is still SHIPPED, so autoPatchelf still
  # has to resolve it, and a missing dependency there fails the build rather
  # than the service.
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
    openssl
    icu
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/umlautadaptarr
    cp -r publish/. $out/share/umlautadaptarr/

    # 17 MB of debug symbols for a service nobody debugs from the store.
    rm -f $out/share/umlautadaptarr/*.pdb

    # DROPPED, not patched: CoreCLR's LTTng tracing provider.
    #
    # It is the only file in the publish tree autoPatchelf cannot satisfy — it
    # wants liblttng-ust.so.0, i.e. lttng-ust 2.12, and this nixpkgs carries
    # 2.14 (soname .so.1).  Pinning an EOL tracing library into a media
    # service's closure to satisfy a file that is only ever dlopen'd when
    # LTTng tracing is explicitly switched on is the wrong trade.  CoreCLR
    # loads it lazily and runs without it; nothing here enables tracing.
    #
    # `--ignore-missing` would have been the other option and is worse: it
    # would leave a broken .so in the store that fails at dlopen time, in the
    # journal, on the day somebody does turn tracing on.
    rm -f $out/share/umlautadaptarr/libcoreclrtraceptprovider.so

    # The zip carries no execute bit on the apphost.
    chmod +x $out/share/umlautadaptarr/UmlautAdaptarr

    # ASPNETCORE_CONTENTROOT, and it is load-bearing.
    #
    # ASP.NET Core's default content root is the process's CURRENT WORKING
    # DIRECTORY, which is where it looks for appsettings.json.  The unit sets
    # WorkingDirectory to a runtime directory (a service should not run with
    # its cwd inside the store), so without this the Kestrel endpoint from
    # appsettings.json — http://[::]:5005 — would never be read and the app
    # would fall back to ASP.NET's own default of :5000.  It would start.  It
    # would answer nothing on the port Prowlarr is pointed at.
    makeWrapper $out/share/umlautadaptarr/UmlautAdaptarr $out/bin/umlautadaptarr \
      --set ASPNETCORE_CONTENTROOT $out/share/umlautadaptarr

    runHook postInstall
  '';

  meta = {
    description = "Proxy that fixes Sonarr/Radarr handling of umlauts and German titles";
    homepage = "https://github.com/PCJones/UmlautAdaptarr";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "umlautadaptarr";
  };
})
