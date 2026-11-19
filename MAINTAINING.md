# HostKeeper 维护手册（自用）

## 1. 版本号规则

`module.prop` 是唯一版本源（`version=` / `versionCode=`）。改版本只改这里，下列兜底值必须同步：

| 位置 | 字段 | 说明 |
|---|---|---|
| `module.prop` | `version=` / `versionCode=` | **唯一来源**，设备端以此为准 |
| `hostkeeper.sh` | `HK_VER=` / `HK_VCODE=`（第 22-23 行） | 仅当 module.prop 缺失时生效，运行时会被文件值覆盖 |
| `webroot/app.js` | `VERSION` / `VERSION_CODE`（第 5-6 行） | 状态接口失败时的兜底值 |
| `webroot/index.html` | `#ver` 品牌兜底、`#credits-ver` 页脚、3 处 `?v=` 缓存参数（第 13-14、203 行） | 页面加载后会被接口值覆盖 |
| `customize.sh` | 安装横幅 | 自动从 module.prop 读取，不需要手改 |

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
| `cmd_*` | WebUI 后端接口（状态、列表、规则、日志、诊断） |

## 4. 路径与 ID 必须一致

- 模块 id：`hostkeeper`（`module.prop`）
- 模块目录：`/data/adb/modules/hostkeeper`
- 数据目录：`/data/adb/hostkeeper`（`hostkeeper.sh` 的 `DATA`、`uninstall.sh`）
- WebUI 侧：`webroot/app.js` 的 `MOD` 常量

改 id 时这四处必须一起改。

## 5. 打包

```bash
VERSION=$(sed -n 's/^version=//p' module.prop)
zip -r "HostKeeper-$VERSION.zip" . -x ".git/*"
```

## 6. 已知外部依赖（不是我们维护的）

- GitHub raw：StevenBlack/hosts、hagezi/dns-blocklists-legacy
- hblock.molinero.dev
- 根管理器自带 BusyBox
- WebUI 字体 Inter（`webroot/fonts`，SIL OFL 1.1）

## 7. 改动后的最小验证

```bash
sh -n hostkeeper.sh && sh -n customize.sh && sh -n service.sh && sh -n post-mount.sh && sh -n uninstall.sh && sh -n action.sh
node --check webroot/app.js

# 版本一致性（四处必须相同）
sed -n 's/^version=//p' module.prop
grep -n 'HK_VER=' hostkeeper.sh
grep -n "VERSION = " webroot/app.js
grep -n 'id="ver"' webroot/index.html
```
