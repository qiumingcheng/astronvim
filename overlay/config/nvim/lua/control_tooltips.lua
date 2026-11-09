local M = {}
local api, fn = vim.api, vim.fn
local win, token, selected = nil, 0, nil
local marker_win, marker_buf, marker_key
local actions = { "play", "step_into", "step_over", "step_out", "step_back", "run_last", "terminate", "disconnect" }
local help = {
  step_into = "步入函数（F7）", step_over = "执行下一行（F8）",
  step_out = "执行到当前函数返回（Shift+F8）",
  step_back = "反向单步（需要调试器支持录制回放）",
  run_last = "重新运行上次调试配置",
  terminate = "停止调试（Ctrl+F2）", disconnect = "断开调试器连接",
}

function M.hide()
  token = token + 1
  selected = nil
  local old = win
  win = nil
  if old and api.nvim_win_is_valid(old) then api.nvim_win_close(old, true) end
  local marker = marker_win
  marker_win, marker_key = nil, nil
  if marker and api.nvim_win_is_valid(marker) then api.nvim_win_close(marker, true) end
end

local function target(pos)
  if pos.winid == 0 or not api.nvim_win_is_valid(pos.winid) or pos.line ~= 0 or pos.winrow ~= 1 then return end
  if vim.bo[api.nvim_win_get_buf(pos.winid)].filetype ~= "dapui_console" then return end
  local dap, config = package.loaded.dap, package.loaded["dapui.config"]
  if not dap or not config then return end
  local session = dap.session()
  local running = session and not session.stopped_thread_id
  local rendered = api.nvim_eval_statusline(vim.wo[pos.winid].winbar,
    { winid = pos.winid, use_winbar = true, maxwidth = api.nvim_win_get_width(pos.winid) }).str
  local finish = #rendered
  -- Read right-to-left so truncation of the title/first buttons does not
  -- confuse the single > (continue) with >| or >>.
  for i = #actions, 1, -1 do
    local action = actions[i]
    local icon = action == "play" and (running and config.controls.icons.pause or config.controls.icons.play)
      or config.controls.icons[action]
    local start, from = nil, 1
    while true do
      local a, b = rendered:find(icon, from, true)
      if not a or b > finish then break end
      start, from = a, b + 1
    end
    if start then
      local col = fn.strdisplaywidth(rendered:sub(1, start - 1)) + 1
      if pos.wincol >= col and pos.wincol < col + fn.strdisplaywidth(icon) then
        local text = help[action]
        if action == "play" then
          text = running and "暂停程序" or (session and "继续运行（F9）" or "启动调试（Shift+F9）")
        elseif action ~= "run_last" and (not session or (running and action:match("^step_"))) then
          text = text .. "（当前不可用）"
        end
        return action, text
      end
      finish = start - 1
    end
  end
end

function M.hover()
  local pos = fn.getmousepos()
  local action, text = target(pos)
  if not action then
    local axis = require("window_mouse").border(pos)
    if axis then
      local key = axis .. ":" .. pos.screenrow .. ":" .. pos.screencol
      if key == marker_key and marker_win and api.nvim_win_is_valid(marker_win) then return end
      -- Reuse the marker while moving along the same separator.
      if win or selected then M.hide() end
      if not marker_buf or not api.nvim_buf_is_valid(marker_buf) then
        marker_buf = api.nvim_create_buf(false, true)
        vim.bo[marker_buf].bufhidden = "hide"
        vim.bo[marker_buf].filetype = "portable_resize_hint"
      end
      local label = axis == "width" and "↔" or "↕"
      if marker_key == nil or marker_key:sub(1, #axis) ~= axis then
        api.nvim_buf_set_lines(marker_buf, 0, -1, false, { label })
      end
      local cfg = { relative = "editor", style = "minimal", border = "none",
        row = pos.screenrow - 1, col = pos.screencol - 1, width = 1, height = 1,
        focusable = false, mouse = false, noautocmd = true, zindex = 65 }
      if marker_win and api.nvim_win_is_valid(marker_win) then api.nvim_win_set_config(marker_win, cfg)
      else
        marker_win = api.nvim_open_win(marker_buf, false, cfg)
        vim.wo[marker_win].winhighlight = "Normal:PortableResizeHint,NormalNC:PortableResizeHint"
        vim.wo[marker_win].winblend = 0
      end
      marker_key = key
      return
    end
  end
  local key = action and (pos.winid .. ":" .. action .. ":" .. text)
  if key == selected then return end
  M.hide()
  if not action then return end
  selected = key
  local expected = token
  vim.defer_fn(function()
    if token ~= expected or not api.nvim_win_is_valid(pos.winid) then return end
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "portable_control_tooltip"
    api.nvim_buf_set_lines(buf, 0, -1, false, { text })
    local width = math.min(fn.strdisplaywidth(text), math.max(1, vim.o.columns - 2))
    win = api.nvim_open_win(buf, false, { relative = "editor", style = "minimal", border = "single",
      row = math.min(pos.screenrow, vim.o.lines - vim.o.cmdheight - 4),
      col = math.max(0, math.min(pos.screencol - 1, vim.o.columns - width - 2)),
      width = width, height = 1, focusable = false, mouse = false, noautocmd = true, zindex = 70 })
  end, 350)
end

function M.setup()
  vim.o.mousemoveevent = true
  local function colors() api.nvim_set_hl(0, "PortableResizeHint", { fg = "#FFFFFF", bg = "#007ACC", bold = true }) end
  colors()
  local group = api.nvim_create_augroup("PortableControlTooltips", { clear = true })
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinScrolled", "WinResized", "WinClosed", "VimResized", "TabLeave", "InsertEnter" },
    { group = group, callback = M.hide })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = colors })
end
return M
