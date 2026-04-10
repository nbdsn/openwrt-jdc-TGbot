#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_NAME="luci-app-tgpasswall"
PKG_VERSION="0.1.0-1"
ARCH="${1:-all}"
OUT_DIR="${ROOT_DIR}/dist"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

mkdir -p "${OUT_DIR}"

DATA_DIR="${WORK_DIR}/data"
CONTROL_DIR="${WORK_DIR}/control"
mkdir -p "${DATA_DIR}" "${CONTROL_DIR}"

cp -R "${ROOT_DIR}/files/." "${DATA_DIR}/"

cat > "${CONTROL_DIR}/control" <<EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Depends: curl, coreutils, coreutils-base64, jq, luci-base, luci-compat, jsonfilter
Architecture: ${ARCH}
Maintainer: nbdsn
Section: luci
Category: LuCI
Submenu: 3. Applications
Title: LuCI app for Telegram + Passwall controller
Description: Telegram bot bridge for OpenWrt router status and passwall control.
EOF

chmod 0755 "${DATA_DIR}/etc/init.d/tgpasswall" "${DATA_DIR}/usr/libexec/tgpasswall/"*.sh

echo "2.0" > "${WORK_DIR}/debian-binary"
tar -C "${CONTROL_DIR}" -czf "${WORK_DIR}/control.tar.gz" .
tar -C "${DATA_DIR}" -czf "${WORK_DIR}/data.tar.gz" .

IPK_PATH="${OUT_DIR}/${PKG_NAME}_${PKG_VERSION}_${ARCH}.ipk"
rm -f "${IPK_PATH}"
ar r "${IPK_PATH}" "${WORK_DIR}/debian-binary" "${WORK_DIR}/control.tar.gz" "${WORK_DIR}/data.tar.gz" >/dev/null

echo "Built: ${IPK_PATH}"
