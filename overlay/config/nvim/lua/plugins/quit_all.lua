-- Close the whole editor, including every split and tab, via Neovim's
-- standard save/discard/cancel dialog. Never force-discard modified buffers.
local pending = false

local function quit_all()
  local unnamed, discard = {}, {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == ""
      and vim.bo[buf].modified and vim.api.nvim_buf_get_name(buf) == "" then
      unnamed[#unnamed + 1] = buf
    end
  end
  local function finish()
    -- A cancelled close must leave even the buffers marked "Don't save"
    -- modified. Defer their discard until all unnamed-buffer choices are made.
    local modified = {}
    for buf in pairs(discard) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
        modified[#modified + 1] = buf
        vim.bo[buf].modified = false
      end
    end
    local ok, err = pcall(vim.cmd, "confirm qall")
    for _, buf in ipairs(modified) do
      if vim.api.nvim_buf_is_valid(buf) then vim.bo[buf].modified = true end
    end
    pending = false
    if not ok then vim.notify("无法退出：" .. tostring(err), vim.log.levels.ERROR) end
  end
  local function choose(index)
    local buf = unnamed[index]
    if not buf then return finish() end
    if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modified then return choose(index + 1) end
    local choice = vim.fn.confirm('Save changes to "[No Name]"?', "&Yes\n&No\n&Cancel", 1, "Question")
    if choice == 2 then discard[buf] = true; return choose(index + 1) end
    if choice ~= 1 then pending = false; return end
    -- Native :confirm qall chooses "Untitled" for an unnamed buffer and can
    -- overwrite an existing file of that name. Require an explicit save path
    -- and use ordinary :write (without !) so existing files remain protected.
    vim.ui.input({ prompt = "保存文件为: ", completion = "file",
      win = { keys = {
        i_esc = { "<esc>", "cancel", mode = "i", expr = false },
        n_esc = { "<esc>", "cancel", mode = "n", expr = false },
      } },
    }, function(path)
      if not path or path == "" or not vim.api.nvim_buf_is_valid(buf) then pending = false; return end
      local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
        vim.api.nvim_cmd({ cmd = "write", args = { path } }, {})
      end)
      -- Declining :write's overwrite confirmation can return without an error.
      -- Only proceed once the write actually cleared the modified flag.
      if not ok or (vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified) then
        if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_set_name, buf, "") end
        pending = false
        vim.notify("未保存，保留编辑内容" .. (not ok and ("：" .. tostring(err)) or ""), vim.log.levels.WARN)
        return
      end
      choose(index + 1)
    end)
  end
  choose(1)
end

return {
  {
    "rebelot/heirline.nvim",
    opts = function(_, opts)
      vim.opt.showtabline = 2
      table.insert(opts.tabline, {
        provider = " × ",
        hl = { fg = "#ffffff", bg = "#a1260d", bold = true },
        on_click = {
          name = "portable_quit_all_click",
          callback = function(_, _, _, button)
            if button ~= "l" or pending then return end
            pending = true
            vim.schedule(quit_all)
          end,
        },
      })
    end,
  },
}
