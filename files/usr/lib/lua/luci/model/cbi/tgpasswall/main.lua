local m, s, o

m = Map("tgpasswall", "TG Passwall 插件", "通过 Telegram 机器人管理路由器状态和 Passwall 节点。")

s = m:section(TypedSection, "main", "基础设置")
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", "启用服务")
o.rmempty = false
o.description = "开启后，后台会启动 TG Bot 监听消息并执行命令。"

o = s:option(Value, "bot_token", "Bot Token")
o.password = true
o.rmempty = false
o.description = "从 BotFather 获取，例如 123456:ABCDEF。请勿泄露。"

o = s:option(Value, "admin_chat_id", "管理员 Chat ID")
o.rmempty = false
o.description = "仅此聊天可控制路由器。可用 @userinfobot 获取。"

o = s:option(Value, "admin_user_id", "管理员 User ID（可选）")
o.rmempty = true
o.description = "二次校验用户 ID，留空则仅校验 Chat ID。"

o = s:option(Value, "poll_timeout", "TG 拉取超时（秒）")
o.datatype = "uinteger"
o.default = 25
o.description = "建议 20-30 秒，值越大请求频率越低。"

o = s:option(Value, "api_base", "Telegram API 地址")
o.default = "https://api.telegram.org"
o.rmempty = false
o.description = "默认官方地址；若你使用代理网关可改这里。"

o = s:option(Flag, "daily_push_enabled", "启用每日定时推送")
o.default = "0"
o.rmempty = false
o.description = "开启后会每天推送一次路由器状态和 Passwall 状态。"

o = s:option(Value, "daily_push_hour", "每日推送小时（0-23）")
o.datatype = "range(0,23)"
o.default = "8"
o.rmempty = false
o.description = "例如填 8 表示每天 08:xx 推送。"

o = s:option(Value, "daily_push_minute", "每日推送分钟（0-59）")
o.datatype = "range(0,59)"
o.default = "0"
o.rmempty = false
o.description = "例如填 30 表示每天 xx:30 推送。"

o = s:option(Value, "passwall_service", "Passwall 服务名")
o.default = "passwall"
o.rmempty = false
o.description = "默认 passwall；若你的环境服务名不同，请改成实际值。"

o = s:option(Value, "passwall_global_section", "Passwall 全局 section")
o.default = "@global[0]"
o.rmempty = false
o.description = "通常保持默认 @global[0]。"

o = s:option(Value, "passwall_enabled_key", "Passwall 启用字段名")
o.default = "enabled"
o.rmempty = false
o.description = "用于启用/关闭 Passwall 的字段名。"

o = s:option(Value, "passwall_node_key", "Passwall 当前节点字段名")
o.default = "tcp_node"
o.rmempty = false
o.description = "用于切换当前节点的字段名。常见为 tcp_node。"

o = s:option(Value, "passwall_node_section_type", "Passwall 节点 section 类型")
o.default = "nodes"
o.rmempty = false
o.description = "导入节点时新增 section 的类型，常见为 nodes。"

o = s:option(Flag, "allow_non_command_menu", "允许中文“菜单”文本触发")
o.default = "1"
o.description = "开启后发送“菜单”两个字也会弹出 TG 键盘。"

m.on_after_commit = function(self)
	luci.sys.call("/etc/init.d/tgpasswall restart >/dev/null 2>&1")
end

return m
