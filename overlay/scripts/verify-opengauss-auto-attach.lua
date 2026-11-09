-- Explicit live-instance check. Set vim.g.astro_verify_pid before running.
local root = assert(vim.env.ASTRONVIM_ROOT)
local pid = assert(tonumber(vim.g.astro_verify_pid), "Specify the current database PID")
local install = "/home/qiumc/data/code/cpp/openGauss-server/mppdb_temp_install"
local dap, checks, stopped, output = nil, {}, {}, ""
local function check(name, condition, detail)
  checks[#checks + 1] = { name = name, passed = not not condition, detail = detail }
  assert(condition, name .. ": " .. vim.inspect(detail))
  print("PASS " .. name)
end
local function wait(name, condition, ms)
  check(name, vim.wait(ms or 15000, condition, 30))
end
local function status()
  return table.concat(vim.fn.readfile("/proc/" .. pid .. "/status"), "\n")
end
local function main()
  vim.o.lines, vim.o.columns = 55, 180
  check("target is actual database", vim.uv.fs_readlink("/proc/" .. pid .. "/exe") == install .. "/bin/gaussdb")
  check("target is not already being debugged", status():match("TracerPid:%s+0\n") ~= nil)
  dap = require "dap"
  dap.listeners.after.event_stopped.auto_signal_test = function(_, event) stopped[#stopped + 1] = vim.deepcopy(event) end
  dap.listeners.after.event_output.auto_signal_test = function(_, event) output = output .. (event.output or "") end
  -- No signal commands or stopOnEntry option here: the adapter must add them.
  dap.run({ name = "Verify automatic openGauss attach", type = "codelldb", request = "attach", pid = pid })
  wait("attach initialized", function() return dap.session() and dap.session().initialized end, 60000)
  vim.wait(500, function() return false end, 50)
  check("signal policy added automatically", vim.tbl_contains(dap.session().config.preRunCommands, "process handle -p true -s false -n false SIGUSR1 SIGUSR2"))
  check("database runs after attach", not dap.session().stopped_thread_id and #stopped == 0)
  for attempt = 1, 3 do
    local response
    vim.system({ install .. "/bin/gsql", "-X", "-h", "/tmp", "-p", "55440", "-U", "qiumc", "-d", "postgres", "-c", "SELECT 1 + 2 AS astro_debug_result;" }, {
      text = true, timeout = 10000, env = { LD_LIBRARY_PATH = install .. "/lib" },
    }, function(result) response = result end)
    wait("gsql connection " .. attempt .. " completes", function() return response ~= nil end)
    check("SQL " .. attempt .. " returns 3", response.code == 0 and response.stdout:match("\n%s+3%s*\n") ~= nil, response)
    check("connection " .. attempt .. " has no signal stop", #stopped == 0 and not dap.session().stopped_thread_id)
  end
  check("SIGUSR1 policy reported", output:match("SIGUSR1%s+true%s+false%s+false") ~= nil)
  check("SIGUSR2 policy reported", output:match("SIGUSR2%s+true%s+false%s+false") ~= nil)
  dap.disconnect({ terminateDebuggee = false })
  wait("detached", function() return dap.session() == nil end)
  check("database alive and detached", status():match("TracerPid:%s+0\n") ~= nil)
end
local ok, err = xpcall(main, debug.traceback)
if dap and dap.session() then
  pcall(dap.disconnect, { terminateDebuggee = false })
  vim.wait(10000, function() return dap.session() == nil end, 30)
end
vim.fn.writefile({ vim.json.encode({ passed = ok, pid = pid, timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"), checks = checks, stopped_events = stopped, output = output, error = err }) }, root .. "/logs/opengauss-auto-attach.json")
if ok then print("OPENGAUSS_AUTO_ATTACH_PASSED"); vim.cmd "qa!"
else print(err); vim.cmd "cquit 1" end
