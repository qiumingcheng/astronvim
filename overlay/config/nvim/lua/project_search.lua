local M = {}
local api = vim.api
local filters = {}

-- Commas separate inclusive globs: *.cpp,*.h means either extension.
function M.parse(value)
  local globs, seen = {}, {}
  for part in (value or ""):gsub("，", ","):gmatch("[^,]+") do
    local glob = vim.trim(part)
    if glob ~= "" and not seen[glob] then
      seen[glob] = true
      globs[#globs + 1] = glob
    end
  end
  return globs
end

local function footer(globs)
  return " 类型: " .. (#globs == 0 and "全部" or table.concat(globs, ",")) .. " [Ctrl+T] "
end

function M.edit_types(picker)
  if not picker or picker.closed or picker._editing_types then return end
  picker._editing_types = true
  require("snacks").input({
    prompt = "文件类型（逗号分隔；留空搜索全部）",
    default = table.concat(picker.opts.glob or {}, ","),
  }, function(value)
    picker._editing_types = nil
    if picker.closed or value == nil then return end
    local globs = M.parse(value)
    filters[picker.opts.cwd] = globs
    picker.opts.glob = vim.deepcopy(globs)
    local win = picker.input.win
    win.opts.footer = footer(globs)
    if win:valid() then api.nvim_win_set_config(win.win, { footer = win.opts.footer, footer_pos = "left" }) end
    picker:find({ refresh = true })
  end)
end

function M.mouse(picker)
  if not picker or picker.closed or not picker.input.win:valid() then return false end
  local win = picker.input.win.win
  local p = vim.fn.screenpos(win, 1, 1)
  local origin = api.nvim_win_get_position(win)
  local pos = vim.fn.getmousepos()
  if pos.screenrow ~= p.row + api.nvim_win_get_height(win)
    or pos.screencol <= origin[2] or pos.screencol > origin[2] + api.nvim_win_get_width(win) + 2 then
    return false
  end
  vim.schedule(function() M.edit_types(picker) end)
  return true
end

function M.open()
  local cwd = vim.fn.getcwd()
  local globs = vim.deepcopy(filters[cwd] or {})
  return require("snacks").picker.grep({
    title = "项目搜索", cwd = cwd, hidden = true, exclude = { ".git" }, glob = globs,
    layout = { preset = "sidebar", layout = { width = 40, min_width = 28 } },
    actions = { file_types = M.edit_types },
    win = {
      input = { footer = footer(globs), footer_pos = "left",
        keys = { ["<C-t>"] = { "file_types", mode = { "n", "i" }, desc = "Filter file types" } } },
      list = { keys = { ["<C-t>"] = { "file_types", mode = { "n", "i" }, desc = "Filter file types" } } },
    },
  })
end

return M
