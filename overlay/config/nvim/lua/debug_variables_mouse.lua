local M = {}
local api = vim.api
local variable_types = { dapui_scopes = true, dapui_watches = true }

local function target()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or not api.nvim_win_is_valid(pos.winid) then return end
  local buf = api.nvim_win_get_buf(pos.winid)
  if not variable_types[vim.bo[buf].filetype] then return end
  return pos, buf
end

function M.click()
  local pos, buf = target()
  if not pos then return false end
  if pos.line < 1 or pos.line > api.nvim_buf_line_count(buf) then return true end
  vim.cmd.stopinsert()
  api.nvim_set_current_win(pos.winid)
  api.nvim_win_set_cursor(pos.winid, { pos.line, 0 })
  local session = require("dap").session()
  if not session or not session.stopped_thread_id then return true end
  -- Only expandable rows have a decoration prefix. Scalar and blank clicks
  -- select the row without prompting, editing values or invoking the debugger.
  local line = api.nvim_buf_get_lines(buf, pos.line - 1, pos.line, false)[1]
  local prefix = line:match("^%s*(%S+)")
  local icons = require("dapui.config").icons
  if prefix ~= icons.expanded and prefix ~= icons.collapsed then return true end
  for _, mapping in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
    if mapping.desc == "expand" and type(mapping.callback) == "function" then
      mapping.callback(pos.line)
      break
    end
  end
  return true
end

function M.setup(opts)
  -- A double click must not immediately undo the first click's expansion.
  opts.element_mappings = opts.element_mappings or {}
  for _, name in ipairs { "scopes", "watches" } do
    opts.element_mappings[name] = opts.element_mappings[name] or {}
    opts.element_mappings[name].expand = { "<CR>" }
  end
  if M.installed then return end
  M.installed = true
  local mouse = require "tree_mouse"
  local click, open = mouse.route_click, mouse.route_open
  mouse.route_click = function()
    if M.click() then return end
    return click()
  end
  mouse.route_open = function()
    if target() then return end
    return open()
  end
end

return M
