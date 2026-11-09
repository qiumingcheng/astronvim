-- Real CodeLLDB attach tests against disposable processes, never a database.
local root = assert(vim.env.ASTRONVIM_ROOT)
local checks, outputs = {}, {}
local dap, child, child_done
local function check(name, condition, detail)
  checks[#checks + 1] = { name = name, passed = not not condition, detail = detail }
  assert(condition, name .. ": " .. vim.inspect(detail))
  print("PASS " .. name)
end
local function wait(name, condition)
  check(name, vim.wait(15000, condition, 30))
end
local function main()
  vim.o.lines, vim.o.columns = 55, 180
  dap = require "dap"
  check("fresh startup loads attach policy", type(dap.adapters.codelldb.enrich_config) == "function")
  local source = root .. "/scripts/test_support/attach-signals.c"
  vim.cmd.edit(source)
  local buf = vim.api.nvim_get_current_buf()
  for _, case in ipairs {
    { binary = "attach-signal-demo", adapter = "codelldb", signals = { 12 } },
    { binary = "gaussdb", adapter = "lldb", signals = { 10, 12 } },
  } do
    local received, stopped = "", {}
    child_done = false
    child = vim.system({ root .. "/tmp/attach-signals/" .. case.binary }, {
      stdout = function(_, chunk) if chunk then received = received .. chunk end end,
    }, function() child_done = true end)
    wait(case.binary .. " ready", function() return received:find("READY", 1, true) ~= nil end)
    local adapter_output = ""
    dap.listeners.after.event_output.signal_test = function(_, event)
      adapter_output = adapter_output .. (event.output or "")
    end
    dap.listeners.after.event_stopped.signal_test = function(_, event)
      stopped[#stopped + 1] = vim.deepcopy(event)
    end
    dap.run({ name = "Disposable signal test", type = case.adapter, request = "attach", pid = child.pid })
    wait(case.binary .. " attach", function() return dap.session() and dap.session().initialized end)
    vim.wait(300, function() return false end, 30)
    check(case.binary .. " automatically running", not dap.session().stopped_thread_id)
    for _, sig in ipairs(case.signals) do
      child:kill(sig)
      wait(case.binary .. " receives " .. sig, function() return received:find("RECEIVED " .. sig, 1, true) ~= nil end)
      check(case.binary .. " signal does not stop", not dap.session().stopped_thread_id and #stopped == 0)
    end
    check(case.binary .. " automatic signal command", adapter_output:find("SIGUSR2", 1, true) ~= nil, adapter_output)
    outputs[#outputs + 1] = { binary = case.binary, pid = child.pid, policy_output = adapter_output }
    vim.cmd.buffer(buf)
    vim.api.nvim_win_set_cursor(0, { 9, 0 })
    vim.fn.maparg("<C-F8>", "n", false, true).callback()
    vim.wait(200, function() return false end, 30)
    child:kill(12)
    wait(case.binary .. " source breakpoint", function()
      local s = dap.session()
      return s and s.stopped_thread_id and s.current_frame and s.current_frame.line == 9
    end)
    check(case.binary .. " breakpoint still works", stopped[#stopped].reason == "breakpoint", stopped[#stopped])
    dap.clear_breakpoints()
    dap.continue()
    dap.disconnect({ terminateDebuggee = false })
    wait(case.binary .. " detached", function() return dap.session() == nil end)
    check(case.binary .. " survives detach", not child_done)
    child:kill(15)
    wait(case.binary .. " test process cleaned up", function() return child_done end)
    child = nil
  end
end
local ok, err = xpcall(main, debug.traceback)
if dap and dap.session() then
  pcall(dap.disconnect, { terminateDebuggee = false })
  vim.wait(5000, function() return dap.session() == nil end, 30)
end
if child and not child_done then child:kill(15) end
vim.fn.writefile({ vim.json.encode({ passed = ok, checks = checks, outputs = outputs, error = err }) }, root .. "/logs/attach-signals.json")
if ok then print("ATTACH_SIGNAL_CHECKS_PASSED"); vim.cmd "qa!"
else print(err); vim.cmd "cquit 1" end
