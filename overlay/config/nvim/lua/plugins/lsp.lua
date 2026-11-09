local jobs = tonumber(vim.env.ASTRO_CLANGD_JOBS) or 4
if jobs < 1 or jobs % 1 ~= 0 then jobs = 4 end
local cpus = vim.uv.available_parallelism and vim.uv.available_parallelism() or #vim.uv.cpu_info()
jobs = math.min(jobs, math.max(1, cpus))
local clangd = {
  cmd = require("clangd_config").command {
    vim.env.ASTRONVIM_ROOT .. "/bin/clangd", "--background-index", "--clang-tidy",
    "--completion-style=detailed", "--header-insertion=never", "-j=" .. jobs, "--pch-storage=memory",
  },
  before_init = function(params)
    -- Both bundled clangd builds support standard LSP positionEncodings.
    -- Drop the legacy lspconfig extension after capability merging, otherwise
    -- clangd emits an error-level deprecation message at every connection.
    params.capabilities.offsetEncoding = nil
  end,
}
if vim.env.ASTRO_CLANGD_CDB_DIR and vim.env.ASTRO_CLANGD_CDB_DIR ~= "" then
  -- CMake sources may have neither a root-level database nor a .clangd file.
  -- Equal-priority markers choose the nearest project root for relative paths.
  clangd.root_markers = { {
    ".clangd", ".clang-tidy", ".clang-format", "compile_commands.json", "compile_flags.txt",
    "configure.ac", ".git", "CMakeLists.txt", "GNUmakefile", "Makefile",
  } }
end

return {
  {
    "AstroNvim/astrolsp",
    init = function() require("lsp_buffer_guard").setup() end,
    opts = {
      servers = { "clangd" },
      formatting = { format_on_save = { enabled = false } },
      config = {
        clangd = clangd,
      },
    },
  },
}
