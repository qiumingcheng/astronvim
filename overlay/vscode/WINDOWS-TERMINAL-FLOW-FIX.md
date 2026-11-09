# Windows VS Code 终端兼容修复（可选）

Linux 新机器仍按正常流程使用：复制对应架构完整包、解压、`source env.sh`。本工具不是 Linux 启动依赖，不需要在每次迁移 Linux 机器时执行。ARM 与 x86 包附带同一份脚本。

此工具只用于已经确认受影响的 Windows VS Code **1.143.1**（commit `e646868227c3e3a9e3f24277c8c7220be42c0be7`）。该版本终端流量控制在恰好剩余 5000 个字符待确认时可能永久暂停，表现为终端不再响应输入。脚本把后台恢复条件 `< 5000` 修正为 `<= 5000`，并同步对应日志文字；不增加定时器，不改快捷键、终端设置或 Linux 程序。

## 使用

在 Windows PowerShell 5.1 或更新版本执行。把脚本复制到 Windows 可访问的位置；`-AppRoot` 必须指向你实际使用的 VS Code 的 `resources\app` 目录，不是 Linux 安装目录，也不是 `Code.exe` 本身。以下路径仅是当前验证机器的示例，其他机器应使用其真实安装路径。

```powershell
$astroCodeAppRoot = 'D:\ProgramData\MicrosoftVSCode\e646868227\resources\app'

# 只读检查。needs_patch 表示该精确版本尚未修复。
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\astro-vscode-terminal-flow-fix.ps1 -Action Check -AppRoot $astroCodeAppRoot

# 确认 Check 成功后，退出相关 VS Code 窗口，避免与更新操作同时进行，再应用。
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\astro-vscode-terminal-flow-fix.ps1 -Action Apply -AppRoot $astroCodeAppRoot

# 手动精确还原。
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\astro-vscode-terminal-flow-fix.ps1 -Action Restore -AppRoot $astroCodeAppRoot
```

Apply 与 Restore 都需重新启动对应 VS Code，才能让新进程加载修改后的文件。脚本不会关闭窗口或结束任何进程。写入失败时会报告错误，不会自行提升权限。

## 备份与边界

原文件与 metadata 保存在当前 Windows 用户家目录：

```text
%USERPROFILE%\.astronvim\vscode-runtime-backups\<安装路径的SHA256>\
    ptyHostMain.js.original
    metadata.json
```

再次 Apply 会识别已经完成的修复；Restore 自动在当前用户家目录找到与指定安装路径匹配的备份，逐字节还原。脚本验证版本、commit、目标文件完整 SHA256、唯一代码片段和备份 SHA256。未知版本、未知修改或损坏备份都会明确报错，不会假装成功。VS Code 升级或其他程序改过目标文件后，Restore 不会覆盖新文件。

本修复只改 `out/vs/platform/terminal/node/ptyHostMain.js`，不改 `product.json`，不绕过安装完整性校验。当前受支持版本的校验清单不包含该后端文件；如果清单包含该文件，脚本拒绝修改。备份保留在用户家目录，不写入 AstroNvim 安装包。

脚本输出 JSON：`success` 表示操作是否成功，`status` 区分 `needs_patch`、`applied`、`already_applied`、`restored`、`already_original` 等状态；失败时退出码为 1。此工具只修复上述已确认的版本边界错误，不代表其他原因引起的卡顿也已解决。

## 本轮实际验证范围

验证机已执行持久 Apply，并在重新启动的原生 VS Code 进程中完成 40 次原菜单/Esc 操作。这个结果不依赖每次卡住后手工回送 ACK；手动回送仅用于最初定位。Check/Apply/Restore 的12项隔离事务检查、真实源码12组边界和8组计数守恒另已通过。该结果仍限于精确匹配的客户端构建，不代表任意版本、全部操作与完整CPU/RSS性能验收。
