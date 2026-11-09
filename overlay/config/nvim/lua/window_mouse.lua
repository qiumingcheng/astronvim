-- Route borders before variable/tree/REPL clicks. With laststatus=3 the
-- horizontal boundary is the lower pane's winbar, not a native statusline.
local M = {}
local gesture
local function native(key) vim.api.nvim_feedkeys(vim.keycode(key), "ni", false) end
local function save_sizes()
  local windows = package.loaded["dapui.windows"]
  if not windows then return end
  for _, layout in ipairs(windows.layouts or {}) do
    if layout:is_open() then layout:update_sizes() end
  end
end

-- Share border detection with the passive hover marker. Exclude floats,
-- scrollbar tracks and the outside edge, where there is no adjacent pane.
function M.border(pos)
  if pos.line ~= 0 or pos.winid == 0 or not vim.api.nvim_win_is_valid(pos.winid) then return end
  if vim.api.nvim_win_get_config(pos.winid).relative ~= "" then return end
  local w = pos.winid
  local p = vim.api.nvim_win_get_position(w)
  local width = vim.api.nvim_win_get_width(w)
  if pos.screencol == p[2] + width + 1 then
    for _, other in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if other ~= w and vim.api.nvim_win_get_config(other).relative == "" then
        local at = vim.api.nvim_win_get_position(other)
        if at[2] == p[2] + width + 1 and pos.screenrow > at[1]
          and pos.screenrow <= at[1] + vim.api.nvim_win_get_height(other) + 1 then return "width" end
      end
    end
  end
  if pos.winrow == 1 and vim.wo[w].winbar ~= "" then
    for _, above in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if above ~= w and vim.api.nvim_win_get_config(above).relative == "" then
        local at = vim.api.nvim_win_get_position(above)
        local bar = vim.wo[above].winbar ~= "" and 1 or 0
        if at[1] + vim.api.nvim_win_get_height(above) + bar == p[1]
          and pos.screencol > at[2] and pos.screencol <= at[2] + vim.api.nvim_win_get_width(above) then
          return "height", above
        end
      end
    end
  end
end

function M.route(key)
  local pos = vim.fn.getmousepos()
  -- Neovim carries the click count onto drag/release events. Match their
  -- action here while preserving the original native key for text selection.
  local action = key:gsub("^<[234]%-", "<")
  if action == "<LeftDrag>" or action == "<LeftRelease>" then
    if not gesture then return false end
    local g = gesture
    if g.above and vim.api.nvim_win_is_valid(g.above) then
      local delta = pos.screenrow - g.row
      if delta ~= 0 then
        vim.fn.win_move_statusline(g.above, delta)
        g.row = pos.screenrow
        g.moved = true
      end
    else
      native(key)
      if action == "<LeftDrag>" then g.moved = true end
    end
    if action == "<LeftRelease>" then
      gesture = nil
      -- A winbar is both a draggable horizontal boundary and a row of DAP
      -- buttons. Defer a simple click until release so starting a drag over
      -- Step/Continue never executes a debugger command first.
      if g.above and not g.moved then native(g.key); native("<LeftRelease>") end
      if g.moved then vim.schedule(save_sizes) end
    end
    return true
  end
  gesture = nil
  local tabline_visible = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  if pos.screenrow == 1 and tabline_visible and pos.line == 0 then
    vim.cmd.stopinsert()
    require("activity_bar").focus_editor()
    native(key)
    return true
  end
  if pos.line ~= 0 or pos.winid == 0 then return false end
  if not vim.api.nvim_win_is_valid(pos.winid) then return false end
  local cfg = vim.api.nvim_win_get_config(pos.winid)
  if cfg.relative ~= "" then return false end
  gesture = { row = pos.screenrow, key = key }
  local axis, above = M.border(pos)
  if axis == "height" then gesture.above = above end
  -- Preserve native Console winbar buttons and vertical-separator dragging.
  if not gesture.above then native(key) end
  return true
end
return M
