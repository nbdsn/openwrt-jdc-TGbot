#!/bin/sh

set -u

CFG="${TG_CONFIG_SECTION:-main}"
BASE_DIR="/usr/libexec/tgpasswall"

. "${BASE_DIR}/state.sh"
. "${BASE_DIR}/fw.sh"
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
FORWARD_WIZARD_DIR="/tmp/tgpasswall.forward"
[ -f "$OFFSET_FILE" ] || echo 0 > "$OFFSET_FILE"
mkdir -p "$FORWARD_WIZARD_DIR" 2>/dev/null || true

tg_send() {
	local chat_id="$1"
	local text="$2"
	curl -fsS "${API_URL}/sendMessage" \
		-d "chat_id=${chat_id}" \
		--data-urlencode "text=${text}" \
		-d "disable_web_page_preview=true" >/dev/null 2>&1
}

tg_send_inline() {
	local chat_id="$1"
	local text="$2"
	local inline_json="$3"
	curl -fsS "${API_URL}/sendMessage" \
		-d "chat_id=${chat_id}" \
		--data-urlencode "text=${text}" \
		--data-urlencode "reply_markup=${inline_json}" \
		-d "disable_web_page_preview=true" >/dev/null 2>&1
}

tg_answer_callback() {
	local cbid="$1"
	local msg="$2"
	[ -n "$cbid" ] || return 0
	curl -fsS "${API_URL}/answerCallbackQuery" \
		-d "callback_query_id=${cbid}" \
		--data-urlencode "text=${msg}" >/dev/null 2>&1 || true
}

tg_set_commands() {
	local cmds
	cmds="$(jq -cn '[
		{"command":"start","description":"显示帮助"},
		{"command":"menu","description":"显示中文菜单"},
		{"command":"status","description":"查看路由器状态"},
		{"command":"online","description":"查看在线主机"},
		{"command":"forwards","description":"查看端口映射"},
		{"command":"forwardpanel","description":"端口映射面板"},
		{"command":"add_forward","description":"交互新增映射"},
		{"command":"cpu","description":"查看CPU负载"},
		{"command":"mem","description":"查看内存信息"},
		{"command":"ports","description":"查看端口监听"},
		{"command":"passwall","description":"查看Passwall状态"},
		{"command":"nodes","description":"查看节点列表"},
		{"command":"nodepanel","description":"节点可点面板"},
		{"command":"enable_pw","description":"开启Passwall"},
		{"command":"disable_pw","description":"关闭Passwall"},
		{"command":"switch","description":"按节点名切换"},
		{"command":"import","description":"导入节点URI"},
		{"command":"reboot","description":"重启路由器"},
		{"command":"daily_now","description":"测试每日推送"}
	]')"
	curl -fsS "${API_URL}/setMyCommands" \
		--data-urlencode "commands=${cmds}" >/dev/null 2>&1 || true
}

tg_menu() {
	local chat_id="$1"
	local kb='{"keyboard":[["🚦 系统状态","🧭 Passwall状态"],["🧠 CPU信息","💾 内存信息"],["🌐 端口信息","🖥️ 在线主机"],["🧱 端口映射","➕ 新增映射"],["🧩 节点列表","🎛️ 节点面板"],["✅ 开启Passwall","⛔ 关闭Passwall"],["📨 每日推送测试","🔁 重启路由"],["📖 帮助"]],"resize_keyboard":true}'
	curl -fsS "${API_URL}/sendMessage" \
		-d "chat_id=${chat_id}" \
		--data-urlencode "text=✨ jdc-TGbot 菜单已就绪，点按钮就能操作。" \
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
📟 机型: $(get_model)
🧾 固件: $(get_release_description)
🏷️ 主机名: $(get_hostname)
🌍 公网IP: $(get_public_ipv4)
📶 Wi-Fi: $(get_wifi_ssids)
⏱️ 运行时长: $(get_uptime_human)
🧠 CPU负载: $(get_loadavg)
🌡️ CPU温度: $(get_cpu_temp_c)°C
📈 CPU占用估算: $(get_cpu_load_percent)%

$(get_mem_summary_mb)
$(get_storage_summary_mb)

🚦 Passwall: $(pw_get_enabled)
🧩 当前节点: $(pw_get_current_node_display)
EOF
}

cmd_cpu() {
	printf "🧠 CPU 信息\n%s" "$(get_cpu_summary)"
}

cmd_mem() {
	printf "💾 内存信息\n%s" "$(get_mem_summary_mb)"
}

cmd_ports() {
	local lines
	lines="$(get_ports | head -n 40)"
	printf "🌐 端口监听（最多40行）\n%s\n" "$lines"
}

cmd_online() {
	local list
	list="$(get_online_hosts | head -n 50)"
	if [ -z "$list" ]; then
		echo "🖥️ 暂无在线主机信息。"
		return 0
	fi
	printf "🖥️ 在线主机（最多50条）\n%s\n" "$list"
}

cmd_forwards() {
	local list
	list="$(fw_list_redirects | head -n 40 | awk -F'|' '
		{
			name=$2; if(name==""){name=$1}
			enabled=($3=="1" ? "启用" : "停用")
			src=$4; if(src==""){src="wan"}
			sport=$5; if(sport==""){sport="*"}
			proto=$6; if(proto==""){proto="all"}
			dip=$8; if(dip==""){dip="-"}
			dport=$9; if(dport==""){dport="*"}
			printf "%d. [%s] %s | %s:%s -> %s:%s | %s\n", NR, enabled, name, src, sport, dip, dport, proto
		}
	')"
	if [ -z "$list" ]; then
		echo "🧱 未找到端口映射规则。"
		return 0
	fi
	printf "🧱 端口映射（最多40条）\n%s\n" "$list"
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
	list="$(pw_list_real_nodes | head -n 80 | awk -F'|' '
		{
			n=NR
			if($2==""){
				printf "%d. %s\n", n, $1
			}else{
				printf "%d. %s  (section: %s)\n", n, $2, $1
			}
		}
	')"
	if [ -z "$list" ]; then
		echo "🧩 未找到节点。"
		return 0
	fi
	printf "🧩 节点列表（可 /switch 节点备注）\n%s\n" "$list"
}

send_node_panel() {
	local chat_id="$1"
	local panel text
	panel="$(pw_list_real_nodes | head -n 20 | awk -F'|' '
		BEGIN { printf "{\"inline_keyboard\":["; first=1 }
		{
			btn=$2; if(btn==""){btn=$1}
			gsub(/"/, "\\\"", btn)
			gsub(/"/, "\\\"", $1)
			if(!first){printf ","}
			first=0
			printf "[{\"text\":\"%s\",\"callback_data\":\"node:%s\"}]", btn, $1
		}
		END { printf "]}" }
	')"
	if [ -z "$panel" ] || [ "$panel" = "{\"inline_keyboard\":[]}" ]; then
		tg_send "$chat_id" "🧩 没有可操作节点。"
		return 0
	fi
	text="🎛️ 节点面板：点击节点可继续操作（启用/停用/删除）。"
	tg_send_inline "$chat_id" "$text" "$panel"
}

send_node_actions() {
	local chat_id="$1"
	local sec="$2"
	local cbid="${3:-}"
	local rem cur txt kb
	rem="$(pw_get_node_remark_by_section "$sec")"
	[ -n "$rem" ] || rem="$sec"
	cur="$(pw_get_current_node)"
	if [ "$cur" = "$sec" ]; then
		txt="🟢 当前选中节点: ${rem}\nsection: ${sec}"
	else
		txt="⚪ 节点: ${rem}\nsection: ${sec}"
	fi
	kb="{\"inline_keyboard\":[[{\"text\":\"✅ 启用此节点\",\"callback_data\":\"node_enable:${sec}\"},{\"text\":\"⛔ 停用Passwall\",\"callback_data\":\"pw_disable\"}],[{\"text\":\"🛠 修改提示\",\"callback_data\":\"node_edit:${sec}\"},{\"text\":\"🗑️ 删除节点\",\"callback_data\":\"node_delete:${sec}\"}],[{\"text\":\"◀ 返回节点列表\",\"callback_data\":\"nodes_panel\"}]]}"
	tg_send_inline "$chat_id" "$txt" "$kb"
	tg_answer_callback "$cbid" "已打开节点操作面板"
}

send_forward_panel() {
	local chat_id="$1"
	local panel text
	panel="$(fw_list_redirects | head -n 20 | awk -F'|' '
		BEGIN { printf "{\"inline_keyboard\":[[{\"text\":\"➕ 新增映射\",\"callback_data\":\"forward_add\"}]"; }
		{
			btn=$2
			if(btn==""){btn=$1}
			prefix=($3=="1" ? "🟢 " : "⚪ ")
			btn=prefix btn
			gsub(/"/, "\\\"", btn)
			gsub(/"/, "\\\"", $1)
			printf ",[{\"text\":\"%s\",\"callback_data\":\"forward:%s\"}]", btn, $1
		}
		END { printf "]}" }
	')"
	text="🧱 端口映射面板：可以点已有规则管理，也可以点“新增映射”进入向导。"
	tg_send_inline "$chat_id" "$text" "$panel"
}

send_forward_actions() {
	local chat_id="$1"
	local sec="$2"
	local cbid="${3:-}"
	local name enabled src sport proto dip dport status toggle_text toggle_cb txt kb

	name="$(fw_get_display_name "$sec")"
	enabled="$(fw_is_enabled "$sec")"
	src="$(fw_get "$sec" src)"
	sport="$(fw_get "$sec" src_dport)"
	proto="$(fw_get "$sec" proto)"
	dip="$(fw_get "$sec" dest_ip)"
	dport="$(fw_get "$sec" dest_port)"

	[ -n "$name" ] || name="$sec"
	[ -n "$src" ] || src="wan"
	[ -n "$sport" ] || sport="*"
	[ -n "$proto" ] || proto="all"
	[ -n "$dip" ] || dip="-"
	[ -n "$dport" ] || dport="*"

	if [ "$enabled" = "1" ]; then
		status="🟢 已启用"
		toggle_text="⛔ 停用规则"
		toggle_cb="forward_disable:${sec}"
	else
		status="⚪ 已停用"
		toggle_text="✅ 启用规则"
		toggle_cb="forward_enable:${sec}"
	fi

	txt="🧱 端口映射: ${name}\n状态: ${status}\n入口: ${src}:${sport}\n目标: ${dip}:${dport}\n协议: ${proto}\nsection: ${sec}"
	kb="{\"inline_keyboard\":[[{\"text\":\"${toggle_text}\",\"callback_data\":\"${toggle_cb}\"}],[{\"text\":\"➕ 新增映射\",\"callback_data\":\"forward_add\"},{\"text\":\"◀ 返回映射列表\",\"callback_data\":\"forwards_panel\"}]]}"
	tg_send_inline "$chat_id" "$txt" "$kb"
	tg_answer_callback "$cbid" "已打开映射操作面板"
}

fw_wizard_file() {
	echo "${FORWARD_WIZARD_DIR}/$1.state"
}

fw_wizard_encode() {
	printf "%s" "$1" | base64 | tr -d '\n'
}

fw_wizard_decode() {
	[ -n "${1:-}" ] || return 0
	printf "%s" "$1" | base64 -d 2>/dev/null
}

fw_wizard_set() {
	local chat_id="$1"
	local key="$2"
	local val="$3"
	local file tmp enc
	file="$(fw_wizard_file "$chat_id")"
	tmp="${file}.$$"
	enc="$(fw_wizard_encode "$val")"
	grep -v "^${key}=" "$file" 2>/dev/null > "$tmp" || true
	printf "%s=%s\n" "$key" "$enc" >> "$tmp"
	mv "$tmp" "$file"
}

fw_wizard_get() {
	local chat_id="$1"
	local key="$2"
	local file raw
	file="$(fw_wizard_file "$chat_id")"
	raw="$(grep "^${key}=" "$file" 2>/dev/null | tail -n 1 | cut -d= -f2-)"
	fw_wizard_decode "$raw"
}

fw_wizard_clear() {
	rm -f "$(fw_wizard_file "$1")"
}

fw_wizard_is_active() {
	[ -n "$(fw_wizard_get "$1" step)" ]
}

fw_wizard_cancel() {
	local chat_id="$1"
	fw_wizard_clear "$chat_id"
	tg_send "$chat_id" "🧱 已取消新增端口映射。"
}

fw_wizard_summary() {
	local chat_id="$1"
	local name proto src dest dest_ip dest_port src_port host_name
	name="$(fw_wizard_get "$chat_id" name)"
	proto="$(fw_wizard_get "$chat_id" proto)"
	src="$(fw_wizard_get "$chat_id" src)"
	dest="$(fw_wizard_get "$chat_id" dest)"
	dest_ip="$(fw_wizard_get "$chat_id" dest_ip)"
	src_port="$(fw_wizard_get "$chat_id" src_dport)"
	dest_port="$(fw_wizard_get "$chat_id" dest_port)"
	host_name="$(fw_host_name_by_ip "$dest_ip")"
	[ -n "$host_name" ] && [ "$host_name" != "-" ] || host_name="未命名主机"
	cat <<EOF
名称: ${name}
协议: ${proto}
来源分区: ${src}
目标分区: ${dest}
内网主机: ${host_name} (${dest_ip})
外网端口: ${src_port}
内网端口: ${dest_port}
EOF
}

fw_wizard_prompt_name() {
	local chat_id="$1"
	tg_send_inline "$chat_id" "🧱 新增端口映射\n第 1 步：请输入规则名称，例如 NAS、相机、飞牛。" '{"inline_keyboard":[[{"text":"取消新增映射","callback_data":"fwadd_cancel"}]]}'
}

fw_wizard_prompt_protocol() {
	local chat_id="$1"
	tg_send_inline "$chat_id" "🧱 第 2 步：请选择协议。" '{"inline_keyboard":[[{"text":"TCP","callback_data":"fwadd_proto:tcp"},{"text":"UDP","callback_data":"fwadd_proto:udp"}],[{"text":"TCP+UDP","callback_data":"fwadd_proto:tcp udp"}],[{"text":"取消新增映射","callback_data":"fwadd_cancel"}]]}'
}

fw_wizard_prompt_host() {
	local chat_id="$1"
	local hosts panel
	hosts="$(fw_list_hosts | head -n 20)"
	panel="$(printf "%s\n" "$hosts" | awk -F'|' '
		BEGIN {
			printf "{\"inline_keyboard\":[[{\"text\":\"✍️ 手动输入 IP\",\"callback_data\":\"fwadd_host_manual\"}]"
			first=1
		}
		{
			if($0==""){ next }
			label=$1
			if($2 != "" && $2 != "-"){
				label=$2 " (" $1 ")"
			}
			gsub(/"/, "\\\"", label)
			gsub(/"/, "\\\"", $1)
			printf ",[{\"text\":\"%s\",\"callback_data\":\"fwadd_host:%s\"}]", label, $1
		}
		END {
			printf ",[{\"text\":\"取消新增映射\",\"callback_data\":\"fwadd_cancel\"}]]}"
		}
	')"
	tg_send_inline "$chat_id" "🧱 第 3 步：请选择内网主机，或者手动输入 IP。" "$panel"
}

fw_wizard_prompt_manual_host() {
	local chat_id="$1"
	tg_send_inline "$chat_id" "🧱 第 3 步：请输入内网主机 IP，例如 192.168.31.2。" '{"inline_keyboard":[[{"text":"取消新增映射","callback_data":"fwadd_cancel"}]]}'
}

fw_wizard_prompt_src_port() {
	local chat_id="$1"
	tg_send_inline "$chat_id" "🧱 第 4 步：请输入外网端口，支持单个端口或范围，例如 702、8000-8010。" '{"inline_keyboard":[[{"text":"取消新增映射","callback_data":"fwadd_cancel"}]]}'
}

fw_wizard_prompt_dest_port_mode() {
	local chat_id="$1"
	tg_send_inline "$chat_id" "🧱 第 5 步：内网端口要怎么设置？" '{"inline_keyboard":[[{"text":"与外网端口相同","callback_data":"fwadd_dport_same"},{"text":"手动输入内网端口","callback_data":"fwadd_dport_manual"}],[{"text":"取消新增映射","callback_data":"fwadd_cancel"}]]}'
}

fw_wizard_prompt_dest_port() {
	local chat_id="$1"
	tg_send_inline "$chat_id" "🧱 第 5 步：请输入内网端口，支持单个端口或范围，例如 80、9000-9010。" '{"inline_keyboard":[[{"text":"取消新增映射","callback_data":"fwadd_cancel"}]]}'
}

fw_wizard_prompt_confirm() {
	local chat_id="$1"
	local summary
	summary="$(fw_wizard_summary "$chat_id")"
	tg_send_inline "$chat_id" "🧱 请确认要创建的端口映射：\n${summary}" '{"inline_keyboard":[[{"text":"✅ 创建并启用","callback_data":"fwadd_create:1"},{"text":"⚪ 创建但先停用","callback_data":"fwadd_create:0"}],[{"text":"取消新增映射","callback_data":"fwadd_cancel"}]]}'
}

fw_wizard_start() {
	local chat_id="$1"
	fw_wizard_clear "$chat_id"
	fw_wizard_set "$chat_id" step "name"
	fw_wizard_prompt_name "$chat_id"
}

fw_wizard_handle_text() {
	local chat_id="$1"
	local text="$2"
	local step
	step="$(fw_wizard_get "$chat_id" step)"
	[ -n "$step" ] || return 1

	case "$step" in
		name)
			if [ -z "$text" ]; then
				tg_send "$chat_id" "❌ 规则名称不能为空，请重新输入。"
				return 0
			fi
			fw_wizard_set "$chat_id" name "$text"
			fw_wizard_set "$chat_id" step "protocol"
			fw_wizard_prompt_protocol "$chat_id"
			return 0
			;;
		dest_ip)
			if ! fw_ipv4_is_valid "$text"; then
				tg_send "$chat_id" "❌ IP 格式不对，请输入类似 192.168.31.2 的 IPv4 地址。"
				return 0
			fi
			fw_wizard_set "$chat_id" dest_ip "$text"
			fw_wizard_set "$chat_id" step "src_port"
			tg_send "$chat_id" "✅ 已记录内网主机：$text"
			fw_wizard_prompt_src_port "$chat_id"
			return 0
			;;
		src_port)
			if ! fw_port_is_valid "$text"; then
				tg_send "$chat_id" "❌ 外网端口格式不对，请输入 1-65535 的端口，或形如 8000-8010 的范围。"
				return 0
				fi
				fw_wizard_set "$chat_id" src_dport "$text"
				fw_wizard_set "$chat_id" step "dest_port_mode"
				fw_wizard_prompt_dest_port_mode "$chat_id"
			return 0
			;;
			dest_port)
				if ! fw_port_is_valid "$text"; then
					tg_send "$chat_id" "❌ 内网端口格式不对，请输入 1-65535 的端口，或形如 8000-8010 的范围。"
					return 0
				fi
				fw_wizard_set "$chat_id" dest_port "$text"
				fw_wizard_set "$chat_id" step "confirm"
				tg_send "$chat_id" "✅ 已记录内网端口：$text，正在生成确认信息。"
				fw_wizard_prompt_confirm "$chat_id"
				return 0
				;;
	esac

	return 1
}

fw_wizard_create() {
	local chat_id="$1"
	local enabled="$2"
	local name proto src dest dest_ip src_dport dest_port sec

	name="$(fw_wizard_get "$chat_id" name)"
	proto="$(fw_wizard_get "$chat_id" proto)"
	src="$(fw_wizard_get "$chat_id" src)"
	dest="$(fw_wizard_get "$chat_id" dest)"
	dest_ip="$(fw_wizard_get "$chat_id" dest_ip)"
	src_dport="$(fw_wizard_get "$chat_id" src_dport)"
	dest_port="$(fw_wizard_get "$chat_id" dest_port)"

	sec="$(fw_create_redirect "$name" "$src" "$proto" "$dest" "$dest_ip" "$src_dport" "$dest_port" "$enabled" 2>/dev/null)" || {
		tg_send "$chat_id" "❌ 创建端口映射失败，请稍后再试。"
		return 1
	}

	fw_wizard_clear "$chat_id"
	tg_send "$chat_id" "✅ 端口映射已创建：${name}\nsection: ${sec}"
	send_forward_panel "$chat_id"
	return 0
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
	local cbid="${3:-}"
	local out="" cmd arg mapped sec

	cmd="$(echo "$text" | awk '{print $1}')"
	arg="$(echo "$text" | cut -d' ' -f2-)"

	case "$text" in
		"🚦 系统状态"|"系统状态") mapped="/status" ;;
		"🧭 Passwall状态"|"Passwall状态") mapped="/passwall" ;;
		"🧠 CPU信息"|"CPU信息") mapped="/cpu" ;;
		"💾 内存信息"|"内存信息") mapped="/mem" ;;
		"🌐 端口信息"|"端口信息") mapped="/ports" ;;
		"🖥️ 在线主机"|"在线主机") mapped="/online" ;;
		"🧱 端口映射"|"端口映射") mapped="/forwards" ;;
		"➕ 新增映射"|"新增映射") mapped="/add_forward" ;;
		"🧩 节点列表"|"节点列表") mapped="/nodes" ;;
		"🎛️ 节点面板"|"节点面板") mapped="/nodepanel" ;;
		"✅ 开启Passwall"|"开启Passwall") mapped="/enable_pw" ;;
		"⛔ 关闭Passwall"|"关闭Passwall") mapped="/disable_pw" ;;
		"📨 每日推送测试"|"每日推送测试") mapped="/daily_now" ;;
		"🔁 重启路由"|"重启路由") mapped="/reboot" ;;
		"📖 帮助"|"帮助") mapped="/help" ;;
		"菜单") mapped="/menu" ;;
		*) mapped="$cmd" ;;
	esac

	case "$mapped" in
		/start|/help)
			out="✨ jdc-TGbot 指令
/status 查看路由器总览
/online 查看在线主机
/forwards 查看端口映射
/forwardpanel 打开端口映射面板
/add_forward 交互新增映射
/cpu 查看CPU负载
/mem 查看内存(MB)
/ports 查看监听端口
/passwall 查看Passwall状态
/nodes 查看节点列表
/nodepanel 可点击节点面板
/enable_pw 开启Passwall
/disable_pw 关闭Passwall
/switch <节点备注或section>
/import <ss/vmess/vless/trojan链接>
/reboot 重启路由器
/daily_now 测试日报
/menu 打开中文菜单"
			tg_send "$chat_id" "$out"
			;;
		/add_forward)
			fw_wizard_start "$chat_id"
			;;
		/menu)
			tg_menu "$chat_id"
			;;
		/status|/host)
			tg_send "$chat_id" "$(cmd_status)"
			;;
		/online)
			tg_send "$chat_id" "$(cmd_online)"
			;;
		/forwards)
			tg_send "$chat_id" "$(cmd_forwards)"
			;;
		/forwardpanel)
			send_forward_panel "$chat_id"
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
		/nodepanel)
			send_node_panel "$chat_id"
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
		/reboot)
			tg_send_inline "$chat_id" "⚠️ 确认重启路由器？" '{"inline_keyboard":[[{"text":"确认重启","callback_data":"reboot_confirm"},{"text":"取消","callback_data":"noop"}]]}'
			;;
		/daily_now)
			tg_send "$chat_id" "$(build_daily_report)"
			;;
		noop)
			tg_answer_callback "$cbid" "已取消"
			;;
		nodes_panel)
			send_node_panel "$chat_id"
			;;
		forwards_panel)
			send_forward_panel "$chat_id"
			;;
		forward_add)
			fw_wizard_start "$chat_id"
			tg_answer_callback "$cbid" "已进入新增映射向导"
			;;
		fwadd_cancel)
			fw_wizard_cancel "$chat_id"
			tg_answer_callback "$cbid" "已取消"
			;;
		fwadd_proto:*)
			fw_wizard_set "$chat_id" proto "${mapped#fwadd_proto:}"
			fw_wizard_set "$chat_id" src "wan"
			fw_wizard_set "$chat_id" dest "lan"
			fw_wizard_set "$chat_id" step "host"
			fw_wizard_prompt_host "$chat_id"
			tg_answer_callback "$cbid" "已选择协议，默认使用 wan -> lan"
			;;
		fwadd_host:*)
			fw_wizard_set "$chat_id" dest_ip "${mapped#fwadd_host:}"
			fw_wizard_set "$chat_id" step "src_port"
			fw_wizard_prompt_src_port "$chat_id"
			tg_answer_callback "$cbid" "已选择内网主机"
			;;
		fwadd_host_manual)
			fw_wizard_set "$chat_id" step "dest_ip"
			fw_wizard_prompt_manual_host "$chat_id"
			tg_answer_callback "$cbid" "请发送内网 IP"
			;;
		fwadd_dport_same)
			fw_wizard_set "$chat_id" dest_port "$(fw_wizard_get "$chat_id" src_dport)"
			fw_wizard_set "$chat_id" step "confirm"
			tg_send "$chat_id" "✅ 已使用与外网相同的内网端口，正在生成确认信息。"
			fw_wizard_prompt_confirm "$chat_id"
			tg_answer_callback "$cbid" "已使用相同端口"
			;;
		fwadd_dport_manual)
			fw_wizard_set "$chat_id" step "dest_port"
			fw_wizard_prompt_dest_port "$chat_id"
			tg_answer_callback "$cbid" "请发送内网端口"
			;;
		fwadd_create:*)
			fw_wizard_create "$chat_id" "${mapped#fwadd_create:}"
			tg_answer_callback "$cbid" "已提交创建"
			;;
		pw_disable)
			if pw_set_enabled 0; then
				tg_send "$chat_id" "⛔ 已关闭 Passwall。"
			else
				tg_send "$chat_id" "❌ 关闭 Passwall 失败。"
			fi
			tg_answer_callback "$cbid" "执行完成"
			;;
		reboot_confirm)
			tg_send "$chat_id" "🔁 路由器正在重启，请稍等 1-2 分钟。"
			tg_answer_callback "$cbid" "已执行重启"
			reboot >/dev/null 2>&1 &
			;;
		node:*)
			sec="${mapped#node:}"
			send_node_actions "$chat_id" "$sec" "$cbid"
			;;
		forward:*)
			sec="${mapped#forward:}"
			send_forward_actions "$chat_id" "$sec" "$cbid"
			;;
		forward_enable:*)
			sec="${mapped#forward_enable:}"
			if fw_set_enabled "$sec" 1; then
				tg_send "$chat_id" "✅ 已启用端口映射: $(fw_get_display_name "$sec")"
			else
				tg_send "$chat_id" "❌ 启用端口映射失败: $sec"
			fi
			tg_answer_callback "$cbid" "执行完成"
			;;
		forward_disable:*)
			sec="${mapped#forward_disable:}"
			if fw_set_enabled "$sec" 0; then
				tg_send "$chat_id" "⛔ 已停用端口映射: $(fw_get_display_name "$sec")"
			else
				tg_send "$chat_id" "❌ 停用端口映射失败: $sec"
			fi
			tg_answer_callback "$cbid" "执行完成"
			;;
		node_enable:*)
			sec="${mapped#node_enable:}"
			if pw_switch_node "$sec" && pw_set_enabled 1; then
				tg_send "$chat_id" "✅ 已启用节点: $(pw_get_current_node_display)"
			else
				tg_send "$chat_id" "❌ 启用节点失败: $sec"
			fi
			tg_answer_callback "$cbid" "执行完成"
			;;
		node_edit:*)
			sec="${mapped#node_edit:}"
			tg_send "$chat_id" "🛠 修改节点建议在 LuCI 内进行：服务 -> Passwall -> 节点管理。\n当前节点 section: ${sec}"
			tg_answer_callback "$cbid" "已发送修改说明"
			;;
		node_delete:*)
			sec="${mapped#node_delete:}"
			if pw_delete_node "$sec"; then
				tg_send "$chat_id" "🗑️ 节点已删除: $sec"
				send_node_panel "$chat_id"
			else
				tg_send "$chat_id" "❌ 删除失败（可能是分流/非节点类型）: $sec"
			fi
			tg_answer_callback "$cbid" "执行完成"
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
		cbid="$(echo "$upd" | jq -r '.callback_query.id // empty')"

		[ -n "$chat_id" ] || continue
		[ -n "$text" ] || continue

		if ! is_admin "$chat_id" "$user_id"; then
			log "ignore non-admin chat_id=${chat_id} user_id=${user_id}"
			continue
		fi

		if fw_wizard_is_active "$chat_id"; then
			case "$text" in
				"取消"|"取消新增映射"|"/cancel")
					fw_wizard_cancel "$chat_id"
					continue
					;;
				/*)
					;;
				*)
					if fw_wizard_handle_text "$chat_id" "$text"; then
						continue
					fi
					;;
			esac
		fi

		handle_command "$chat_id" "$text" "$cbid"
	done

	sleep 1
done
