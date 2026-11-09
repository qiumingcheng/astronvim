local M = {}

-- Called after nvim-dap has resolved the process picker and launch.json values.
function M.enrich(config, done)
  if config.request ~= "attach" or vim.uv.os_uname().sysname ~= "Linux" then
    done(config)
    return
  end
  local result = vim.deepcopy(config)
  local signals = "SIGUSR2"
  local pid = tonumber(config.pid)
  local executable = pid and vim.uv.fs_readlink("/proc/" .. pid .. "/exe")
  -- openGauss also uses SIGUSR1 for internal notifications.
  if executable and vim.fs.basename(executable) == "gaussdb" then signals = "SIGUSR1 SIGUSR2" end
  local command = "process handle -p true -s false -n false " .. signals
  result.preRunCommands = result.preRunCommands or {}
  if not vim.tbl_contains(result.preRunCommands, command) then
    result.preRunCommands[#result.preRunCommands + 1] = command
  end
  -- Keep a running server running unless the user explicitly requests a stop.
  if result.stopOnEntry == nil then result.stopOnEntry = false end
  done(result)
end

return M
