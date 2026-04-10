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

tg_menu() {
	local chat_id="$1"
	local kb='{"keyboard":[["/status","/passwall"],["/cpu","/mem"],["/ports","/nodes"]],"resize_keyboard":true}'
	curl -fsS "${API_URL}/sendMessage" \
		-d "chat_id=${chat_id}" \
		--data-urlencode "text=TG Passwall menu ready." \
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
	status_summary
}

cmd_cpu() {
	printf "CPU loadavg: %s\n" "$(get_loadavg)"
}

cmd_mem() {
	get_meminfo
}

cmd_ports() {
	get_ports | head -n 40
}

cmd_passwall() {
	printf "Passwall enabled: %s\n" "$(pw_get_enabled)"
	printf "Current node: %s\n" "$(pw_get_current_node)"
}

build_daily_report() {
	printf "Daily Router Report\n"
	printf "Time: %s\n\n" "$(date '+%Y-%m-%d %H:%M:%S')"
	status_summary
	printf "\n"
	cmd_passwall
}

cmd_nodes() {
	pw_list_nodes | head -n 60
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
	local out=""
	local cmd arg

	cmd="$(echo "$text" | awk '{print $1}')"
	arg="$(echo "$text" | cut -d' ' -f2-)"

	case "$cmd" in
		/start|/help)
			out="TG Passwall commands:
/status /host /cpu /mem /ports
/passwall /nodes
/enable_pw /disable_pw
/switch <section_name>
/import <node_uri>
/daily_now
/menu"
			tg_send "$chat_id" "$out"
			;;
		/menu)
			tg_menu "$chat_id"
			;;
		/status|/host)
			out="$(cmd_status)"
			tg_send "$chat_id" "$out"
			;;
		/cpu)
			out="$(cmd_cpu)"
			tg_send "$chat_id" "$out"
			;;
		/mem)
			out="$(cmd_mem)"
			tg_send "$chat_id" "$out"
			;;
		/ports)
			out="$(cmd_ports)"
			tg_send "$chat_id" "$out"
			;;
		/passwall)
			out="$(cmd_passwall)"
			tg_send "$chat_id" "$out"
			;;
		/nodes)
			out="$(cmd_nodes)"
			tg_send "$chat_id" "$out"
			;;
		/enable_pw)
			if pw_set_enabled 1; then
				tg_send "$chat_id" "Passwall enabled."
			else
				tg_send "$chat_id" "Passwall enable failed."
			fi
			;;
		/disable_pw)
			if pw_set_enabled 0; then
				tg_send "$chat_id" "Passwall disabled."
			else
				tg_send "$chat_id" "Passwall disable failed."
			fi
			;;
		/switch)
			if [ -z "$arg" ] || [ "$arg" = "$cmd" ]; then
				tg_send "$chat_id" "Usage: /switch <section_name>"
			elif pw_switch_node "$arg"; then
				tg_send "$chat_id" "Switched to node: $arg"
			else
				tg_send "$chat_id" "Switch node failed: $arg"
			fi
			;;
		/import)
			if [ -z "$arg" ] || [ "$arg" = "$cmd" ]; then
				tg_send "$chat_id" "Usage: /import <node_uri>"
			else
				msg="$("${BASE_DIR}/pw_import.sh" "$arg" 2>&1)"
				tg_send "$chat_id" "$msg"
			fi
			;;
		/daily_now)
			out="$(build_daily_report)"
			tg_send "$chat_id" "$out"
			;;
		*)
			if [ "$ALLOW_NON_COMMAND_MENU" = "1" ] && [ "$text" = "menu" ]; then
				tg_menu "$chat_id"
			fi
			;;
	esac
}

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
