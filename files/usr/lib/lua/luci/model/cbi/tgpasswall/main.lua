local m, s, o

m = Map("tgpasswall", "TG Passwall", "Telegram Bot controller for system status and Passwall operations.")

s = m:section(TypedSection, "main", "Main Settings")
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", "Enable Service")
o.rmempty = false

o = s:option(Value, "bot_token", "Bot Token")
o.password = true
o.rmempty = false

o = s:option(Value, "admin_chat_id", "Admin Chat ID")
o.rmempty = false

o = s:option(Value, "admin_user_id", "Admin User ID")
o.rmempty = true

o = s:option(Value, "poll_timeout", "Poll Timeout (sec)")
o.datatype = "uinteger"
o.default = 25

o = s:option(Value, "api_base", "Telegram API Base")
o.default = "https://api.telegram.org"
o.rmempty = false

o = s:option(Flag, "daily_push_enabled", "Enable Daily Router Report")
o.default = "0"
o.rmempty = false

o = s:option(Value, "daily_push_hour", "Daily Push Hour (0-23)")
o.datatype = "range(0,23)"
o.default = "8"
o.rmempty = false

o = s:option(Value, "daily_push_minute", "Daily Push Minute (0-59)")
o.datatype = "range(0,59)"
o.default = "0"
o.rmempty = false

o = s:option(Value, "passwall_service", "Passwall Init Service")
o.default = "passwall"
o.rmempty = false

o = s:option(Value, "passwall_global_section", "Passwall Global Section")
o.default = "@global[0]"
o.rmempty = false

o = s:option(Value, "passwall_enabled_key", "Passwall Enabled Key")
o.default = "enabled"
o.rmempty = false

o = s:option(Value, "passwall_node_key", "Passwall Node Key")
o.default = "tcp_node"
o.rmempty = false

o = s:option(Flag, "allow_non_command_menu", "Allow 'menu' plain text trigger")
o.default = "1"

m.on_after_commit = function(self)
	luci.sys.call("/etc/init.d/tgpasswall restart >/dev/null 2>&1")
end

return m
