local p = require "portable"
local edit = require "editor_actions"
local function e(fn, desc) return { fn, desc = desc } end
local function pick(source, opts) return function() require("snacks").picker[source](opts) end end
local function conditional_breakpoint()
  vim.ui.input({ prompt = "Breakpoint condition: " }, function(condition)
    if condition and condition ~= "" then require("dap").set_breakpoint(condition) end
  end)
end
local function reload_launch()
  -- nvim-dap reads launch.json on every configuration selection. Importing it
  -- into dap.configurations as well duplicates entries and leaks old projects.
  local path = vim.fs.joinpath(vim.fn.getcwd(), ".vscode", "launch.json")
  local ok, configs = pcall(require("dap.ext.vscode").getconfigs, path)
  if not ok then
    vim.notify("读取调试配置失败：" .. tostring(configs), vim.log.levels.ERROR)
  elseif #configs == 0 then
    vim.notify("当前项目没有可用调试配置，请检查 " .. path, vim.log.levels.WARN)
  else
    vim.notify(("已读取 %d 项调试配置，下次启动自动使用当前文件。"):format(#configs), vim.log.levels.INFO)
  end
end
local common = {
  ["<RightMouse>"] = e(function() require("tree_mouse").route_menu() end, "File tree context menu"),
  ["<LeftMouse>"] = e(function() require("tree_mouse").route_click() end, "Mouse selection / folder expansion"),
  ["<2-LeftMouse>"] = e(function() require("tree_mouse").route_open() end, "Mouse open file"),
  ["<C-S-N>"] = e(p.files, "IDEA: Go to file"),
  ["<C-N>"] = e(p.workspace_symbols, "Go to symbol / class / function"),
  ["<M-C-S-N>"] = e(p.workspace_symbols, "IDEA: Go to symbol"),
  ["<C-F12>"] = e(p.symbols, "IDEA: File structure"),
  ["<C-S-F>"] = e(p.grep, "IDEA: Find in path"),
  ["<C-F>"] = e(p.lines, "IDEA: Find in file"),
  ["<C-S-A>"] = e(p.commands, "IDEA: Find action"),
  ["<C-E>"] = e(pick "recent", "IDEA: Recent files"),
  ["<M-1>"] = e(p.explorer, "IDEA: Project window"),
  ["<M-7>"] = e(function() vim.cmd "AerialToggle" end, "IDEA: Structure window"),
  ["<M-F12>"] = e(p.terminal, "IDEA: Terminal"),
  ["<C-B>"] = e(pick "lsp_definitions", "IDEA: Go to declaration / definition"),
  ["<C-LeftMouse>"] = e(function()
    -- Capture the buffer position before leaving Insert mode. stopinsert can
    -- move a horizontally scrolled view, changing what getmousepos resolves.
    local pos = vim.fn.getmousepos()
    if pos.winid == 0 or not vim.api.nvim_win_is_valid(pos.winid) then return end
    local buf = vim.api.nvim_win_get_buf(pos.winid)
    if vim.bo[buf].buftype ~= "" or pos.line < 1 then return end
    vim.cmd.stopinsert()
    vim.schedule(function()
      if not vim.api.nvim_win_is_valid(pos.winid) or vim.api.nvim_win_get_buf(pos.winid) ~= buf then return end
      vim.api.nvim_set_current_win(pos.winid)
      vim.api.nvim_win_set_cursor(pos.winid, { pos.line, math.max(0, pos.column - 1) })
      require("snacks").picker.lsp_definitions()
    end)
  end, "Go to definition at mouse"),
  ["<M-C-Left>"] = e(function() vim.cmd.normal { args = { tostring(vim.v.count1) .. vim.keycode("<C-o>") }, bang = true } end, "IDEA: Navigate back"),
  ["<M-C-Right>"] = e(function() vim.cmd.normal { args = { tostring(vim.v.count1) .. vim.keycode("<C-i>") }, bang = true } end, "IDEA: Navigate forward"),
  ["<M-C-B>"] = e(pick "lsp_implementations", "IDEA: Go to implementation"),
  ["<C-S-B>"] = e(pick "lsp_type_definitions", "IDEA: Go to type"),
  ["<M-F7>"] = e(pick "lsp_references", "IDEA: Find usages"),
  ["<S-F6>"] = e(vim.lsp.buf.rename, "IDEA: Rename"),
  ["<F18>"] = e(vim.lsp.buf.rename, "IDEA: Rename"),
  ["<M-C-L>"] = e(function() vim.lsp.buf.format { async = true } end, "IDEA: Reformat code"),
  ["<M-CR>"] = e(vim.lsp.buf.code_action, "IDEA: Context actions"),
  ["<C-P>"] = e(vim.lsp.buf.signature_help, "IDEA: Parameter info"),
  ["<C-Q>"] = e(vim.lsp.buf.hover, "IDEA: Quick documentation"),
  ["<C-S>"] = e(edit.save, "Save current file"),
  ["<C-S-S>"] = e(edit.save_all, "Save all files"),
  ["<C-F4>"] = e(function() require("astrocore.buffer").close() end, "IDEA: Close editor tab"),
  ["<C-G>"] = e(function()
    vim.ui.input({ prompt = "Go to line: " }, function(value)
      local line = tonumber(value)
      if line then vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(line, vim.api.nvim_buf_line_count(0))), 0 }) end
    end)
  end, "IDEA: Go to line"),
  ["<M-Right>"] = e(function() require("astrocore.buffer").nav(1) end, "IDEA: Next editor tab"),
  ["<M-Left>"] = e(function() require("astrocore.buffer").nav(-1) end, "IDEA: Previous editor tab"),
  ["<F2>"] = e(function() vim.diagnostic.jump { count = 1, float = true } end, "IDEA: Next problem"),
  ["<S-F2>"] = e(function() vim.diagnostic.jump { count = -1, float = true } end, "IDEA: Previous problem"),
  ["<S-F9>"] = e(p.debug "continue", "IDEA: Debug"),
  ["<F21>"] = e(p.debug "continue", "IDEA: Debug"),
  ["<F7>"] = e(p.debug "step_into", "IDEA: Step into"),
  ["<F8>"] = e(p.debug "step_over", "IDEA: Step over"),
  ["<F9>"] = e(p.debug "continue", "IDEA: Resume program"),
  ["<S-F8>"] = e(p.debug "step_out", "IDEA: Step out"),
  ["<F20>"] = e(p.debug "step_out", "IDEA: Step out"),
  ["<C-F8>"] = e(p.debug "toggle_breakpoint", "IDEA: Toggle breakpoint"),
  ["<F32>"] = e(p.debug "toggle_breakpoint", "IDEA: Toggle breakpoint"),
  ["<C-S-F8>"] = e(function() require("dapui").float_element "breakpoints" end, "IDEA: View breakpoints"),
  ["<M-F9>"] = e(p.debug "run_to_cursor", "IDEA: Run to cursor"),
  ["<M-F8>"] = e(function() require("dapui").eval(nil, { enter = true }) end, "IDEA: Evaluate expression"),
  ["<C-F2>"] = e(p.debug "terminate", "IDEA: Stop"),
  ["<F26>"] = e(p.debug "terminate", "IDEA: Stop"),
  ["<M-5>"] = e(function() require("dapui").toggle() end, "IDEA: Debug window"),
  ["<F1>"] = e(p.help, "Portable keymap help"),
}
-- Terminals report rapid repeated Ctrl+clicks as multi-click mouse keys.
-- Keep the navigation action consistent instead of falling back to Vim's
-- unmapped Ctrl+double/triple-click behavior.
for count = 2, 4 do common["<C-" .. count .. "-LeftMouse>"] = common["<C-LeftMouse>"] end
local normal = vim.deepcopy(common)
-- Remove conflicting AstroNvim / VS Code defaults; IDEA F7 is never a terminal key.
for _, key in ipairs { "<F5>", "<F6>", "<F10>", "<F11>", "<F17>", "<F23>", "<F29>" } do normal[key] = false end
normal["<C-C>"] = e(edit.copy, "Copy selection / current line")
normal["<C-V>"] = e(edit.paste, "Paste clipboard")
normal["<C-X>"] = e(edit.cut, "Cut selection / current line")
normal["<C-A>"] = e(edit.select_all, "Select all")
normal["<C-Z>"] = e(edit.undo, "Undo")
normal["<C-S-Z>"] = e(edit.redo, "Redo")
local visual = {
  ["<C-C>"] = e(edit.copy, "Copy selection"),
  ["<C-V>"] = e(edit.paste, "Replace selection from clipboard"),
  ["<C-X>"] = e(edit.cut, "Cut selection"),
  ["<C-A>"] = e(edit.select_all, "Select all"),
  ["<C-Z>"] = e(edit.undo, "Undo"),
  ["<C-S-Z>"] = e(edit.redo, "Redo"),
  ["<C-S>"] = common["<C-S>"],
  ["<C-S-S>"] = common["<C-S-S>"],
  ["<RightMouse>"] = common["<RightMouse>"],
}
local alternatives = {
  ["<Leader>ff"] = e(p.files, "Go to file"),
  ["<Leader>fw"] = e(p.grep, "Find in path"),
  ["<Leader>ss"] = e(p.symbols, "File symbols"),
  ["<Leader>sw"] = e(p.workspace_symbols, "Workspace symbols"),
  ["<Leader>sc"] = e(p.classes, "Classes and structs"),
  ["<Leader><Space>"] = e(p.everywhere, "Search menu"),
  ["<Leader>:"] = e(p.commands, "Find action"),
  ["<Leader>?"] = e(p.help, "Portable keymap help"),
  ["<Leader>db"] = e(p.debug "toggle_breakpoint", "Toggle breakpoint (C-F8)"),
  ["<Leader>dB"] = e(conditional_breakpoint, "Set conditional breakpoint"),
  ["<Leader>dc"] = e(p.debug "continue", "Start / resume (S-F9 / F9)"),
  ["<Leader>di"] = e(p.debug "step_into", "Step into (F7)"),
  ["<Leader>do"] = e(p.debug "step_over", "Step over (F8)"),
  ["<Leader>dO"] = e(p.debug "step_out", "Step out (S-F8)"),
  ["<Leader>dQ"] = e(p.debug "terminate", "Stop (C-F2)"),
  ["<Leader>de"] = e(function() require("dapui").eval() end, "Evaluate expression (A-F8)"),
  ["<Leader>dr"] = e(p.debug "restart", "Restart debug session"),
  ["<Leader>dR"] = e(function() require("repl_input").focus() end, "Focus debug console and enter input"),
  ["<Leader>dl"] = e(reload_launch, "Reload launch.json"),
  ["<Leader>da"] = e(function()
    require("dap").run { name = "Attach C/C++", type = require("gdb_backend").attach_type(), request = "attach", pid = require("dap.utils").pick_process, cwd = p.workspace() }
  end, "Attach to process"),
}
for key, mapping in pairs(alternatives) do normal[key] = mapping end
local insert = {}
for key, mapping in pairs(common) do
  local fn = mapping[1]
  insert[key] = e(function() vim.cmd.stopinsert(); vim.schedule(fn) end, mapping.desc)
end
-- These callbacks capture the click before stopping Insert mode themselves.
insert["<C-LeftMouse>"] = common["<C-LeftMouse>"]
for count = 2, 4 do insert["<C-" .. count .. "-LeftMouse>"] = common["<C-LeftMouse>"] end
insert["<C-C>"] = e(edit.copy, "Copy current line")
insert["<C-V>"] = e("<C-G>u<Cmd>lua require('editor_actions').paste()<CR>", "Paste clipboard")
insert["<C-X>"] = e("<C-G>u<Cmd>lua require('editor_actions').cut()<CR>", "Cut current line")
insert["<C-A>"] = e(function() vim.cmd.stopinsert(); vim.schedule(edit.select_all) end, "Select all")
insert["<C-Z>"] = e("<C-G>u<C-O>u", "Undo")
insert["<C-S-Z>"] = e("<C-G>u<C-O><C-R>", "Redo")
-- Preserve Insert mode for ordinary text clicks; stop it when entering tool windows.
insert["<LeftMouse>"] = e(function()
  if require("repl_input").click() then return end
  local pos = vim.fn.getmousepos()
  if require("debug_mouse").left_click() then return end
  if pos.winid ~= 0 and vim.api.nvim_win_is_valid(pos.winid)
    and vim.bo[vim.api.nvim_win_get_buf(pos.winid)].buftype == "" then
    vim.cmd.normal { args = { vim.keycode("<LeftMouse>") }, bang = true }
  else
    vim.cmd.stopinsert()
    vim.schedule(function() require("tree_mouse").route_click() end)
  end
end, "Mouse selection")
for _, key in ipairs { "<C-P>", "<C-Q>" } do insert[key] = common[key] end
insert["<C-S>"] = e("<C-G>u<Cmd>lua require('editor_actions').save()<CR>", "Save current file")
insert["<C-S-S>"] = e("<C-G>u<Cmd>lua require('editor_actions').save_all()<CR>", "Save all files")
-- Physical key spellings are canonical for the packaged Neovim version.
-- Keep Leader tokens literal so normal plugin merging and user overrides apply.
return {
  n = normal, i = insert,
  x = visual, s = visual,
  t = { ["<F7>"] = false, ["<M-F12>"] = e(p.terminal, "IDEA: Terminal") },
}
