# Bash: source /path/to/astronvim/env.sh
# Resolve this file's actual location each time; no installation path is hardcoded.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  printf '请用 source 加载本文件，而不是执行它。\n' >&2
  exit 1
fi
ASTRO_ENV_PACKAGE_FILE=$(readlink -f -- "${BASH_SOURCE[0]}")
ASTRO_ENV_PACKAGE_ROOT=$(cd -- "$(dirname -- "$ASTRO_ENV_PACKAGE_FILE")" && pwd -P)
ASTRO_ENV_PACKAGE_ARCH=$(cat -- "$ASTRO_ENV_PACKAGE_ROOT/platform-architecture" 2>/dev/null || true)
if [[ $ASTRO_ENV_PACKAGE_ARCH != x86_64 && $ASTRO_ENV_PACKAGE_ARCH != aarch64 ]]; then
  printf '安装包缺少有效的 platform-architecture；请重新解压完整包。\n' >&2
  unset ASTRO_ENV_PACKAGE_FILE ASTRO_ENV_PACKAGE_ROOT ASTRO_ENV_PACKAGE_ARCH
  return 1
fi
if [[ $(uname -s) != Linux || $(uname -m) != "$ASTRO_ENV_PACKAGE_ARCH" ]]; then
  printf '此包包含 Linux %s 二进制；当前系统为 %s %s，请使用对应架构的包。\n' "$ASTRO_ENV_PACKAGE_ARCH" "$(uname -s)" "$(uname -m)" >&2
  unset ASTRO_ENV_PACKAGE_FILE ASTRO_ENV_PACKAGE_ROOT ASTRO_ENV_PACKAGE_ARCH
  return 1
fi
ASTRO_LIBC_VERSION=$(getconf GNU_LIBC_VERSION 2>/dev/null || true)
ASTRO_LIBC_REQUIRED=$(cat -- "$ASTRO_ENV_PACKAGE_ROOT/minimum-glibc" 2>/dev/null || printf '2.34')
if [[ ! $ASTRO_LIBC_REQUIRED =~ ^([0-9]+)\.([0-9]+)$ ]]; then
  printf '安装目录中的 minimum-glibc 无效。\n' >&2
  unset ASTRO_LIBC_REQUIRED ASTRO_LIBC_VERSION ASTRO_ENV_PACKAGE_FILE ASTRO_ENV_PACKAGE_ROOT ASTRO_ENV_PACKAGE_ARCH
  return 1
fi
ASTRO_LIBC_REQUIRED_MAJOR=${BASH_REMATCH[1]}
ASTRO_LIBC_REQUIRED_MINOR=${BASH_REMATCH[2]}
if [[ ! $ASTRO_LIBC_VERSION =~ ^glibc\ ([0-9]+)\.([0-9]+)$ ]] || (( BASH_REMATCH[1] < ASTRO_LIBC_REQUIRED_MAJOR || (BASH_REMATCH[1] == ASTRO_LIBC_REQUIRED_MAJOR && BASH_REMATCH[2] < ASTRO_LIBC_REQUIRED_MINOR) )); then
  printf '此安装目录需要 glibc >= %s；当前为: %s。请在目标系统上使用源码安装器构建。\n' "$ASTRO_LIBC_REQUIRED" "${ASTRO_LIBC_VERSION:-unknown}" >&2
  unset ASTRO_LIBC_REQUIRED ASTRO_LIBC_REQUIRED_MAJOR ASTRO_LIBC_REQUIRED_MINOR ASTRO_LIBC_VERSION ASTRO_ENV_PACKAGE_FILE ASTRO_ENV_PACKAGE_ROOT ASTRO_ENV_PACKAGE_ARCH
  return 1
fi
unset ASTRO_LIBC_VERSION ASTRO_LIBC_REQUIRED ASTRO_LIBC_REQUIRED_MAJOR ASTRO_LIBC_REQUIRED_MINOR
if [[ ${ASTRONVIM_ENV_ACTIVE:-} == 1 ]] && declare -F astro_deactivate >/dev/null; then astro_deactivate; fi
ASTRONVIM_ENV_SNAPSHOT=$(declare -p PATH XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME TMPDIR NVIM_APPNAME VIMRUNTIME TERMINFO_DIRS LD_LIBRARY_PATH GIT_EXEC_PATH GIT_TEMPLATE_DIR GIT_SSL_CAINFO CURL_CA_BUNDLE ASTRO_CLANGD_JOBS ASTRO_CLANGD_CDB_DIR ASTRO_GDB_PYTHONHOME ASTRO_DAP_SHOW_ALL_THREADS TERMINFO ASTRO_TUI_COMPAT NVIM_NOTTYFAST 2>/dev/null || true)
export ASTRONVIM_ROOT="$ASTRO_ENV_PACKAGE_ROOT"
unset ASTRO_ENV_PACKAGE_FILE ASTRO_ENV_PACKAGE_ROOT ASTRO_ENV_PACKAGE_ARCH
# Use Neovim's official non-fast startup policy for SSH, unless already set.
# It avoids the synchronous background-color wait; other terminal queries remain.
# This package explicitly selects a dark theme and truecolor. To request fast
# detection again, run: unset NVIM_NOTTYFAST (after sourcing this file).
# Even an empty value or "0" counts as set to Neovim; preserve caller values.
if [[ ! ${NVIM_NOTTYFAST+x} && ( -n ${SSH_CONNECTION:-} || -n ${SSH_TTY:-} ) ]]; then
  export NVIM_NOTTYFAST=1
fi
# Keep GDB's embedded Python private; do not change the shell's PYTHONHOME.
export ASTRO_GDB_PYTHONHOME="$ASTRONVIM_ROOT/opt/python"
export NVIM_APPNAME=nvim
# clangd foreground/background workers. Four is a conservative default for 8 GB.
# Edit this value, then source env.sh and reopen AstroNvim to apply it.
export ASTRO_CLANGD_JOBS=4
# Optional compilation database directory. Relative paths use each project root.
# Empty keeps clangd's automatic discovery and project .clangd configuration.
# Example: export ASTRO_CLANGD_CDB_DIR="cmake-build-debug"
export ASTRO_CLANGD_CDB_DIR=${ASTRO_CLANGD_CDB_DIR:-}
# Show only the stopped and worker threads by default. Set to 1 before
# launching AstroNvim when auxiliary threads must also be visible.
export ASTRO_DAP_SHOW_ALL_THREADS=${ASTRO_DAP_SHOW_ALL_THREADS:-0}
# Optional: set to 1 only when the terminal uses a Nerd Font.
# export ASTRO_ICONS=1
export XDG_CONFIG_HOME="$ASTRONVIM_ROOT/config"
export XDG_DATA_HOME="$ASTRONVIM_ROOT/data"
export XDG_STATE_HOME="$ASTRONVIM_ROOT/state"
export XDG_CACHE_HOME="$ASTRONVIM_ROOT/cache"
export TMPDIR="$ASTRONVIM_ROOT/tmp"
export VIMRUNTIME="$ASTRONVIM_ROOT/opt/nvim/share/nvim/runtime"
export LD_LIBRARY_PATH="$ASTRONVIM_ROOT/opt/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GIT_EXEC_PATH="$ASTRONVIM_ROOT/opt/git/libexec"
export GIT_TEMPLATE_DIR="$ASTRONVIM_ROOT/opt/git/templates"
export GIT_SSL_CAINFO="$ASTRONVIM_ROOT/opt/certs/ca-bundle.crt"
export CURL_CA_BUNDLE="$ASTRONVIM_ROOT/opt/certs/ca-bundle.crt"
export TERMINFO_DIRS="$ASTRONVIM_ROOT/opt/terminfo:/etc/terminfo:/lib/terminfo:/usr/share/terminfo"
case ":$PATH:" in *":$ASTRONVIM_ROOT/bin:"*) ;; *) export PATH="$ASTRONVIM_ROOT/bin:$PATH" ;; esac
ASTRONVIM_ENV_ACTIVE=1
astro_deactivate() {
  unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME TMPDIR NVIM_APPNAME VIMRUNTIME TERMINFO_DIRS LD_LIBRARY_PATH GIT_EXEC_PATH GIT_TEMPLATE_DIR GIT_SSL_CAINFO CURL_CA_BUNDLE ASTRO_CLANGD_JOBS ASTRO_CLANGD_CDB_DIR ASTRO_GDB_PYTHONHOME ASTRO_DAP_SHOW_ALL_THREADS TERMINFO ASTRO_TUI_COMPAT NVIM_NOTTYFAST
  # 'declare -g' restores the original variables at shell scope, including export flags.
  eval "${ASTRONVIM_ENV_SNAPSHOT//declare /declare -g }"
  unset ASTRONVIM_ROOT ASTRONVIM_ENV_ACTIVE ASTRONVIM_ENV_SNAPSHOT
  unset -f astro_deactivate
  hash -r
}
hash -r

# BEGIN ASTRO_TUI_COMPAT
# Some SSH terminals advertise scroll margins but corrupt neighbouring panes.
# Paint changed cells instead of relying on terminal line-scroll operations.
# Set to 0 and source env.sh again to use the terminal's original capabilities.
export ASTRO_TUI_COMPAT=1
if [[ $ASTRO_TUI_COMPAT == 1 ]]; then
  export TERMINFO="$ASTRONVIM_ROOT/opt/terminfo-compat"
fi
# END ASTRO_TUI_COMPAT
