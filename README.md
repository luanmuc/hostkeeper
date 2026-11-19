# HostKeeper

系统级 `/system/etc/hosts` 广告拦截模块，适用于 KernelSU / Magisk / APatch。自用维护版。

## 特点

- **静态 hosts**：无后台进程、不开 VPN、不 hook，空闲功耗接近 0
- **WebUI 管理**：状态、列表切换、增删自定义域名、日志、健康检查
- **列表体系**：7 个主列表 + 附加列表 + 最多 8 个自定义 HTTPS 列表
- **域名规则**：Allow 支持 `*.example.com` 通配，Block 为精确域名
- **安全机制**：备份、校验、回滚；设备支持时免重启生效
- **Private DNS 保护**：不会误伤正在使用的 DoT 提供方

## 安装

仓库根目录本身就是模块包（`module.prop` 位于根），打包成 zip 后刷入 KernelSU / Magisk / APatch，重启即可。

## 使用

1. 打开模块 WebUI（模块卡片的 WebUI / Action 按钮）
2. **Lists** 选主列表，**Add-ons** 叠加附加列表，**Rules** 里加 Allow / Block
3. 每次修改会重建 hosts 并校验，状态页可确认是否已生效

## 注意

- hosts 只能按精确域名拦截，不支持子域通配（Allow 规则除外）
- 与 AdAway 等其它 hosts 模块冲突，同一时间只能保留一个
- 开启「私人 DNS」（DoT）时系统会绕过 hosts，需要关闭后再用
