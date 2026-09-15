#!/usr/bin/env bash
#
# Reproducible local build for the Magisk/KernelSU Tailscaled module.
#
# 1. Checks out the exact upstream Tailscale tag pinned in TAILSCALE_VERSION
# 2. Applies android.ssh.patch (Android Tailscale SSH support)
# 3. Builds the arm64 (aarch64) combined binary with version metadata
# 4. Assembles the Magisk/KernelSU module ZIP and prints its SHA-256
#
# Usage:
#   ./build.sh                    # use version from TAILSCALE_VERSION
#   ./build.sh v1.102.4           # override upstream version
#
# Environment:
#   ANDROID_NDK_HOME  NDK path. When set, the binary is built with
#                     CGO_ENABLED=1 using the NDK clang toolchain (same as CI).
#                     Without it, a fully static CGO_ENABLED=0 build is used,
#                     which needs no Android toolchain and works fine for
#                     rooted Android (user/group lookups are handled by
#                     android.ssh.patch).
#   UPX               optional; if available, the binary is compressed.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAILSCALE_VERSION="${1:-$(tr -d '[:space:]' < "${REPO_ROOT}/TAILSCALE_VERSION")}"
MODULE_VERSION="${MODULE_VERSION:-${TAILSCALE_VERSION}-module.1}"

# Build workspace. Override MAGISK_TS_BUILD_DIR if a nested git checkout under
# the module repository is problematic on your setup (some sync tools strip
# nested .git directories, which would break version stamping).
BUILD_ROOT="${MAGISK_TS_BUILD_DIR:-${REPO_ROOT}/build}"
SRC_DIR="${BUILD_ROOT}/tailscale-${TAILSCALE_VERSION}"
DIST_DIR="${REPO_ROOT}/dist"
ZIP_NAME="Magisk-Tailscaled-${MODULE_VERSION}.zip"

echo "==> Upstream Tailscale : ${TAILSCALE_VERSION}"
echo "==> Module version    : ${MODULE_VERSION}"

# ---------------------------------------------------------------------------
# 1. Obtain the exact upstream tag
#
# mkversion derives version/commit metadata from git, so the source tree must
# be a git repo whose HEAD is the upstream tag commit. We shallow-fetch only
# the pinned tag (small download); the working tree is then reset to pristine
# upstream before patching. An existing tree for a previous build is reused
# (reset to the pinned tag) rather than re-downloaded.
# ---------------------------------------------------------------------------
if [ -d "${SRC_DIR}/.git" ]; then
  echo "==> Reusing existing source tree at ${SRC_DIR}"
  cd "${SRC_DIR}"
  git remote set-url origin https://github.com/tailscale/tailscale 2>/dev/null \
    || git remote add origin https://github.com/tailscale/tailscale
  git fetch -q --depth 1 origin "refs/tags/${TAILSCALE_VERSION}:refs/tags/${TAILSCALE_VERSION}"
  git reset -q --hard "${TAILSCALE_VERSION}"
  rm -f ./tailscale.combined
elif [ -n "${TAILSCALE_TARBALL:-}" ] && [ -f "${TAILSCALE_TARBALL}" ]; then
  echo "==> Extracting local tarball ${TAILSCALE_TARBALL}"
  mkdir -p "${SRC_DIR}"
  tar -xzf "${TAILSCALE_TARBALL}" -C "${SRC_DIR}" --strip-components=1
  cd "${SRC_DIR}"
  git init -q
  git remote add origin https://github.com/tailscale/tailscale
  git fetch -q --depth 1 origin "refs/tags/${TAILSCALE_VERSION}:refs/tags/${TAILSCALE_VERSION}"
  git reset -q --hard "${TAILSCALE_VERSION}"
else
  echo "==> Shallow-cloning tailscale at ${TAILSCALE_VERSION}"
  git clone -q --depth 1 --branch "${TAILSCALE_VERSION}" \
    https://github.com/tailscale/tailscale "${SRC_DIR}"
  cd "${SRC_DIR}"
fi

# Safety: every later git invocation (patch apply, mkversion) must resolve to
# the tailscale source tree, never to a parent repository.
if [ ! -e "${SRC_DIR}/.git" ]; then
  echo "ERROR: ${SRC_DIR}/.git is missing after checkout." >&2
  echo "       Refusing to continue: git commands could leak into a parent repository." >&2
  echo "       If a sync tool strips nested .git dirs, set MAGISK_TS_BUILD_DIR outside the repository." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Apply the Android patch + Android-safe resolv.conf paths
# ---------------------------------------------------------------------------
echo "==> Applying android.ssh.patch"
if git apply --check "${REPO_ROOT}/android.ssh.patch" 2>/dev/null; then
  git apply "${REPO_ROOT}/android.ssh.patch"
else
  # fallback for checkouts where git apply is unavailable/unreliable
  patch -p1 < "${REPO_ROOT}/android.ssh.patch"
fi

echo "==> Redirecting resolv.conf paths to /data/adb/tailscale/etc"
sed -i 's|/etc/resolv.conf|/data/adb/tailscale/etc/resolv.conf|g' net/dns/resolvconfpath_default.go
sed -i 's|/etc/resolv.pre-tailscale-backup.conf|/data/adb/tailscale/etc/resolv.pre-tailscale-backup.conf|g' net/dns/resolvconfpath_default.go

# ---------------------------------------------------------------------------
# 3. Build arm64 combined binary with upstream version metadata
# ---------------------------------------------------------------------------
echo "==> Computing version stamps (mkversion)"
eval "$(CGO_ENABLED=0 go run ./cmd/mkversion)"
echo "    VERSION_SHORT=${VERSION_SHORT} VERSION_LONG=${VERSION_LONG}"
ldflags="-X tailscale.com/version.longStamp=${VERSION_LONG} -X tailscale.com/version.shortStamp=${VERSION_SHORT}"

if [ -n "${ANDROID_NDK_HOME:-}" ]; then
  NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt"
  case "$(go env GOHOSTOS)" in
    windows) NDK_TRIPLE="windows-x86_64" ;;
    darwin)  NDK_TRIPLE="darwin-x86_64" ;;
    *)       NDK_TRIPLE="linux-x86_64" ;;
  esac
  NDK_BIN="${NDK_BIN}/${NDK_TRIPLE}/bin"
  echo "==> Building arm64 with NDK CGO (${NDK_BIN}/aarch64-linux-android21-clang)"
  CC="${NDK_BIN}/aarch64-linux-android21-clang" \
  CXX="${NDK_BIN}/aarch64-linux-android21-clang++" \
  CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
    go build -tags ts_include_cli,ts_omit_systray -trimpath -ldflags "${ldflags} -s -w" \
    -o ./tailscale.combined ./cmd/tailscaled
else
  echo "==> ANDROID_NDK_HOME not set; building static CGO_ENABLED=0 arm64"
  CGO_ENABLED=0 GOOS=android GOARCH=arm64 \
    go build -tags ts_include_cli,ts_omit_systray -trimpath -ldflags "${ldflags} -s -w" \
    -o ./tailscale.combined ./cmd/tailscaled
fi

if command -v upx >/dev/null 2>&1; then
  echo "==> Compressing binary with UPX"
  upx --lzma --best ./tailscale.combined
fi

# Sanity checks: ELF arm64 + embedded version stamp
file ./tailscale.combined || true
go version -m ./tailscale.combined | grep -E 'GOARCH|GOOS|shortStamp|longStamp' || true

# ---------------------------------------------------------------------------
# 4. Assemble the Magisk/KernelSU module ZIP
# ---------------------------------------------------------------------------
echo "==> Assembling module ZIP"
STAGE="${BUILD_ROOT}/module"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/files"

# Copy module payload (everything the installer needs; no docs/CI/build files)
cp -r "${REPO_ROOT}/META-INF" "${STAGE}/"
cp -r "${REPO_ROOT}/system" "${STAGE}/"
cp -r "${REPO_ROOT}/tailscale" "${STAGE}/"
cp "${REPO_ROOT}/customize.sh" "${REPO_ROOT}/service.sh" "${REPO_ROOT}/uninstall.sh" "${REPO_ROOT}/module.prop" "${STAGE}/"

# GitHub repo slug for updateJson: CI env, else git remote, else upstream default
GH_REPO_SLUG="${GITHUB_REPOSITORY:-}"
if [ -z "${GH_REPO_SLUG}" ]; then
  ORIGIN_URL="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
  GH_REPO_SLUG="$(echo "${ORIGIN_URL}" | sed -n 's#.*[:/]\([^/]*\)/\([^/]*\)\(\.git\)*$#\1/\2#p')"
fi
GH_REPO_SLUG="${GH_REPO_SLUG:-mgksu/tailscaled}"

# Stamp version fields into module.prop (repo copy stays the source of truth)
sed -i \
  -e "s|^version=.*|version=${MODULE_VERSION}|" \
  -e "s|^versionCode=.*|versionCode=$(echo "${MODULE_VERSION}" | tr -dc '0-9')|" \
  -e "s|^updateJson=.*|updateJson=https://raw.githubusercontent.com/${GH_REPO_SLUG}/refs/heads/main/update.json|" \
  "${STAGE}/module.prop"

cp ./tailscale.combined "${STAGE}/files/tailscale.combined"

mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}/${ZIP_NAME}"
# -X strips extra file attributes (timezone-uid-gid) for more reproducible zips
zip_ok=0
if (cd "${STAGE}" && zip -9 -r -X "${DIST_DIR}/${ZIP_NAME}" .) > /dev/null; then
  zip_ok=1
# Native Windows zip.exe cannot read MSYS-style (/c/...) paths; retry with a
# Windows-style path (C:/...), which both the shell and the exe accept.
elif command -v cygpath > /dev/null 2>&1 && (cd "${STAGE}" && zip -9 -r -X "$(cygpath -m "${DIST_DIR}/${ZIP_NAME}")" .) > /dev/null; then
  zip_ok=1
fi
if [ "${zip_ok}" -ne 1 ]; then
  echo "ERROR: failed to create ${DIST_DIR}/${ZIP_NAME}" >&2
  exit 1
fi

echo "==> ZIP contents:"
unzip -l "${DIST_DIR}/${ZIP_NAME}"
echo "==> SHA-256:"
sha256sum "${DIST_DIR}/${ZIP_NAME}"
echo "==> Done: ${DIST_DIR}/${ZIP_NAME}"
