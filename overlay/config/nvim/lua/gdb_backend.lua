-- Optional native GDB DAP adapter. ARM GCC TLS symbols require this backend.
local M = {}
function M.available()
  return vim.fn.executable(vim.env.ASTRONVIM_ROOT .. "/bin/gdb") == 1
end
function M.attach_type()
  return M.available() and "gdb" or "codelldb"
end
function M.setup(dap)
  if not M.available() then return end
  dap.adapters.gdb = function(done, config)
    local args = { "--interpreter=dap", "--quiet", "--nx",
      "-iex", "set pagination off", "-iex", "set debuginfod enabled off",
      "-iex", "set print elements 0" }
    -- GDB DAP defers launch/attach (including `file`) until configurationDone,
    -- after the client has sent its source breakpoints. Load the symbol file
    -- during GDB startup so those breakpoints can resolve immediately.
    local program = type(config.program) == "string" and config.program or nil
    local pid = tonumber(config.pid)
    if not program and config.request == "attach" and pid then
      program = vim.uv.fs_readlink("/proc/" .. pid .. "/exe")
      if program and program:match(" %(deleted%)$") then program = "/proc/" .. pid .. "/exe" end
    end
    if program and vim.fn.filereadable(program) == 1 then
      args[#args + 1] = "--se=" .. program
    end
    if config.request == "attach" then
      local signals = { "SIGUSR2" }
      local pid = tonumber(config.pid)
      local exe = pid and vim.uv.fs_readlink("/proc/" .. pid .. "/exe")
      if exe and vim.fs.basename(exe) == "gaussdb" then table.insert(signals, "SIGUSR1") end
      for _, signal in ipairs(signals) do
        vim.list_extend(args, { "-iex", "handle " .. signal .. " noprint nostop pass" })
      end
    end
    done { type = "executable", command = vim.env.ASTRONVIM_ROOT .. "/bin/gdb", args = args }
  end
  -- GDB reports an initial attach stop. Resume it only when the user did not
  -- explicitly request stopOnEntry; ordinary breakpoint/signal stops stay put.
  dap.listeners.after.event_stopped.portable_gdb_attach = function(session, event)
    if session.config.type ~= "gdb" or session.config.request ~= "attach"
      or session.config.stopOnEntry == true or event.reason ~= "attach" then return end
    -- nvim-dap resolves threads asynchronously after the stopped event.
    local attempts = 0
    local function resume_when_ready()
      if dap.session() ~= session then return end
      if session.stopped_thread_id then dap.continue(); return end
      attempts = attempts + 1
      if attempts < 100 then vim.defer_fn(resume_when_ready, 25) end
    end
    vim.schedule(resume_when_ready)
  end
  -- Native GDB sends inferior output as DAP events instead of runInTerminal.
  -- Keep program output in the same Console pane used by CodeLLDB.
  dap.listeners.after.event_initialized.portable_gdb_console = function(session)
    if session.config.type ~= "gdb" then return end
    require("debug_console").reset(session)
  end
  dap.defaults.gdb.on_output = function(session, body)
    if body.category == "stdout" or body.category == "stderr" then
      require("debug_console").append(session, body.output or "")
    elseif body.category ~= "telemetry" then
      require("dap.repl").append(body.output or "", "$", { newline = false })
    end
  end
end
return M
