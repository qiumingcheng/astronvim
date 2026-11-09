local M = {}

-- SSH cannot synchronously read the Windows clipboard. Keep explicit copies
-- independent of Vim's delete/unnamed registers, and write them through OSC 52.
-- VS Code's Ctrl+V uses terminal.paste to deliver its current system clipboard.
function M.clipboard()
  local cache = { ["+"] = { {}, "v" }, ["*"] = { {}, "v" } }
  local provider = { name = "OSC 52 portable", copy = {}, paste = {} }
  for _, register in ipairs { "+", "*" } do
    local send = require("vim.ui.clipboard.osc52").copy(register)
    provider.copy[register] = function(lines, regtype)
      cache[register] = { vim.deepcopy(lines), regtype }
      send(lines, regtype)
    end
    provider.paste[register] = function() return vim.deepcopy(cache[register]) end
  end
  return provider
end

local function selected()
  local mode = vim.fn.mode():sub(1, 1)
  return mode == "v" or mode == "V" or mode == "\22" or mode == "s" or mode == "S" or mode == "\19", mode
end

-- Select treats printable operator/register keys as replacement text. Switch
-- to the matching Visual mode without rebuilding byte/cell selection bounds.
local function select_to_visual(mode)
  local was_select = mode == "s" or mode == "S" or mode == "\19"
  if was_select then vim.cmd.normal { args = { vim.keycode("<C-G>") }, bang = true } end
  return was_select
end

local function writable()
  if vim.bo.modifiable and not vim.bo.readonly then return true end
  vim.notify("当前窗口只读，未修改内容", vim.log.levels.WARN)
  return false
end

local function run(fn)
  local ok, err = pcall(fn)
  if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
end

function M.copy()
  local has_selection, mode = selected()
  if has_selection then
    local was_select = select_to_visual(mode)
    vim.cmd.normal { args = { '"+y' }, bang = true }
    vim.cmd.normal { args = { "gv" }, bang = true }
    if was_select then vim.cmd.normal { args = { vim.keycode("<C-G>") }, bang = true } end
  else
    -- No mode change, cursor movement or undo entry when copying a whole line.
    vim.fn.setreg("+", { vim.api.nvim_get_current_line() }, "V")
  end
end

function M.cut()
  if not writable() then return end
  local has_selection, mode = selected()
  if has_selection then
    select_to_visual(mode)
    vim.cmd.normal { args = { '"+d' }, bang = true }
  else
    M.copy()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, row - 1, row, false, {})
  end
end

function M.paste()
  if not writable() then return end
  local text = vim.fn.getreg("+")
  if text == "" then return end
  -- Use the very same path as native bracketed terminal paste: Normal puts
  -- after the cursor, Insert at the insertion point, Visual replaces selection.
  vim.api.nvim_paste(text, true, -1)
end

function M.select_all()
  vim.cmd.normal { args = { "ggVG" }, bang = true }
end

function M.undo()
  if not writable() then return end
  if selected() then vim.cmd.normal { args = { vim.keycode("<Esc>") }, bang = true } end
  run(function() vim.cmd.undo() end)
end

function M.redo()
  if not writable() then return end
  if selected() then vim.cmd.normal { args = { vim.keycode("<Esc>") }, bang = true } end
  run(function() vim.cmd.redo() end)
end

function M.save()
  if vim.bo.buftype ~= "" or not writable() then return end
  local buf = vim.api.nvim_get_current_buf()
  local function write(path)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    run(function()
      vim.api.nvim_buf_call(buf, function()
        -- No !: preserve read-only protection and external-file conflict checks.
        vim.api.nvim_cmd({ cmd = "write", args = path and { path } or {} }, {})
      end)
    end)
  end
  if vim.api.nvim_buf_get_name(buf) ~= "" then return write() end
  vim.ui.input({
    prompt = "保存文件为: ", completion = "file",
    win = { keys = {
      i_esc = { "<esc>", "cancel", mode = "i", expr = false },
      n_esc = { "<esc>", "cancel", mode = "n", expr = false },
    } },
  }, function(path)
    if path and path ~= "" then write(path) end
  end)
end

function M.save_all() run(function() vim.cmd.wall() end) end

return M
