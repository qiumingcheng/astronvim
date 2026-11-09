-- Mouse operations use Neo-tree's own file commands and confirmation dialogs.
local M = {}
local function mouse_state()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or not vim.api.nvim_win_is_valid(pos.winid) then return end
  if vim.bo[vim.api.nvim_win_get_buf(pos.winid)].filetype ~= "neo-tree" then return end
  local state = require("neo-tree.sources.manager").get_state("filesystem")
  if state.winid == pos.winid then return state end
end
function M.route_menu()
  local state = mouse_state()
  if state then M.menu(state); return end
  if not state and require("debug_mouse").right_click() then return end
end
function M.route_click()
  if require("repl_input").click() then return end
  if require("debug_mouse").breakpoint_click() then return end
  local state = mouse_state()
  if state then M.click(state); return end
  if require("debug_mouse").left_click() then return end
  vim.cmd.normal { args = { vim.keycode("<LeftMouse>") }, bang = true }
end
function M.route_open()
  if require("debug_mouse").stack_click(nil, nil, true) then return end
  local state = mouse_state()
  if state then M.open(state) else vim.cmd.normal { args = { vim.keycode("<2-LeftMouse>") }, bang = true } end
end
local function focus_mouse(state)
  local pos = vim.fn.getmousepos()
  if pos.winid ~= state.winid or pos.line < 1 then return false end
  vim.api.nvim_set_current_win(state.winid)
  vim.api.nvim_win_set_cursor(state.winid, { pos.line, 0 })
  return true
end
function M.click(state)
  if not focus_mouse(state) then return end
  local node = state.tree:get_node()
  if node and node.type == "directory" then state.commands.toggle_node(state) end
end
function M.open(state)
  if not focus_mouse(state) then return end
  local node = state.tree:get_node()
  if node and node.type == "file" then state.commands.open(state) end
end
function M.menu(state)
  if not focus_mouse(state) then return end
  local node = state.tree:get_node()
  if not node then return end
  M.show_menu(state)
end
function M.show_menu(state)
  local node = state.tree:get_node()
  if not node then return end
  local entries = {
    { "Open / Expand", "open" },
    { "Open in vertical split", "open_vsplit" },
    { "Open in horizontal split", "open_split" },
    { "New file...", "add" },
    { "New folder...", "add_directory" },
    { "Rename...", "rename" },
    { "Copy", "copy_to_clipboard" },
    { "Cut", "cut_to_clipboard" },
    { "Paste into folder", "paste_from_clipboard" },
    { "Copy absolute path", function() vim.fn.setreg('+', node:get_id()); vim.fn.setreg('"', node:get_id()) end },
    { "Delete... (confirm)", "delete" },
    { "Refresh", "refresh" },
  }
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for _, item in ipairs(entries) do table.insert(lines, "  " .. item[1] .. "  ") end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "astro_file_menu"
  local pos = vim.fn.getmousepos()
  local row = math.min(math.max(0, pos.screenrow - 1), math.max(0, vim.o.lines - #lines - 4))
  local col = math.min(math.max(1, pos.screencol), math.max(1, vim.o.columns - 34))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col, width = 32, height = #lines,
    style = "minimal", border = "rounded", title = " File operations ", title_pos = "center",
    zindex = 100,
  })
  vim.wo[win].cursorline = true
  local closed = false
  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  local function choose(index)
    local item = entries[index]
    close()
    if not item or not vim.api.nvim_win_is_valid(state.winid) then return end
    vim.api.nvim_set_current_win(state.winid)
    vim.schedule(function()
      -- Entering/leaving the popup can restore Neo-tree's previous selection.
      -- Resolve the node the user actually right-clicked immediately before use.
      if not vim.api.nvim_win_is_valid(state.winid) then return end
      local selected, line = state.tree:get_node(node:get_id())
      if not selected or not line then return end
      vim.api.nvim_set_current_win(state.winid)
      vim.api.nvim_win_set_cursor(state.winid, { line, 0 })
      -- Neo-tree normally supplies per-command options through its key dispatcher.
      -- Mouse menu commands bypass that dispatcher, so initialize fresh options.
      state.config = {}
      if type(item[2]) == "function" then item[2]() else state.commands[item[2]](state) end
    end)
  end
  vim.keymap.set("n", "<LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid == win then choose(mouse.line) else close() end
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<CR>", function() choose(vim.api.nvim_win_get_cursor(win)[1]) end, { buffer = buf })
  for _, key in ipairs { "<Esc>", "q", "<RightMouse>" } do
    vim.keymap.set("n", key, close, { buffer = buf, nowait = true })
  end
  vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = function() vim.schedule(close) end })
end
return M
