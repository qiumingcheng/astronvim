# 编译数据库目录配置

允许在 AstroNvim 安装目录的 `env.sh` 中指定 C/C++ 编译数据库目录。此补丁修改 Lua 和环境配置，无需重新编译 Neovim、clangd 或项目。

## 使用

当前 x86 与 ARM 总包已包含这项功能，不需要另外下载或安装旧补丁。

在安装目录 `env.sh` 中修改新增配置项，例如构建目录名称是 `cmake-build-debug`：

```bash
export ASTRO_CLANGD_CDB_DIR="cmake-build-debug"
```

相对路径按当前项目根目录解析，也支持绝对目录及带空格的路径。目录中须已有可读取的 `compile_commands.json`。设置后退出当前编辑器，重新 source `env.sh` 并启动：

```bash
source /实际/astronvim/安装目录/env.sh
cd /实际项目目录
astronvim .
```

此项配置对该环境启动的所有项目生效，并通过 clangd 的 `--compile-commands-dir` 参数优先于项目 `.clangd` 的数据库目录设置。相对路径随切换项目重新解析。设为空值时保留自动查找和项目 `.clangd` 用法：

```bash
export ASTRO_CLANGD_CDB_DIR=""
```

此说明面向当前总包；旧版只添加环境变量而没有相应 Lua 实现不会生效。目录缺少数据库时会提示具体路径；通过 `:lua Snacks.notifier.show_history()` 查看通知历史。编译数据库由构建系统生成；CMake 应对原构建目录启用 `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`，保留工具链及其他配置参数，生成 JSON 本身无需完整编译。`astro-clangd-cdb` 适用于已配置的 openGauss Makefile 源码树。

正常启动和“重建索引”沿用目录配置；重建只清理项目内部缓存，不清理项目外构建目录的缓存，也不执行编译。根目录选择会优先识别更近的 CMake 项目，避免外层数据库覆盖当前项目。

## 已连接但没有索引进度

“clangd 已连接”只表示语言服务已连接，不证明全项目编译数据库已找到或索引已经完成。百分比来自 clangd 实际上报的进度；缓存可复用、工程较小或服务尚未上报时，不一定能看到持续变化的百分比。

如果同时搜索不到函数，先确认配置目录中存在可读取的 `compile_commands.json`，其中包含当前环境的实际源码路径、宏和头文件目录。迁移了项目或工具链之后，旧 JSON 内的绝对路径可能不再适用，需要由原构建系统重新生成。CMake 项目不使用仅面向 openGauss Makefile 的 `astro-clangd-cdb`。

在编辑器中查看本次重建清理数量与项目根目录：

```vim
:lua print(vim.inspect(require("workspace_lsp").last_rebuild))
:LspInfo
:LspLog
```

`removed=0` 表示这次没有删除项目内的 `*.idx`，不能单独作为失败或成功结论：首次运行、缓存位于项目外、数据库未找到等都需要结合日志区分。索引线程数由 `env.sh` 的 `ASTRO_CLANGD_JOBS` 控制，默认 4，并被限制为不超过当前可用逻辑 CPU 数。重建沿用当前进程的参数；修改配置后需要重新 source 并重启 AstroNvim。

## 验证

本地 x86 使用完整 AstroNvim UI、真实 CMake 和 clangd 22.1.6，临时项目/状态/缓存均隔离。测试包含：相对目录、绝对目录、目录含空格、子目录启动、项目切换、配置优先级、空值兼容、缺失数据库提示，以及实际百分比、Ctrl+N 搜索、Ctrl+B 跳转、鼠标重建、LspRestart、环境变量恢复。

当前验证范围见 [最终验收报告](最终验收报告.md)。ARM 部分仅检查包内原始文件的补丁适用性、安装幂等性、平台配置保留和回滚，没有在新 ARM 主机执行 UI/LSP 功能测试。

安装后可在宿主环境安装有 Python 3、CMake、Ninja 和 C++ 编译器时运行完整功能验证：

```bash
python3 /实际/astronvim/安装目录/scripts/verify-clangd-cdb-env.py
```

## 撤销目录设置

将 `env.sh` 中的 `ASTRO_CLANGD_CDB_DIR` 设为空，重新 source 并启动编辑器，即恢复 clangd 原有的自动查找及 `.clangd` 配置方式。此操作不删除编译数据库或源码。

完整安装目录的版本回退应使用自己保留的旧版完整目录；不要把历史补丁的回滚脚本套用到当前总包。
