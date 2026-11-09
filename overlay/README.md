# AstroNvim Portable

## 源码小包的首次安装

这份 README 描述**安装完成后的目录**。若下载的是 `astronvim-source.tar.gz`，应先运行源码包的 `install.sh --prefix <新目录>`；第三方组件将按锁定版本下载或构建。之后再按本文 source、启动和迁移。详见[源码安装说明](docs/源码安装.md)。下文有日期的验收记录保留其历史范围。

## 2026-11-09：总包已合入文件搜索修复

本包以 2026-11-01 的 focus111 为基础，已合入 2026-11-06 的文件搜索补丁，无需另外安装该补丁。`Ctrl+Shift+N` / 空格 f f 默认搜索隐藏文件和被忽略的文件，排除 Git 元数据及 clangd 索引缓存；`Alt+I` 可切换忽略规则。文件名搜索与 clangd 符号索引彼此独立，详见[文件搜索与索引](docs/文件搜索与索引.md)。

Linux 端仍是解压后 `source /实际目录/astronvim/env.sh`，再运行 `astronvim /项目目录`。Windows VS Code 配套扩展为 **1.0.9**，位于 `vscode/astronvim-terminal-keys.vsix`。修复的 Windows VS Code＋SSH 实测范围及现有验收边界见[最终验收报告](docs/最终验收报告.md)；这次总包刷新不代表新增 ARM 实机或全功能性能验收。

## 2026-11-01：Windows 客户端焦点路由更新

当前候选为 focus111：Linux 运行时完整保留 closeout110，Windows 扩展更新为 **1.0.9**。新增内置焦点快捷键，Ctrl+Shift+N 在 AstroNvim 终端和 VS Code 编辑区按键盘焦点分别处理，使用说明见 [客户端说明](vscode/README.md)。在 Windows 客户端更新一次随包 VSIX；此后不需要为该功能手工编辑 keybindings.json。两种架构包包含相同扩展和共同源码。

本次仅做客户端焦点路由专项验证，不改变已有整体未验收结论；下文旧日期的测试及限制保持原范围。

独立安装的 AstroNvim 6.1.0 / Neovim 0.12.5，预装 C/C++ 搜索、代码导航、GDB 17.2 与 CodeLLDB 调试。
界面接近 VS Code；主要快捷键采用 IntelliJ IDEA 的 Windows/Linux 方案。

```bash
source /实际安装目录/astronvim/env.sh
astronvim /你的项目目录
```

Linux 部署只需复制对应架构完整包、解压、source `env.sh`；换 Linux 机器不需要逐个补丁安装。也可进入项目后执行 `astronvim .`。所有环境变量集中在 `env.sh`；不会修改 `.bashrc`。

Windows VS Code 扩展是客户端一次性安装的组件，与 Linux 迁移分开；SSH 启动器不能替 Windows 安装扩展。命名/临时 Profile 使用显式 User 配置路径，见 [客户端说明](vscode/README.md) 和 [Profile 配置](vscode/PROFILE-SETUP.md)。特定 VS Code 版本的终端 ACK 修复是独立可选工具，见 [兼容说明](vscode/WINDOWS-TERMINAL-FLOW-FIX.md)，不是 `env.sh` 的依赖。

本次按约定的四项进行收尾，当前组合为Linux C110与Windows客户端1.0.8。维护操作5项已完成固定8组耗时/CPU/内存对照，真实VS Code链路的45项核心与10项剪贴板端点分别完成固定8组采集；核心前两组复用相同源码与测量脚本的已成功记录。其中52个端点有可比较数据，旧版不支持调用栈单击刷新，以及已复现的Select复制/剪切错误，均单独保留，不将失败耗时与修复后成功耗时比较。本轮核心对照有3个耗时指标出现待复核的正向信号。五项既有成本差异、两项历史搜索信号及右键菜单偶发问题未关闭，ARM/EulerOS/手机缺少本轮实机证据。总包保持明确的未验收候选身份，不宣称全功能、全平台性能无劣化或商用验收通过。 详见 [最终验收报告](docs/最终验收报告.md)。
从目录启动时，左侧显示文件树，右侧保留空编辑区；打开文件后编辑区才显示源码。
进入 C/C++ 项目即自动在后台启动 clangd，不需要先打开源码。底部全局状态栏显示启动状态以及真实索引进度，例如 `clangd 索引 [####......] 42% 920/2175`，完成后显示 `clangd 索引就绪`；尚未收到进度数字时只显示等待标记。再次进入会复用已有索引缓存。空白编辑区、文件树中均可用 `Ctrl+N` 搜索全项目符号。
底部状态栏的 **[重建索引]** 支持鼠标左键单击：自动停止当前项目的 clangd、清理项目内索引缓存并重新启动，进度继续显示在旁边，无需编译。新增文件或编译参数变化时，先更新 `compile_commands.json`，再点击该按钮；按钮本身使用现有编译数据库。
索引支持多线程；并发数统一在 `env.sh` 的 `export ASTRO_CLANGD_JOBS=4` 调整，实际不超过可用逻辑 CPU 数。修改后重新 source 并启动编辑器。默认配置为 4，增加线程也会增加峰值内存；日常修改已有代码会自动增量更新，不必反复点击全量重建。
调试继续运行时，局部变量和线程/调用栈区域会清空上一次暂停位置的数据，下一次断点暂停后自动刷新。
调试当前行使用琥珀色整行高亮、亮黄色 `=>` 箭头和加粗行号；标记跟随单步执行位置，继续运行后清除。旧会话执行 `:lua require("debug_highlight").setup()` 可立即应用，新启动自动加载。
断点按启动项目目录自动保存到包内 `state/nvim/breakpoints/<项目路径哈希>.json`，再次从同一目录启动会自动恢复普通断点、条件、命中次数和日志表达式；删除/清空断点也会保存。单击“断点 / Breakpoints”窗格中的断点或条件说明行，可在编辑区定位到对应源码，不改变程序的暂停位置。
各窗格顶部显示中英文名称：文件目录、编辑区、局部变量、监视表达式、线程与调用栈、断点、调试控制台、程序输出。输入表达式或调试器命令使用“调试控制台 / REPL”；“程序输出 / Console”显示被调程序输出和 Attach 完成标志。
控制台输入：单击 REPL 末尾 `dap>` 提示行或其下方空白，或先按 Esc，再按“空格 → d → Shift+R”，即可输入。Enter 执行、↑/↓ 调出历史、Esc 退出输入；点击历史输出仍可选择文字。GDB 会话可输入 `info b`、`bt`、`p query_string`；显式选择 CodeLLDB 时，使用 `breakpoint list`、`thread backtrace`、`frame variable query_string` 或 `? a + b`。局部变量需要先暂停并选择正确栈帧。注意大写 R 聚焦控制台，小写 r 重启调试。
主命令已由 `nvim` 改为 `astronvim`，`astro` 保留为兼容入口。
关闭当前子窗口用 `:q`；退出整个编辑器点击最上方的 ×，或执行 `:qa`。有未保存内容时先处理保存提示。恢复当前 shell 原环境用 `astro_deactivate`。

## 快捷键

| 操作 | IntelliJ 风格按键 | 普通终端备用键（先按 Esc） |
|---|---|---|
| 文件搜索 | Ctrl+Shift+N | 空格 f f |
| 全项目关键字 | Ctrl+Shift+F | 空格 f w |
| 当前文件符号 | Ctrl+F12 | 空格 s s |
| 全项目符号 | Ctrl+Alt+Shift+N | 空格 s w |
| 全项目符号（含函数、类、struct） | Ctrl+N | 空格 s w |
| 类型（类、struct、接口、枚举等） | — | 空格 s c |
| 当前文件查找 | Ctrl+F | 空格 f l |
| 命令搜索 | Ctrl+Shift+A | 空格 : |
| 定义跳转 | Ctrl+B / Ctrl+鼠标左键 | g d |
| 查找引用 | Alt+F7 | 空格 l R |
| 前进 / 后退 | Ctrl+Alt+→ / ← | Ctrl+i / Ctrl+o |
| 文件树 | Alt+1 | 空格 e |
| 复制选中内容 / 当前行 | Ctrl+C | "+y / "+yy |
| 粘贴 / 替换选区 | Ctrl+V | 终端粘贴键；编辑器内可用 "+p |
| 剪切选中内容 / 当前行 | Ctrl+X | "+d / "+dd |
| 撤销 / 重做 | Ctrl+Z / Ctrl+Shift+Z | u / Ctrl+r |
| 保存当前文件 | Ctrl+S | :write |
| 保存全部文件 | Ctrl+Shift+S | :wall |
| 全选当前文件 | Ctrl+A | ggVG |
| 底部终端 | Alt+F12 | 空格 t h |
| 启动 / 继续调试 | Shift+F9 / F9 | 空格 d c |
| 断点 | Ctrl+F8 | 空格 d b |
| 条件断点 | — | 空格 d Shift+B |
| 单步进入 / 跳过 / 跳出 | F7 / F8 / Shift+F8 | 空格 d i / d o / d O |
| 停止调试 | Ctrl+F2 | 空格 d Q |
| 求值 | Alt+F8 | 空格 d e |
| Attach：附加已有进程 | — | Esc → 空格 → d → a |
| 调试窗格 | Alt+5 | :lua require("dapui").toggle() |

**Attach 完整操作：先按 Esc，再依次按空格 → d → a，输入当前环境的目标 PID，选中目标后按 Enter。** 这些键依次按，不同时按；数据库重启后需要核对新的 PID。

x86_64 与 ARM64 全量包均自带 GDB 17.2，`空格 d a` 优先使用包内 GDB。启动新程序时，Shift+F9 选择名称含 `GDB` 的 Launch 配置；原有 CodeLLDB 配置和示例仍保留。GDB 启动时自动设置 `set print elements 0`，attach 自动放行 SIGUSR2，识别到 gaussdb 时也放行 SIGUSR1。`bin/gdb` 使用包内 Python 和运行库，不要求目标机安装 GDB 或 Python；`env.sh` 的 `ASTRO_GDB_PYTHONHOME` 指向包内 Python，不修改当前 shell 的 `PYTHONHOME`。

调试暂停时，在“线程与调用栈”中单击栈帧，会跳转到该栈帧的源码，并同步显示对应的参数和局部变量；点击当前栈帧可重新聚焦编辑区。

导航快捷键统一配置在 `config/nvim/lua/idea_keys.lua`：`<C-M-Left>` 对应 Ctrl+Alt+←（后退），`<C-M-Right>` 对应 Ctrl+Alt+→（前进）。普通模式和插入模式均已配置；修改后重新启动 AstroNvim 生效。这两个操作使用 Vim 跳转历史，包含文件、定义等跳转，普通方向键移动不会逐次记入；可用 `:jumps` 查看历史。终端截获组合键时，先按 Esc，再用 Ctrl+o / Ctrl+i。

编辑区支持上述常用组合键，普通模式、插入模式和选区下均可用。Ctrl+S 保存当前文件，未命名文件会询问路径；Ctrl+Shift+S 保存全部。Ctrl+Z 用于撤销，不再挂起编辑器。Ctrl+Y 未改为重做，重做使用 Ctrl+Shift+Z。Windows VS Code 终端经 SSH 使用时，请使用与完整包配套的客户端组件：Ctrl+C 通过 OSC 52 复制到 Windows 剪贴板，Ctrl+V 由 VS Code 读取客户端剪贴板并发送到远端。普通模式粘贴在当前字符之后，插入模式在当前插入点；有选区时替换选区。启动器与 Neovim 维持本次运行的动态标题标记，避免切换文件导致客户端识别失效，退出恢复原标题。说明及测试范围见 [编辑区常用快捷键](docs/编辑区常用快捷键.md)。

`F1` 打开内置速查。默认是 Vim 的普通模式，`i` 输入，`Esc` 回到普通模式。
终端可能截获 Ctrl+Shift、Alt 或功能键；备用键不需要修改终端设置。
终端不能可靠上报单独的 Shift，双 Shift 用“空格 空格”搜索菜单代替。

## 鼠标

客户端1.0.8在AstroNvim活跃终端接管期间，同时设置 `terminal.integrated.rightClickBehavior="nothing"` 与 `editor.multiCursorModifier="ctrlCmd"`。Ctrl+单击交给Neovim，VS Code终端链接改用Alt+单击；这也会临时改变VS Code编辑器的多光标修饰键。共享配置按键合并租约，每个键在最后持有者释放后恢复；无用户修改时恢复原文件字节，有用户修改时保留其修改。双键备份放在当前Windows用户HOME的 `.astronvim/vscode-settings-backups-v3/`，不放Linux安装目录。 手动恢复使用 `astro-vscode-restore`，详见 [客户端说明](vscode/README.md)。

文件树：单击目录展开/收起，双击文件打开，右键菜单可打开、新建文件/目录、重命名、复制、剪切、粘贴、删除、刷新。
代码编辑区的行号/标记栏：左键单击切换普通断点，右键单击输入条件并设置条件断点。

左侧“搜索”支持文件类型筛选：单击搜索输入框底部的“类型”，或在该搜索区域按 Ctrl+T，输入 `*.cpp,*.h`，即搜索这两类文件。多个类型取并集，清空表示全部；筛选在当前项目的本次会话内保留。Ctrl+Shift+F 是独立的全项目关键词搜索入口，不自动复用侧栏筛选。

`Ctrl+N` 和全项目符号搜索支持空格分词输入：例如 `subquery planner` 可匹配 `subquery_planner`，也可匹配 `subqueryPlanner`。输入框保留原文字，发送给 clangd 时去掉空白，由 clangd 做模糊匹配；选中结果回车跳转。搜索结果依赖项目 LSP 索引。

升级前已打开的会话，如果还有需要保留的断点，退出前先执行 `:lua require("dap"); require("breakpoint_store").setup(); require("breakpoint_store").save()`；随后重启加载全部修复。旧版本已经退出且未保存的断点无法追溯恢复。项目路径变化后视为另一个项目；多窗口同时编辑同一项目的断点时，以最后保存的会话为准。
右键菜单单击执行；确认列表双击选择。文件名需要键盘输入。
支持点击标签和拖动窗口分隔线，不实现桌面文件管理器式的文件拖放搬移。

## C/C++

**“重建索引”按钮的后台执行顺序**：

1. 使用包内 `fd --hidden --no-ignore --type d --full-path --prune --print0 --exclude .git '/\.cache/clangd/index$' <项目目录>` 查找缓存目录。
2. 调用 Neovim LSP 的 `client:stop(false)` 正常停止当前项目 clangd，等待退出；超时则取消清理并在退出后恢复服务。
3. 通过 `uv.fs_unlink()` 删除项目内缓存目录中的 `*.idx` 文件，保留源码、编译数据库及其他文件。
4. 使用 `vim.lsp.start()` 沿用当前会话的配置重新启动 clangd，并重新连接原来的缓冲区。当前进程参数如下：

   ```bash
   "$ASTRONVIM_ROOT/bin/clangd" --background-index --clang-tidy \
     --completion-style=detailed --header-insertion=never \
     -j=4 --pch-storage=memory
   ```

clangd 随后读取现有 `compile_commands.json`，按配置的工作线程数解析源码和相关头文件、生成缓存；默认最多 4 个，实际不超过可用逻辑 CPU 数。主要耗时在这个解析阶段。按钮不执行 `make`、`make -n` 或 `astro-clangd-cdb`，也不重新生成编译数据库。实现见 `config/nvim/lua/index_rebuild.lua`；线程数配置见 `env.sh`，修改后需要重新 source 并启动编辑器。

大型项目应提供 `compile_commands.json`，例如 CMake 的 `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`。

**通过环境变量指定目录**：在 `env.sh` 中把 `ASTRO_CLANGD_CDB_DIR` 设置为实际构建目录，例如：

```bash
export ASTRO_CLANGD_CDB_DIR="cmake-build-debug"
```

相对路径以当前项目根目录为基准，也支持绝对路径和带空格的目录。修改后退出当前编辑器，重新 source `env.sh` 并启动 AstroNvim；运行中的编辑器不会获得父 shell 的新环境变量。此项适用于该环境启动的所有项目，并优先于 `.clangd` 中的数据库目录设置。留空时继续使用 clangd 的自动查找和项目 `.clangd` 配置。指定目录缺少可读取的 `compile_commands.json` 时，自动启动会提示具体路径；通知历史可通过 `:lua Snacks.notifier.show_history()` 查看。

**自定义编译数据库目录**：在项目根目录的 `.clangd` 文件中指定目录名称，例如：

```yaml
CompileFlags:
  CompilationDatabase: cmake-build-debug
```

将 `cmake-build-debug` 改为实际构建目录，其中须已有 `compile_commands.json`。相对路径以 `.clangd` 所在目录为基准；已有 `.clangd` 时合并该字段，保留其他设置。此配置由 clangd 原生读取，说明见 [clangd 配置文档](https://clangd.llvm.org/config#compilationdatabase)。修改后执行 `:LspRestart`；项目内自定义目录支持自动启动、索引进度和“重建索引”缓存清理。绝对路径也可以用于读取数据库，但当前重建按钮只清理项目目录内的缓存。

配置目录不会生成编译数据库。CMake 项目应在原构建目录启用导出，保留原工具链和配置参数；`astro-clangd-cdb` 仅适用于已配置的 openGauss Makefile 源码树。
clangd、GDB、CodeLLDB 及各自的内部 Python/运行库均已随包安装；你的项目编译器、SDK 和被调程序依赖仍由项目准备。

openGauss 可以直接用随包工具从现有 Makefile 生成数据库，不需要为 clangd 重新编译项目：

```bash
source /实际安装目录/astronvim/env.sh
astro-clangd-cdb /实际项目目录/openGauss-server
```

该命令只执行 `make -n`/`make -n -W` 和 Bear `parse-sh`，不会安装或重启 openGauss。普通 `make -n` 会遗漏已经存在的 `.o` 对应命令，工具会自动补齐；生成后在 AstroNvim 执行 `:LspRestart`。`compile_commands.json` 含当前主机的绝对三方库路径，换环境后应重新生成。

修改已有源码时 clangd 会自动重新解析；新增源码且已加入 Makefile、重命名文件，或修改 Makefile/宏/头文件目录后，重新运行上面的命令，再执行 `:LspRestart`。只在编辑器中新建但尚未加入构建目标的文件没有完整编译命令，需先加入 Makefile。
无需为编辑器另装 Node、Python、Rust、Neovim 或系统 clangd。

带调试符号的示例：

```bash
cd "$ASTRONVIM_ROOT/examples/cpp"
make                 # 示例已预编译；本命令用于重新构建，需要宿主 C++ 编译器
astronvim .
```

打开 `main.cpp`，在第 4 行按 Ctrl+F8，再按 Shift+F9，选择 `Demo: C++ launch`。
支持 `.vscode/launch.json` 的 GDB 配置（`type: "gdb"`）与 CodeLLDB 配置（`type: "lldb"` / `"codelldb"`）；不自动执行 VS Code tasks.json 或 preLaunchTask。空格 d l 检查当前项目配置，启动选择器每次读取最新文件，不再重复导入到全局配置；旧会话已有的重复项可通过重启编辑器清除。
其他调试器的 `cppdbg` 配置不能直接当作 CodeLLDB 配置使用。

## 断点调试

默认 Attach 使用包内 GDB 17.2。完整步骤、条件断点、线程过滤、变量展开、监视表达式删除和源码路径排查见 [调试操作](docs/调试操作.md)。

示例：先打开带调试符号的源码，按 Ctrl+F8 设置断点，再按 Esc → 空格 → d → a，选择**当前环境**中实际运行的 PID。程序输出窗显示 Attach 完成后，再向被调程序发送请求。F8 单步、F9 继续。结束数据库调试时执行 `:lua require("dap").disconnect({terminateDebuggee=false})`，保留数据库进程。

示例工程的 `Demo: C++ launch` 使用 CodeLLDB；可在 Shift+F9 的选择器中改选名称含 GDB 的配置。两种调试器的 REPL 命令不同，使用前核对当前会话。

### 日志目录与错误记录


正常启动的运行日志位于安装目录 `state/nvim/`：`dap.log` 记录调试器，`lsp.log` 记录语言服务，`nvim.log` 记录 Neovim 内部消息。调试器运行时还可能产生 `dap-*-stderr.log`；适配器正常退出后这些临时日志可能被清理。总包不包含开发和验收期间的运行日志。

当前没有单一的“全量日志”文件：Lua 异常、通知和调试器错误可能分布在不同位置。通过 Windows VS Code 使用时，还需保存当前客户端窗口的“输出”面板中 `AstroNvim Keyboard` 通道，以及该窗口的 extensionHost 和 renderer 日志；这些客户端日志不在 Linux 的 `state/nvim/` 中。具体入口和审计边界见 [客户端日志](vscode/README.md#客户端日志与错误排查)。迁移或覆盖 XDG 环境后，请在当前实例中查看实际路径，并在退出前保存消息：

```vim
:lua print(vim.fn.stdpath("log"))
:messages
:lua Snacks.notifier.show_history()
:lua vim.fn.writefile(vim.split(vim.fn.execute("messages"), "\n"), vim.fn.stdpath("log") .. "/messages.log")
```

需要记录复现过程时，可先在 Linux 终端 source 环境、进入项目，再启动临时详细日志：

```bash
mkdir -p "$XDG_STATE_HOME/nvim"
astronvim -V0"$XDG_STATE_HOME/nvim/session-$(date +%Y%m%d-%H%M%S)-$$.log"
```

调试器通信细节可在复现前执行 `:lua require("dap").set_log_level("TRACE")`；语言服务细节用 `:lua vim.lsp.set_log_level("debug")`。复现后保存日志，分别改回 `INFO` 和 `WARN`。详细日志有额外开销，只用于排查，不作为默认启动设置，也不用于性能验收。日志可能包含源码路径、表达式和程序输出，分享前检查内容。

包内文档从 [文档目录](docs/README.md) 进入；当前验收范围和未完成项见 [最终验收报告](docs/最终验收报告.md)。原始测试输出保存在验证工作区，不装入总包。

## 自检与复制

Select模式修复与当前剪贴板验证范围见 [编辑区快捷键](docs/编辑区常用快捷键.md)。

```bash
astro-check
astro-pack /你选择的位置/astronvim-linux-$(cat "$ASTRONVIM_ROOT/platform-architecture").tar.gz
```

压缩包包含配置、插件、工具、运行库、解析器、许可证、示例、使用文档和最终审计/验收报告，排除测试原始 JSON/日志/截图等中间运行结果、缓存、历史会话、断点记录、日志、临时构建、安装根目录的开发仓库 `.git` 与补丁备份。插件 Git 仓库的对象、引用、配置和索引保留，便于核对版本和显式更新；本地 Git 操作日志（reflog）及 Python 字节码缓存不装入包，Python 源码保留。安装目录中的原文件不会因打包而删除。
也可以直接复制整个目录。解压/复制后，`source 新目录/env.sh`，再运行 `astronvim`。
目录名可以变化，也支持包含空格；无须联网下载已安装组件。

**提供 Linux x86_64 和 Linux aarch64（ARM64）两份包，均要求 glibc ≥ 2.34。选用与目标机器相同架构的包；同架构 Linux / WSL2 可复制复用。**
宿主仍需 Bash 和基础 Linux 命令。不适用于 macOS、原生 Windows 或 musl/Alpine。`platform-architecture` 记录包内二进制架构，`env.sh` 自动检查；不要通过修改这个标记尝试跨架构运行。

两种架构使用同一套二次开发源码，包括 Lua 配置、插件补丁、启动及维护脚本、VS Code 集成、文档与示例。源码小包的 `source-files.json` 记录交付源码 SHA256，`plugins.lock.json` 和 `patches.lock.json` 记录固定提交及补丁前后哈希。原生程序、运行库及编译后的解析器在安装时按目标架构下载或构建；来源记录在 `installation-provenance.json`。此前的 `ASTRO_CLANGD_CDB_DIR` 补丁已内置，无须另装。

使用说明见 [文档目录](docs/README.md)，依赖说明见 [第三方组件](docs/third-party/组件与许可证.md)。GDB 的 Python 支持源码也属于两架构共同维护的源文件，本轮原生 `delete` 后重新设置/清空断点的修复及精确 SHA 见 [GDB 本地修改](docs/GDB-DAP-PATCH.md)；最终发布仍须核对归档实际包含的字节。

默认关闭自动联网更新和自动安装解析器。插件版本记录在 `config/nvim/lazy-lock.json`，工具版本在 `versions.json`。
为保留已验证组合和本地补丁，不应使用 `:Lazy update` 绕过锁定文件。升级由维护者显式修改锁定版本、适配补丁并重新验证。
本轮候选还修复 Snacks 输入窗口关闭后延迟回调访问已释放 picker 的竞态；修前/修后 4 个定向场景保留完整证据。维护时应同时保留 `lua/snacks/picker/core/input.lua` 的关闭生命周期保护，完整范围见 [性能优化记录](docs/性能优化记录.md)。
包内 Snacks 的 `lua/snacks/layout.lua` 有一处本地修补：调整搜索侧栏大小时，不把独立预览窗的尺寸变化再次计入侧栏。插件更新或重新安装前，应保留并核对此修补，避免编辑区被挤窄的问题重新出现。

包内 DAP UI 的 `lua/dapui/windows/layout.lua` 保留了可拖动边界和重置后保存面板比例的修补；活动栏移动到最左侧后，也会重新应用保存的调试面板比例。鼠标调整后的比例在主窗口缩小再放大时继续使用；显式 `open({reset=true})` 则恢复配置中的默认比例。
包内 AstroUI 的 `lua/astroui/folding.lua` 调整了折叠检查顺序：先判断当前缓冲区是否启用 Treesitter，再查解析器，避免对已停用语法解析的文件逐行重复查询。插件更新或重装前也应保留并核对此修改。新版性能结果与实际范围见 [最终验收报告](docs/最终验收报告.md)。
包内 Neo-tree 的 `lua/neo-tree/sources/filesystem/init.lua` 修复了重开侧栏期间的跟随错误：新窗口已创建而旧树尚未替换时，不再读取旧树的光标，继续正常扫描并定位当前文件。修前在真实 Windows 使用链路和隔离用例中均捕获 `Invalid 'win': Expected Lua number`；修后 Linux x86 的 6 项定向用例、60 轮快速切换，以及 Windows VS Code → PowerShell/SSH → Linux x86 的 7 项调试复测均通过，后者未捕获错误通知。ARM 实机和正式性能的状态另见最终验收报告；插件更新时须保留此修复。维护方法见 [安装与更新](docs/性能优化安装.md)。
Neo-tree 的 `lua/neo-tree/sources/filesystem/lib/fs_scan.lua` 还修复了扫描完成顺序颠倒时旧结果覆盖新文件的问题：新整树扫描使此前的整树和局部扫描结果失效，同一轮的不同目录展开仍可并行完成。修后 6 项定向用例通过，原连续创建压力用例不再在重命名节点处失败；完整 CRUD 和最终性能仍以最新验收报告为准。
Neo-tree 的 `lua/neo-tree/git/ls-files.lua` 与 `lua/neo-tree/sources/filesystem/lib/fs_scan.lua` 另修复冷启动期间同步枚举整个 Git 仓库的阻塞：仅对本轮显示的路径异步判断 ignored 状态，结果齐备后渲染，并拒绝已关闭或过期扫描的回调。原调用曾阻塞约 4.7 秒；同一原大仓库的旧版复现再次记录同步 Git 4966.290 ms、RPC 等待 4947.595 ms。修复候选的同仓库 40 次查询无一次超过原 1500 ms 期限，原失败保留。20 项定向用例及真实扫描/渲染/协程展开通过；Windows 原冷启动请求通过，目录展开的后续超时已定位为测试准备重复打开文件引起的模态提示，修正测试器后真实 Windows 的 18 项菜单操作通过；这不是全界面或性能验收。插件更新前应保留这两处共同 Lua 修改，范围见 [最终验收报告](docs/最终验收报告.md)。
编辑器滚动条减少了前台 Insert 输入时的重复刷新排队，后台调试窗格继续自动更新。相同源码的 10 项滚动条功能验证通过；包含本轮四项 Lua 修复的 14,000 行输入复测中，原路径和连续 Insert 的耗时差值置信区间均跨 0，旧内部变慢信号未再次确认。这不等于所有场景和平台严格零劣化，测量口径与源码范围见 [最终验收报告](docs/最终验收报告.md)。
为避免字体依赖，默认使用普通字符图标；终端已配置 Nerd Font 时可在 `env.sh` 中取消 `export ASTRO_ICONS=1` 的注释，再 source 并启动。
剪贴板复制使用终端 OSC 52。VS Code 客户端组件将 Ctrl+V 交给客户端原生粘贴，因此 Windows 本地复制的内容可经 SSH 粘贴进 Linux 编辑区；Linux 端无需安装 xclip/Node/Python。普通 SSH 终端若直接转发 Ctrl+V，则粘贴编辑器内部保存的最近复制/剪切内容；外部剪贴板使用客户端已配置的原生粘贴键。当前 Windows VS Code 不安装组件时可使用 Ctrl+Shift+V；Shift+Insert 是否读取系统剪贴板取决于客户端，不能作为通用保证。删除文本不会污染这份内部复制缓存。

持续输出优化、clangd 日志判读和 SSH 静默断网边界见 [持续输出与日志验收](docs/持续输出与日志验收.md)。

上游参考：[AstroNvim](https://docs.astronvim.com/)、[IDEA 快捷键](https://resources.jetbrains.com/storage/products/intellij-idea/docs/IntelliJIDEA_ReferenceCard.pdf)、[CodeLLDB 1.12.3](https://github.com/vadimcn/codelldb/blob/v1.12.3/MANUAL.md)。本包的实际安装方式、启用功能和快捷键以本 README 为准；上游可选插件/API 不代表本包已安装或完成验收。按用户要求，Ctrl+S 保存当前文件、Ctrl+Shift+S 保存全部，Ctrl+N 搜索全部符号，这几项与原版 IDEA 的默认含义有所调整。

<!-- BEGIN STEP REFRESH UPDATE -->

## 单步刷新优化（2026-09-30）

同一暂停内合并重复调用栈和变量读取，等待新 scopes 后再刷新，丢弃旧暂停的延迟结果。ARM / GDB 17.2 的 17 线程短变量样例，中位请求刷新耗时约 142 → 78 ms，调用栈读取 49 → 17 次；源码单步期间复用现有缓冲区。14,000 行样例也没有每步重读全文。首次打开和复杂语法解析仍可能增加时间。详见 [安装与实测说明](docs/单步刷新优化.md)。

<!-- END STEP REFRESH UPDATE -->

<!-- BEGIN PERFORMANCE UPDATE -->

## 性能优化与鼠标边框提示（2026-09-30）

启动编译数据库选源异步化，实时搜索加快，界面重复重绘减少；调试变量读取去重，可见调用栈有界预取。修复拖动误触单步、关闭后文件树重开和启动 E216；分割线悬停显示 ↔ / ↕。ARM 的 600 文件关键词样例约 226 → 123 ms，17 线程短变量单步刷新约 78 → 70 ms。第二轮进一步优化调试文本生成和未变化画布复用：300 个局部变量 / 17 线程的真实单步约 118 → 91 ms。保留完整搜索结果、全部可见调用栈及 print elements 0。详见 [性能与逐项验收](docs/性能优化与功能验收.md) 和 [安装回滚](docs/性能优化安装.md)。

<!-- END PERFORMANCE UPDATE -->
