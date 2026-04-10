#!/bin/sh

set -u

CFG="${TG_CONFIG_SECTION:-main}"
BASE_DIR="/usr/libexec/tgpasswall"

. "${BASE_DIR}/pw.sh"

uri="${1:-}"

if [ -z "$uri" ]; then
	echo "ERR: empty uri"
	exit 1
fi

tmpdir="/tmp/tgpasswall"
mkdir -p "$tmpdir"

url_decode() {
	# decode %xx and + space in URL fragments/query values
	printf '%b' "$(echo "$1" | sed 's/+/ /g;s/%/\\x/g')"
}

b64_decode() {
	# urlsafe base64 + missing padding compatibility
	local s="$1" mod
	s="$(echo "$s" | tr '_-' '/+')"
	mod=$((${#s} % 4))
	if [ "$mod" = "2" ]; then s="${s}=="; fi
	if [ "$mod" = "3" ]; then s="${s}="; fi
	printf '%s' "$s" | base64 -d 2>/dev/null
}

new_node_section() {
	local t sec
	t="$(pw_node_section_type)"
	sec="$(uci -q add passwall "$t")" || return 1
	echo "$sec"
}

set_if() {
	local sec="$1" key="$2" val="$3"
	[ -n "$val" ] || return 0
	uci -q set "passwall.${sec}.${key}=${val}"
}

set_common() {
	local sec="$1" typ="$2" remarks="$3" host="$4" port="$5"
	set_if "$sec" type "$typ"
	set_if "$sec" remarks "$remarks"
	set_if "$sec" address "$host"
	set_if "$sec" port "$port"
}

import_ss() {
	local raw payload remark before_hash query hostport creds host port method password sec
	raw="${uri#ss://}"
	remark=""
	query=""

	if echo "$raw" | grep -q '#'; then
		remark="$(url_decode "${raw#*#}")"
		raw="${raw%%#*}"
	fi
	if echo "$raw" | grep -q '?'; then
		query="${raw#*\?}"
		raw="${raw%%\?*}"
	fi

	# form1: base64(method:password@host:port)
	# form2: method:password@host:port (or its b64 userinfo + @host:port)
	if echo "$raw" | grep -q '@'; then
		before_hash="${raw%@*}"
		hostport="${raw#*@}"
		if echo "$before_hash" | grep -q ':'; then
			creds="$before_hash"
		else
			creds="$(b64_decode "$before_hash")"
		fi
	else
		creds="$(b64_decode "$raw")"
		hostport="$(echo "$creds" | awk -F@ '{print $2}')"
		creds="$(echo "$creds" | awk -F@ '{print $1}')"
	fi

	method="$(echo "$creds" | awk -F: '{print $1}')"
	password="$(echo "$creds" | cut -d: -f2-)"
	host="$(echo "$hostport" | awk -F: '{print $1}')"
	port="$(echo "$hostport" | awk -F: '{print $2}')"

	[ -n "$remark" ] || remark="ss-${host}:${port}"

	sec="$(new_node_section)" || return 1
	set_common "$sec" "sing_shadowsocks" "$remark" "$host" "$port" || return 1
	set_if "$sec" method "$method" || return 1
	set_if "$sec" password "$password" || return 1
}

import_trojan() {
	local raw creds rest hostport host port remark query sec sni
	raw="${uri#trojan://}"
	remark=""
	if echo "$raw" | grep -q '#'; then
		remark="$(url_decode "${raw#*#}")"
		raw="${raw%%#*}"
	fi
	query=""
	if echo "$raw" | grep -q '?'; then
		query="${raw#*\?}"
		raw="${raw%%\?*}"
	fi

	creds="${raw%@*}"
	rest="${raw#*@}"
	hostport="$rest"
	host="$(echo "$hostport" | awk -F: '{print $1}')"
	port="$(echo "$hostport" | awk -F: '{print $2}')"
	sni="$(echo "$query" | tr '&' '\n' | awk -F= '$1=="sni"{print $2; exit}')"
	sni="$(url_decode "$sni")"

	[ -n "$remark" ] || remark="trojan-${host}:${port}"

	sec="$(new_node_section)" || return 1
	set_common "$sec" "trojan" "$remark" "$host" "$port" || return 1
	set_if "$sec" password "$creds" || return 1
	set_if "$sec" tls "1"
	set_if "$sec" sni "$sni"
}

import_vless() {
	local raw uuid rest hostport host port query remark sec net path hosth sni security
	raw="${uri#vless://}"
	remark=""
	if echo "$raw" | grep -q '#'; then
		remark="$(url_decode "${raw#*#}")"
		raw="${raw%%#*}"
	fi
	query=""
	if echo "$raw" | grep -q '?'; then
		query="${raw#*\?}"
		raw="${raw%%\?*}"
	fi

	uuid="${raw%@*}"
	rest="${raw#*@}"
	hostport="$rest"
	host="$(echo "$hostport" | awk -F: '{print $1}')"
	port="$(echo "$hostport" | awk -F: '{print $2}')"

	net="$(echo "$query" | tr '&' '\n' | awk -F= '$1=="type"{print $2; exit}')"
	path="$(echo "$query" | tr '&' '\n' | awk -F= '$1=="path"{print $2; exit}')"
	hosth="$(echo "$query" | tr '&' '\n' | awk -F= '$1=="host"{print $2; exit}')"
	sni="$(echo "$query" | tr '&' '\n' | awk -F= '$1=="sni"{print $2; exit}')"
	security="$(echo "$query" | tr '&' '\n' | awk -F= '$1=="security"{print $2; exit}')"

	path="$(url_decode "$path")"
	hosth="$(url_decode "$hosth")"
	sni="$(url_decode "$sni")"

	[ -n "$remark" ] || remark="vless-${host}:${port}"
	[ -n "$net" ] || net="tcp"

	sec="$(new_node_section)" || return 1
	set_common "$sec" "vless" "$remark" "$host" "$port" || return 1
	set_if "$sec" id "$uuid"
	set_if "$sec" encryption "none"
	set_if "$sec" transport "$net"
	set_if "$sec" path "$path"
	set_if "$sec" host "$hosth"
	set_if "$sec" sni "$sni"
	if [ "$security" = "tls" ]; then
		set_if "$sec" tls "1"
	fi
}

import_vmess() {
	local payload json host port id aid net path hosth tls ps sec
	payload="${uri#vmess://}"
	json="$(b64_decode "$payload")"
	if [ -z "$json" ]; then
		echo "ERR: invalid vmess base64 payload"
		return 1
	fi

	host="$(echo "$json" | jq -r '.add // empty')"
	port="$(echo "$json" | jq -r '.port // empty')"
	id="$(echo "$json" | jq -r '.id // empty')"
	aid="$(echo "$json" | jq -r '.aid // empty')"
	net="$(echo "$json" | jq -r '.net // "tcp"')"
	path="$(echo "$json" | jq -r '.path // empty')"
	hosth="$(echo "$json" | jq -r '.host // empty')"
	tls="$(echo "$json" | jq -r '.tls // empty')"
	ps="$(echo "$json" | jq -r '.ps // empty')"

	[ -n "$ps" ] || ps="vmess-${host}:${port}"

	sec="$(new_node_section)" || return 1
	set_common "$sec" "vmess" "$ps" "$host" "$port" || return 1
	set_if "$sec" id "$id"
	set_if "$sec" alter_id "$aid"
	set_if "$sec" transport "$net"
	set_if "$sec" path "$path"
	set_if "$sec" host "$hosth"
	if [ "$tls" = "tls" ]; then
		set_if "$sec" tls "1"
	fi
}

scheme="$(echo "$uri" | awk -F:// '{print $1}')"
case "$scheme" in
	ss) import_ss ;;
	vmess) import_vmess ;;
	vless) import_vless ;;
	trojan) import_trojan ;;
	*)
		echo "ERR: unsupported scheme: $scheme"
		exit 1
		;;
esac

if ! pw_apply; then
	echo "ERR: import parsed but apply failed"
	exit 1
fi

echo "OK: node imported and passwall reloaded"
