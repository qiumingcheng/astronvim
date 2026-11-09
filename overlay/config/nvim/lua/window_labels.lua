local M = {}
local titles = {
  dapui_scopes = "局部变量 / Scopes",
  dapui_watches = "监视表达式 / Watches",
  dapui_stacks = "线程与调用栈 / Stacks",
  dapui_breakpoints = "断点 / Breakpoints",
  ["dap-repl"] = "调试控制台 / REPL",
  dapui_console = "程序输出 / Console",
  ["neo-tree"] = "文件目录 / Explorer",
  aerial = "代码结构 / Outline",
  toggleterm = "终端 / Terminal",
}

local function label(text)
  return "%#PortableWinBar# " .. text:gsub("%%", "%%%%") .. " %*%T"
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "PortableWinBar", { bg = "#303640", fg = "#e6edf3", bold = true })
  vim.api.nvim_set_hl(0, "WinBar", { bg = "#303640", fg = "#e6edf3", bold = true })
  vim.api.nvim_set_hl(0, "WinBarNC", { bg = "#252a33", fg = "#aab4c3", bold = true })
  vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#96a4b8", bg = "#303640", bold = true })
end

function M.refresh()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      local buf = vim.api.nvim_win_get_buf(win)
      local title = titles[vim.bo[buf].filetype]
      if not title and vim.bo[buf].buftype == "" then
        local name = vim.api.nvim_buf_get_name(buf)
        title = "编辑区 / Editor — " .. (name == "" and "未打开文件" or vim.fn.fnamemodify(name, ":t"))
      end
      if title then
        local bar = label(title)
        -- DAP uses Console's winbar for clickable controls. Keep those buttons.
        if vim.bo[buf].filetype == "dapui_console" and package.loaded["dapui.controls"] then
          bar = require("dapui.controls").controls(win == vim.api.nvim_get_current_win())
        end
        if vim.wo[win].winbar ~= bar then vim.wo[win].winbar = bar end
      end
    end
  end
end

function M.setup()
  setup_highlights()
  local pending = false
  local function queue()
    if pending then return end
    pending = true
    vim.schedule(function() pending = false; M.refresh() end)
  end
  local group = vim.api.nvim_create_augroup("PortableWindowLabels", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "FileType", "TermOpen", "VimEnter" }, {
    group = group, callback = queue,
  })
  vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "winbar", callback = queue })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = setup_highlights })
  queue()
end

function M.setup_debug()
  local controls = require "dapui.controls"
  if not controls.portable_labels then
    local original = controls.controls
    controls.controls = function(active)
      return label(titles.dapui_console) .. "%<" .. original(active)
    end
    controls.portable_labels = true
  end
  M.refresh()
end

return M
