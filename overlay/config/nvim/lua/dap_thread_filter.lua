-- DAP Stacks 默认显示的线程名称。
-- 修改后重新启动 AstroNvim 即可生效，不需要重新编译或重建索引。
-- 名称按不区分大小写的完整名称匹配。
return {
  names = {
    "worker",
    "TPLworker",
    "TPLstream",
    "streamworker",
    "gaussdb",
  },

  -- 可按需增加 Lua 模式，例如 "^worker[%s%-%._]"。
  -- 默认不启用模式，避免把 openGauss 的后台 *worker 线程混入来。
  patterns = {},
}
