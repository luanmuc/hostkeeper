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
