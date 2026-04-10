#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_NAME="luci-app-jdc-tgbot"
PKG_VERSION="0.1.0-1"
ARCH="${1:-all}"
OUT_DIR="${ROOT_DIR}/dist"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

mkdir -p "${OUT_DIR}"

PKG_DIR="${WORK_DIR}/pkg"
DATA_DIR="${WORK_DIR}/data"
CONTROL_DIR="${WORK_DIR}/control"
mkdir -p "${PKG_DIR}" "${DATA_DIR}" "${CONTROL_DIR}"

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
Title: jdc-TGbot for Telegram + Passwall controller
Description: jdc-TGbot Telegram bridge for OpenWrt router status and passwall control.
Provides: luci-app-tgpasswall
Replaces: luci-app-tgpasswall
Conflicts: luci-app-tgpasswall
EOF

# Keep user config on reinstall/upgrade.
cat > "${CONTROL_DIR}/conffiles" <<EOF
/etc/config/tgpasswall
EOF

# Keep existing runtime config across reinstall/upgrade/remove+install flows.
cat > "${CONTROL_DIR}/preinst" <<'EOF'
#!/bin/sh
if [ -f /etc/config/tgpasswall ]; then
	cp -f /etc/config/tgpasswall /tmp/tgpasswall.config.bak 2>/dev/null || true
fi
exit 0
EOF

cat > "${CONTROL_DIR}/postinst" <<'EOF'
#!/bin/sh
if [ -f /tmp/tgpasswall.config.bak ]; then
	cp -f /tmp/tgpasswall.config.bak /etc/config/tgpasswall 2>/dev/null || true
	rm -f /tmp/tgpasswall.config.bak 2>/dev/null || true
fi
exit 0
EOF

chmod 0755 "${CONTROL_DIR}/preinst" "${CONTROL_DIR}/postinst"
chmod 0755 "${DATA_DIR}/etc/init.d/tgpasswall" "${DATA_DIR}/usr/libexec/tgpasswall/"*.sh

# Kwrt/OpenWrt opkg variant expects an outer gzip tarball package:
#   ./debian-binary ./data.tar.gz ./control.tar.gz
export COPYFILE_DISABLE=1
echo "2.0" > "${PKG_DIR}/debian-binary"
tar -C "${CONTROL_DIR}" --format=ustar --uid=0 --gid=0 -czf "${PKG_DIR}/control.tar.gz" .
tar -C "${DATA_DIR}" --format=ustar --uid=0 --gid=0 -czf "${PKG_DIR}/data.tar.gz" .

IPK_PATH="${OUT_DIR}/${PKG_NAME}_${PKG_VERSION}_${ARCH}.ipk"
rm -f "${IPK_PATH}"
tar -C "${PKG_DIR}" --format=ustar --uid=0 --gid=0 -czf "${IPK_PATH}" ./debian-binary ./data.tar.gz ./control.tar.gz

echo "Built: ${IPK_PATH}"
