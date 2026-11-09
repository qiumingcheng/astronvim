# VS Code 快捷键：自动接管、家目录备份与恢复

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

以下为此前接管与配置事务的说明；1.0.9 沿用这些事务，新增内置规则不受 Profile 路径识别结果限制。

客户端组件 `astronvim-terminal-keys.vsix` 会在启动 AstroNvim 时备份并接管快捷键，退出整个编辑器后自动恢复。备份、原始快照和恢复记录均放在**运行 VS Code 的当前用户家目录**，不放在安装目录，不随 ARM 包迁移。

## 首次配置

在运行 VS Code 的电脑上安装一次组件。Windows PowerShell：

```powershell
code --install-extension .\astronvim-terminal-keys.vsix --force
```

也可使用扩展页面“从 VSIX 安装”。它在本地客户端运行，终端里可以使用 WSL、PowerShell + SSH 或 Remote SSH。只复制 ARM 目录无法替代这一次客户端安装。若首次安装未激活，执行“Developer: Reload Window”。

本轮客户端 **1.0.8** VSIX已冻结为候选，完整SHA与成员摘要见 [依赖清单](../docs/third-party/依赖清单.json)。当前准备组合为Linux C110与Windows客户端1.0.8，仍为未发布的candidate-only。Windows108的Ctrl单击/文件目录操作20次、焦点切换、整体退出、手动恢复与保留用户编辑已有指定功能验证；C110经真实Windows链路的10项复制/剪切/粘贴每项1次通过。五项既有成本差异、两项搜索信号及其余未完成验收仍保留，ARM/EulerOS缺少本轮实机；这些功能结果不是配对性能或商用验收通过。 从旧版升级时先退出旧窗口中的AstroNvim，安装配套VSIX并重载旧扩展窗口。Linux启动器不能通过SSH替Windows安装组件；以后每次使用的HOME备份、接管和恢复自动执行。

随后照常启动：

```bash
source /path/to/astronvim/env.sh
astronvim /path/to/project
```

启动器通过终端标题通知客户端。只有本地布局确认仅存在 Default Profile 时，组件才自动选用其配置文件；存在命名/临时 Profile、关联或未知布局时停止猜测，需要在当前 Profile 的 User settings 显式填写两个真实路径。步骤见 [Profile 配置](PROFILE-SETUP.md)。工作区不能提供这些用户文件路径。每次启动生成独立 token，经 `ASTRO_VSCODE_TITLE_TOKEN` 传给 Neovim，并在本次运行的 `titlestring` 中维持 `AstroNvimPortable:active:<token>`；切换文件也继续使用该标记，避免被 Neovim 默认的文件名标题覆盖而失去接管。该设置仅作用于运行中的 AstroNvim 终端，退出恢复原标题。扩展同时提供 `terminal.integrated.tabs.title = "${sequence}"` 的配置默认值，让 VS Code 显示应用发送的 OSC 标题并供组件识别；这项默认值不写入用户 `settings.json`；鼠标路由会备份并事务修改右键行为及多光标修饰键两项，按租约恢复，详见下文。若用户曾显式将此项设置为 `${process}` 或其他自定义值，显式设置仍优先，此时终端可能只显示 `ssh` 而不能自动识别。请在 VS Code 设置中将 **Terminal › Integrated › Tabs: Title** 重置为默认，再新建终端启动 AstroNvim。不要手动固定/重命名该终端标题，否则可能无法识别通知。正常使用不需要 Python；扩展按受保护的 Default 布局或显式 User 路径工作，没有使用稳定公开的 Profile 身份 API。首次取得新租约会重新核对身份，持续运行每 5 秒复查；配置变更会触发复查。切换路径先释放旧文件事务，无法读取、未知类型或重定向的资源会拒绝接管。`install.py` 是旧的手动快捷键合并工具，只读取同目录的 `keybindings.json`，不读取VSIX manifest、不安装或升级扩展，也不管理双键设置事务；不能用它替代1.0.9 VSIX安装，不要在扩展运行期间并发执行。

## 接管和退出

- 焦点在 AstroNvim 终端时，578 条临时规则接管 Ctrl、Alt、Shift 组合和功能键：Ctrl+V 使用 VS Code 原生终端粘贴，其余 577 条转发给远端，包括 Ctrl+C、Ctrl+Z、Ctrl+S、Ctrl+F、Ctrl+Shift+N、Ctrl+K 等常见快捷键及组合键前缀。普通字符正常输入；操作系统保留键不属于 VS Code 能转发的范围。
- 条件为 `terminalFocus && portableAstro.active`；点回 VS Code 编辑区即恢复 VS Code 行为，也不把其他全屏程序当作 AstroNvim。
- 点击整体关闭的 × 或正常退出时自动恢复。取消未保存文件的退出提示，会保留编辑会话及接管。
- 按实际配置文件路径跟踪活动窗口；最后一个持有该文件租约的窗口退出才恢复它。共享 Default 资源的 Profile 也可能使用同一文件。未活动的历史 Profile 不会被重新写入或创建。
- 修改前保存原始快照；未被用户改动的配置逐字节恢复，包括注释、BOM、换行。用户使用期间新增的快捷键会保留，只移除本工具区块。
- 接管只修改已确认的配置文件；手动恢复即使无法确认当前 Profile，也会查找家目录注册记录，并跳过仍有活动窗口使用的文件，不依赖 Linux 安装路径。标题检查仍为 150 ms；租约和 Profile 身份检查每 5 秒续期/复查，不把 Profile 元数据读取加入每次输入。

1.0.4 引入的行为继续保留：在 VS Code 提供 shell integration 命令结束事件时立即重新检查终端标题：例如 PowerShell 中直接执行 SSH 启动命令，该命令返回且标题已恢复时，可提前执行快捷键恢复。事件本身不会强制释放其他活动会话的租约。先 SSH 进入远端常驻 shell，再从中启动 AstroNvim 的用法，可能没有客户端命令结束事件；旧版 VS Code 或未启用 shell integration 时也继续使用原 150 ms 检查。此改动没有提高轮询频率。

## 鼠标右键与 Profile 配置

客户端1.0.8在AstroNvim活跃终端接管期间，同时设置 `terminal.integrated.rightClickBehavior="nothing"` 与 `editor.multiCursorModifier="ctrlCmd"`。Ctrl+单击交给Neovim，VS Code终端链接改用Alt+单击；这也会临时改变VS Code编辑器的多光标修饰键。共享配置按键合并租约，每个键在最后持有者释放后恢复；无用户修改时恢复原文件字节，有用户修改时保留其修改。双键备份放在当前Windows用户HOME的 `.astronvim/vscode-settings-backups-v3/`，不放Linux安装目录。 Profile、单目录 `.vscode/settings.json` 和本地 `.code-workspace` 按有效设置层处理。用户主动修改任一受管键会保留，并暂停需要该键的当前会话接管。Remote-SSH工作区仅在两项有效值均满足上述要求时无需修改，冲突时提示，不尝试未验证的远端文件事务。原有有界EPERM恢复与失败记录仍保留。

Remote-SSH 工作区的远端覆盖若已是 `nothing` 无需修改；冲突时明确提示，不执行未验证的远端配置文件事务。快捷键文件路径始终只取本地当前 User 配置，不能由工作区声明；具体路径、共享 Default 资源和拒绝条件见 [Profile 设置步骤](PROFILE-SETUP.md)。

## 手动恢复

在同一个 VS Code 终端执行安装目录内的命令：

```bash
/path/to/astronvim/bin/astro-vscode-restore
# source env.sh 后也可直接执行：
astro-vscode-restore
```

或者在 VS Code 命令面板执行 **AstroNvim: Restore VS Code Shortcuts**。当前会话恢复后不再自动接管，新启动的会话会重新接管。

## 备份位置

- Windows：`%USERPROFILE%\.astronvim\vscode-backups\`
- Linux：`~/.astronvim/vscode-backups/`
- 双键鼠标设置事务：同一用户家目录下的 `.astronvim/vscode-settings-backups-v3/`；旧单键备份保留于 `.astronvim/vscode-settings-backups/`
- 可选 Windows ACK 修复：同一用户家目录下的 `.astronvim/vscode-runtime-backups/`，使用该工具自己的 Restore 命令恢复，与快捷键恢复分开。

从 Windows SSH 登录 ARM 时备份仍在运行 VS Code 的 Windows 用户家目录，**不是 ARM 的 /root**。恢复自动寻找，无需指定备份名。

子目录按配置路径区分，1.0.2 引入、后续候选继续使用 `profile.json` 记录目标，并兼容读取旧的 `registration.json`。每个 Profile 的 `leases/` 记录活动窗口；`before-*.json` 保存原始内容，`baseline-*.json` 保存恢复基线，`pending.json` 记录尚未完成的写入，`active.json` 记录已完成变更，恢复后保留 `restored-*.json`。异常中断会在后续接管或恢复时重试。1.0.8隔离双键v3数据并与旧目录共用锁，运行中的旧107与108设置客户端互相拒绝接管；旧版退出后108可恢复其schema2备份。硬退出108后若要降级107，须先用108完成v3恢复，旧107不能恢复v3双键事务。

同一新协议的多个版本共用 Profile 时，最高版本决定规则；同版本不同规则按固定摘要顺序选一个，避免相互改写。决定规则的窗口退出后，仍活动的版本接续。此规则只适用于理解 1.0.2 引入的租约协议的版本，不适用于仍运行的 1.0.1 及更早扩展。

## 客户端日志与错误排查

通过VS Code使用时，Linux日志不能覆盖Windows客户端。请在出问题的那个VS Code窗口打开“输出”面板，选择 `AstroNvim Keyboard` 通道；同时从命令面板打开当前VS Code日志目录，保留该窗口的extensionHost和renderer日志。Output对应的文件名通常为 `1-AstroNvim Keyboard.log`，前缀编号随窗口/通道而变；自定义user-data-dir或Profile的日志位置可能不同，不要只检查个人默认目录。

记录问题时间、VS Code/扩展版本、活动Profile及退出方式。受控测试强制Stop-Process后的Canceled必须用准确PID及时间关联；普通关闭时的同名错误不能自动豁免。EPERM等IO错误即使后来重试成功也要保留首次错误、恢复结果和备份状态。只有实际核对过的日志渠道才能报告未发现错误；旧门禁遗漏Output的问题及本轮补审结论见 [验收报告](../docs/最终验收报告.md#windows-客户端日志补审与当前阻断)。原始日志可能含用户路径，分享前检查内容。

## Windows VS Code → SSH 的编辑区剪贴板

- Ctrl+C：Neovim 复制选区；未选中时复制当前行，并经终端 OSC 52 写入 Windows 剪贴板。
- Ctrl+V：由 **Windows 本地 VS Code** 读取剪贴板，用终端的原生粘贴通道传入 SSH；支持从浏览器、记事本或本地 VS Code 文件复制的文字，不要求 Linux 读取 Windows 剪贴板。
- Ctrl+Z、Ctrl+S、Ctrl+X、Ctrl+A、Ctrl+Shift+Z 和 Ctrl+Shift+S 继续转发给 Neovim，在编辑区执行撤销、保存当前文件、剪切、全选、重做和全部保存。
- 点击回 VS Code 自身编辑区、切换到普通终端或退出 AstroNvim 后，原客户端快捷键继续生效。
- 1.0.4 可迁移旧版留下的备份并保留最初快照；升级前应退出运行旧扩展的 AstroNvim 会话，按“首次配置”步骤更新和重载。1.0.0 等仍将 Ctrl+V 作为按键转发的旧客户端，只能使用远端编辑器缓存，不能借此读取最新 Windows 剪贴板。

## Windows 终端永久暂停的可选兼容工具

本轮在 VS Code 1.143.1 的特定构建中复现了终端 ACK 恰好停在 5000 字符时无法恢复的错误。包内提供 [Check/Apply/Restore 脚本](astro-vscode-terminal-flow-fix.ps1) 和 [使用说明](WINDOWS-TERMINAL-FLOW-FIX.md)：精确校验版本、commit 和目标 SHA，HOME 备份，原子替换；不改 `product.json`，不结束用户进程。实际验证机已应用持久修复，新进程中的 40 次原菜单/Esc 操作通过。未知版本明确拒绝，不能把该工具当作所有终端卡顿的统一修复。

它是 Windows 客户端可选工具，不是扩展自动安装步骤、Linux `env.sh` 依赖或每次 Linux 迁移都要执行的命令。

## 搜索使用

- Ctrl+Shift+N：输入文件名后回车、单击或双击结果，内容显示到编辑区。
- Ctrl+F：搜索编辑区当前文件；从调试窗格触发也使用该文件。
- 左侧“搜索”：点击搜索框底部“类型”或按 Ctrl+T，输入 `*.cpp,*.h`，只搜索这两类文件；清空表示全部。多个类型取并集，同一项目的本次会话内记住筛选。

## 历史验证情况

下列记录用于说明已有测试范围，不作为当前版本已完成全部平台验收的声明。当前 ARM 云主机已释放，后续共同源码修改尚未在新的 ARM 实机复测；最终状态见 [最终验收报告](../docs/最终验收报告.md)。

- x86/ARM 真实终端：43 个 IDEA 按键在 Normal/Insert 下各验证一次，每个平台 86 次；Ctrl+Shift+N 真正打开文件并检查内容，Ctrl+F 搜索编辑区文件，Ctrl+T 打开类型设置。
- 两平台完整 UI：从编辑区、目录树、活动栏和调试窗格打开文件；回车、单击、双击均通过。
- 两平台真实启动器：启动标题通知、点击整体 × 的取消/确认退出、手动恢复通知均通过。
- 备份模块通过真实文件测试：精确恢复、并发会话、中途编辑、原文件不存在、崩溃记录、重复恢复；生命周期 API 测试使用模拟 VS Code API。
- 2026-09 历史测试曾被 VS Code 更新锁阻止，当时未验收完整图形链路；2026-10-25 的 1.0.1 版本后来使用 Windows 图形客户端完成了实际 SSH 链路测试，见下一节。

原始按键、备份恢复和启动退出记录留存在验证工作区，不随总包发布。

## 1.0.1 历史验证（2026-10-25）

2026-10-25，在当时的 Windows 的真实 VS Code 图形窗口，通过 PowerShell 和 Windows OpenSSH 连接 Linux，6 组实际键盘与系统剪贴板测试通过：外部中文粘贴、复制回 Windows、选区替换、撤销/重做、保存及全选/剪切。用户设置为 `{}`，标题识别使用新版扩展默认值。测试通过 CDP 向真实 VS Code 窗口发送键盘事件；产品操作读取实际 Windows 剪贴板及 Linux 文件。

11 项新增规则/升级/标题默认值测试与 11 项原生命周期回归通过，使用 VSIX 内的真实 key-store 模块对临时用户家目录进行文件操作，覆盖活动会话升级、BOM/CRLF/注释精确恢复、原配置不存在、用户中途编辑及多会话。VS Code 生命周期 API 使用模拟对象；实际 Neovim/PTY 编辑和括号粘贴由编辑区测试覆盖。这两组属于文件/模拟 API 测试，与上一段的真实 Windows 端到端测试分别记录。原始记录留在验证工作区。

## 1.0.2 历史验证范围

以下为 1.0.2 的历史验证，不能直接作为 1.0.3 已完成实际 Windows 性能验收的证明。该版修复先在冻结的 1.0.1 VSIX 上复现 6 项问题，再验证 14 项真实隔离文件回归和 7 项模拟 VS Code 控制器回归。覆盖 Profile 隔离、已删除 Profile、同 Profile 多窗口、版本规则竞争、用户中途修改、BOM/CRLF 精确恢复、写入失败和中断恢复、锁竞争、手动恢复抑制以及失败时不启用转发。100 次稳态轮询没有配置内容读写；这是 I/O 计数验证，不能替代实际 Windows 的延迟测试。1.0.2 的 Windows 图形链路及整体性能验收另行记录，历史 1.0.1 结果不作为该候选已通过的证明。

追加持久写入失败回归：在隔离文件系统中仅对目标替换注入 EACCES，模拟 60 秒、400 次 150 ms 轮询。旧版产生 800 份重复备份，候选固定为 2 份，保持每次轮询都尝试目标写入；解除故障后可接管并精确恢复。这项使用模拟时钟，不作为一分钟真实时间性能结果。

当前整体验收结论见 [最终验收报告](../docs/最终验收报告.md)。本页历史测试记录不代表所有平台已完成性能验收。

## 1.0.3 历史变更与验证

1.0.3 保留 578 条规则、客户端控制器和租约/事务协议，只优化备份模块两处重复操作：原子替换成功后不再删除已移动的临时路径；恢复缓存不可能命中时，不计算完整签名，但仍严格检查目标路径，避免把无访问权限或路径中间不是目录误当成文件不存在。备份、用户改动保护、多窗口租约和中断恢复逻辑保留。

相同优化源码在隔离副本中与未修改的 1.0.2 对照，两版各 14 项租约/恢复、7 项控制器、2 项同版本竞争、10 项原子写和访问错误检查均通过；另验证 400 次目标写失败重试不增加重复备份，故障解除后精确恢复。控制器测试使用模拟 VS Code API，文件与故障恢复使用真实隔离目录；这组结果不冒称实际 Windows 界面测试。

随后每路径使用 8 个全新 Linux Node 进程、ABBA 两轮、每版 100 个正式样本比较。坏 JSON 拒绝 0.5307 → 0.5223 ms，区间跨 0；原本不存在文件的恢复 0.4296 → 0.4066 ms，首次接管并备份 2.6239 → 2.4934 ms，进程级区间偏向优化，但分层区间仍跨 0。这是本机存储模块耗时，不是 Windows 快捷键响应或界面延迟。

此前原 1.0.1 对未优化 1.0.2 的独立复测，确实确认坏 JSON 拒绝、原本无文件的恢复和首次接管三条存储路径变慢；本次两处优化尚不能证明这三个差异已全部消除。新增每 Profile 租约和 pending 事务用于修复真实的多窗口与精确恢复问题，没有为追求旧耗时而移除。1.0.3 的真实 Windows 对照和整体状态见 [最终验收报告](../docs/最终验收报告.md)，不据此签署全功能、全平台性能无劣化。

## 1.0.4 历史变更与验证

1.0.4 包含退出恢复路径和 KeyStore 的当轮优化。此前1.0.2/1.0.3章节属于历史记录，不改写旧测试结果；1.0.4当时实际测量源码、最终并发分支、Windows链路及RSS结论见 [性能优化记录](../docs/性能优化记录.md) 和 [最终验收报告](../docs/最终验收报告.md)。版本升级后仍需在Windows安装随包VSIX并重载窗口；仅更新远端目录不会更新客户端。

## 本轮候选验证状态（2026-10-27）

当前准备组合为Linux C110与Windows客户端1.0.8，仍为未发布的candidate-only。Windows108的Ctrl单击/文件目录操作20次、焦点切换、整体退出、手动恢复与保留用户编辑已有指定功能验证；C110经真实Windows链路的10项复制/剪切/粘贴每项1次通过。五项既有成本差异、两项搜索信号及其余未完成验收仍保留，ARM/EulerOS缺少本轮实机；这些功能结果不是配对性能或商用验收通过。 108的混合工作区租约已完成104项Node正确性检查；真实手动恢复验证保留无关用户编辑并清理事务，含用户编辑时不要求把用户格式恢复成旧文件字节。110修复Select模式复制/剪切：先用Ctrl+G转换到对应Visual选择，再执行原复制/删除操作；复制后恢复原Select选择，避免把寄存器与操作命令当成替换文字。字符、行、块选区使用同一通用Lua逻辑，没有新增架构条件。22项headless正确性通过；该轮实际Windows的10项剪贴板操作是正确性记录；后续测试器间歇错误的根因与正式配对结果见本次收尾部分。

以下历史记录保留各自的源码版本与日志范围。

已知 Default 的三层鼠标事务最初完成 54 项（Profile、单目录、workspace 各 18）；合并本轮 Linux 修复与非阻塞提示后又完成 18 项及焦点/恢复检查。最小 Profile 第一版的真实 Default、named 缺配置拒绝、named 显式路径精确恢复、临时 Profile 目录存在而无持久元数据时拒绝均已有证据。随后独立审查补上重定向文件与权限错误拒绝；相关模块和 guard 单元测试共 52 项通过。最终R2实际Windows已通过named手动恢复并保留其他编辑、Default菜单18项，以及普通终端焦点、再次接管、Ctrl+F、两次Esc和整体退出恢复的操作断言；当时ErrorGate仅覆盖已接入渠道，不能称完整客户端日志干净。补审保留Copilot宿主proposal错误、准确受控关闭关联的10条Canceled及另外4条关闭原因待核记录。不能将早先版本结果当作最终 VSIX 的性能或全部平台验收。

1.0.5的原EPERM与日志漏捕保留为历史证据。1.0.6随后通过18项实际文件菜单、Save/Discard/Cancel、两方向焦点和两条真实句柄占用事务；1.0.7只追加正常关闭路径修复并已冻结，7项定向与真实Windows正常关闭通过。产品日志门禁通过的记录不能称完整客户端无错误，仍有3条Copilot/Node宿主记录。原始截图和JSON留在验证工作区；全功能性能和ARM实机仍未验收。

关闭整个VS Code窗口与先退出AstroNvim是不同流程。真实Windows直接SSH启动、没有script录屏包装时，正常关闭VS Code已验证5个远端测试PID及Windows SSH全部退出，快捷键和鼠标设置逐字节恢复。此前诊断残留已归因于录屏包装将stdin EOF转为子PTY的字面Ctrl+D，产品代码未改。断网、强杀或其他环境不在本次结论内，范围见 [当前验收](../docs/最终验收报告.md#当前状态)。
