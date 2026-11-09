# AstroNvim 源码安装包

本包交付我们的配置、封装脚本、VS Code 扩展源码、增量补丁和使用文档。第三方程序、插件完整源码、编译目录、缓存、运行日志和旧验收现场不在压缩包中。Linux x86_64 和 aarch64 共用这一个源码包；安装器在目标机器上选择对应架构的依赖。

## 安装

首次安装需要联网，目标目录应为空。不要直接覆盖已有 AstroNvim 安装。

```bash
tar -xzf astronvim-source.tar.gz
cd astronvim-source
bash install.sh --prefix /home/yourname/programs/astronvim --jobs 2
source /home/yourname/programs/astronvim/env.sh
astronvim /path/to/project
```

`--prefix` 是完整安装目录，所有运行依赖和默认的下载、编译缓存均在其中。安装器不执行 sudo，不修改 `.bashrc`，不全局安装 Rust、Node 或编辑器插件。安装完成后仍须手动 `source env.sh`；`astro_deactivate` 恢复当前 shell 原有环境。

首次安装的 `--prefix` 路径不能含空格、制表符等空白字符，这是上游源码构建工具的限制，安装器会在下载和编译前检查。安装完成后可以搬到含空格的新路径，再 `source "<新路径>/env.sh"`，此搬迁方式已验证。

安装前提：Linux x86_64/aarch64、glibc ≥ 2.34、Python ≥ 3.8（标准库须含 ssl/lzma/bz2）、C/C++ 编译器及 libc 开发头文件、GNU make、m4、file、patch、Perl、pkg-config、binutils 和系统 CA 证书。建议 GCC ≥ 10。系统包管理器只用于准备这些基础工具；编辑器依赖版本由本包锁定，不从系统包管理器追踪最新版本。

Ubuntu/Debian 可准备 `build-essential python3 perl patch pkg-config binutils m4 file ca-certificates`；openEuler/RHEL 系可准备 `gcc gcc-c++ glibc-devel make python3 perl patch pkgconf-pkg-config binutils m4 file ca-certificates`。不同发行版的包名可能稍有差别。安装器先检查缺失工具并报出名称。若已有 curl，安装器优先使用它下载；否则使用 Python HTTPS，完成私有 curl 构建后自动使用私有版本。

首次构建 GDB、Python、Bear 和运行库需要时间与磁盘空间。ARM 上 clangd 22.1.6 没有对应的官方 Linux 二进制，必须编译 LLVM 中的 clangd。建议至少 8 GB 内存并准备交换空间、20 GB 可用磁盘；`--jobs 2` 限制编译并发，LLVM 链接固定为单任务。内存不足时应降低并发或增加交换空间，不要反复重试同一配置。

## 版本锁定和源码回退

[`dependencies.lock.json`](dependencies.lock.json) 记录固定版本、下载 URL 和 SHA256。下载后先校验，再解压、执行。校验失败立即报错，不会换另一个版本继续安装。

| 组件 | 固定版本 | 默认安装方式 |
| --- | --- | --- |
| Neovim | 0.12.5 | 对应架构二进制；不兼容时同版本源码构建 |
| clangd | 22.1.6 | x86 二进制；ARM 源码构建 |
| GDB / 私有 Python | 17.2 / 3.9.9 | 源码构建，启用 Python 和 DAP |
| CodeLLDB | 1.12.3 | 对应架构二进制；同版本源码回退配套 LLDB 22.1.8 |
| ripgrep / fd | 15.2.0 / 10.5.0 | 对应架构二进制；同版本源码回退 |
| Bear | 4.2.2 | 源码构建 |
| tree-sitter CLI | 0.26.6 | 二进制兼容性检查；不兼容时源码构建 |
| 构建工具 | CMake 3.31.8、Ninja 1.12.1、Rust 1.91.0 | 安装在 `.installer` 内；Node 22.14.0 仅用于 CodeLLDB 源码回退 |

插件由 [`plugins.lock.json`](plugins.lock.json) 固定到完整 Git commit；10 个解析器由 [`parsers.lock.json`](parsers.lock.json) 固定到完整 commit，使用该提交内的生成 C/C++ 源码编译，不重新生成语法。Rust 构建使用原版 `Cargo.lock` 和 `--locked`，CodeLLDB 的 npm 使用 `package-lock.json` 和 `npm ci`。Neovim 源码构建采用固定版本源码中自带的依赖 URL/哈希。没有 `latest` 或自动更新版本的逻辑。

对 6 个插件、Neovim loader 和 GDB DAP 的定制以 [`patches`](patches) 中的增量补丁交付。应用前检查原文件哈希，应用后检查修复文件哈希。包含最近的文件搜索修复：默认搜索隐藏和被 ignore 排除的项目文件，并排除 `.git` 和 clangd 索引缓存。

本包锁定下载的程序和源码依赖；宿主 C/C++ 编译器、glibc 和信任证书是安装边界。安装器记录它们的来源和版本，不承诺不同编译器生成的二进制逐字节一致。

## 查看计划、失败续装和日志

```bash
# 只查看目标架构的固定版本计划，不下载、不写入目标目录
bash install.sh --prefix /opt/astronvim --plan --architecture aarch64

# 失败后重复原命令，复用校验通过的下载和已完成组件
bash install.sh --prefix /home/yourname/programs/astronvim --jobs 2

# 有需要时强制验证指定组件的同版本源码构建路径
bash install.sh --prefix /home/yourname/programs/astro-source-test --from-source neovim,tree-sitter --jobs 2
```

默认缓存位置是 `<安装目录>/.installer/downloads`。可用 `--cache /path/to/shared-cache` 复用另一个目录中的已校验下载。构建日志在 `.installer/logs`，阶段与错误记录在 `.installer/events.jsonl`，可恢复状态在 `.installer/state.json`。构建期间每 15 秒显示当前命令的日志位置；失败会显示最后的错误输出，不把失败当成完成。

同一目录只能有一个安装进程。已安装目录如果来自另一版本锁定文件，不会被自动混合覆盖。升级应安装到新目录，验证后再切换；不要使用 `:Lazy update` 绕过锁定版本和补丁。

## 安装后搬迁

安装完成后的目录仍可离线复制到另一台同架构、兼容 glibc 的 Linux 主机：

```bash
source /path/to/astronvim/env.sh
astro-check
astro-pack /path/outside-installation/astronvim-linux-x86_64.tar.gz
```

`astro-pack` 生成的是包含依赖的离线完整包；本次交付的 `astronvim-source.tar.gz` 是联网安装的小包，两者用途不同。完整包排除 `.installer`、用户状态、缓存和日志。复制后重新 `source <新路径>/env.sh`，无需再次下载。x86 的已编译目录不能复制到 ARM；应在 ARM 上用同一个源码小包安装一次。

glibc ≥ 2.34 是本版最低要求，源码构建还受构建主机 glibc 限制：在较新 glibc 上构建的程序，不保证能在较旧 glibc 上运行。若需部署到多个系统，应在其中最旧的目标基线系统上安装/构建，再向更新的同架构系统复制。`installation-provenance.json` 和 `runtime-libraries.json` 记录安装方式与运行库来源。

## 使用文档与 VS Code

- [完整使用说明](overlay/README.md)
- [使用文档目录](overlay/docs/README.md)
- [编辑、复制粘贴和快捷键](overlay/docs/编辑区常用快捷键.md)
- [断点、条件断点、attach 和调试操作](overlay/docs/调试操作.md)
- [文件搜索与符号索引](overlay/docs/文件搜索与索引.md)
- [编译数据库目录配置](overlay/docs/clangd-cdb-env.md)
- [VS Code 终端快捷键扩展](overlay/vscode/README.md)

Windows 本地 VS Code 与 Linux SSH 终端是两端程序。安装器会从包内的扩展源码生成 `<安装目录>/vscode/astronvim-terminal-keys.vsix`。若需要 VS Code 转发被它抢占的快捷键，仍须在 **Windows 本地 VS Code** 安装这个扩展；Linux 安装器不能隔着普通 SSH 自动修改 Windows 客户端。扩展源码和使用说明均在本包中，版本保持 1.0.9。

`overlay/docs` 中的历史功能/性能验收文档说明原功能包的验证背景，不能代替本次源码安装器的验证结果。本次安装验收范围见 [验证记录](VALIDATION.md)；未进行 ARM 实机测试时不会标为已通过。

## 开发维护

```bash
python3 tests/test_installer.py
python3 build-package.py --output /path/to/astronvim-source.tar.gz
```

修改依赖版本需要同时更新下载地址、SHA256、插件提交和受影响补丁，并重新验证。构建工具不读取滚动的版本列表。交付构建脚本采用文件白名单，拒绝把 ELF、压缩的依赖、缓存或测试结果塞入源码小包。
