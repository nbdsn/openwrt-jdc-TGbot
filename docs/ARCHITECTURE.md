# Architecture

## Overview

`luci-app-tgpasswall` is a lightweight OpenWrt plugin that bridges Telegram Bot commands with local router operations and `luci-app-passwall` control.

The design intentionally uses shell + UCI + procd to stay friendly to low-resource devices.

## Components

1. `procd service`
- File: `files/etc/init.d/tgpasswall`
- Starts and respawns the bot process.

2. `UCI config`
- File: `files/etc/config/tgpasswall`
- Stores runtime settings:
  - bot token
  - admin chat/user id
  - daily push schedule
  - passwall config key mapping

3. `Telegram bot loop`
- File: `files/usr/libexec/tgpasswall/bot.sh`
- Uses Telegram `getUpdates` long polling.
- Verifies admin allowlist.
- Dispatches command handlers.
- Performs scheduled daily report push.

4. `Router state collector`
- File: `files/usr/libexec/tgpasswall/state.sh`
- Reads data from `/proc` and system tools:
  - hostname
  - uptime
  - load
  - memory
  - listening ports

5. `Passwall controller`
- File: `files/usr/libexec/tgpasswall/pw.sh`
- Reads/writes passwall values through UCI.
- Applies changes by restarting/reloading passwall service.

6. `LuCI integration`
- Files:
  - `files/usr/lib/lua/luci/controller/tgpasswall.lua`
  - `files/usr/lib/lua/luci/model/cbi/tgpasswall/main.lua`
- Exposes menu path: `Services -> TG Passwall`.
- Save & Apply triggers service restart.

## Command Flow

1. Telegram message arrives in admin chat.
2. `bot.sh` receives update and validates sender.
3. Matching handler executes local script/UCI action.
4. Result is returned via Telegram `sendMessage`.

## Daily Push Flow

1. Each bot loop checks local router time.
2. If `daily_push_enabled=1` and `hour/minute` matches configured schedule:
- Build report (system + passwall status)
- Send report to admin chat
- Write today marker in `/tmp/tgpasswall.daily.last`
3. Marker prevents duplicate sends for the same day.

## Security Model

- Strict allowlist:
  - required `admin_chat_id`
  - optional `admin_user_id`
- Non-admin messages are ignored.
- No credentials are hardcoded in source.
- Sensitive values are expected to be configured on device via LuCI/UCI.

## Compatibility Notes

- Passwall schema differs between forks.
- The plugin keeps section/key fields configurable:
  - `passwall_global_section`
  - `passwall_enabled_key`
  - `passwall_node_key`

## Extension Plan

- v2 node URI parser for `ss/vmess/vless/trojan` import.
- inline keyboard pagination for large node lists.
- richer status (temperature, WAN summary, iptables counters) based on device capabilities.
