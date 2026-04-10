#!/bin/sh

CFG="${TG_CONFIG_SECTION:-main}"

pw_cfg_section() {
	uci -q get tgpasswall."$CFG".passwall_global_section 2>/dev/null || echo "@global[0]"
}

pw_enabled_key() {
	uci -q get tgpasswall."$CFG".passwall_enabled_key 2>/dev/null || echo "enabled"
}

pw_node_key() {
	uci -q get tgpasswall."$CFG".passwall_node_key 2>/dev/null || echo "tcp_node"
}

pw_service() {
	uci -q get tgpasswall."$CFG".passwall_service 2>/dev/null || echo "passwall"
}

pw_node_section_type() {
	uci -q get tgpasswall."$CFG".passwall_node_section_type 2>/dev/null || echo "nodes"
}

pw_get_section_type() {
	local sec="$1"
	uci -q show "passwall.${sec}" 2>/dev/null | awk -F= '
		NR==1 {
			v=$2
			gsub(/^'\''|'\''$/, "", v)
			print v
		}
	'
}

pw_apply() {
	uci -q commit passwall || return 1
	/etc/init.d/"$(pw_service)" restart >/dev/null 2>&1 || /etc/init.d/"$(pw_service)" reload >/dev/null 2>&1
}

pw_get_enabled() {
	local sec key
	sec="$(pw_cfg_section)"
	key="$(pw_enabled_key)"
	uci -q get "passwall.${sec}.${key}"
}

pw_set_enabled() {
	local v="$1" sec key
	sec="$(pw_cfg_section)"
	key="$(pw_enabled_key)"
	uci -q set "passwall.${sec}.${key}=${v}" || return 1
	pw_apply
}

pw_get_current_node() {
	local sec key
	sec="$(pw_cfg_section)"
	key="$(pw_node_key)"
	uci -q get "passwall.${sec}.${key}"
}

pw_get_node_remark_by_section() {
	local sec="$1"
	uci -q get "passwall.${sec}.remarks"
}

pw_get_current_node_display() {
	local cur sec rem
	cur="$(pw_get_current_node)"
	[ -n "$cur" ] || {
		echo "未设置"
		return 0
	}

	rem="$(pw_get_node_remark_by_section "$cur")"
	if [ -n "$rem" ]; then
		echo "${rem} (${cur})"
		return 0
	fi

	# fallback: some forks store node id instead of section name
	sec="$(uci -q show passwall | awk -F= -v id="$cur" '
		$1 ~ /^passwall\.[^.]+\.id$/ {
			v=$2
			gsub(/^'\''|'\''$/, "", v)
			if (v == id) {
				s=$1
				sub(/^passwall\./, "", s)
				sub(/\.id$/, "", s)
				print s
				exit
			}
		}
	')"
	if [ -n "$sec" ]; then
		rem="$(pw_get_node_remark_by_section "$sec")"
		[ -n "$rem" ] && echo "${rem} (${sec})" || echo "$sec"
		return 0
	fi

	echo "$cur"
}

pw_list_nodes() {
	# output: section|remark
	uci -q show passwall | awk -F= '
		$1 ~ /^passwall\.[^.]+\.remarks$/ {
			s=$1
			sub(/^passwall\./,"",s)
			sub(/\.remarks$/,"",s)
			gsub(/^'\''|'\''$/,"",$2)
			printf "%s|%s\n", s, $2
		}
	'
}

pw_list_real_nodes() {
	local typ
	typ="$(pw_node_section_type)"
	pw_list_nodes | while IFS='|' read -r sec rem; do
		[ -n "$sec" ] || continue
		if [ "$(pw_get_section_type "$sec")" = "$typ" ]; then
			echo "${sec}|${rem}"
		fi
	done
}

pw_find_node_section() {
	local needle="$1"
	local sec rem
	[ -n "$needle" ] || return 1

	# exact section
	if uci -q get "passwall.${needle}.remarks" >/dev/null 2>&1 && [ "$(pw_get_section_type "$needle")" = "$(pw_node_section_type)" ]; then
		echo "$needle"
		return 0
	fi

	# exact remark match
	sec="$(pw_list_real_nodes | awk -F'|' -v q="$needle" '$2 == q {print $1; exit}')"
	if [ -n "$sec" ]; then
		echo "$sec"
		return 0
	fi

	# substring remark match (first hit)
	sec="$(pw_list_real_nodes | awk -F'|' -v q="$needle" 'index($2, q) > 0 {print $1; exit}')"
	[ -n "$sec" ] || return 1
	echo "$sec"
}

pw_switch_node() {
	local target="$1" sec key
	sec="$(pw_cfg_section)"
	key="$(pw_node_key)"
	uci -q set "passwall.${sec}.${key}=${target}" || return 1
	pw_apply
}

pw_delete_node() {
	local sec="$1"
	[ -n "$sec" ] || return 1
	[ "$(pw_get_section_type "$sec")" = "$(pw_node_section_type)" ] || return 1
	uci -q delete "passwall.${sec}" || return 1
	# If deleted node is current, clear pointer to avoid dangling section.
	local cur key gsec
	cur="$(pw_get_current_node)"
	if [ "$cur" = "$sec" ]; then
		gsec="$(pw_cfg_section)"
		key="$(pw_node_key)"
		uci -q set "passwall.${gsec}.${key}=''"
	fi
	pw_apply
}
