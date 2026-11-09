local M = {}

local function enter(win)
  vim.api.nvim_set_current_win(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local last = vim.api.nvim_buf_line_count(buf)
  local line = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1]
  vim.api.nvim_win_set_cursor(win, { last, #line })
  vim.cmd.startinsert { bang = true }
end

function M.focus()
  -- DAP UI owns its REPL window; reuse it instead of creating another split.
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "dap-repl" then
      enter(win)
      return
    end
  end
  local _, win = require("dap").repl.open()
  enter(win)
end

function M.click()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or not vim.api.nvim_win_is_valid(pos.winid) then return false end
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  if vim.bo[buf].filetype ~= "dap-repl" or vim.bo[buf].buftype ~= "prompt" then return false end
  -- History stays selectable. Only the prompt (or blank space below it) enters input.
  if pos.line < vim.api.nvim_buf_line_count(buf) then return false end
  enter(pos.winid)
  return true
end

return M
