local M = {}
M.root = assert(vim.env.ASTRONVIM_ROOT)
function M.workspace() return vim.fn.getcwd() end
function M.files()
  require("activity_bar").focus_editor()
  require("snacks").picker.files { cwd = M.workspace(), hidden = true }
end
function M.lines()
  require("activity_bar").focus_editor()
  require("snacks").picker.lines()
end
-- Mouse mappings are resolved in the focused input buffer, even when clicking
-- the result list. Route by the clicked window and row before other pane maps.
function M.picker_mouse(key)
  if key ~= "<LeftMouse>" and key ~= "<2-LeftMouse>" then return false end
  local snacks = package.loaded["snacks"]
  if not snacks then return false end
  local pos = vim.fn.getmousepos()
  for _, picker in ipairs(snacks.picker.get()) do
    if picker.list.win.win == pos.winid and pos.line > 0 then
      local open_on_click = picker.opts.source == "files" or picker.opts.source == "lines" or picker.opts.source == "recent"
      if key == "<LeftMouse>" and not open_on_click then
        -- Keep the native press ahead of its release. The generic Insert-mode
        -- tool-window click schedules its press; a fast release can overtake
        -- it and leave a Visual selection active in the next picker.
        vim.api.nvim_feedkeys(vim.keycode(key), "ni", false)
      else
        local index = picker.list:row2idx(pos.line)
        if index >= 1 and index <= picker.list:count() then
          picker.list:move(index, true, true)
          picker:action("confirm")
        end
      end
      return true
    end
  end
  return false
end
function M.grep() require("snacks").picker.grep { cwd = M.workspace(), hidden = true } end
function M.symbols() require("snacks").picker.lsp_symbols() end
function M.workspace_symbols()
  return require("workspace_lsp").pick()
end
function M.classes()
  return require("workspace_lsp").pick({ "Class", "Struct", "Interface", "Enum", "TypeParameter" })
end
function M.everywhere()
  local actions = {
    { "Files", M.files }, { "Workspace symbols", M.workspace_symbols },
    { "File symbols", M.symbols }, { "Workspace text", M.grep },
    { "Actions", M.commands },
    { "Recent files", function() require("snacks").picker.recent() end },
  }
  vim.ui.select(actions, { prompt = "Search", format_item = function(item) return item[1] end }, function(item) if item then item[2]() end end)
end
function M.commands() require("snacks").picker.commands() end
function M.explorer() vim.cmd "Neotree toggle position=left" end
function M.terminal() vim.cmd "ToggleTerm direction=horizontal" end
function M.debug(action) return function() require("dap")[action]() end end
function M.help()
  local lines = {
    "AstroNvim Portable — IntelliJ IDEA (Linux) keys", "",
    "Ctrl+Shift+N   Files                Space f f   Files",
    "Ctrl+Shift+F   Workspace text       Space f w   Workspace text",
    "Ctrl+F12       File symbols         Space s s   File symbols",
    "Ctrl+Alt+Shift+N Workspace symbols  Space s w   Workspace symbols",
    "Ctrl+N         Workspace symbols   Space s c   Classes/structs",
    "Symbol search: subquery planner also finds subquery_planner",
    "Ctrl+Shift+A   Actions              Space :     Actions",
    "Ctrl+F         Current file text    Space f l   Current file text",
    "Alt+1          Explorer             Space e     Explorer",
    "Alt+F12        Bottom terminal      Space t h   Bottom terminal",
    "Ctrl+C copy   Ctrl+V paste   Ctrl+X cut   Ctrl+A select all",
    "Ctrl+Z undo   Ctrl+Shift+Z redo (no shell suspend)",
    "Ctrl+S save file   Ctrl+Shift+S save all   Ctrl+E recent files",
    "VS Code Ctrl+V pastes the Windows clipboard through the terminal.",
    "Ctrl+B declaration  Alt+F7 usages  Shift+F6 rename",
    "Ctrl+Click definition  Ctrl+Alt+Left/Right navigate back/forward",
    "Shift+F9 debug  Ctrl+F8 breakpoint  F9 resume  Ctrl+F2 stop",
    "Space d B conditional breakpoint (enter expression)",
    "F7 step into  F8 step over  Shift+F8 step out  Alt+F8 evaluate",
    "Space d e evaluate  Space d u debug panes  Space d a attach",
    "Space d l check launch.json (GDB: gdb; CodeLLDB: lldb/codelldb)",
    "", "Space means the leader key, used in Normal mode (press Esc first).",
    "Terminals may intercept Ctrl+Shift keys; use the Space alternatives.",
    "i insert; Esc normal; :q close pane; :qa or top X exit editor.",
    "File tree: click folders; double-click files; right-click for operations.",
    "Space Space opens a search menu (terminal cannot report double Shift).",
  }
  -- Help belongs to the editor grid. LSP previews size themselves around the
  -- current window, which can be a one-line picker input with no spare row.
  vim.cmd.stopinsert()
  return require("snacks").win {
    text = lines,
    ft = "text",
    relative = "editor",
    width = function() return math.max(1, math.min(78, vim.o.columns - 2)) end,
    height = function() return math.max(1, math.min(#lines, vim.o.lines - 4)) end,
    border = "rounded",
    backdrop = false,
    zindex = 100,
    enter = true,
    bo = { modifiable = false },
    keys = { q = "close", ["<Esc>"] = "close" },
  }
end
return M
