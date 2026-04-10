#!/bin/sh

get_hostname() {
	uci -q get system.@system[0].hostname 2>/dev/null || uname -n
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
		ip neigh show 2>/dev/null | awk '
			($(NF)=="REACHABLE" || $(NF)=="STALE" || $(NF)=="DELAY" || $(NF)=="PROBE") {
				if ($4=="lladdr") {
					printf "%s  iface=%s  mac=%s  state=%s\n", $1, $3, $5, $(NF)
				} else {
					printf "%s  iface=%s  state=%s\n", $1, $3, $(NF)
				}
			}
		'
	else
		arp -an 2>/dev/null
	fi
}

status_summary() {
	printf "主机名: %s\n" "$(get_hostname)"
	printf "运行时长: %s\n" "$(get_uptime_human)"
	printf "系统负载: %s\n" "$(get_loadavg)"
	printf "%s" "$(get_mem_summary_mb)"
	printf "%s\n" "$(get_storage_summary_mb)"
}
