#!/usr/bin/env bash
# fetch-cross-sysroot.sh — populate the cross-compile target sysroot cache that
# `march --compile --target linux/<arch>` links TLS (OpenSSL 3) + gzip (zlib)
# against.
#
# Why this exists: the main executable cannot defer undefined symbols the way a
# .so can, so the cross-linker needs TARGET copies of libssl/libcrypto/libz (and
# their headers) at link time — not just at runtime.  We extract them from the
# Debian *bookworm* packages so the soname/ABI matches the deploy image
# (debian:bookworm-slim → OpenSSL 3.0.x, zlib 1.2.13, glibc 2.36).  See
# specs/2026-07-04-cross-compile-linux-hot-deploy-design.md §5.
#
# It populates:
#   ~/.cache/march/cross-sysroot/linux-<arch>/
#     lib/     libssl.so.3  libcrypto.so.3  libz.so.1
#     include/ openssl/*    zlib.h  zconf.h   (+ multiarch openssl/opensslconf.h)
#
# The compiler looks here automatically; override with MARCH_CROSS_SYSROOT_<ARCH>
# (e.g. MARCH_CROSS_SYSROOT_AMD64=/path) or MARCH_CROSS_SYSROOT pointing at an
# arch dir directly.
#
# Requirements: curl, ar, tar (macOS ships all three — dpkg-deb is NOT needed).
#
# Usage:
#   scripts/fetch-cross-sysroot.sh amd64
#   scripts/fetch-cross-sysroot.sh arm64
#   scripts/fetch-cross-sysroot.sh            # both
set -euo pipefail

MIRROR="${MARCH_DEBIAN_MIRROR:-http://deb.debian.org/debian}"
SUITE="bookworm"

die() { echo "fetch-cross-sysroot: $*" >&2; exit 1; }

for tool in curl ar tar; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool '$tool' not found on PATH"
done

cache_root="${HOME:-.}/.cache/march/cross-sysroot"

# Temp dirs to remove on exit (populated per-arch).
CLEANUP_DIRS=()
cleanup() { for d in "${CLEANUP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# Map our arch name → debian arch.
deb_arch_of() {
  case "$1" in
    amd64) echo "amd64" ;;
    arm64) echo "arm64" ;;
    *) die "unknown arch '$1' (expected amd64 or arm64)" ;;
  esac
}
# Debian multiarch header/lib subdirectory for an arch.
multiarch_of() {
  case "$1" in
    amd64) echo "x86_64-linux-gnu" ;;
    arm64) echo "aarch64-linux-gnu" ;;
    *) die "unknown arch '$1'" ;;
  esac
}

# Resolve the exact bookworm pool path for a package from the suite Packages
# index (pins to bookworm — the flat pool/ dir mixes in trixie/sid versions, so
# we must NOT grep the pool listing).  Pinned known-good fallbacks are used only
# if the index fetch fails.
resolve_filename() {
  local pkg="$1" packages_file="$2"
  awk -v p="$pkg" '
    BEGIN { RS=""; FS="\n" }
    {
      name=""; fname=""
      for (i=1;i<=NF;i++) {
        if ($i ~ /^Package: /)  name=substr($i,10)
        if ($i ~ /^Filename: /) fname=substr($i,11)
      }
      if (name==p) { print fname; exit }
    }' "$packages_file"
}

# Known-good bookworm fallbacks (used only if the Packages index is unreachable).
fallback_filename() {
  local deb_arch="$1" pkg="$2"
  case "$pkg" in
    libssl3)    echo "pool/main/o/openssl/libssl3_3.0.17-1~deb12u2_${deb_arch}.deb" ;;
    libssl-dev) echo "pool/main/o/openssl/libssl-dev_3.0.17-1~deb12u2_${deb_arch}.deb" ;;
    zlib1g)     echo "pool/main/z/zlib/zlib1g_1.2.13.dfsg-1_${deb_arch}.deb" ;;
    zlib1g-dev) echo "pool/main/z/zlib/zlib1g-dev_1.2.13.dfsg-1_${deb_arch}.deb" ;;
    *) die "no fallback for package '$pkg'" ;;
  esac
}

fetch_arch() {
  local arch="$1"
  local deb_arch multiarch
  deb_arch="$(deb_arch_of "$arch")"
  multiarch="$(multiarch_of "$arch")"

  local dest="$cache_root/linux-$arch"
  echo "==> fetching cross sysroot for linux/$arch ($SUITE, $multiarch) into $dest"

  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/march-sysroot-$arch.XXXXXX")"
  # Register cleanup on script EXIT (RETURN-scoped traps can't see $work once the
  # function has returned under `set -u`).
  CLEANUP_DIRS+=("$work")

  # 1. Resolve exact bookworm deb paths from the suite Packages index.
  local packages_gz="$work/Packages.gz" packages_txt="$work/Packages"
  local index_ok=0
  if curl -fsSL --max-time 120 \
       "$MIRROR/dists/$SUITE/main/binary-$deb_arch/Packages.gz" \
       -o "$packages_gz" 2>/dev/null; then
    if gzip -dc "$packages_gz" > "$packages_txt" 2>/dev/null; then
      index_ok=1
    fi
  fi
  [ "$index_ok" = 1 ] || echo "    (Packages index unavailable — using pinned fallback versions)"

  # 2. Download + extract each package.
  local pkg fname url
  for pkg in libssl3 libssl-dev zlib1g zlib1g-dev; do
    if [ "$index_ok" = 1 ]; then
      fname="$(resolve_filename "$pkg" "$packages_txt")"
      [ -n "$fname" ] || fname="$(fallback_filename "$deb_arch" "$pkg")"
    else
      fname="$(fallback_filename "$deb_arch" "$pkg")"
    fi
    url="$MIRROR/$fname"
    echo "    - $pkg: ${fname##*/}"
    curl -fsSL --max-time 300 "$url" -o "$work/$pkg.deb" \
      || die "download failed: $url"

    # Extract data.tar.* from the .deb (ar archive) and unpack it.
    local pdir="$work/x-$pkg"
    mkdir -p "$pdir"
    ( cd "$pdir" && ar x "../$pkg.deb" )
    local data
    data="$(ls "$pdir"/data.tar.* 2>/dev/null | head -1)"
    [ -n "$data" ] || die "no data.tar.* inside $pkg.deb"
    tar -xf "$data" -C "$pdir"
  done

  # 3. Assemble the sysroot: shared objects into lib/, headers into include/.
  local libdir="$dest/lib" incdir="$dest/include"
  rm -rf "$dest"
  mkdir -p "$libdir" "$incdir"

  # 3a. Shared objects (runtime packages).  Copy the REAL versioned object under
  #     the soname the linker records as DT_NEEDED.  Debian ships some .sos under
  #     usr/lib/<multiarch>/ (libssl3) and some under lib/<multiarch>/ (zlib1g),
  #     and libz is a symlink libz.so.1 → libz.so.1.2.13 — so search both roots
  #     and dereference to the real file.  install_so <pkgdir> <soname>.
  install_so() {
    local pkgdir="$1" soname="$2" src=""
    local root
    for root in "usr/lib/$multiarch" "lib/$multiarch" "usr/lib" "lib"; do
      if [ -e "$pkgdir/$root/$soname" ]; then
        # Follow the symlink chain to the real object (portable: no readlink -f).
        src="$pkgdir/$root/$soname"
        while [ -L "$src" ]; do
          local tgt; tgt="$(readlink "$src")"
          case "$tgt" in
            /*) src="$tgt" ;;
            *)  src="$(dirname "$src")/$tgt" ;;
          esac
        done
        break
      fi
    done
    [ -n "$src" ] && [ -e "$src" ] || die "$soname not found in $(basename "$pkgdir")"
    cp -f "$src" "$libdir/$soname"
  }
  install_so "$work/x-libssl3" libssl.so.3
  install_so "$work/x-libssl3" libcrypto.so.3
  install_so "$work/x-zlib1g"  libz.so.1

  # 3b. Headers (dev packages).  openssl/ + zlib.h + zconf.h from usr/include,
  #     PLUS the multiarch openssl config headers (Debian puts the arch-specific
  #     opensslconf.h / configuration.h under usr/include/<multiarch>/openssl,
  #     NOT usr/include/openssl — miss it and the compile fails with
  #     "openssl/opensslconf.h file not found").
  cp -a "$work/x-libssl-dev/usr/include/openssl" "$incdir/openssl"
  if [ -d "$work/x-libssl-dev/usr/include/$multiarch/openssl" ]; then
    cp -f "$work/x-libssl-dev/usr/include/$multiarch/openssl/"*.h "$incdir/openssl/"
  fi
  cp -f "$work/x-zlib1g-dev/usr/include/zlib.h"  "$incdir/zlib.h"
  cp -f "$work/x-zlib1g-dev/usr/include/zconf.h" "$incdir/zconf.h"

  # 4. Record a manifest (versions + digest) — the compiler folds a digest of the
  #    .so files into the CAS key, but this is human-readable provenance.
  {
    echo "# march cross-sysroot manifest"
    echo "arch $arch"
    echo "suite $SUITE"
    echo "multiarch $multiarch"
    for so in libssl.so.3 libcrypto.so.3 libz.so.1; do
      if command -v shasum >/dev/null 2>&1; then
        echo "$so $(shasum -a 256 "$libdir/$so" | awk '{print $1}')"
      fi
    done
  } > "$dest/MANIFEST"

  echo "==> done: $dest"
  echo "    lib/     $(ls "$libdir" | tr '\n' ' ')"
  echo "    include/ openssl/ zlib.h zconf.h"
}

main() {
  local arches=("$@")
  if [ "${#arches[@]}" -eq 0 ]; then
    arches=(amd64 arm64)
  fi
  for a in "${arches[@]}"; do
    fetch_arch "$a"
  done
}

main "$@"
