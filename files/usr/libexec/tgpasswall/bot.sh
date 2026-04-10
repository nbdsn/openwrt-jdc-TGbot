#!/bin/sh

set -u

CFG="${TG_CONFIG_SECTION:-main}"
BASE_DIR="/usr/libexec/tgpasswall"

. "${BASE_DIR}/state.sh"
. "${BASE_DIR}/pw.sh"

log() {
	logger -t tgpasswall "$*"
}

cfg_get() {
	uci -q get "tgpasswall.${CFG}.$1"
}

BOT_TOKEN="$(cfg_get bot_token)"
ADMIN_CHAT_ID="$(cfg_get admin_chat_id)"
ADMIN_USER_ID="$(cfg_get admin_user_id)"
POLL_TIMEOUT="$(cfg_get poll_timeout)"
API_BASE="$(cfg_get api_base)"
ALLOW_NON_COMMAND_MENU="$(cfg_get allow_non_command_menu)"
DAILY_PUSH_ENABLED="$(cfg_get daily_push_enabled)"
DAILY_PUSH_HOUR="$(cfg_get daily_push_hour)"
DAILY_PUSH_MINUTE="$(cfg_get daily_push_minute)"

[ -n "$POLL_TIMEOUT" ] || POLL_TIMEOUT=25
[ -n "$API_BASE" ] || API_BASE="https://api.telegram.org"
[ -n "$DAILY_PUSH_ENABLED" ] || DAILY_PUSH_ENABLED=0
[ -n "$DAILY_PUSH_HOUR" ] || DAILY_PUSH_HOUR=8
[ -n "$DAILY_PUSH_MINUTE" ] || DAILY_PUSH_MINUTE=0
DAILY_PUSH_HOUR="$(echo "$DAILY_PUSH_HOUR" | sed 's/^0//')"
DAILY_PUSH_MINUTE="$(echo "$DAILY_PUSH_MINUTE" | sed 's/^0//')"
[ -n "$DAILY_PUSH_HOUR" ] || DAILY_PUSH_HOUR="0"
[ -n "$DAILY_PUSH_MINUTE" ] || DAILY_PUSH_MINUTE="0"

if [ -z "$BOT_TOKEN" ] || [ -z "$ADMIN_CHAT_ID" ]; then
	log "missing bot_token or admin_chat_id, sleeping"
	sleep 60
	exit 1
fi

API_URL="${API_BASE}/bot${BOT_TOKEN}"
OFFSET_FILE="/tmp/tgpasswall.offset"
LAST_PUSH_FILE="/tmp/tgpasswall.daily.last"
[ -f "$OFFSET_FILE" ] || echo 0 > "$OFFSET_FILE"

tg_send() {
	local chat_id="$1"
	local text="$2"
	curl -fsS "${API_URL}/sendMessage" \
		-d "chat_id=${chat_id}" \
		--data-urlencode "text=${text}" \
		-d "disable_web_page_preview=true" >/dev/null 2>&1
}

tg_set_commands() {
	local cmds
	cmds="$(jq -cn '[
		{"command":"start","description":"显示帮助"},
		{"command":"menu","description":"显示中文菜单"},
		{"command":"status","description":"查看路由器状态"},
		{"command":"cpu","description":"查看CPU负载"},
		{"command":"mem","description":"查看内存信息"},
		{"command":"ports","description":"查看端口监听"},
		{"command":"passwall","description":"查看Passwall状态"},
		{"command":"nodes","description":"查看节点列表"},
		{"command":"enable_pw","description":"开启Passwall"},
		{"command":"disable_pw","description":"关闭Passwall"},
		{"command":"switch","description":"按节点名切换"},
		{"command":"import","description":"导入节点URI"},
		{"command":"daily_now","description":"测试每日推送"}
	]')"
	curl -fsS "${API_URL}/setMyCommands" \
		--data-urlencode "commands=${cmds}" >/dev/null 2>&1 || true
}

tg_menu() {
	local chat_id="$1"
	local kb='{"keyboard":[["🚦 系统状态","🧭 Passwall状态"],["🧠 CPU信息","💾 内存信息"],["🌐 端口信息","🧩 节点列表"],["✅ 开启Passwall","⛔ 关闭Passwall"],["📨 每日推送测试","📖 帮助"]],"resize_keyboard":true}'
	curl -fsS "${API_URL}/sendMessage" \
		-d "chat_id=${chat_id}" \
		--data-urlencode "text=✨ TG Passwall 菜单已就绪，点按钮就能操作。" \
		-d "reply_markup=${kb}" >/dev/null 2>&1
}

is_admin() {
	local chat_id="$1"
	local user_id="$2"
	[ "$chat_id" = "$ADMIN_CHAT_ID" ] || return 1
	if [ -n "$ADMIN_USER_ID" ] && [ "$user_id" != "$ADMIN_USER_ID" ]; then
		return 1
	fi
	return 0
}

cmd_status() {
	cat <<EOF
📊 路由器状态总览
🏷️ 主机名: $(get_hostname)
⏱️ 运行时长: $(get_uptime_human)
🧠 CPU负载: $(get_loadavg)

$(get_mem_summary_mb)
$(get_storage_summary_mb)

🚦 Passwall: $(pw_get_enabled)
🧩 当前节点: $(pw_get_current_node_display)
EOF
}

cmd_cpu() {
	printf "🧠 CPU 负载: %s\n" "$(get_loadavg)"
}

cmd_mem() {
	printf "💾 内存信息\n%s" "$(get_mem_summary_mb)"
}

cmd_ports() {
	local lines
	lines="$(get_ports | head -n 40)"
	printf "🌐 端口监听（最多40行）\n%s\n" "$lines"
}

cmd_passwall() {
	printf "🚦 Passwall 启用状态: %s\n" "$(pw_get_enabled)"
	printf "🧩 当前节点: %s\n" "$(pw_get_current_node_display)"
}

build_daily_report() {
	cat <<EOF
📮 路由器每日报告
🕒 时间: $(date '+%Y-%m-%d %H:%M:%S')

$(cmd_status)
EOF
}

cmd_nodes() {
	local list
	list="$(pw_list_nodes | head -n 80 | awk -F'|' '{if($2==""){printf "• %s\n",$1}else{printf "• %s  (section: %s)\n",$2,$1}}')"
	if [ -z "$list" ]; then
		echo "🧩 未找到节点。"
		return 0
	fi
	printf "🧩 节点列表（可 /switch 节点备注）\n%s\n" "$list"
}

maybe_send_daily_report() {
	local today now_h now_m last sent
	[ "$DAILY_PUSH_ENABLED" = "1" ] || return 0

	today="$(date +%F)"
	now_h="$(date +%H | sed 's/^0//')"
	now_m="$(date +%M | sed 's/^0//')"
	[ -n "$now_h" ] || now_h="0"
	[ -n "$now_m" ] || now_m="0"

	last="$(cat "$LAST_PUSH_FILE" 2>/dev/null)"
	if [ "$last" = "$today" ]; then
		return 0
	fi

	if [ "$now_h" = "$DAILY_PUSH_HOUR" ] && [ "$now_m" = "$DAILY_PUSH_MINUTE" ]; then
		sent="$(build_daily_report)"
		tg_send "$ADMIN_CHAT_ID" "$sent"
		echo "$today" > "$LAST_PUSH_FILE"
		log "daily report sent for ${today} at ${DAILY_PUSH_HOUR}:${DAILY_PUSH_MINUTE}"
	fi
}

handle_command() {
	local chat_id="$1"
	local text="$2"
	local out="" cmd arg mapped sec

	cmd="$(echo "$text" | awk '{print $1}')"
	arg="$(echo "$text" | cut -d' ' -f2-)"

	case "$text" in
		"🚦 系统状态"|"系统状态") mapped="/status" ;;
		"🧭 Passwall状态"|"Passwall状态") mapped="/passwall" ;;
		"🧠 CPU信息"|"CPU信息") mapped="/cpu" ;;
		"💾 内存信息"|"内存信息") mapped="/mem" ;;
		"🌐 端口信息"|"端口信息") mapped="/ports" ;;
		"🧩 节点列表"|"节点列表") mapped="/nodes" ;;
		"✅ 开启Passwall"|"开启Passwall") mapped="/enable_pw" ;;
		"⛔ 关闭Passwall"|"关闭Passwall") mapped="/disable_pw" ;;
		"📨 每日推送测试"|"每日推送测试") mapped="/daily_now" ;;
		"📖 帮助"|"帮助") mapped="/help" ;;
		"菜单") mapped="/menu" ;;
		*) mapped="$cmd" ;;
	esac

	case "$mapped" in
		/start|/help)
			out="✨ TG Passwall 指令
/status 查看路由器总览
/cpu 查看CPU负载
/mem 查看内存(MB)
/ports 查看监听端口
/passwall 查看Passwall状态
/nodes 查看节点列表
/enable_pw 开启Passwall
/disable_pw 关闭Passwall
/switch <节点备注或section>
/import <ss/vmess/vless/trojan链接>
/daily_now 测试日报
/menu 打开中文菜单"
			tg_send "$chat_id" "$out"
			;;
		/menu)
			tg_menu "$chat_id"
			;;
		/status|/host)
			tg_send "$chat_id" "$(cmd_status)"
			;;
		/cpu)
			tg_send "$chat_id" "$(cmd_cpu)"
			;;
		/mem)
			tg_send "$chat_id" "$(cmd_mem)"
			;;
		/ports)
			tg_send "$chat_id" "$(cmd_ports)"
			;;
		/passwall)
			tg_send "$chat_id" "$(cmd_passwall)"
			;;
		/nodes)
			tg_send "$chat_id" "$(cmd_nodes)"
			;;
		/enable_pw)
			if pw_set_enabled 1; then
				tg_send "$chat_id" "✅ 已开启 Passwall。"
			else
				tg_send "$chat_id" "❌ 开启 Passwall 失败。"
			fi
			;;
		/disable_pw)
			if pw_set_enabled 0; then
				tg_send "$chat_id" "⛔ 已关闭 Passwall。"
			else
				tg_send "$chat_id" "❌ 关闭 Passwall 失败。"
			fi
			;;
		/switch)
			if [ -z "$arg" ] || [ "$arg" = "$cmd" ]; then
				tg_send "$chat_id" "用法: /switch <节点备注或section>"
			else
				sec="$(pw_find_node_section "$arg" || true)"
				if [ -z "$sec" ]; then
					tg_send "$chat_id" "❌ 没找到节点: $arg"
				elif pw_switch_node "$sec"; then
					tg_send "$chat_id" "✅ 已切换到: $(pw_get_current_node_display)"
				else
					tg_send "$chat_id" "❌ 切换节点失败: $arg"
				fi
			fi
			;;
		/import)
			if [ -z "$arg" ] || [ "$arg" = "$cmd" ]; then
				tg_send "$chat_id" "用法: /import <node_uri>"
			else
				tg_send "$chat_id" "$("${BASE_DIR}/pw_import.sh" "$arg" 2>&1)"
			fi
			;;
		/daily_now)
			tg_send "$chat_id" "$(build_daily_report)"
			;;
		*)
			if [ "$ALLOW_NON_COMMAND_MENU" = "1" ] && { [ "$text" = "menu" ] || [ "$text" = "菜单" ]; }; then
				tg_menu "$chat_id"
			fi
			;;
	esac
}

tg_set_commands

while true; do
	maybe_send_daily_report

	OFFSET="$(cat "$OFFSET_FILE" 2>/dev/null)"
	[ -n "$OFFSET" ] || OFFSET=0

	resp="$(curl -fsS "${API_URL}/getUpdates?offset=${OFFSET}&timeout=${POLL_TIMEOUT}" 2>/dev/null)"
	if [ -z "${resp}" ]; then
		sleep 3
		continue
	fi

	echo "$resp" | jq -c '.result[]?' | while IFS= read -r upd; do
		update_id="$(echo "$upd" | jq -r '.update_id')"
		next_offset=$((update_id + 1))
		echo "$next_offset" > "$OFFSET_FILE"

		chat_id="$(echo "$upd" | jq -r '.message.chat.id // .callback_query.message.chat.id // empty')"
		user_id="$(echo "$upd" | jq -r '.message.from.id // .callback_query.from.id // empty')"
		text="$(echo "$upd" | jq -r '.message.text // .callback_query.data // empty')"

		[ -n "$chat_id" ] || continue
		[ -n "$text" ] || continue

		if ! is_admin "$chat_id" "$user_id"; then
			log "ignore non-admin chat_id=${chat_id} user_id=${user_id}"
			continue
		fi

		handle_command "$chat_id" "$text"
	done

	sleep 1
done
