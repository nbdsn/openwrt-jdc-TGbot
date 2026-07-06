#!/bin/sh

get_board_json() {
	ubus call system board 2>/dev/null
}

get_hostname() {
	uci -q get system.@system[0].hostname 2>/dev/null || uname -n
}

get_model() {
	local model
	model="$(get_board_json | jsonfilter -e '@.model' 2>/dev/null)"
	[ -n "$model" ] || model="$(cat /tmp/sysinfo/model 2>/dev/null)"
	[ -n "$model" ] || model="$(uname -m 2>/dev/null)"
	echo "$model"
}

get_release_description() {
	local desc
	desc="$(get_board_json | jsonfilter -e '@.release.description' 2>/dev/null)"
	[ -n "$desc" ] || desc="$(awk -F"'" '/DISTRIB_DESCRIPTION=/ {print $2}' /etc/openwrt_release 2>/dev/null)"
	echo "$desc"
}

get_uptime_seconds() {
	cut -d. -f1 /proc/uptime 2>/dev/null
}

get_uptime_human() {
	local sec d h m s
	sec="$(get_uptime_seconds)"
	[ -n "$sec" ] || sec=0
	d=$((sec / 86400))
	h=$(((sec % 86400) / 3600))
	m=$(((sec % 3600) / 60))
	s=$((sec % 60))
	printf "%d天 %d小时 %d分 %d秒" "$d" "$h" "$m" "$s"
}

get_loadavg() {
	awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null
}

get_cpu_cores() {
	local n
	n="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
	[ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null || n=1
	echo "$n"
}

get_cpu_load_percent() {
	local load1 cores pct
	load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
	[ -n "$load1" ] || load1="0"
	cores="$(get_cpu_cores)"
	[ -n "$cores" ] || cores=1
	pct="$(awk -v l="$load1" -v c="$cores" 'BEGIN {
		if (c <= 0) c = 1
		v = (l / c) * 100
		if (v < 0) v = 0
		if (v > 999) v = 999
		printf "%.0f", v
	}')"
	echo "$pct"
}

get_cpu_temp_c() {
	local path raw
	for path in \
		/sys/class/thermal/thermal_zone0/temp \
		/sys/class/thermal/thermal_zone1/temp \
		/sys/devices/virtual/thermal/thermal_zone0/temp \
		/sys/devices/virtual/thermal/thermal_zone1/temp
	do
		[ -f "$path" ] || continue
		raw="$(cat "$path" 2>/dev/null)"
		[ -n "$raw" ] || continue
		case "$raw" in
			*[!0-9]*)
				continue
				;;
		esac
		if [ "$raw" -ge 1000 ] 2>/dev/null; then
			awk -v t="$raw" 'BEGIN { printf "%.1f", t / 1000 }'
		else
			awk -v t="$raw" 'BEGIN { printf "%.1f", t }'
		fi
		return 0
	done

	echo "-"
}

get_cpu_summary() {
	printf "CPU 负载: %s\n" "$(get_loadavg)"
	printf "CPU 占用估算: %s%%\n" "$(get_cpu_load_percent)"
	printf "CPU 温度: %s°C\n" "$(get_cpu_temp_c)"
}

get_public_ipv4() {
	local ip
	ip="$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)"
	[ -n "$ip" ] || ip="$(ubus call network.interface.wwan status 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)"
	[ -n "$ip" ] || ip="$(ifstatus wan 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)"
	[ -n "$ip" ] || ip="-"
	echo "$ip"
}

get_wifi_ssids() {
	local ssids
	ssids="$(uci -q show wireless 2>/dev/null | awk -F= '
		$1 ~ /^wireless\.[^.]+\.ssid$/ {
			v=$2
			gsub(/^'\''|'\''$/, "", v)
			if (v != "" && !seen[v]++) {
				list = list ? list ", " v : v
			}
		}
		END {
			if (list != "") print list
		}
	')"
	[ -n "$ssids" ] || ssids="-"
	echo "$ssids"
}

get_mem_kb() {
	awk '
		/MemTotal:/ {t=$2}
		/MemAvailable:/ {a=$2}
		END {
			u=t-a
			printf "%s %s %s\n", t, u, a
		}
	' /proc/meminfo
}

get_mem_summary_mb() {
	local t u a tp up ap pct
	read -r t u a <<EOF
$(get_mem_kb)
EOF
	[ -n "$t" ] || t=0
	[ -n "$u" ] || u=0
	[ -n "$a" ] || a=0
	tp=$((t / 1024))
	up=$((u / 1024))
	ap=$((a / 1024))
	if [ "$t" -gt 0 ]; then
		pct=$((u * 100 / t))
	else
		pct=0
	fi
	printf "总内存: %d MB\n已用内存: %d MB (%d%%)\n可用内存: %d MB\n" "$tp" "$up" "$pct" "$ap"
}

get_storage_summary_mb() {
	df -m / 2>/dev/null | awk 'NR==2 {
		total=$2; used=$3; avail=$4; pct=$5
		printf "系统存储: %s MB / %s MB (剩余 %s MB, 已用 %s)\n", used, total, avail, pct
	}'
}

get_ports() {
	if command -v ss >/dev/null 2>&1; then
		ss -lntup 2>/dev/null
	else
		netstat -lntup 2>/dev/null
	fi
}

get_online_hosts() {
	if command -v ip >/dev/null 2>&1; then
		{
			cat /tmp/dhcp.leases 2>/dev/null
			echo "__TG_NEIGH__"
			ip neigh show 2>/dev/null
		} | awk '
			seen_neigh == 0 {
				if ($0 == "__TG_NEIGH__") {
					seen_neigh=1
					next
				}
				name=$4
				if (name == "" || name == "*") {
					name="-"
				}
				lease[$3]=name
				next
			}
			($1 !~ /:/) && ($(NF)=="REACHABLE" || $(NF)=="STALE" || $(NF)=="DELAY" || $(NF)=="PROBE") {
				host=(lease[$1] ? lease[$1] : "-")
				if ($4=="lladdr") {
					printf "%s  host=%s  iface=%s  mac=%s  state=%s\n", $1, host, $3, $5, $(NF)
				} else {
					printf "%s  host=%s  iface=%s  state=%s\n", $1, host, $3, $(NF)
				}
			}
		'
	else
		arp -an 2>/dev/null
	fi
}

status_summary() {
	printf "机型: %s\n" "$(get_model)"
	printf "固件: %s\n" "$(get_release_description)"
	printf "主机名: %s\n" "$(get_hostname)"
	printf "公网 IP: %s\n" "$(get_public_ipv4)"
	printf "Wi-Fi: %s\n" "$(get_wifi_ssids)"
	printf "运行时长: %s\n" "$(get_uptime_human)"
	printf "%s" "$(get_cpu_summary)"
	printf "%s" "$(get_mem_summary_mb)"
	printf "%s\n" "$(get_storage_summary_mb)"
}
