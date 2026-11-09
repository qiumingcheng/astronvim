local root = assert(vim.env.ASTRONVIM_ROOT)
local checks = {}
local function check(name, condition, detail)
  assert(condition, name .. ": " .. vim.inspect(detail))
  checks[#checks + 1] = { name = name, passed = true, detail = type(detail) == "table" and vim.inspect(detail) or detail }
  print("PASS " .. name)
end
local function wait(name, fn, timeout)
  check(name, vim.wait(timeout or 15000, fn, 30), "timed asynchronous integration check")
end
local function main()
  vim.o.lines = 55
  vim.o.columns = 180
  vim.cmd.cd(root .. "/examples/cpp")
  vim.cmd.edit "main.cpp"
  check("portable config", vim.fn.stdpath("config") == root .. "/config/nvim")
  for _, name in ipairs { "rg", "fd", "clangd", "codelldb", "git", "tree-sitter" } do
    check("bundled " .. name, vim.fn.exepath(name):find(root, 1, true) == 1, vim.fn.exepath(name))
  end
  for key, desc in pairs {
    ["<C-S-n>"] = "IDEA: Go to file", ["<C-b>"] = "IDEA: Go to declaration / definition",
    ["<F7>"] = "IDEA: Step into", ["<F8>"] = "IDEA: Step over", ["<F9>"] = "IDEA: Resume program",
    ["<C-F8>"] = "IDEA: Toggle breakpoint", ["<M-F12>"] = "IDEA: Terminal",
  } do check("key " .. key, vim.fn.maparg(key, "n", false, true).desc == desc) end
  check("offline parser policy", not require("astrocore").config.treesitter.auto_install and #require("astrocore").config.treesitter.ensure_installed == 0)
  local parser = vim.treesitter.get_parser(0, "cpp")
  check("C++ syntax parser", parser and #parser:parse() > 0)
  local client
  wait("clangd attach", function()
    client = vim.lsp.get_clients({ name = "clangd", bufnr = 0 })[1]
    return client and client.initialized
  end, 30000)
  local uri = vim.uri_from_bufnr(0)
  local symbols = client:request_sync("textDocument/documentSymbol", { textDocument = { uri = uri } }, 15000, 0)
  check("file symbols", symbols and symbols.result and #symbols.result >= 2, symbols and symbols.result)
  local workspace = client:request_sync("workspace/symbol", { query = "add" }, 15000, 0)
  check("workspace symbols", workspace and workspace.result and #workspace.result > 0)
  local definition = client:request_sync("textDocument/definition", { textDocument = { uri = uri }, position = { line = 8, character = 18 } }, 10000, 0)
  check("go to definition", definition and definition.result and #definition.result > 0)
  local files = require("snacks").picker.files { cwd = vim.fn.getcwd(), pattern = "main" }
  wait("file picker results", function() return #files:items() > 0 end)
  check("file picker main.cpp", vim.tbl_contains(vim.tbl_map(function(i) return i.file end, files:items()), "main.cpp"))
  files:close()
  local grep = require("snacks").picker.grep { cwd = vim.fn.getcwd(), search = "answer", live = false }
  wait("keyword picker results", function() return #grep:items() >= 2 end)
  grep:close()
  local dap = require "dap"
  vim.cmd.edit "main.cpp"
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  dap.toggle_breakpoint()
  require("dap.ext.vscode").load_launchjs(nil, { lldb = { "cpp", "c" } })
  local launch
  for _, cfg in ipairs(dap.configurations.cpp) do if cfg.name == "Demo: C++ launch" then launch = cfg end end
  check("launch.json load", launch ~= nil)
  dap.run(launch)
  wait("debug breakpoint hit", function() return dap.session() and dap.session().stopped_thread_id ~= nil end, 20000)
  local session = dap.session()
  wait("debug stack frame", function() return session.current_frame ~= nil end)
  check("breakpoint source line", session.current_frame.line == 4, session.current_frame)
  local result, failure
  session:request("evaluate", { expression = "a + b", frameId = session.current_frame.id, context = "watch" }, function(err, response) failure = err; result = response end)
  wait("debug evaluate", function() return result ~= nil or failure ~= nil end)
  check("debug variables = 42", not failure and result.result == "42", result)
  dap.step_over()
  wait("debug step over", function() return session.current_frame and session.current_frame.line == 5 end)
  dap.continue()
  wait("debug program exited", function() return dap.session() == nil end)
  check("debug UI loaded", package.loaded.dapui ~= nil)
  vim.fn.writefile({ vim.json.encode({ passed = true, checks = checks }) }, root .. "/logs/verification.json")
  print("ALL_INTEGRATION_CHECKS_PASSED")
end
local ok, err = xpcall(main, debug.traceback)
if not ok then
  vim.fn.writefile({ vim.json.encode({ passed = false, checks = checks, error = err }) }, root .. "/logs/verification.json")
  print(err)
  vim.cmd "cquit 1"
else
  vim.cmd "qa!"
end
