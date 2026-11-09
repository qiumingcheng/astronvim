local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("portable_activity_bar")
local tabs, pending, exiting = {}, false, false
local rows = { [2] = "explorer", [3] = "explorer", [5] = "search", [7] = "debug", [8] = "debug" }
local lines = { "", "  资源", "  管理", "", "  搜索", "", "  运行", "  调试", "" }

local function state()
  local tab = api.nvim_get_current_tabpage()
  tabs[tab] = tabs[tab] or { active = "explorer" }
  return tabs[tab]
end

local function valid(win) return win and api.nvim_win_is_valid(win) end

local function scratch(ft, text)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = ft
  api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
  return buf
end

local function style(win, title, options)
  local fixed_width = not (options and options.fixed_width == false)
  for key, value in pairs({ number = false, relativenumber = false, signcolumn = "no",
    statuscolumn = "", foldcolumn = "0", wrap = false, spell = false, list = false,
    cursorline = false, cursorcolumn = false, colorcolumn = "", winfixwidth = fixed_width,
    winfixbuf = true, scrolloff = 0, winbar = title or "", fillchars = "eob: " }) do
    vim.wo[win][key] = value
  end
  -- New splits can inherit the editor's horizontal view. Toolbar text starts
  -- at column zero even when the source window is scrolled far to the right.
  api.nvim_win_call(win, function() vim.fn.winrestview({ topline = 1, leftcol = 0 }) end)
end

local function focus_editor()
  local s = state()
  if valid(s.editor) and api.nvim_win_get_tabpage(s.editor) == api.nvim_get_current_tabpage()
    and vim.bo[api.nvim_win_get_buf(s.editor)].buftype == "" then
    api.nvim_set_current_win(s.editor)
    return
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == "" and vim.bo[api.nvim_win_get_buf(win)].buftype == "" then
      s.editor = win
      api.nvim_set_current_win(win)
      return
    end
  end
  local buf = api.nvim_create_buf(true, false)
  s.editor = api.nvim_open_win(buf, true, { split = "right", win = -1 })
end

-- File-tab callbacks must target the last editor, even when a DAP/tree/prompt
-- pane currently has focus and forces its own buffer back into that pane.
M.focus_editor = focus_editor

local function paint()
  local s = state()
  if not s.buf or not api.nvim_buf_is_valid(s.buf) then return end
  if s.painted_buf == s.buf and s.painted_active == s.active then return end
  s.painted_buf, s.painted_active = s.buf, s.active
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for line, action in pairs(rows) do
    if action == s.active then
      api.nvim_buf_set_extmark(s.buf, ns, line - 1, 0, {
        line_hl_group = "PortableActivitySelected",
        virt_text = { { "▏", "PortableActivityAccent" } }, virt_text_pos = "overlay",
      })
    end
  end
end

function M.ensure()
  if exiting or vim.v.exiting ~= vim.NIL or #api.nvim_list_uis() == 0 then return end
  local s = state()
  if not valid(s.win) then
    s.buf = scratch("astro_activity_bar", lines)
    s.win = api.nvim_open_win(s.buf, false, { split = "left", win = -1, width = 8 })
    style(s.win)
    vim.wo[s.win].winhighlight = "Normal:PortableActivity,NormalNC:PortableActivity,EndOfBuffer:PortableActivity"
    vim.keymap.set("n", "<CR>", function() M.select(rows[api.nvim_win_get_cursor(s.win)[1]]) end, { buffer = s.buf })
    vim.keymap.set("n", "<Esc>", focus_editor, { buffer = s.buf })
  end
  -- Neo-tree and DAP create their own topleft splits. Keep this rail outside them.
  local layout = vim.fn.winlayout()
  -- A panel close can temporarily leave only the rail. Neovim cannot move its
  -- last non-floating window; recreate the empty editor before restoring width.
  if layout[1] == "leaf" and layout[2] == s.win then
    focus_editor()
    layout = vim.fn.winlayout()
  end
  if layout[1] ~= "row" or layout[2][1][1] ~= "leaf" or layout[2][1][2] ~= s.win then
    local widths = {}
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
      if win ~= s.win and api.nvim_win_get_config(win).relative == "" then
        local ft = vim.bo[api.nvim_win_get_buf(win)].filetype
        if vim.wo[win].winfixwidth or ft == "astro_run_debug" or ft:match("^dapui_") then
          widths[win] = api.nvim_win_get_width(win)
        end
      end
    end
    api.nvim_win_set_config(s.win, { split = "left", win = -1, width = 8 })
    -- Moving a split can equalize it. Restore the rail first: shrinking it
    -- after the panels would give the released columns to the debug sidebar.
    if api.nvim_win_get_width(s.win) ~= 8 then api.nvim_win_set_width(s.win, 8) end
    for win, width in pairs(widths) do
      if valid(win) and api.nvim_win_get_width(win) ~= width then api.nvim_win_set_width(win, width) end
    end
    -- DAP splits were sized before the rail moved outside them. Preserve
    -- their saved layout ratios, including the REPL/Console pair; restoring
    -- only the Console width can leave the REPL squeezed to a few columns.
    local windows = package.loaded["dapui.windows"]
    if windows then
      for _, dap_layout in ipairs(windows.layouts or {}) do
        if dap_layout:is_open() then dap_layout:resize() end
      end
    end
  end
  if api.nvim_win_get_width(s.win) ~= 8 then api.nvim_win_set_width(s.win, 8) end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[api.nvim_win_get_buf(win)].filetype
    if ft == "neo-tree" then s.active = "explorer"
    elseif ft == "astro_run_debug" or ft == "dapui_scopes" then s.active = "debug"; break end
  end
  paint()
end

function M.queue()
  if pending or exiting then return end
  pending = true
  vim.schedule(function()
    pending = false
    M.ensure()
  end)
end

local function close_panel()
  local s = state()
  if valid(s.panel) then api.nvim_win_close(s.panel, true) end
  s.panel = nil
end

local function close_picker()
  local s = state()
  if s.picker then s.picker:close(); s.picker = nil end
end

local function debug_ui()
  close_panel()
  focus_editor()
  require("dapui").open()
  M.queue()
end

local debug_actions = {
  [3] = function()
    focus_editor()
    if vim.bo.filetype == "" and not require("dap").session() then
      vim.notify("请先打开待调试的源码文件，再启动调试。", vim.log.levels.WARN)
      return
    end
    require("dap").continue()
  end,
  [5] = function()
    focus_editor()
    require("dap").run({ name = "Attach C/C++", type = require("gdb_backend").attach_type(), request = "attach",
      pid = require("dap.utils").pick_process, cwd = vim.fn.getcwd() })
  end,
  [7] = function()
    if vim.fn.filereadable(vim.fn.getcwd() .. "/.vscode/launch.json") == 0 then
      vim.notify("当前项目没有 .vscode/launch.json", vim.log.levels.WARN)
      return
    end
    local ok, configs = pcall(require("dap.ext.vscode").getconfigs)
    if not ok then vim.notify(tostring(configs), vim.log.levels.ERROR); return end
    -- nvim-dap reads this file on every launch; avoid the deprecated API that
    -- permanently copies project configurations into global filetype lists.
    vim.notify("已读取 " .. #configs .. " 项调试配置；启动时自动加载。")
  end,
  [9] = debug_ui,
}

local function watch_debug()
  local dap = require("dap")
  if dap.listeners.after.event_initialized.portable_activity_bar then return end
  dap.listeners.after.event_initialized.portable_activity_bar = function()
    close_panel()
    state().active = "debug"
    M.queue()
  end
  local function finished()
    vim.schedule(function() if not exiting then M.select("explorer") end end)
  end
  dap.listeners.after.event_terminated.portable_activity_bar = finished
  dap.listeners.after.event_exited.portable_activity_bar = finished
  dap.listeners.after.disconnect.portable_activity_bar = finished
end

local function debug_panel()
  require("dapui")
  watch_debug()
  if require("dap").session() then debug_ui(); return end
  local s = state()
  local buf = scratch("astro_run_debug", {
    "", "  运行与调试", "  [>] 启动 / 继续调试", "", "  [+] 附加到进程", "",
    "  [L] 加载 launch.json", "", "  [=] 显示调试面板", "", "  先打开源码，再启动调试。",
    "  Shift+F9 启动   F9 继续", "  F7 步入        F8 步过", "  Ctrl+F2 停止",
  })
  s.panel = api.nvim_open_win(buf, false, { split = "left", win = -1, width = 36 })
  style(s.panel, " 运行与调试 / Run and Debug", { fixed_width = false })
  for line in pairs(debug_actions) do
    api.nvim_buf_set_extmark(buf, ns, line - 1, 0, { line_hl_group = "PortableActivityAction" })
  end
  vim.keymap.set("n", "<CR>", function()
    local action = debug_actions[api.nvim_win_get_cursor(s.panel)[1]]
    if action then action() end
  end, { buffer = buf })
end

function M.select(action)
  if not action then return end
  local s, tab = state(), api.nvim_get_current_tabpage()
  s.selection = (s.selection or 0) + 1
  local selection = s.selection
  vim.cmd.stopinsert()
  focus_editor()
  close_picker()
  -- Snacks closes its split on the next event-loop turn. Creating a panel
  -- before that close lets Neovim redistribute the new panel's width again.
  vim.schedule(function()
    if exiting or s.selection ~= selection or api.nvim_get_current_tabpage() ~= tab then return end
    close_panel()
    if package.loaded.dapui then require("dapui").close() end
    vim.cmd("Neotree close")
    s.active = action
    if action == "explorer" then
      vim.cmd("Neotree show position=left")
    elseif action == "search" then
      s.picker = require("project_search").open()
    elseif action == "debug" then
      debug_panel()
    end
    M.queue()
  end)
end

-- Called before the existing click handlers: regular editor, tree and DAP
-- clicks retain their original behavior, including breakpoints and selection.
function M.mouse()
  if require("project_search").mouse(state().picker) then return true end
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or not valid(pos.winid) then return false end
  local ft = vim.bo[api.nvim_win_get_buf(pos.winid)].filetype
  local action
  if ft == "astro_activity_bar" then
    local target = rows[pos.line]
    action = target and function() M.select(target) end
  elseif ft == "astro_run_debug" then
    action = debug_actions[pos.line]
  else
    return false
  end
  if action then
    vim.cmd.stopinsert()
    vim.schedule(action)
  end
  return true
end

local function colors()
  api.nvim_set_hl(0, "PortableActivity", { fg = "#bdbdbd", bg = "#333333" })
  api.nvim_set_hl(0, "PortableActivitySelected", { fg = "#ffffff", bg = "#094771", bold = true })
  api.nvim_set_hl(0, "PortableActivityAccent", { fg = "#4fc1ff", bg = "#094771" })
  api.nvim_set_hl(0, "PortableActivityAction", { fg = "#4fc1ff", bold = true })
end

function M.setup()
  colors()
  local group = api.nvim_create_augroup("PortableActivityBar", { clear = true })
  api.nvim_create_autocmd({ "WinNew", "WinClosed", "TabEnter", "VimResized", "BufWinEnter" }, { group = group, callback = M.queue })
  api.nvim_create_autocmd("WinEnter", { group = group, callback = function()
    if vim.bo.buftype == "" and api.nvim_win_get_config(0).relative == "" then state().editor = api.nvim_get_current_win() end
  end })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = colors })
  api.nvim_create_autocmd("ExitPre", { group = group, callback = function() exiting = true end })
  api.nvim_create_autocmd("SafeState", { group = group, callback = function()
    if exiting and vim.v.exiting == vim.NIL then exiting = false end
  end })
  M.queue()
end

return M
