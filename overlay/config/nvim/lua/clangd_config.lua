-- Resolve the optional environment setting consistently for startup and LSP.
local M = {}

function M.database_dir(root)
  local path = vim.env.ASTRO_CLANGD_CDB_DIR
  if not path or path == "" then return nil end
  path = vim.fs.normalize(path)
  if path:sub(1, 1) ~= "/" then path = vim.fs.joinpath(root or vim.fn.getcwd(), path) end
  return vim.fs.normalize(path)
end

function M.command(base)
  if not M.database_dir(vim.fn.getcwd()) then return base end
  -- A relative setting must be resolved for each client, rather than when the
  -- plugin loads, so opening another project does not reuse the first path.
  return function(dispatchers, config)
    local command = vim.deepcopy(base)
    local directory = M.database_dir(config.root_dir)
    if directory then command[#command + 1] = "--compile-commands-dir=" .. directory end
    return vim.lsp.rpc.start(command, dispatchers, {
      cwd = config.cmd_cwd,
      env = config.cmd_env,
      detached = config.detached,
    })
  end
end

return M
