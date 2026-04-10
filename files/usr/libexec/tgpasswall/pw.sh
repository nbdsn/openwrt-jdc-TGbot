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

pw_switch_node() {
	local target="$1" sec key
	sec="$(pw_cfg_section)"
	key="$(pw_node_key)"
	uci -q set "passwall.${sec}.${key}=${target}" || return 1
	pw_apply
}
