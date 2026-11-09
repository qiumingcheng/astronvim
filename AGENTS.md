# AstroNvim 维护与本机安装记录

以下记录来自 2026-11-09 的本机安装，用于维护本仓库时参考，不应直接套用于其他主机。除非另有说明，文中的相对路径均相对于 `/home/qiumc/data/programs`，不是仓库根目录。

本机适配脚本、构建缓存和安装日志位于仓库外，不随 Git 仓库分发；其他机器需要重新检查环境并准备适配工具。

## 目录与安装状态

- 工作区：`/home/qiumc/data/programs`，本身就是 `programs`，不要再创建一层同名目录。
- 源码仓库：`https://github.com/qiumingcheng/astronvim`，克隆在 `tmp/astronvim`。
- 安装目录：`astronvim`，与源码目录分开。
- 本机适配入口：`tmp/install-astronvim-local.py`。
- 2026-11-09 安装完成时的环境：WSL2、Linux x86_64、glibc 2.34、GCC 10.3.1。
- 当次自检通过：Neovim 0.12.5、35 个插件、10 个已编译解析器，以及 GDB 17.2 / 私有 Python 3.9.9 / DAP 握手。
- 后续操作前，以 `astronvim/.installer/state.json` 和当前自检结果确认实际状态；历史记录不代表未来环境始终不变。

## 已遇到的问题与处理方式

### 下载时 TLS 连接失败

首次安装曾出现 `SSL_ERROR_SYSCALL`，GitHub 和多个依赖站点连接失败。同期 Windows 上有约 2.5 万个 `TIME_WAIT` 连接，并出现新建连接地址占用错误；这些是排查线索，未确定唯一根因。网络恢复后续装成功。

- 遇到同类错误时，先检查当前网络与 WSL 可访问的代理，再重试下载。
- Windows 本地代理地址不一定能从 WSL 访问，不要把历史代理地址当作固定配置。
- 保留已完成组件和通过校验的下载缓存，使用安装器续装。
- 保留 HTTPS 证书校验和下载 SHA256 校验，不通过关闭校验解决连接问题。

### 系统 Clang 返回错误的目标架构信息

本机 Clang 12.0.1 曾在指定 x86_64 目标时仍报告 ILP32 / 4 字节指针。这导致 OpenSSL 自动选择 `linux-x32`，编译时报缺少 `gnu/stubs-x32.h`；Rust bindgen 使用系统 libclang 时也报缺少 `gnu/stubs-32.h`。

- 先检查编译器实际返回的架构信息，不要直接安装 32 位头文件来掩盖误判。
- 本机适配脚本在安装器重置环境后，显式设置 `CC=/usr/bin/gcc`、`CXX=/usr/bin/g++`。只在外部 shell 设置这两个变量会被原安装器清除。
- bindgen 使用独立的 libclang 18.1.1，位置为：
  `astronvim/.installer/tools/libclang-18.1.1/libclang-18.1.1.data/platlib/clang/native`。
- 脚本设置 `LIBCLANG_PATH` 指向上述目录，并设置 `BINDGEN_EXTRA_CLANG_ARGS=-resource-dir=/usr/lib64/clang/12.0.1`。此资源路径依赖本机环境，换机器或升级系统后需重新检查。
- 独立库的下载地址、版本和 SHA256 记录在 `astronvim/.installer/local-build-overrides.json`。使用的 wheel SHA256 为 `c533091d8a3bbf7460a00cb6c1a71da93bffe148f172c7d03b1c31fbf8aa2a0b`。
- 独立 libclang 仅用于构建；当次已验证其 64 位类型布局和系统头文件解析。系统编译器未被替换，仓库源码及依赖锁定文件未修改。

### tree-sitter 预编译包与本机 glibc 不兼容

锁定的 tree-sitter 0.26.6 预编译包要求 `GLIBC_2.35` / `GLIBC_2.39`，本机只有 glibc 2.34。安装器已回退到同版本源码构建，并成功完成。

- 保留安装器的同版本源码回退机制，不为此升级系统 glibc 或跳过版本检查。
- 本机源码构建需要上面的 libclang 适配；出现 bindgen 架构错误时按该记录排查。

## 续装与验证

从本工作区根目录运行本机适配入口：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tmp/install-astronvim-local.py \
  --prefix /home/qiumc/data/programs/astronvim --jobs 4
```

该命令复用已完成组件；安装器对已完成安装直接返回，不覆盖用户配置。适配脚本不会自动下载独立 libclang：若安装到新目录或清理了 `.installer`，需按记录的地址和哈希准备构建库，并验证类型布局后再运行。

启动和自检：

```bash
source /home/qiumc/data/programs/astronvim/env.sh
astro-check
astronvim /你的项目目录
```

- 安装日志：`astronvim/.installer/logs/`。
- 阶段及错误记录：`astronvim/.installer/events.jsonl`。
- 可恢复状态：`astronvim/.installer/state.json`。
- 当次通过的自检日志：`astronvim/.installer/logs/20261109-130829-172389-00270-check.log`。
- 安装器使用锁定版本和补丁；维护时保留校验，不通过 `:Lazy update` 绕过它们。
- 本次验证范围是安装和上述自检，不代表全部交互功能、性能或其他平台均已验证。
