# GDB DAP 本地修复说明

修改日期：2026-10-27。组件：GDB 17.2 的 Python DAP 支持代码。

## 修复内容

在调试控制台通过原生 GDB `delete` 命令删除断点后，DAP 缓存可能仍保留已经失效的断点对象。随后在编辑器里重新设置或清空断点，原版可能报 `Breakpoint N is invalid.`。

本修复只调整 `_set_breakpoints_callback`：取出缓存后先判断对象有效性，失效则新建；两处清理只对仍然有效的对象调用 `delete()`。缓存取值使用一次 `pop`，合并原来的 membership 检查和 `pop`。不增加反向索引，不修改 native 断点事件回调，不引入新依赖，不需要重编 GDB 二进制。x86_64 与 aarch64 安装完全相同的 Python 源码。

包内运行文件：`opt/gdb/share/gdb/python/gdb/dap/breakpoint.py`。

上游源码对应位置：`gdb/python/lib/gdb/dap/breakpoint.py`。

精确差异附在同目录 [gdb-dap-validity-guards.patch](gdb-dap-validity-guards.patch)。

| 内容 | SHA256 |
|---|---|
| 原版源码 | `b6a00cb5bac504d2043c15b475866c52fc2228d4f33836e767a07616166c30a5` |
| 修改后源码 | `d3a81c156866f93539e4a8a83cdd06dc8c84b400ed753ac307ced37fa7d93df5` |
| 修改补丁 | `009566f582d71d95dd0cf9247e0a71628332d601157fcb636271f106fb0718ed` |

## 验证范围

修改版本独立通过 6 项原生 GDB 回归、50 次删除→重建→清空循环，以及 25 项 Linux 编辑器 DAP 功能回归。测试保留 `set print elements 0`。同一 runtime 路径的 8 块配对测试覆盖 1/100/1000 断点的设置/清空和复用，以及 100/1000 断点的原生删除；在这些场景中未观察到显著 wall/CPU/RSS 劣化。这不构成任意负载或所有平台性能绝对不变的数学证明，也不代替 ARM 运行验收或完整 Windows 资源性能对照。

随后在实际 Windows VS Code 1.0.5 客户端→PowerShell/SSH→Linux x86 链路，真实条件断点命中、支持源码 SHA 核对、`print elements` 为 unlimited、3次原生 `delete` 后 Ctrl+F8 重建、Ctrl+F2 停止及整体退出恢复快捷键均通过。该记录是功能回归，没有复用为上面的 native 性能样本。

源码安装器在目标架构构建 GDB 17.2 后，使用 `patches.lock.json` 检查本文件的原始哈希并应用同一份补丁，再验证修复后哈希。其他 GDB 可执行文件、运行库和 Python 平台文件按目标架构构建，不用 x86 原生文件覆盖 ARM。

## GPL 来源与对应源码边界

原文件保留 Free Software Foundation 的版权声明及 **GNU GPL version 3 or later** 许可头。本地修复继续作为该 GDB Python 代码的修改提供；本说明未为上游代码另行指定许可。安装完成后的 GDB 许可文本位于 `licenses/gdb/`；源码小包的补丁许可位于 `patches/LICENSES/`。

本次提供的是实际运行的修改后 Python 源码、本补丁、校验值和修改说明。它们足以审查并还原这一文件的差异，但不是整个 GDB、其构建工具链及所有动态/静态依赖的完整对应源码包。本说明不宣称已经完成所有组件的对应源码提供审核；其他来源和未决项仍以包内第三方依赖审计文档为准。
