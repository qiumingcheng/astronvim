local M = {}

function M.stack_click(pos, buf, repeated)
  pos = pos or vim.fn.getmousepos()
  if pos.winid == 0 or not vim.api.nvim_win_is_valid(pos.winid) then return false end
  buf = buf or vim.api.nvim_win_get_buf(pos.winid)
  if vim.bo[buf].filetype ~= "dapui_stacks" then return false end
  if pos.line < 1 or pos.line > vim.api.nvim_buf_line_count(buf) then return true end
  vim.cmd.stopinsert()
  vim.api.nvim_set_current_win(pos.winid)
  vim.api.nvim_win_set_cursor(pos.winid, { pos.line, 0 })
  local session = require("dap").session()
  if not session or not session.stopped_thread_id then return true end
  local line = vim.api.nvim_buf_get_lines(buf, pos.line - 1, pos.line, false)[1]
  if line:match("^%s*$") then return true end
  -- Frame rows reuse DAP UI's source/locals action. Thread headings retain
  -- its native subtle-frame toggle, without toggling twice on a double click.
  local header = line:match(":%s*$") ~= nil
  if header and repeated then return true end
  local action = header and "toggle" or "open"
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if mapping.desc == action and type(mapping.callback) == "function" then
      mapping.callback(pos.line)
      break
    end
  end
  return true
end

function M.breakpoint_click()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or not vim.api.nvim_win_is_valid(pos.winid) then return false end
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  local ft = vim.bo[buf].filetype
  if ft == "dapui_stacks" then return M.stack_click(pos, buf) end
  if ft ~= "dapui_breakpoints" then return false end
  if pos.line < 1 or pos.line > vim.api.nvim_buf_line_count(buf) then return true end
  vim.api.nvim_set_current_win(pos.winid)
  vim.api.nvim_win_set_cursor(pos.winid, { pos.line, 0 })
  local line = vim.api.nvim_buf_get_lines(buf, pos.line - 1, pos.line, false)[1]
  if not line:match("^%s+%S") then return true end -- File headings and blank rows.
  -- Reuse DAP UI's row-to-source mapping, including condition/log detail rows.
  -- Its open action targets the editor and leaves the debugger frame unchanged.
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if mapping.desc == "open" and mapping.callback then
      mapping.callback(pos.line)
      break
    end
  end
  return true
end

local function code_target()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or not vim.api.nvim_win_is_valid(pos.winid) or pos.line < 1 then return end
  local buffer = vim.api.nvim_win_get_buf(pos.winid)
  if vim.bo[buffer].buftype ~= "" or vim.bo[buffer].filetype == "neo-tree" then return end
  vim.api.nvim_set_current_win(pos.winid)
  vim.api.nvim_win_set_cursor(pos.winid, { math.min(pos.line, vim.api.nvim_buf_line_count(buffer)), 0 })
  return pos
end

local function gutter_click(pos)
  local info = vim.fn.getwininfo(pos.winid)[1]
  local textoff = info and info.textoff or 0
  return pos.wincol and pos.wincol > 0 and pos.wincol <= textoff
end

function M.left_click()
  local pos = code_target()
  if not pos or not gutter_click(pos) then return false end
  require("dap").toggle_breakpoint()
  return true
end

function M.right_click()
  local pos = code_target()
  if not pos or not gutter_click(pos) then return false end
  vim.ui.input({ prompt = "Breakpoint condition: " }, function(condition)
    if condition and condition ~= "" then require("dap").set_breakpoint(condition) end
  end)
  return true
end

return M
