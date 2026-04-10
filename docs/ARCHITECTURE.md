# 实现原理（Architecture）

## 1. 总体架构

插件采用 OpenWrt 原生组合：

- `procd` 守护进程
- `UCI` 配置中心
- `LuCI CBI` 页面配置
- `Shell` 脚本执行业务逻辑

这样做的目标是：依赖少、占用低、在大多数 OpenWrt 设备上可运行。

## 2. 组件说明

### 2.1 启动与守护

- 文件：`files/etc/init.d/tgpasswall`
- 作用：
  - 开机自启
  - 异常退出自动拉起
  - 使用 `procd` 管理 Bot 进程

### 2.2 配置中心

- 文件：`files/etc/config/tgpasswall`
- 作用：
  - 存储 Token、管理员 ID、定时推送时间
  - 存储 Passwall 字段映射（兼容不同分支）

### 2.3 LuCI 配置页

- 文件：
  - `files/usr/lib/lua/luci/controller/tgpasswall.lua`
  - `files/usr/lib/lua/luci/model/cbi/tgpasswall/main.lua`
- 作用：
  - 在 `服务 -> TG Passwall 插件` 提供可视化配置
  - 全中文字段 + 中文备注说明
  - 保存后自动重启服务生效

### 2.4 TG Bot 主循环

- 文件：`files/usr/libexec/tgpasswall/bot.sh`
- 作用：
  - 调用 Telegram `getUpdates` 长轮询
  - 校验管理员（Chat ID + 可选 User ID）
  - 处理指令和中文菜单文本
  - 调度每日定时推送

### 2.5 路由器状态采集

- 文件：`files/usr/libexec/tgpasswall/state.sh`
- 作用：
  - 读取主机名、运行时长、负载、内存、端口监听
  - 输出统一文本给 Bot 返回

### 2.6 Passwall 控制

- 文件：`files/usr/libexec/tgpasswall/pw.sh`
- 作用：
  - 通过 `uci` 读取/写入 Passwall 配置
  - 节点切换、启用关闭
  - `commit` 后重启/重载 passwall 服务

### 2.7 节点导入解析

- 文件：`files/usr/libexec/tgpasswall/pw_import.sh`
- 作用：
  - 解析 `ss://` `vmess://` `vless://` `trojan://`
  - 写入 Passwall 节点 section
  - 应用配置并重启/重载服务

## 3. 命令处理流程

1. 管理员向 Bot 发送命令或中文菜单文本。
2. `bot.sh` 收到 update，校验管理员身份。
3. 根据命令分发到状态脚本或 Passwall 控制脚本。
4. 结果通过 `sendMessage` 回推到 Telegram。

## 4. 每日定时推送机制

1. 每次主循环都会检查当前本地时间（路由器时区）。
2. 若达到设定时刻（小时+分钟）且当日未推送：
  - 生成“路由器状态 + Passwall 状态”报告
  - 推送给管理员 chat
  - 写入当日标记，防止重复推送

## 5. 兼容性设计

不同 Passwall 分支的字段并不完全一致，所以做了可配置映射：

- `passwall_global_section`
- `passwall_enabled_key`
- `passwall_node_key`
- `passwall_node_section_type`

当你的环境字段不同，只需在 LuCI 页面改参数，不需要改代码。

## 6. 安全策略

- 强制管理员白名单（Chat ID）
- 可选用户白名单（User ID）
- 非管理员消息直接忽略
- 代码仓库不存放真实 token/id

## 7. 后续可扩展方向

- 增强导入器对更多协议参数的映射（例如更完整 Reality 字段）
- 节点分页菜单与一键切换按钮
- 增加 WAN 状态、温度、流量等监控项
