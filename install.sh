#!/bin/sh
# March toolchain installer.
#
#   curl -fsSL https://github.com/march-language/march/releases/latest/download/install.sh | sh
#
# Downloads a prebuilt March release from GitHub, verifies its checksum, and
# installs it under ~/.march. Installs the most recent stable release by
# default; set MARCH_VERSION=<tag> (e.g. v0.1.0 or nightly-20260612) to pin one,
# or MARCH_VERSION=nightly for the latest nightly.
#
# Layout (shared with `forge toolchain`):
#   ~/.march/versions/<tag>/   extracted release (bin/ stdlib/ runtime/ LICENSE)
#   ~/.march/current        -> versions/<tag>     (active toolchain)
#   ~/.march/bin/{march,forge}  wrapper scripts that exec through current/
set -eu

REPO="march-language/march"
API="https://api.github.com/repos/${REPO}"
MARCH_HOME="${MARCH_HOME:-$HOME/.march}"

err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*" >&2; }

# --- dependencies ---------------------------------------------------------
command -v curl >/dev/null 2>&1 || err "curl is required"
command -v tar  >/dev/null 2>&1 || err "tar is required"
if command -v sha256sum >/dev/null 2>&1; then
  SHACHECK="sha256sum -c --ignore-missing"
elif command -v shasum >/dev/null 2>&1; then
  SHACHECK="shasum -a 256 -c --ignore-missing"
else
  err "need sha256sum or shasum to verify downloads"
fi

# Pass a token through if present, to dodge the unauthenticated API rate limit.
api_get() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$1"
  else
    curl -fsSL "$1"
  fi
}

# --- detect platform ------------------------------------------------------
os="$(uname -s)"
arch="$(uname -m)"
case "${os}-${arch}" in
  Darwin-arm64)        PLATFORM="darwin-arm64" ;;
  Linux-x86_64)        PLATFORM="linux-x86_64" ;;
  Linux-aarch64|Linux-arm64) PLATFORM="linux-aarch64" ;;
  Darwin-x86_64)       err "no prebuilt for Intel macOS (darwin-x86_64); build from source: https://github.com/${REPO}#installing-from-source" ;;
  *)                   err "unsupported platform: ${os}-${arch}" ;;
esac
info "Platform: ${PLATFORM}"

# --- resolve the release tag ----------------------------------------------
if [ "${MARCH_VERSION:-}" = "nightly" ]; then
  TAG="$(api_get "${API}/releases" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' | grep '^nightly-' | head -1)"
  [ -n "${TAG}" ] || err "no nightly releases found"
elif [ -n "${MARCH_VERSION:-}" ]; then
  TAG="${MARCH_VERSION}"
else
  # Prefer the latest stable release; fall back to the newest nightly.
  TAG="$(api_get "${API}/releases/latest" 2>/dev/null | sed -E -n 's/.*"tag_name": *"([^"]+)".*/\1/p' | head -1 || true)"
  if [ -z "${TAG:-}" ]; then
    info "No stable release yet; using the latest nightly."
    TAG="$(api_get "${API}/releases" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' | grep '^nightly-' | head -1)"
  fi
  [ -n "${TAG}" ] || err "could not determine a release to install"
fi
info "Release: ${TAG}"

# --- find the asset URLs for this platform --------------------------------
ASSETS="$(api_get "${API}/releases/tags/${TAG}" | grep '"browser_download_url"' | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')"
TARBALL_URL="$(printf '%s\n' "${ASSETS}" | grep -- "-${PLATFORM}\.tar\.gz$" | head -1)"
SUMS_URL="$(printf '%s\n' "${ASSETS}" | grep -- "checksums\.txt$" | head -1)"
[ -n "${TARBALL_URL}" ] || err "release ${TAG} has no asset for ${PLATFORM}"

# --- download + verify ----------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
TARBALL="${TMP}/$(basename "${TARBALL_URL}")"
NAME="$(basename "${TARBALL}")"
info "Downloading ${NAME} ..."
curl -fsSL -o "${TARBALL}" "${TARBALL_URL}"

# Fail closed: refuse to install anything we can't verify.
[ -n "${SUMS_URL}" ] || err "release ${TAG} has no checksums asset; refusing to install an unverified download"
info "Verifying checksum ..."
# The checksums file may prefix hashes with "sha256:" (legacy) — strip it.
api_get "${SUMS_URL}" | sed 's/^sha256://' > "${TMP}/checksums.txt"
grep -q " ${NAME}\$" "${TMP}/checksums.txt" \
  || err "${NAME} is not listed in the checksums file; refusing unverified install"
( cd "${TMP}" && grep " ${NAME}\$" checksums.txt | eval "${SHACHECK}" >/dev/null ) \
  || err "checksum verification failed for ${NAME}"

# --- install --------------------------------------------------------------
DEST="${MARCH_HOME}/versions/${TAG}"
info "Installing to ${DEST} ..."
rm -rf "${DEST}"
mkdir -p "${DEST}"
# The archive holds a single top-level dir (march-<ver>-<platform>/); lift its
# contents up into the version dir so bin/ stdlib/ runtime/ sit at the top.
tar xzf "${TARBALL}" -C "${TMP}"
INNER="$(find "${TMP}" -maxdepth 1 -type d -name 'march-*' | head -1)"
[ -n "${INNER}" ] || err "unexpected archive layout"
( cd "${INNER}" && tar cf - . ) | ( cd "${DEST}" && tar xf - )

# Point `current` at this version.
ln -sfn "versions/${TAG}" "${MARCH_HOME}/current"

# Install wrapper scripts that exec through current/ (so the binaries resolve
# their bundled stdlib/runtime relative to the real version dir on every OS).
mkdir -p "${MARCH_HOME}/bin"
for tool in march forge; do
  cat > "${MARCH_HOME}/bin/${tool}" <<EOF
#!/bin/sh
exec "${MARCH_HOME}/current/bin/${tool}" "\$@"
EOF
  chmod +x "${MARCH_HOME}/bin/${tool}"
done

info ""
info "March ${TAG} installed."

# --- sanity check ---------------------------------------------------------
# Make sure the installed compiler actually runs (e.g. catches missing dylibs).
if ! "${MARCH_HOME}/bin/march" --version >/dev/null 2>&1; then
  info ""
  info "warning: the installed 'march' did not run."
  case "${PLATFORM}" in
    darwin-*) info "On macOS, install its linked libraries:  brew install blake3 zstd brotli" ;;
    *)        info "Make sure a C toolchain (clang/llvm) and required libraries are available." ;;
  esac
fi

# --- PATH guidance --------------------------------------------------------
case ":${PATH}:" in
  *":${MARCH_HOME}/bin:"*) : ;;  # already on PATH
  *)
    info "Add March to your PATH:"
    info ""
    info "    export PATH=\"${MARCH_HOME}/bin:\$PATH\""
    info ""
    info "(append that line to your ~/.zshrc or ~/.bashrc to make it permanent)"
    ;;
esac
