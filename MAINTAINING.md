# HostKeeper 维护手册（自用）

## 1. 版本号规则

`module.prop` 是唯一版本源（`version=` / `versionCode=`）。改版本只改这里，下列兜底值必须同步：

| 位置 | 字段 | 说明 |
|---|---|---|
| `module.prop` | `version=` / `versionCode=` | **唯一来源**，设备端以此为准 |
| `hostkeeper.sh` | `HK_VER=` / `HK_VCODE=`（第 22-23 行） | 仅当 module.prop 缺失时生效，运行时会被文件值覆盖 |
| `webroot/app.js` | `VERSION` / `VERSION_CODE`（第 5-6 行） | 状态接口失败时的兜底值 |
| `webroot/index.html` | `#ver` 品牌兜底、`#credits-ver` 页脚、3 处 `?v=` 缓存参数（第 14-15、25、173、204 行） | 页面加载后会被接口值覆盖 |
| `customize.sh` | `HK_VER` 兜底（第 4 行） | module.prop 读不到时的安装横幅兜底 |

发布时上表所有值必须一致；`version=`、`HK_VER`、`VERSION` 与页面显示文本都保留 `v` 前缀。

## 2. 列表与规则从哪里来

- 两个源前缀在 `hostkeeper.sh` 第 92-93 行：
  - `STEVENBLACK_RAW` → StevenBlack/hosts
  - `HAGEZI_RAW` → HaGeZi dns-blocklists-legacy
- 每个列表的定义集中在 `list_info()`：`L_NAME`、`L_GROUP`、`L_LEVEL`、`L_URL`、`L_DESC`
- 新增一个列表：在 `list_info()` 里加一个 `case` 分支，并在 WebUI 侧确认分组能被识别
- 某个源失效时：只改对应 `L_URL`，不要动规则引擎

## 3. 核心逻辑（改动前先读）

| 函数/区块 | 作用 |
|---|---|
| `list_info()` | 列表元数据与下载地址 |
| `custom_info()` / `custom_ids()` | 自定义 HTTPS 列表 |
| `AWK_RULES` / `rules_engine` | Allow / Block 规则解析与冲突检测 |
| `rebuild()` | 生成 hosts、校验、挂载、回滚 |
| `verify_hosts_file()` / `verify_hosts_deep()` | 对指定文件/当前 hosts 做深度校验（首两行 + 域名数） |
| `lock_take()` / `lock_drop()` / `lock_clear_stale()` | 锁获取校验、owner-only 释放、无主锁清理 |
| `repair_hosts()` | 深度修复：缓存重建 → 候选校验 → 原子替换 → clean fallback + setup pending |
| `stage_commit()` | 缓存提交：备份、逐项 mv 检查、失败整体回滚；排除 `extras.domains` |
| `sched_exit()` | 调度器 TERM/INT/HUP 收口：停 sleep、清 stage、释放自己的锁、删 SCHEDPID |
| `restore_original_for_uninstall()` | 卸载前 umount 并原子恢复原始 hosts；备份缺失/失败保留数据 |
| `proc_cmdline()` / `pid_is_*` | 按 `/proc/<pid>/cmdline` 校验服务/调度进程身份，避免杀错进程 |
| `cmd_*` | WebUI 后端接口（状态、列表、规则、日志、诊断） |

## 4. 路径与 ID 必须一致

- 模块 id：`hostkeeper`（`module.prop`）
- 模块目录：`/data/adb/modules/hostkeeper`
- 数据目录：`/data/adb/hostkeeper`（`hostkeeper.sh` 的 `DATA`、`uninstall.sh`）
- WebUI 侧：`webroot/app.js` 的 `MOD` 常量

改 id 时这四处必须一起改。

## 5. 打包

```bash
sh scripts/package.sh
```

脚本只复制模块运行所需的文件到 `../out/HostKeeper-<version>.zip`，自动排除 `.git`、`scripts/`、README 与维护文档，并把入口脚本设为 0755。自定义输出目录：

```bash
OUT_DIR=/path/to/out sh scripts/package.sh
```

## 6. 已知外部依赖（不是我们维护的）

- GitHub raw：StevenBlack/hosts、hagezi/dns-blocklists-legacy
- hblock.molinero.dev
- 根管理器自带 BusyBox
- WebUI 字体 Inter（`webroot/fonts`，SIL OFL 1.1）

## 7. 改动后的最小验证

```bash
sh scripts/check.sh
```

`check.sh` 覆盖：全部 shell 语法、`app.js` / `theme.js` 语法、`module.prop` 字段、各处版本兜底值、模块必需文件、入口脚本执行位、旧内部命名与凭证扫描。v1.0.3 另跑 `notes/stress/evidence/v1.0.2/p2p3-regression.sh`（36 用例，主机侧 36/36 PASS）。需要单独看某一项时：

```bash
sh -n hostkeeper.sh
node --check webroot/app.js
sed -n 's/^version=//p' module.prop
grep -n 'HK_VER=' hostkeeper.sh customize.sh
grep -n "VERSION = " webroot/app.js
grep -nE '?v=|id="ver"' webroot/index.html
```

## 8. 安全边界

- WebUI httpd 只监听 `127.0.0.1:9090`，`httpd.conf` 用 `A:127.0.0.1` + `D:*` 拒绝非本机来源
- 会话 token 为 32 位十六进制，`/data/adb/hostkeeper/token` 权限 0600；页面用 POST body 传递，不走 URL query
- CGI 只接受 POST（GET 一律 403）；校验 token、必须为本地 `HTTP_HOST`、`HTTP_REFERER` 为空或同源；响应带 `no-store`、`nosniff`、`DENY`、CSP 等头
- 静态页 CSP 禁止外部脚本、对象与表单提交；样式允许 `unsafe-inline`，因为进度条用 JS 写 `style.transform`
- 自定义列表只允许 HTTPS，下载限速/限大小；`curl` 路径强制 HTTPS 重定向，`wget` 回退拒绝 HTTP/FTP 重定向
- 数据目录 0700；WebUI 运行目录与 `cgi-bin` 也设为 0700
- inplace 写入 hosts 时使用同目录临时文件 + `cmp` + `mv -f`，失败保留旧文件
- 源元数据 `src_write` 使用 `.tmp` + `mv` 原子写；`stage_commit` 提交失败整体回滚
- 卸载只有在原始 hosts 恢复成功后才删除 `/data/adb/hostkeeper`
