-- Include service accounts and processes without a controlling terminal.
local M = {}
local installed = false

function M.setup()
  if installed or vim.uv.os_uname().sysname ~= "Linux" then return end
  installed = true
  local utils = require "dap.utils"
  local pick_process = utils.pick_process
  utils.get_processes = function(opts)
    opts = opts or {}
    local output = vim.fn.system { "ps", "-e", "-o", "pid=,user=,args=" }
    if vim.v.shell_error ~= 0 then
      vim.notify("无法读取进程列表: " .. output, vim.log.levels.ERROR)
      return {}
    end
    local filter = opts.filter
    if filter and type(filter) ~= "string" and type(filter) ~= "function" then
      error "opts.filter must be a string or a function"
    end
    local procs = {}
    for line in output:gmatch("[^\n]+") do
      local pid, user, name = line:match("^%s*(%d+)%s+(%S+)%s+(.+)$")
      pid = tonumber(pid)
      if pid and pid ~= vim.fn.getpid() then
        local proc = { pid = pid, user = user, name = name }
        if not filter or (type(filter) == "string" and name:find(filter))
          or (type(filter) == "function" and filter(proc)) then
          procs[#procs + 1] = proc
        end
      end
    end
    table.sort(procs, function(a, b) return a.pid < b.pid end)
    return procs
  end
  utils.pick_process = function(opts)
    opts = vim.tbl_extend("keep", opts or {}, {
      prompt = "Attach: PID / 用户 / 进程（全部用户）",
      label = function(proc)
        return string.format("%d  [%s]  %s", proc.pid, proc.user or "?", proc.name)
      end,
    })
    return pick_process(opts)
  end
end

return M
