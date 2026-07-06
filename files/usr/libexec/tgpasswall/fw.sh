#!/bin/sh

fw_service() {
	echo "firewall"
}

fw_apply() {
	uci -q commit firewall || return 1
	if [ -x /sbin/fw4 ]; then
		/sbin/fw4 check >/dev/null 2>&1 || return 1
		/sbin/fw4 reload >/dev/null 2>&1 || true
		return 0
	fi
	/etc/init.d/"$(fw_service)" reload >/dev/null 2>&1 || /etc/init.d/"$(fw_service)" restart >/dev/null 2>&1 || true
	return 0
}

fw_redirect_sections() {
	uci -q show firewall 2>/dev/null | awk -F= '
		$0 ~ /^firewall\.[^.]+=redirect$/ {
			s=$1
			sub(/^firewall\./, "", s)
			print s
		}
	'
}

fw_get() {
	local sec="$1"
	local key="$2"
	uci -q get "firewall.${sec}.${key}"
}

fw_is_enabled() {
	local sec="$1"
	local disabled
	disabled="$(fw_get "$sec" disabled)"
	[ "$disabled" = "1" ] && echo "0" || echo "1"
}

fw_set_enabled() {
	local sec="$1"
	local enabled="$2"
	[ -n "$sec" ] || return 1
	if [ "$enabled" = "1" ]; then
		uci -q delete "firewall.${sec}.disabled" >/dev/null 2>&1 || uci -q set "firewall.${sec}.disabled=0" || return 1
	else
		uci -q set "firewall.${sec}.disabled=1" || return 1
	fi
	fw_apply
}

fw_get_display_name() {
	local sec="$1"
	local name
	name="$(fw_get "$sec" name)"
	[ -n "$name" ] && echo "$name" || echo "$sec"
}

fw_list_zones() {
	uci -q show firewall 2>/dev/null | awk -F= '
		$1 ~ /^firewall\.@zone\[[0-9]+\]\.name$/ {
			v=$2
			gsub(/^'\''|'\''$/, "", v)
			if (v != "") {
				print v
			}
		}
	'
}

fw_list_hosts() {
	awk '
		{
			ip=$3
			name=$4
			if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
				if (name == "" || name == "*") {
					name="-"
				}
				if (!seen[ip]++) {
					printf "%s|%s\n", ip, name
				}
			}
		}
	' /tmp/dhcp.leases 2>/dev/null
}

fw_host_name_by_ip() {
	local ip="$1"
	fw_list_hosts | awk -F'|' -v q="$ip" '$1 == q {print $2; exit}'
}

fw_ipv4_is_valid() {
	local ip="$1"
	local o1 o2 o3 o4

	case "$ip" in
		""|*[!0-9.]*|*.*.*.*.*|.*|*.)
			return 1
			;;
	esac

	IFS=. read -r o1 o2 o3 o4 <<EOF
$ip
EOF

	for octet in "$o1" "$o2" "$o3" "$o4"; do
		case "$octet" in
			""|*[!0-9]*)
				return 1
				;;
		esac
		[ "$octet" -ge 0 ] && [ "$octet" -le 255 ] || return 1
	done

	return 0
}

fw_port_is_valid() {
	local port="$1"
	local a b

	case "$port" in
		""|*[!0-9-]*|*-|-*|*--*)
			return 1
			;;
	esac

	case "$port" in
		*-*)
			a="${port%-*}"
			b="${port#*-}"
			case "$a" in ""|*[!0-9]*) return 1 ;; esac
			case "$b" in ""|*[!0-9]*) return 1 ;; esac
			[ "$a" -ge 1 ] && [ "$a" -le 65535 ] || return 1
			[ "$b" -ge 1 ] && [ "$b" -le 65535 ] || return 1
			[ "$a" -le "$b" ] || return 1
			;;
		*)
			[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
			;;
	esac

	return 0
}

fw_create_redirect() {
	local name="$1"
	local src="$2"
	local proto="$3"
	local dest="$4"
	local dest_ip="$5"
	local src_dport="$6"
	local dest_port="$7"
	local enabled="$8"
	local sec

	sec="$(uci add firewall redirect)" || return 1
	uci -q set "firewall.${sec}.name=${name}" || return 1
	uci -q set "firewall.${sec}.src=${src}" || return 1
	uci -q set "firewall.${sec}.dest=${dest}" || return 1
	uci -q set "firewall.${sec}.target=DNAT" || return 1
	uci -q set "firewall.${sec}.proto=${proto}" || return 1
	uci -q set "firewall.${sec}.src_dport=${src_dport}" || return 1
	uci -q set "firewall.${sec}.dest_ip=${dest_ip}" || return 1
	uci -q set "firewall.${sec}.dest_port=${dest_port}" || return 1
	uci -q set "firewall.${sec}.family=ipv4" || return 1

	if [ "$enabled" = "1" ]; then
		uci -q delete "firewall.${sec}.disabled" >/dev/null 2>&1 || true
	else
		uci -q set "firewall.${sec}.disabled=1" || return 1
	fi

	fw_apply || return 1
	echo "$sec"
}

fw_list_redirects() {
	local sec name enabled src src_dport proto dest dest_ip dest_port family reflection
	fw_redirect_sections | while IFS= read -r sec; do
		[ -n "$sec" ] || continue
		name="$(fw_get_display_name "$sec")"
		enabled="$(fw_is_enabled "$sec")"
		src="$(fw_get "$sec" src)"
		src_dport="$(fw_get "$sec" src_dport)"
		proto="$(fw_get "$sec" proto)"
		dest="$(fw_get "$sec" dest)"
		dest_ip="$(fw_get "$sec" dest_ip)"
		dest_port="$(fw_get "$sec" dest_port)"
		family="$(fw_get "$sec" family)"
		reflection="$(fw_get "$sec" reflection)"
		printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
			"$sec" "$name" "$enabled" "$src" "$src_dport" "$proto" "$dest" "$dest_ip" "$dest_port" "$family" "$reflection"
	done
}

fw_find_redirect_section() {
	local needle="$1"
	local sec name
	[ -n "$needle" ] || return 1

	for sec in $(fw_redirect_sections); do
		[ -n "$sec" ] || continue
		if [ "$sec" = "$needle" ]; then
			echo "$sec"
			return 0
		fi
		name="$(fw_get_display_name "$sec")"
		if [ "$name" = "$needle" ]; then
			echo "$sec"
			return 0
		fi
	done

	for sec in $(fw_redirect_sections); do
		name="$(fw_get_display_name "$sec")"
		case "$name" in
			*"$needle"*)
				echo "$sec"
				return 0
				;;
		esac
	done

	return 1
}
