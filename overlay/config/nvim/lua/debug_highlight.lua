local M = {}

local function sign_columns()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative == ""
      and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" and vim.wo[win].signcolumn ~= "yes:2" then
      -- Keep both the stopped arrow and breakpoint visible on the same line.
      vim.wo[win].signcolumn = "yes:2"
    end
  end
end

local function apply()
  -- Highlight the debugger's frame, independently of the editor cursor.
  local light = vim.o.background == "light"
  vim.api.nvim_set_hl(0, "PortableDebugLine", { bg = light and "#FFE49A" or "#594619" })
  vim.api.nvim_set_hl(0, "PortableDebugArrow", { fg = "#1E1E1E", bg = "#FFD75F", bold = true })
  vim.api.nvim_set_hl(0, "PortableDebugNumber", { fg = light and "#6B4400" or "#FFD75F", bg = light and "#FFE49A" or "#594619", bold = true })
  vim.api.nvim_set_hl(0, "PortableBreakpoint", { fg = "#FFFFFF", bg = "#B91C1C", bold = true })
  vim.api.nvim_set_hl(0, "PortableConditionalBreakpoint", { fg = "#FFFFFF", bg = "#7C3AED", bold = true })
  vim.fn.sign_define("DapBreakpoint", { text = "B", texthl = "PortableBreakpoint" })
  vim.fn.sign_define("DapBreakpointCondition", { text = "C", texthl = "PortableConditionalBreakpoint" })
  vim.fn.sign_define("DapStopped", {
    text = "=>", texthl = "PortableDebugArrow",
    linehl = "PortableDebugLine", numhl = "PortableDebugNumber",
  })
  sign_columns()
end

function M.setup()
  apply()
  local group = vim.api.nvim_create_augroup("PortableDebugHighlight", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = apply,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, { group = group, callback = sign_columns })
end

return M
