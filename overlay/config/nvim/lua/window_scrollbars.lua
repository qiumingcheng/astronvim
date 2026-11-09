-- Mouse scrollbars for terminal Neovim. Floats occupy only the content edge;
-- winbars and split separators remain available for window resizing.
local M = { bars = {} }
local api, fn = vim.api, vim.fn
local ns = api.nvim_create_namespace("portable_scrollbars")
local widths, pending, updating, exiting, drag = {}, false, false, false, nil
local watching, visible = {}, {}
-- Foreground Insert changes already emit TextChangedI/TextChangedP. Keep the
-- background observer, without scheduling the same work for every typed byte.
local typing_buf
local function track_typing(mode)
  typing_buf = nil
  if mode:sub(1, 1) == "i" then
    local buf = api.nvim_get_current_buf()
    if vim.bo[buf].buftype == "" then typing_buf = buf end
  end
end
local excluded = { astro_activity_bar = true, portable_scrollbar = true }
local function valid(w) return w and api.nvim_win_is_valid(w) end
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
local function close(bar)
  if valid(bar.win) then api.nvim_win_close(bar.win, true) end
end

function M.queue()
  if pending or updating or exiting then return end
  pending = true
  vim.defer_fn(function()
    pending = false
    if not exiting then M.refresh() end
  end, 35)
end

-- Width of the displayed rows: a long row further down becomes horizontally
-- scrollable when brought into view. Cache on buffer version and viewport.
local function max_width(buf, first, last)
  local tick, tabstop = api.nvim_buf_get_changedtick(buf), vim.bo[buf].tabstop
  local key = table.concat({tick, tabstop, vim.bo[buf].vartabstop, vim.o.ambiwidth, first, last}, ":")
  local c = widths[buf]
  if c and c.key == key then return c.max end
  c = { key = key, max = 0 }
  widths[buf] = c
  api.nvim_buf_call(buf, function()
    for _, line in ipairs(api.nvim_buf_get_lines(buf, first - 1, last, false)) do
      c.max = math.max(c.max, fn.strdisplaywidth(line))
    end
  end)
  return c.max
end

local function draw(owner, axis, row, col, length, page, total, offset)
  local key = owner .. axis
  local bar = M.bars[key] or { owner = owner, axis = axis }
  M.bars[key] = bar
  bar.seen = true
  local thumb = clamp(math.floor(length * page / total), 1, length)
  local max = math.max(0, total - page)
  local start = max > 0 and math.floor(clamp(offset, 0, max) * (length - thumb) / max + 0.5) or 0
  bar.row, bar.col, bar.length, bar.page, bar.total = row, col, length, page, total
  bar.offset, bar.start, bar.thumb, bar.max = offset, start, thumb, max
  if not bar.buf or not api.nvim_buf_is_valid(bar.buf) then
    bar.drawn_length, bar.drawn_start, bar.drawn_thumb = nil, nil, nil
    bar.buf = api.nvim_create_buf(false, true)
    vim.bo[bar.buf].bufhidden = "wipe"
    vim.bo[bar.buf].filetype = "portable_scrollbar"
  end
  local resized = bar.drawn_length ~= length
  if resized then
    local lines = axis == "h" and { string.rep(" ", length) } or vim.fn["repeat"]({ " " }, length)
    api.nvim_buf_set_lines(bar.buf, 0, -1, false, lines)
    bar.drawn_length = length
  end
  if resized or bar.drawn_start ~= start or bar.drawn_thumb ~= thumb then
    api.nvim_buf_clear_namespace(bar.buf, ns, 0, -1)
    if axis == "h" then
      api.nvim_buf_set_extmark(bar.buf, ns, 0, start, {
        end_col = start + thumb, hl_group = "PortableScrollThumb" })
    else
      api.nvim_buf_set_extmark(bar.buf, ns, start, 0, {
        end_row = start + thumb - 1, end_col = 1, hl_group = "PortableScrollThumb", hl_eol = true })
    end
    bar.drawn_start, bar.drawn_thumb = start, thumb
  end
  local cfg = { relative = "editor", row = row, col = col, width = axis == "h" and length or 1,
    height = axis == "v" and length or 1, style = "minimal", border = "none",
    focusable = false, mouse = true, zindex = 45, noautocmd = true }
  local geometry = table.concat({row, col, cfg.width, cfg.height}, ":")
  if valid(bar.win) then
    if bar.geometry ~= geometry then api.nvim_win_set_config(bar.win, cfg) end
  else
    bar.win = api.nvim_open_win(bar.buf, false, cfg)
    vim.wo[bar.win].winhighlight = "Normal:PortableScrollTrack,NormalNC:PortableScrollTrack"
    vim.wo[bar.win].winblend = 0
    vim.wo[bar.win].winbar = ""
  end
  bar.geometry = geometry
end

function M.refresh()
  if updating or exiting or #api.nvim_list_uis() == 0 then return end
  updating = true
  visible = {}
  for _, bar in pairs(M.bars) do bar.seen = false end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local buf = api.nvim_win_get_buf(win)
    if api.nvim_win_get_config(win).relative == "" and not excluded[vim.bo[buf].filetype] then
      visible[buf] = true
      if not watching[buf] then
        -- TextChanged is not delivered for background debug panes. Observe
        -- their actual buffer updates, sharing the existing coalesced refresh.
        watching[buf] = api.nvim_buf_attach(buf, false, {
          on_lines = function(_, changed)
            if not visible[changed] then watching[changed] = nil; return true end
            if changed ~= typing_buf then M.queue() end
          end,
          on_detach = function(_, detached)
            watching[detached], visible[detached], widths[detached] = nil, nil, nil
          end,
        })
      end
      local h, w = api.nvim_win_get_height(win), api.nvim_win_get_width(win)
      local pos = api.nvim_win_get_position(win)
      local row = pos[1] + (vim.wo[win].winbar ~= "" and 1 or 0)
      -- Never cover the global index/status line, even during cmdheight or
      -- terminal-size transitions before all WinResized callbacks settle.
      local bottom = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus == 3 and 1 or 0)
      h = math.min(h, bottom - row)
      if h >= 3 and w >= 8 then
        local info = fn.getwininfo(win)[1]
        local view = api.nvim_win_call(win, fn.winsaveview)
        local count, wide = api.nvim_buf_line_count(buf), max_width(buf, view.topline, info.botline)
        local vert = count > h
        local pagew = math.max(1, w - info.textoff - (vert and 1 or 0))
        local horiz = not vim.wo[win].wrap and (wide > pagew or view.leftcol > 0)
        local pageh = h - (horiz and 1 or 0)
        vert = count > pageh or view.topline > 1
        pagew = math.max(1, w - info.textoff - (vert and 1 or 0))
        if horiz then draw(win, "h", row + h - 1, pos[2] + info.textoff, pagew, pagew, math.max(wide, view.leftcol + pagew), view.leftcol) end
        if vert then draw(win, "v", row, pos[2] + w - 1, pageh, pageh, count, view.topline - 1) end
      end
    end
  end
  for key, bar in pairs(M.bars) do
    if not bar.seen then close(bar); M.bars[key] = nil end
  end
  updating = false
end

local function scroll(bar, offset)
  if not valid(bar.owner) then return end
  offset = clamp(math.floor(offset + 0.5), 0, bar.max)
  api.nvim_win_call(bar.owner, function()
    local v = fn.winsaveview()
    if bar.axis == "h" then
      v.leftcol = offset
      -- Neovim keeps the cursor visible; move it into the scrolled viewport
      -- just as native horizontal scrolling does, without changing text.
      local wanted_min = offset + vim.wo.sidescrolloff
      local line = api.nvim_buf_get_lines(0, v.lnum - 1, v.lnum, false)[1] or ""
      if fn.strdisplaywidth(line) <= wanted_min then
        -- A scope heading/blank line can be shorter than its variables. Select
        -- the nearest visible long row so native cursor visibility does not
        -- snap the viewport back to column zero.
        local closest
        for i, text in ipairs(api.nvim_buf_get_lines(0, v.topline - 1, fn.line("w$"), false)) do
          local lnum = v.topline + i - 1
          if fn.strdisplaywidth(text) > wanted_min and
            (not closest or math.abs(lnum - v.lnum) < math.abs(closest - v.lnum)) then closest = lnum end
        end
        if closest then v.lnum = closest end
      end
      local col = fn.virtcol({ v.lnum, v.col + 1 }) - 1
      local wanted = clamp(col, offset + vim.wo.sidescrolloff, offset + bar.page - 1 - vim.wo.sidescrolloff)
      v.col = math.max(0, fn.virtcol2col(bar.owner, v.lnum, wanted + 1) - 1)
      v.curswant = wanted
    else
      v.topline = offset + 1
      local margin = math.min(vim.wo.scrolloff, math.floor((bar.page - 1) / 2))
      v.lnum = clamp(v.lnum, v.topline + margin, v.topline + bar.page - 1 - margin)
    end
    fn.winrestview(v)
  end)
  M.queue()
end

function M.mouse(key)
  -- Neovim retains a rapid click's count on its drag/release events too.
  -- A scrollbar gesture has the same meaning for all click counts.
  key = key:gsub("^<[234]%-", "<")
  local pos = fn.getmousepos()
  if key == "<LeftMouse>" or key == "<2-LeftMouse>" then
    drag = nil
    for _, bar in pairs(M.bars) do
      if pos.winid == bar.win then
        -- Prompt buffers otherwise force Insert-mode cursor back to dap>.
        vim.cmd.stopinsert()
        local at = bar.axis == "h" and pos.screencol - 1 - bar.col or pos.screenrow - 1 - bar.row
        local in_thumb = at >= bar.start and at < bar.start + bar.thumb
        drag = { bar = bar, grab = in_thumb and at - bar.start or math.floor(bar.thumb / 2) }
        if not in_thumb then
          scroll(bar, (at - drag.grab) * bar.max / math.max(1, bar.length - bar.thumb))
        end
        return true
      end
    end
  elseif drag and (key == "<LeftDrag>" or key == "<LeftRelease>") then
    local bar = drag.bar
    local at = bar.axis == "h" and pos.screencol - 1 - bar.col or pos.screenrow - 1 - bar.row
    scroll(bar, (at - drag.grab) * bar.max / math.max(1, bar.length - bar.thumb))
    if key == "<LeftRelease>" then drag = nil end
    return true
  end
  return false
end

function M.setup()
  local function colors()
    api.nvim_set_hl(0, "PortableScrollTrack", { bg = "#303030" })
    api.nvim_set_hl(0, "PortableScrollThumb", { bg = "#808080" })
  end
  colors()
  local group = api.nvim_create_augroup("PortableWindowScrollbars", { clear = true })
  api.nvim_create_autocmd({ "WinScrolled", "WinResized", "VimResized", "BufWinEnter", "WinClosed",
    "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT", "TabEnter", "CursorMoved" }, { group = group, callback = function(ev)
      if vim.bo[ev.buf].filetype ~= "portable_scrollbar" then M.queue() end
    end })
  api.nvim_create_autocmd("InsertEnter", { group = group, callback = function()
    track_typing(vim.v.insertmode == "i" and "i" or "n")
  end })
  api.nvim_create_autocmd("InsertLeave", { group = group, callback = function() typing_buf = nil end })
  api.nvim_create_autocmd("BufEnter", { group = group, callback = function() track_typing(api.nvim_get_mode().mode) end })
  -- CTRL-O and Replace mode can temporarily leave ordinary Insert without a
  -- buffer change; a stale typing_buf must not suppress their Normal updates.
  api.nvim_create_autocmd("ModeChanged", { group = group, callback = function() track_typing(vim.v.event.new_mode) end })
  api.nvim_create_autocmd("OptionSet", { group = group, pattern = "buftype",
    callback = function() track_typing(api.nvim_get_mode().mode) end })
  api.nvim_create_autocmd("OptionSet", { group = group, pattern = { "wrap", "number", "tabstop", "vartabstop", "ambiwidth" }, callback = M.queue })
  api.nvim_create_autocmd("BufWipeout", { group = group, callback = function(ev)
    widths[ev.buf] = nil
    if typing_buf == ev.buf then typing_buf = nil end
  end })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = colors })
  api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function() exiting = true end })
  M.queue()
end
return M
