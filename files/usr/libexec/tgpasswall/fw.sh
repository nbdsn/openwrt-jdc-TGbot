#!/bin/sh

fw_service() {
	echo "firewall"
}

fw_apply() {
	uci -q commit firewall || return 1
	/etc/init.d/"$(fw_service)" reload >/dev/null 2>&1 || /etc/init.d/"$(fw_service)" restart >/dev/null 2>&1
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
