# HostKeeper 维护手册（自用）

## 1. 版本号必须同步的 5 个位置

改版本时以下位置必须一起改，否则 UI 和模块信息会不一致：

| 位置 | 字段 |
|---|---|
| `module.prop` | `version=` / `versionCode=` |
| `sb.sh` | `SB_VER=` / `SB_VCODE=`（第 22-23 行） |
| `webroot/app.js` | `VERSION` / `VERSION_CODE`（第 5-6 行，状态接口未返回时的兜底值） |
| `webroot/index.html` | `?v=` 缓存版本号（3 处：style.css / theme.js / app.js） |
| `customize.sh` | `ui_print` 里的版本行 |

## 2. 列表与规则从哪里来

- 两个源前缀在 `sb.sh` 第 84-85 行：
  - `SB_RAW` → StevenBlack/hosts
  - `HZ_RAW` → HaGeZi dns-blocklists-legacy
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
| `cmd_*` | WebUI 后端接口（状态、列表、规则、日志、诊断） |

## 4. 路径与 ID 必须一致

- 模块 id：`hostkeeper`（`module.prop`）
- 模块目录：`/data/adb/modules/hostkeeper`
- 数据目录：`/data/adb/hostkeeper`（`sb.sh` 的 `DATA`、`uninstall.sh`）
- WebUI 侧：`webroot/app.js` 的 `MOD` 常量

改 id 时这四处必须一起改。

## 5. 打包

```bash
zip -r HostKeeper-v1.0.0.zip . -x ".git/*"
```

## 6. 已知外部依赖（不是我们维护的）

- GitHub raw：StevenBlack/hosts、hagezi/dns-blocklists-legacy
- hblock.molinero.dev
- 根管理器自带 BusyBox
- WebUI 字体 Inter（`webroot/fonts`，SIL OFL 1.1）

## 7. 改动后的最小验证

```bash
sh -n sb.sh && sh -n customize.sh && sh -n service.sh && sh -n post-mount.sh && sh -n uninstall.sh && sh -n action.sh
node --check webroot/app.js
```
