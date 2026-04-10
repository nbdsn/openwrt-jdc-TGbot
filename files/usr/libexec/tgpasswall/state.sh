#!/bin/sh

get_hostname() {
	uci -q get system.@system[0].hostname 2>/dev/null || uname -n
}

get_uptime() {
	cut -d. -f1 /proc/uptime 2>/dev/null
}

get_loadavg() {
	cat /proc/loadavg 2>/dev/null | awk '{print $1" "$2" "$3}'
}

get_meminfo() {
	awk '
		/MemTotal:/ {t=$2}
		/MemAvailable:/ {a=$2}
		END {
			u=t-a
			printf("内存总量KB=%s\n已用内存KB=%s\n可用内存KB=%s\n", t, u, a)
		}
	' /proc/meminfo
}

get_ports() {
	if command -v ss >/dev/null 2>&1; then
		ss -lntup 2>/dev/null
	else
		netstat -lntup 2>/dev/null
	fi
}

status_summary() {
	h="$(get_hostname)"
	u="$(get_uptime)"
	l="$(get_loadavg)"
	m="$(get_meminfo)"

	printf "主机名: %s\n运行时长(秒): %s\n系统负载: %s\n%s\n" "$h" "$u" "$l" "$m"
}
