# openwrt-jdc-TGbot

OpenWrt 插件：在 Telegram 中查看路由器状态、管理 Passwall，并支持每日定时推送。

GitHub 仓库：

- `https://github.com/nbdsn/openwrt-jdc-TGbot`

安装后在 LuCI 菜单中可见：

- `服务 -> jdc-TGbot`

你可以在页面中直接设置：

- Bot Token
- 管理员 Chat ID / User ID
- 每日定时推送开关
- 每日推送时间（小时 / 分钟）

## 已实现功能

- Telegram 指令查询：
  - `/status` `/host` `/cpu` `/mem` `/ports`
- Passwall 状态与控制：
  - `/passwall` `/nodes`
  - `/enable_pw` `/disable_pw`
  - `/switch <section_name>`
- 节点导入（真实解析）：
  - `/import <uri>`
  - 支持：`ss://` `vmess://` `vless://` `trojan://`
- 每日定时推送：
  - 根据 LuCI 配置的“小时 + 分钟”每天推送一次
- 中文交互菜单：
  - `系统状态` `Passwall状态` `CPU信息` `内存信息`
  - `端口信息` `节点列表`
  - `开启Passwall` `关闭Passwall`
  - `每日推送测试` `帮助`

## 仓库结构

- `Makefile` OpenWrt 包定义（包名：`luci-app-jdc-tgbot`）
- `files/etc/config/tgpasswall` UCI 默认配置
- `files/etc/init.d/tgpasswall` procd 启动脚本
- `files/usr/libexec/tgpasswall/bot.sh` TG Bot 主逻辑
- `files/usr/libexec/tgpasswall/state.sh` 路由器状态采集
- `files/usr/libexec/tgpasswall/pw.sh` Passwall 控制
- `files/usr/libexec/tgpasswall/pw_import.sh` 节点导入解析器
- `files/usr/lib/lua/luci/controller/tgpasswall.lua` LuCI 入口
- `files/usr/lib/lua/luci/model/cbi/tgpasswall/main.lua` LuCI 中文配置页
- `docs/ARCHITECTURE.md` 实现原理

## 获取 IPK

### 方式 1：本地直接打包

```bash
chmod +x scripts/build-ipk.sh
scripts/build-ipk.sh all
```

输出：

- `dist/luci-app-jdc-tgbot_0.1.0-1_all.ipk`

### 方式 2：GitHub Actions 自动构建

仓库已内置工作流：

- `.github/workflows/build-ipk.yml`

触发方式：

- push 到 `main` 自动构建并上传 artifact
- 打 tag（如 `v0.1.0`）自动构建并发布 Release 附件

## 安装到路由器

```bash
opkg install /tmp/luci-app-jdc-tgbot_0.1.0-1_all.ipk
```

### 依赖自动安装说明

- `opkg` 会尝试自动安装本插件依赖（如 `curl`、`jq`、`luci-base`、`luci-compat`、`jsonfilter` 等）。
- 但如果软件源未更新、网络不可用、或源中缺少对应包，自动安装会失败并导致安装中断。
- 建议先手动更新并补齐依赖，再安装插件：

```bash
opkg update
opkg install curl jq luci-base luci-compat jsonfilter coreutils coreutils-base64
opkg install /tmp/luci-app-jdc-tgbot_0.1.0-1_all.ipk
```

安装后打开：

- `服务 -> jdc-TGbot`

填写：

- 启用服务：开启
- Bot Token：你的 TG 机器人 token
- 管理员 Chat ID：你的 chat id
- 管理员 User ID（可选）：建议填写，增加安全性
- 启用每日定时推送：按需开启
- 每日推送小时 / 分钟：比如 `8` 和 `30`

保存并应用后，插件会自动重启服务。

## TG 使用说明

### 英文 Slash 指令

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
- `/daily_now`

### 中文菜单按钮

发送 `/menu` 或直接发送 `菜单`，会出现中文键盘按钮。

## Passwall 兼容配置

不同 Passwall 分支字段可能不同，页面里可以调：

- `Passwall 全局 section`（默认 `@global[0]`）
- `Passwall 启用字段名`（默认 `enabled`）
- `Passwall 当前节点字段名`（默认 `tcp_node`）
- `Passwall 节点 section 类型`（默认 `nodes`）

如果你发现节点写入后没生效，优先检查这四项是否与你当前 Passwall 配置一致。

## 安全说明

- 不要把真实 `Bot Token`、`Chat ID`、`User ID` 提交到仓库。
- 本仓库示例均为占位符。
- 建议开启 `管理员 User ID` 二次校验。
- 若 token 曾泄露，请在 BotFather 立即重置。

## 备注

- 当前导入器优先保证“可落地 + 可维护”，已支持常见 URI。
- 若你使用非常定制化节点参数（例如特殊 Reality 字段），可以在 `pw_import.sh` 按你的 Passwall 分支继续补字段映射。
