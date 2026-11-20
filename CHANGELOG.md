## v1.1.4（2026-11-20）

- 触发：用户安装 v1.1.3 后顺丰同城骑士开屏广告仍出现。v1.1.3 只覆盖 5 条 ToBid/美数聚合入口 + 11 条 GDT 漏项，未覆盖 Pangle/Gromore、Sigmob、AdScope、Octopus、泛为这一层 ADN；本次按实测反馈补下一层。
- 新增：随包 `block-default-adn.list`，16 条精确域名——Pangle/Gromore 7 条（`api-access.pangolin-sdk-toutiao.com`、`api-access.pangolin-sdk-toutiao-b.com`、`api-access.pangolin-sdk-toutiao1.com`、`gromore.pangolin-sdk-toutiao.com`、`pangolin.snssdk.com`、`is.snssdk.com`、`i.snssdk.com`）、Sigmob/ToBid 素材 3 条（`adservice.sigmob.cn`、`dc.sigmob.cn`、`tbiu.sigmob.cn`）、AdScope 1 条（`sdk.beizi.biz`）、Octopus 2 条（`sdk.zhangyuyidong.cn`、`sdklog.zhangyuyidong.cn`）、泛为 3 条（`t2.fancyapi.com`、`g.fancyapi.com`、`mpcfg.fancydsp.com`）。与 v1.1.3 的 `block-default.list` 合计 32 条。
- 合并：`block_seed()` 改为两段独立合并——基础集 `block-default.list` 用 `$BLOCKF.seed-v1`，ADN 补充集用 `$BLOCKF.seed-v2`。v1.1.3 升级后旧 marker 不会阻止新 ADN 规则写入；只补缺失，不覆盖、不重排用户 `block.list`；注释/空行/通配跳过；任一段失败时该段 marker 不写，可下次重试。
- 版本：v1.1.3 → v1.1.4，versionCode 14 → 15；`module.prop`、`HK_VER` / `HK_VCODE`、`customize.sh`、`app.js`、`index.html` 五处版本串与三处 `?v=` 全部同步。
- 验证：`check.sh` 全绿；`block_seed` 19/19 PASS（全新 32 条、v1.1.3→v1.1.4 只补 16 条 ADN、v1.1.1→v1.1.4 补 32 条、用户行保留、幂等、去重、末尾换行、缺基础集只补 ADN、双 marker 防回填、通配跳过）；编译回归 6/6 PASS（32 条在源列表无命中时仍输出 `0.0.0.0`）；包 452,307 字节，SHA256 `d87eb7b3b4d6a8505837cad3208fbc82c046dd8427c1c9b1c551ffa7776899cd`；`unzip -t` 通过。
- 状态：已推送 `main`；tag `v1.1.4`；GitHub Release `v1.1.4` 已发布。真机 v1.1.3→v1.1.4 升级迁移、顺丰骑士实机开屏复测、管理器矩阵、重启/断电、72h/7d 长稳仍 BLOCKED；不能写成“广告已修复”。即使 32 条全部生效，若 App 走 HTTPDNS/IP 直连或 ToBid 缓存瀑布流，hosts 仍可能拦不住。

## v1.1.3（2026-11-20）

- 新增：随包 `block-default.list`，内置 16 条顺丰同城骑士开屏广告定向拦截域名——5 条聚合入口（`tm.sigmob.cn`、`c.tobidad.cn`、`sdk.1rtb.net`、`c.etoolads.cn`、`dsp.1rtb.com`）+ 11 条腾讯优量汇 GDT 漏项（`c/sc/win/h5/a/v2/c2.gdt.qq.com`、`union.eff.qq.com`、`qzs.gdtimg.com`、`pgdt.ugdtimg.com`、`adsmind.ugdtimg.com`）。依据 APK 12.1.0.1 静态取证与官方第三方 SDK 清单。
- 合并：`ensure_dirs()` 新增 `block_seed()`。只用精确域名规则行追加到 `block.list`，注释/空行/通配不写入；空文件补齐 16 条，已有内容只补缺失，用户自定义规则逐字保留；首次合并成功写 `$BLOCKF.seed-v1`，之后手动删除规则不会被再次补回。
- 保留：v1.1.2 的 `allow-default.list` 收窄（删除 `*.qq.com` / `*.163.com`，QQ/网易只放行音乐业务子域）与 `allow_seed()` 的 `$ALLOWF.seed-v2` 迁移一并进入本版；v1.1.2 不单独发布。
- 版本：v1.1.2 → v1.1.3，versionCode 13 → 14；`module.prop`、`HK_VER` / `HK_VCODE`、`customize.sh`、`app.js`、`index.html` 五处版本串与三处 `?v=` 全部同步。
- 验证：`check.sh` 全绿；`block_seed` 14/14 PASS（全新 16 条、注释/空行不写入、用户行保留、幂等、去重、末尾换行、缺文件静默、marker 防回填、通配跳过）；编译回归 5/5 PASS（16 条内置拦截在源列表无命中时仍输出 `0.0.0.0`）；UI/后端/向导等历史回归保持通过。
- 状态：本地构建并验证；真机升级迁移、顺丰骑士实机开屏复测、72h/7d 长稳仍 BLOCKED，不能写成已验证。

## v1.1.2（2026-11-20）

- 修复：v1.1.1 的 `allow-default.list` 使用 `*.qq.com` / `*.163.com` 整域放行，覆盖 StevenBlack 中的腾讯优量汇、Gromore 广告域（如 `e.qq.com`、`*.gdt.qq.com`），导致顺丰同城骑士等接入腾讯广告 SDK 的应用仍能加载开屏广告。用户截图确认模块已启用且 76,005 域名生效，问题不在模块未运行。
- 收窄：QQ 音乐只保留 `y.qq.com`、`*.y.qq.com`、`qqmusic.qq.com`、`*.qqmusic.qq.com`、`aqqmusic.tc.qq.com`；网易云音乐只保留 `music.163.com`、`*.music.163.com`、`u.y.163.com`；其余酷我 / 酷狗 / 咪咕 / 126 / 第三方源不变。清单由 17 条增至 23 条。
- 迁移：`allow_seed()` 增加一次性迁移标记 `$ALLOWF.seed-v2`；升级到 v1.1.2 后首次运行删除旧 `allow.list` 中逐行精确匹配的 `*.qq.com` / `*.163.com`，再按原有逐行补入逻辑补齐窄规则。迁移失败不写标记，可下次重试；用户其他规则保留。
- 版本：v1.1.1 → v1.1.2，versionCode 12 → 13；`module.prop`、`HK_VER` / `HK_VCODE`、`customize.sh`、`app.js`、`index.html` 五处版本串与三处 `?v=` 全部同步。
- 验证：`check.sh` 全绿；allow_seed 12/12 PASS（新增旧宽泛项迁移用例）；QQ/网易音乐 6 个正例 ALLOW、腾讯广告 2 个反例 BLOCK；UI 22/22、操作 13/13、首次向导 28/28、Bridge 3/3、源防护 37/37、下载防护 6/6、后端 10/10、诊断互斥 PASS、镜像回退 PASS、100k 454ms。
- 状态：本地构建并验证；真机/长稳未执行。发布状态以 GitHub Releases 页为准。

## v1.1.1（2026-11-20）

- 内置放行清单：新增随包文件 `allow-default.list`，覆盖豆包定制聚合音源（lx-music-mobile）全链域名——音乐平台主站与 API（`*.163.com` / `*.qq.com` / `*.kuwo.cn` / `*.kugou.com` / `*.migu.cn`）、播放 CDN（`*.126.net`）、第三方聚合与中转源（`*.oiapi.net` / `*.lzmhhh.com` / `*.zddyr.top` / `*.haitangw.cc` / `*.haitangw.net` / `*.gdstudio.xyz` / `*.onrender.com` / `*.xcvts.cn` / `*.dpdns.org` / `*.lingchuan.com` / `*.wwwweb.top`），合计 17 条规则。
- 合并策略：`ensure_dirs()` 调用新增的 `allow_seed()`。只写入域名规则行，注释/空行不进入 `allow.list`；空文件补齐 17 条，已有内容只补缺失条目并按行去重（`grep -qxF --`），用户自定义规则永不覆盖；补入条数写入日志。
- 版本：v1.1.0 → v1.1.1，versionCode 11 → 12；`HK_VER` / `HK_VCODE` 兜底、`customize.sh` 兜底、`app.js` 的 VERSION / VERSION_CODE、`index.html` 五处版本串与三处 `?v=` 全部同步。
- 验证：`sh -n hostkeeper.sh` 通过；`check.sh` 全绿（含 HK_VER / HK_VCODE 契约项）；`allow_seed` 回归 10/10（全新设备只写 17 条规则、无注释/空行、用户行保留、重复执行幂等、内置条目去重、缺文件静默、`allow.list` 末尾缺换行不粘连）；通配实测 6 正例放行 / 3 反例拦截。
- 状态：版本提交见仓库 `main`；发布状态以 GitHub Releases 页为准。

## v1.1.0（2026-11-20）

- 首次安装向导：新增“下载主列表 → 检查挂载 → 重启确认”三步卡片；按 `setup` / `reboot` / `applied` 状态自动切换当前步骤，明确“向导不会自动重启”，可“稍后再说”。
- 下载源可观测：`status`、`lists` 新增 `listHost` / `listAltHost` / `listHasAlt` 与列表/附加列表 `altHost` / `hasAlt` / `errorText`；WebUI 列表卡片显示“备源”或“单源”，失败时显示具体原因；完整主源/备用源放在 tooltip 和状态弹窗。
- 源状态收口：健康检查显示主源、备用源；hBlock 明确标注“没有备用源”，不伪造镜像；主源失败时说明更新会尝试备用源。
- 诊断与日志导出：报告和日志文本弹窗新增“⬇️ 导出”，生成 `HostKeeper-v1.1.0-report-*.txt` / `HostKeeper-v1.1.0-logs-*.txt`；WebView 不支持 Blob 下载时保留复制路径。
- 安全边界：自定义列表新增本地域名后缀与 DNS 解析私网/保留地址拦截（`nslookup` 可用时）；修复 BusyBox `Address 1:` 与多地址续行解析漏判；下载前再次解析私网；自定义列表禁止跳转、非 curl 工具拒绝；内置列表 curl 跳转最多 5 次；继续强制 HTTPS、限制 64 MB 体积上限。
- 文案收口：空列表、首次下载失败、待重启、被覆盖、未生效、网络失败等状态在首屏、状态弹窗、列表卡片和向导中统一说明。
- 性能：主机侧 10 万条域名归一化 + hosts 编译基准 459 ms（100000/100000，阈值 10 s）；72 h / 7 d 长稳未执行。
- 版本：v1.0.9 → v1.1.0，versionCode 10 → 11；WebUI 三处资源 query 同步 `?v=1.1.0`。
- 验证：UI 22/22、操作按钮 13/13、Bridge 3/3、首次向导 28/28、自定义列表防护 37/37、后端 status/source 10/10、100k 基准 PASS、`check.sh` 全绿；真机矩阵未执行（稳定版发布门槛仍为 NO-GO）。
- 状态：版本提交见仓库 `main`；发布状态以 GitHub Releases 页为准。包 449,161 字节，SHA256 `93cee66fcf07ec53ca914785a79d17e6302a4298b4a32eef86019130fea1c4b9`。

## v1.0.9（2026-11-20）

- 诊断：`cmd_diag()` 新增“健康检查开始/完成”日志，完成行包含 ok/warn/err 数量和耗时；网络探测失败、下载工具缺失单独记 WARN/ERROR。
- 并发：新增 `$RUND/diag.lock` 后端互斥；重复点击返回 `diag_busy`，前端显示“健康检查正在进行”，不再并发执行诊断。
- 文案：待重启状态改为“待重启完成挂载”；主开关首次开启 toast、状态弹窗和 hero 说明明确“首次安装通常重启一次，之后切换可即时生效”。
- 版本：v1.0.8 → v1.0.9，versionCode 9 → 10；WebUI 三处资源 query 同步 `?v=1.0.9`。
- 验证：UI 22/22、操作按钮 13/13、Bridge 3/3、`check.sh` 全绿；设备侧待复测。
- 状态：版本提交见仓库 `main`；发布状态以 GitHub Releases 页为准。

## v1.0.8（2026-11-20）

- 修复：`#act-diag` 改为文档级点击委托，点击图标/文字子元素也能触发健康检查。
- 修复：`applyBusy()` 每次状态刷新强制清除 `#act-diag` 的 `disabled` / `aria-disabled`，旧请求不再锁死按钮。
- 修复：WebUI 资源 query 升级 `?v=1.0.8`，避免同版本重复安装时 WebView 继续使用旧 `app.js`。
- 修复：主开关首次开启返回 `live:false` 时提示“首次安装/未挂载需重启一次，之后可即时生效”。
- 验证：UI 22/22、操作按钮 9/9、Bridge 3/3、`check.sh` 全绿、镜像回退成功。
- 版本：v1.0.7 → v1.0.8，versionCode 8 → 9。
- 状态：已推送 `a8f8d87`；GitHub Pre-release `v1.0.8` 已发布；设备侧待复测健康检查。

## v1.0.7（2026-11-20）

- 下载：修复 `curl: (35) Recv failure: Connection reset by peer` 导致首次列表无法下载的问题
- 下载：GitHub `raw.githubusercontent.com` 主源失败时，自动尝试 jsDelivr 镜像；主源保留，不替换第三方列表源
- 下载：主源重试 2 次、镜像源重试 1 次；列表详情和首次下载都走同一回退链
- 修复：meta 详情 peek 成功后 full 仍保留主源+镜像，避免二次请求被同一网络重置
- 修复：WebUI 健康检查不再用 disabled 锁按钮；25 秒超时、关闭后重开可再次检查、过期响应丢弃
- 修复：状态/设置/规则/修复/重启/导入/日志等交互统一加超时或 `try/finally`，异常不再卡住按钮和 busy 状态
- 修复：自定义列表「添加列表」按钮在 busy 结束后恢复；规则导入失败或异常时也会解除 busy
- 工程检查：`scripts/check.sh` 增加下载回退、meta full 回退、`apiTimeout`、健康检查超时/过期响应契约
- 回归：主机侧 UI 22/22 PASS、操作按钮 8/8 PASS、Bridge 3/3 PASS、`check.sh` 全绿；镜像回退用无效主源实测成功
- 版本：v1.0.6 → v1.0.7，versionCode 7 → 8
- 状态：已推送 `origin/main`（`c560dfc`）；已发布 GitHub Pre-release `v1.0.7`

## v1.0.6（2026-11-19）

- WebUI：整个界面改为简体中文（`lang="zh-CN"`），涵盖导航、防护区、列表、附加列表、域名规则、操作、日志、设置、状态、健康检查、报告、导入导出、进度与结果弹窗、确认框、无障碍标签
- 后端：`list_info` 的强度标签与列表说明、`reply` 提示、`cmd_diag` 标题与详情、安装/修复/重启/打开链接提示全部中文化
- 日志：管理器中可见的技术日志正文改为中文；保留 `INFO` / `WARN` / `ERROR` 级别键和原始技术标识，便于排错
- 字体：CSS 增加 `Noto Sans SC` / `Source Han Sans SC` / `PingFang SC` / `Microsoft YaHei` 回退，避免中文缺字
- 工程检查：`scripts/check.sh` 新增中文 UI 契约（locale、关键文案、无遗留英文标签），并把安装失败 `abort` 断言同步为中文
- 回归：主机侧 UI 22/22 PASS；Bridge mock 3/3 PASS；`check.sh` 全绿
- 版本：v1.0.5 → v1.0.6，versionCode 6 → 7
- 状态：GitHub Pre-release `v1.0.6`（资产 `HostKeeper-v1.0.6.zip` 与 `.sha256`）

## v1.0.5（2026-11-19）

- 管理器适配（主机侧）：`customize.sh` 安装失败分支改用 `abort`，不再从 sourced 脚本直接 `exit`
- 管理器适配（主机侧）：KernelSU/SukiSU 安装成功文案不再承诺“无 metamodule 也可用”；改为说明 metamodule 条件与 Diagnostics 的 mount 状态
- 管理器适配（主机侧）：APatch 安装文案单独说明 OverlayFS；`restore_original_for_uninstall` 只 umount `/system/etc/hosts`，不再对模块内文件做无效 umount
- WebUI：Bridge 兼容 `window.ksu` / `window.apatch`，并兼容返回 Promise 的 `exec()`；回调式管理器保持原路径
- 文档：README 区分 Magisk App/TWRP 与 KernelSU/APatch 管理器安装，补 KSU metamodule 前置；新增“检测与边界”说明，不宣称反检测
- 工程检查：`scripts/check.sh` 新增管理器适配契约（无 sourced `exit`、KSU/APatch 安装文案、README Recovery/metamodule、Bridge 对象、卸载 umount 目标）
- 版本：v1.0.4 → v1.0.5，versionCode 5 → 6
- 验证：主机侧 `check.sh`、shell/JS 语法、mock bridge 回归；真机管理器矩阵仍未执行

## v1.0.4（2026-11-19）

- WebUI：把 Actions 里的 `Disable/Enable Blocker` 按钮改为 Protection 区的 `role="switch"` 拨动开关，`aria-checked`、ON/OFF 状态、禁用态与确认弹窗同步
- WebUI：移除 Actions 里重复的 `act-toggle` tile；修复首帧 `toggle-state` 显示 `On` 而 switch 初始为 off 的不一致
- WebUI：提取 `renderPowerSwitch()`；清理 `tile-power`、`tile.is-danger`、`tile.is-on` 死样式
- 工程检查：`scripts/check.sh` 新增 WebUI 控件契约检查（唯一 `act-toggle`、`role=switch`、`toggle-state`、无 legacy 引用、`renderStatus` 设置 `aria-checked`）
- 版本：v1.0.3 → v1.0.4，versionCode 4 → 5
- 验证：`check.sh` 全绿；`app.js` / `theme.js` 语法通过；Playwright 主机侧开关状态与确认弹窗通过；真机矩阵仍未执行

## v1.0.3（R3，2026-11-19）

- 修复 15 个 P2：安装/卸载退出码与数据保留、禁用状态不被 setup 改回、gzip 尺寸校验、空 extras、stage 原子提交、服务/调度进程身份、spawn 超时、规则提交回滚、源增删并发/回滚、repair pending 重建、内容未变收口、安装器退出码
- 修复 15 个 P3：JSON C0 转义、日期/闰年校验、TLD 规则统一、源 ready 元数据、status 全字段转义、guard 子域、前端 URL userinfo、调度器文案、CGI 只收 POST/本地 Host、sum_check 返回值、元数据原子写、Private DNS 文案、管理器兼容说明、CSS @supports 兜底
- 额外修复：`stage_commit` 误把 `extras.domains` 当普通源；`install_main` 无条件删 `SUMF`；dispatch 吞掉安装退出码；陈旧 checksum 被当匹配；诊断把 `sum_check=2` 当匹配；`source-del` 删除最后一行时 `grep -v` 返回 1 被误判；卸载备份缺失仍删数据
- 新增 6 个函数：`proc_cmdline`、`pid_is_hostkeeper_serve`、`pid_is_httpd_for_run`、`stage_commit`、`sched_exit`、`restore_original_for_uninstall`
- 回归：主机侧 P2/P3 36/36 PASS；P1 回归全通过；真机/模拟器矩阵仍未执行
- versionCode 3 → 4

## v1.0.2 维护修复（R2，2026-11-19，未升版）

- 修复 HK-AUD-001：`repair_hosts deep` 不再把 2 行 hosts + 缺失 `SUMF` 当有效；优先按缓存重建，重建失败写 clean hosts 并把 `C_DOMAINS=0`/`C_SETUP=pending`；`mount_main` 改为 deep 修复
- 修复 HK-AUD-002：`pipeline` 的 `up_to_date` 增加 `C_SETUP=ready`、`hosts_sane`、深度校验与 `sum_check`；截断 hosts 会进入重建
- 修复 HK-AUD-003：锁目录写 pid 后校验；陈旧锁先移出再判定活进程；`lock_drop` 只删除自己的锁；新增 `lock_clear_stale` 供 `op_reconcile` 清理无主锁
- 修复 HK-AUD-004：inplace hosts 写入改为同目录临时文件 + `cmp` + 原子 `mv`；失败不截断旧 hosts
- 回归：隔离主机侧脚本；5 并发 disable 5/5、20 并发 status 20/20；详见本地维护记录
- 说明：本轮为本地维护修复，不升版本；真机安装/挂载/重启/卸载仍未验证

# HostKeeper v1.0.2

- 安全加固：WebUI 页面增加 CSP；CGI 响应增加 CSP、CORP、Permissions-Policy；WebUI 运行目录与 `cgi-bin` 设为 0700
- 下载加固：`wget` 回退路径拒绝 HTTP/FTP 重定向，避免 HTTPS 列表被降级到明文
- 新增 `scripts/check.sh`：检查 shell / JS 语法、module.prop 字段、各处版本兜底值、模块必需文件、执行位、旧命名与凭证
- 新增 `scripts/package.sh`：只打包模块运行文件，自动排除开发文件并修正脚本执行位
- 新增 `.gitignore`
- 修正 `customize.sh` 安装横幅兜底版本未跟随 `module.prop` 的问题
- versionCode 2 → 3

# HostKeeper v1.0.1

- 版本号统一：`module.prop` 成为唯一版本源，`hostkeeper.sh` 启动时读取，安装横幅同步读取
- 内部标识统一：入口脚本更名为 `hostkeeper.sh`，变量前缀统一为 `HK_`，临时文件与浏览器存储键同步改名
- 附加列表 ID 改为完整的源前缀（`stevenblack-*` / `hagezi-*`）
- 清理 WebUI 与安装流程中的旧版本、旧品牌残留文案
- 页脚字体署名改为 `Inter (SIL OFL 1.1)`，版权信息保留在字体 LICENSE
- versionCode 1 → 2

# HostKeeper v1.0.0

- 初始版本：静态 hosts 系统级拦截，无后台进程
- 支持主列表切换、附加列表、自定义列表（HTTPS 地址）
- 支持 Allow / Block 规则（Allow 支持 *.example.com 通配）
- 内置 WebUI：状态、列表、规则、日志、健康检查
- 备份 / 校验 / 回滚，支持免重启实时生效
