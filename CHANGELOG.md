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
