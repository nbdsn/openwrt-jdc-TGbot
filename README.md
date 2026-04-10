# luci-app-tgpasswall

OpenWrt plugin for Telegram Bot control and `luci-app-passwall` operations.

After installing this plugin, you can configure it in:

- `Services -> TG Passwall`

and set:

- Telegram Bot Token
- Telegram Admin Chat ID / User ID
- Daily report switch
- Daily report time (hour/minute)

## What It Can Do

- Query router status from Telegram:
  - `/status` `/host` `/cpu` `/mem` `/ports`
- Query Passwall status:
  - `/passwall` `/nodes`
- Control Passwall:
  - `/enable_pw` `/disable_pw` `/switch <node_section>`
- Import node URI entrypoint:
  - `/import <uri>` (v1 writes request to temp file; parser can be extended)
- Daily scheduled report:
  - Pushes router + passwall summary once per day at configured hour/minute
- Quick menu:
  - `/menu`

## Repository Layout

- `Makefile`
- `files/etc/config/tgpasswall`
- `files/etc/init.d/tgpasswall`
- `files/usr/libexec/tgpasswall/bot.sh`
- `files/usr/libexec/tgpasswall/state.sh`
- `files/usr/libexec/tgpasswall/pw.sh`
- `files/usr/libexec/tgpasswall/pw_import.sh`
- `files/usr/lib/lua/luci/controller/tgpasswall.lua`
- `files/usr/lib/lua/luci/model/cbi/tgpasswall/main.lua`
- `docs/ARCHITECTURE.md`

## Build (OpenWrt SDK / source tree)

Copy this repository into your OpenWrt source tree:

```sh
cp -r /path/to/openwrt-tg-bot /path/to/openwrt/package/luci-app-tgpasswall
```

Compile:

```sh
cd /path/to/openwrt
make menuconfig
# LuCI -> Applications -> luci-app-tgpasswall
make package/luci-app-tgpasswall/compile V=s
```

Generated ipk will be under:

- `bin/packages/<arch>/base/luci-app-tgpasswall_*.ipk`

## Install On Router

```sh
opkg install /tmp/luci-app-tgpasswall_*.ipk
```

Then open LuCI:

- `Services -> TG Passwall`

Set required fields:

- `Enable Service`
- `Bot Token`
- `Admin Chat ID`

Optional:

- `Admin User ID` (extra allowlist hardening)
- `Enable Daily Router Report`
- `Daily Push Hour (0-23)`
- `Daily Push Minute (0-59)`

Save & Apply will restart service automatically.

## CLI Quick Setup

```sh
uci set tgpasswall.main.enabled='1'
uci set tgpasswall.main.bot_token='REPLACE_WITH_BOT_TOKEN'
uci set tgpasswall.main.admin_chat_id='REPLACE_WITH_CHAT_ID'
uci set tgpasswall.main.daily_push_enabled='1'
uci set tgpasswall.main.daily_push_hour='8'
uci set tgpasswall.main.daily_push_minute='0'
uci commit tgpasswall
/etc/init.d/tgpasswall enable
/etc/init.d/tgpasswall restart
```

## Telegram Commands

- `/start` `/help`
- `/menu`
- `/status` `/host`
- `/cpu`
- `/mem`
- `/ports`
- `/passwall`
- `/nodes`
- `/enable_pw`
- `/disable_pw`
- `/switch <section_name>`
- `/import <node_uri>`
- `/daily_now` (manual test for daily report output)

## Daily Push Behavior

- The bot checks time in local router timezone.
- It sends once per day when `hour/minute` matches config.
- A local marker file prevents duplicate pushes on the same day.

## Security Notes

- Do not commit real token/chat id/user id to git.
- Only admin chat/user is accepted; other chats are ignored.
- Keep router shell and LuCI credentials outside this repository.
- Recommended: rotate Telegram token if it was ever exposed.

## Known Limits (v1)

- `/import` is a safe stub currently. It records import requests in `/tmp/tgpasswall/`.
- Passwall config key names vary across forks; configurable fields are provided in LuCI:
  - `passwall_global_section`
  - `passwall_enabled_key`
  - `passwall_node_key`

## License

Use under your own project policy. Add your preferred license file if you plan public distribution.
