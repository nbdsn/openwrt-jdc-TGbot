#!/bin/sh

uri="$1"

if [ -z "$uri" ]; then
	echo "ERR: empty uri"
	exit 1
fi

# v1: stub entry point; replace with protocol-specific parser in v2.
# keep uri in a temp file for operator audit.
mkdir -p /tmp/tgpasswall
ts="$(date +%s)"
printf '%s\n' "$uri" > "/tmp/tgpasswall/import_${ts}.txt"
echo "OK: import request recorded"
