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
