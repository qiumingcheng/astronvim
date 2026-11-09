# Windows VS Code 配置与自动恢复

## 1.0.9：按编辑区和终端焦点自动分流

扩展现在内置原有 578 条终端快捷键，条件是 `terminalFocus && portableAstro.focusRouting`。只有当前终端标题标识为正在运行的 AstroNvim、且键盘焦点位于终端时才生效；切回 VS Code 编辑区时继续使用 VS Code / IDEA 的快捷键。退出 AstroNvim、切到普通终端或执行恢复命令后，内置规则自动失效。仅鼠标悬停不转移键盘焦点。

这层内置规则不需要改写用户 keybindings.json，也不依赖 Profile 文件识别成功。原有更高优先级的用户规则接管、家目录备份和鼠标设置事务保持原样；Profile 无法识别时仍不会猜测配置路径，但不会因此禁用内置键盘路由。用户自己定义的快捷键仍具有更高优先级。

已经在 Windows VS Code + IntelliJ IDEA Keybindings 0.2.41 + 终端内 OpenSSH → Linux 的真实窗口验证：没有手工转发规则时，Ctrl+Shift+N 打开 AstroNvim 文件搜索并选中文件；点击 VS Code 编辑区后打开 IDEA 文件搜索；退出后普通终端恢复 IDEA 的原快捷键。10 项控制器和配置一致性检查通过，400 次稳定轮询没有新增定时器或重复发送上下文更新。上述计数不代表全功能性能验收，Remote-SSH 远程工作区及 ARM 实机本轮未执行。

在运行 VS Code 的 Windows 客户端更新一次本包的 `astronvim-terminal-keys.vsix`，然后重载窗口。Linux 的 source env.sh 和启动方式不变；通过 SSH 启动 Linux 程序不能替 Windows 安装客户端扩展。x86 和 ARM 包内使用完全相同的 VSIX。

如需手工把 IDEA 的 Go to File 限定在 VS Code 编辑区，在当前窗口执行 `Preferences: Open Keyboard Shortcuts (JSON)`。先移除原全局绑定，再添加局部绑定：

```json
[
  { "key": "ctrl+shift+n", "command": "-workbench.action.quickOpen" },
  { "key": "ctrl+shift+n", "command": "workbench.action.quickOpen", "when": "editorTextFocus" }
]
```

有既有配置时将这两项加到原数组中，不覆盖其他规则。内置版本不需要再手工添加无条件 `terminalFocus` 转发项；那种项会覆盖所有终端，包括普通 shell。

使用链路：Windows VS Code 的终端，通过 SSH 连接 Linux，再运行 AstroNvim。包内的 Windows 扩展安装在 Windows 客户端；快捷键和鼠标设置的备份放在当前 Windows 用户的家目录 `.astronvim` 下，不放到 Linux 安装目录。

只有 Default 配置的普通 VS Code，无需额外配置。扩展在接管前检查本地 User 布局、Profile 目录和元数据；不会根据可能过期的工作区关联猜测当前 Profile。

存在命名或临时 Profile 时，需要首次明确指定当前 Profile 的两个配置文件：

1. 在正在使用的 Profile 中执行 `Preferences: Open User Settings (JSON)`，取得文件的绝对路径。
2. 执行 `Preferences: Open Keyboard Shortcuts (JSON)`，取得快捷键文件的绝对路径。
3. 在该 Profile 的 **User settings** 中加入下面的配置，替换为实际路径：

```json
"portableAstro.profileFiles": {
  "settings": "C:\\Users\\YOUR_USER\\AppData\\Roaming\\Code\\User\\profiles\\PROFILE_ID\\settings.json",
  "keybindings": "C:\\Users\\YOUR_USER\\AppData\\Roaming\\Code\\User\\profiles\\PROFILE_ID\\keybindings.json"
}
```

使用自定义 `--user-data-dir` 时，路径会不同。若 Profile 与 Default 共享其中一个资源，应分别填写两个文件的真实路径。工作区和项目 `.vscode/settings.json` 不能指定这些用户文件，扩展会明确拒绝这种覆盖。

首次选择后，启动 AstroNvim 自动接管。普通终端获得焦点时释放本窗口的鼠标设置；最后退出、点击整体关闭按钮或执行 `AstroNvim: Restore VS Code Shortcuts` 时自动恢复。其他窗口仍有活跃租约时保留其设置。期间修改的其他偏好会保留；用户主动改动任一受管键也会保留，并暂停需要该键的当前会话的鼠标接管。

鼠标路由使用 VS Code 窗口/Profile 级别的设置，没有稳定的逐终端覆盖 API。共享同一配置文件的其他窗口可能在另一 AstroNvim 窗口持有租约时观察到 `nothing` 和 `ctrlCmd`。本地 Profile、单文件夹工作区和 `.code-workspace` 的有效设置层均可备份恢复。Remote-SSH 工作区只有在两项有效设置均满足 `terminal.integrated.rightClickBehavior="nothing"` 和 `editor.multiCursorModifier="ctrlCmd"` 时无需修改；任一项冲突时明确提示，不尝试未验证的远端文件事务。

自动识别 Default 使用经过检查的本地布局，不能当作 VS Code 的公开 Profile 身份 API。真实 Windows 验证覆盖版本 1.143.1；新版需要重新验证。无法读取的元数据、未知布局、重定向的配置文件和无法确认的 Profile 会停止接管，保留原文件并给出原因。


### 1.0.8：Ctrl+鼠标与终端链接

AstroNvim 活跃终端接管期间，鼠标事务同时设置
`terminal.integrated.rightClickBehavior="nothing"` 和
`editor.multiCursorModifier="ctrlCmd"`。后者让 VS Code 的终端链接改由 Alt+单击激活，避免 Ctrl+单击既在 Neovim 跳转又异步打开 VS Code Quick Open；它不是关闭全部链接，也会临时改变 VS Code 编辑器多光标修饰键。

切换普通终端、退出 AstroNvim、手动恢复或关闭窗口时复用原租约恢复。无用户修改时最终恢复原文件字节；有用户修改时保留用户改过的键并恢复仍由扩展持有的键。同一配置文件按键合并各窗口的租约：只有不再被任何窗口使用的键才恢复，其他键继续保持。VS Code 配置文件重新加载仍是异步过程。

双键备份位于 `.astronvim/vscode-settings-backups-v3/`，与 1.0.7 单键备份隔离，并共用旧目录 `update.lock`。运行中的 1.0.7 与 1.0.8 设置事务互相拒绝接管；守卫只使用真实客户端进程 PID。1.0.8 启动和原有 Restore 命令会发现并恢复旧 schema2 备份与遗留 v3 事务。`bin/astro-vscode-restore` 仍发送同一恢复通知，由 1.0.8 执行双键恢复。

硬退出 1.0.8 后若要降级到 1.0.7，必须先启动 1.0.8 或执行其恢复命令完成 v3 恢复。旧 1.0.7 不理解 v3 备份，不能直接负责恢复它们；本实现不使用伪造 PID 或永久守卫阻止降级。
