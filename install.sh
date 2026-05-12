#!/usr/bin/env bash
# install.sh
#
# Install the vibesync CLI on macOS or Linux (including WSL / Git Bash).
# Native Windows users should use install.ps1 instead.
#
# This script downloads a prebuilt vibesync binary from GitHub Releases
# and copies it into a user-writable bin directory.
# It does NOT build from source.
#
# Usage:
#     ./install.sh [--prefix <dir>] [--version <tag>] [--force] [--help]
#     VIBESYNC_FORCE=1 ./install.sh
#     VIBESYNC_INSTALL_DIR=/usr/local/bin ./install.sh
#     VIBESYNC_VERSION=v1.2.3 ./install.sh
#     VIBESYNC_INSTALL_BASE_URL=https://... ./install.sh
#
# Resolution order for each setting:
#     CLI flag > environment variable > built-in default
#
# Expected remote layout (GitHub Releases):
#     https://github.com/rakeit-in/vibesync/releases/download/<TAG>/
#       vibesync-macos-arm64
#       vibesync-macos-x86_64
#       vibesync-linux-x86_64
#       vibesync-windows-x86_64.exe
#       SHA256SUMS
#
# Exit codes:
#     0  success
#     1  generic failure
#     2  unsupported platform (or running under native Windows shell)
#     3  download or checksum failure

set -eu

# ---------- Defaults ----------

GITHUB_REPO="rakeit-in/vibesync"
DEFAULT_BASE_URL="https://github.com/${GITHUB_REPO}/releases/download"
BASE_URL="${VIBESYNC_INSTALL_BASE_URL:-${DEFAULT_BASE_URL}}"
VERSION="${VIBESYNC_VERSION:-latest}"
PREFIX="${VIBESYNC_INSTALL_DIR:-${HOME}/.local/bin}"
# Boolean: "1" means force.
if [ "${VIBESYNC_FORCE:-0}" = "1" ]; then
    FORCE="1"
else
    FORCE="0"
fi
BINARY_NAME="vibesync"

# Hooks for tests (not part of the public contract).
TEST_LOG_DIR="${VIBESYNC_TEST_LOG_DIR:-}"

# ---------- Helpers ----------

log()  { printf '[install] %s\n' "$*"; }
warn() { printf '[install][warn] %s\n' "$*" >&2; }
err()  { printf '[install][error] %s\n' "$*" >&2; }
fail() {
    err "$1"
    exit "${2:-1}"
}

usage() {
    sed -n '2,36p' "$0"
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---------- Parse args ----------

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || fail "--prefix needs a value"
            PREFIX="$2"
            shift 2
            ;;
        --version)
            [ $# -ge 2 ] || fail "--version needs a value"
            VERSION="$2"
            shift 2
            ;;
        --force)
            FORCE="1"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

# ---------- Resolve "latest" to an actual tag ----------

if [ "${VERSION}" = "latest" ]; then
    log "resolving latest version from GitHub releases..."
    # Use the HTML redirect at /releases/latest instead of the REST API,
    # because the API enforces a 60-req/hr limit on unauthenticated IPs,
    # which routinely breaks installs on shared networks.
    # /releases/latest responds with 302 -> /releases/tag/<TAG>.
    latest_url="https://github.com/${GITHUB_REPO}/releases/latest"
    if have curl; then
        location="$(curl --head --silent --show-error --location --max-redirs 0 \
            "${latest_url}" 2>/dev/null | awk 'tolower($1)=="location:" {print $2}' | tr -d '\r\n')"
    elif have wget; then
        location="$(wget --max-redirect=0 --method=HEAD --server-response --quiet \
            -O /dev/null "${latest_url}" 2>&1 | awk 'tolower($1)=="location:" {print $2}' | tr -d '\r\n')"
    else
        fail "Neither curl nor wget is available."
    fi
    # Extract tag from the redirect URL: .../releases/tag/<TAG>
    resolved="${location##*/tag/}"
    if [ -z "${resolved}" ] || [ "${resolved}" = "${location}" ]; then
        fail "failed to resolve latest version from GitHub (no release published yet?)" 3
    fi
    log "latest version: ${resolved}"
    VERSION="${resolved}"
fi

# ---------- Detect platform ----------

uname_s="$(uname -s 2>/dev/null || echo unknown)"
uname_m="$(uname -m 2>/dev/null || echo unknown)"

case "${uname_s}" in
    Darwin)
        os="macos"
        ;;
    Linux)
        os="linux"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        fail "Native Windows detected. Please use install.ps1 instead of install.sh." 2
        ;;
    *)
        fail "Unsupported OS: ${uname_s}" 2
        ;;
esac

case "${uname_m}" in
    arm64|aarch64)
        arch="arm64"
        ;;
    x86_64|amd64)
        arch="x86_64"
        ;;
    *)
        fail "Unsupported CPU arch: ${uname_m}" 2
        ;;
esac

# Current release matrix: macOS arm64/x86_64, Linux x86_64 only.
if [ "${os}" = "linux" ] && [ "${arch}" != "x86_64" ]; then
    fail "Unsupported Linux arch: ${arch}. Only linux-x86_64 is published." 2
fi

asset="vibesync-${os}-${arch}"
asset_url="${BASE_URL}/${VERSION}/${asset}"
sums_url="${BASE_URL}/${VERSION}/SHA256SUMS"

log "target : ${asset}"
log "version: ${VERSION}"
log "prefix : ${PREFIX}"
log "asset  : ${asset_url}"

# ---------- Pick tools ----------

if have curl; then
    download() {
        # download <output-path> <url>
        curl --fail --location --silent --show-error --output "$1" "$2"
    }
elif have wget; then
    download() {
        wget -qO "$1" "$2"
    }
else
    fail "Neither curl nor wget is available."
fi

if have shasum; then
    sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
elif have sha256sum; then
    sha256() { sha256sum "$1" | awk '{print $1}'; }
else
    warn "Neither shasum nor sha256sum found; checksum verification will be skipped."
    sha256() { printf ''; }
fi

# ---------- Download ----------

work_dir="$(mktemp -d)"
cleanup() { rm -rf "${work_dir}"; }
trap cleanup EXIT

asset_path="${work_dir}/${asset}"
sums_path="${work_dir}/SHA256SUMS"

log "downloading asset..."
if [ -n "${TEST_LOG_DIR}" ]; then
    printf '%s\n' "${asset_url}" >> "${TEST_LOG_DIR}/urls.log"
fi
if ! download "${asset_path}" "${asset_url}"; then
    fail "failed to download ${asset_url}" 3
fi

have_sums="0"
log "downloading SHA256SUMS..."
if [ -n "${TEST_LOG_DIR}" ]; then
    printf '%s\n' "${sums_url}" >> "${TEST_LOG_DIR}/urls.log"
fi
if download "${sums_path}" "${sums_url}"; then
    have_sums="1"
else
    warn "SHA256SUMS not available at ${sums_url}; skipping checksum verification."
fi

if [ "${have_sums}" = "1" ]; then
    expected="$(awk -v name="${asset}" '$2==name || $2=="*"name {print $1; exit}' "${sums_path}" || true)"
    if [ -z "${expected}" ]; then
        fail "checksum entry for ${asset} not found in SHA256SUMS" 3
    fi
    actual="$(sha256 "${asset_path}")"
    if [ -z "${actual}" ]; then
        warn "checksum verification skipped (no sha tool)."
    elif [ "${expected}" != "${actual}" ]; then
        fail "checksum mismatch for ${asset}: expected ${expected}, got ${actual}" 3
    else
        log "checksum ok"
    fi
fi

# ---------- Install ----------

dest="${PREFIX}/${BINARY_NAME}"

if [ -e "${dest}" ] && [ "${FORCE}" != "1" ]; then
    err "${dest} already exists."
    err "Re-run with --force or VIBESYNC_FORCE=1 to overwrite."
    exit 1
fi

mkdir -p "${PREFIX}"
install -m 0755 "${asset_path}" "${dest}"
log "installed: ${dest}"

# ---------- PATH shadow warning ----------

if command -v "${BINARY_NAME}" >/dev/null 2>&1; then
    found="$(command -v "${BINARY_NAME}")"
    if [ "${found}" != "${dest}" ]; then
        warn "${BINARY_NAME} is shadowed by ${found} (appears before ${PREFIX} in PATH)."
    fi
fi

# ---------- PATH hint ----------

case ":${PATH}:" in
    *":${PREFIX}:"*)
        ;;
    *)
        warn "${PREFIX} is not in PATH. Add it, for example:"
        printf '    export PATH="%s:$PATH"\n' "${PREFIX}" >&2
        ;;
esac

# ---------- Self check ----------

if "${dest}" --version >/dev/null 2>&1; then
    "${dest}" --version
else
    warn "installed binary did not respond to --version; please verify manually."
fi

log "done"
