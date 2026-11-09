-- Run inside the affected editor before :redraw! to distinguish stale terminal
-- pixels from a live picker/window. Source text and process arguments are omitted.
local api = vim.api
local root = assert(vim.env.ASTRONVIM_ROOT)
local version_file = root .. "/opt/terminfo-compat/VERSION"
local version = vim.fn.filereadable(version_file) == 1 and vim.fn.readfile(version_file)[1] or "1 or absent"
local report = {
  time = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  nvim = vim.version(),
  term = vim.env.TERM,
  term_program = vim.env.TERM_PROGRAM,
  terminfo = vim.env.TERMINFO,
  terminfo_dirs = vim.env.TERMINFO_DIRS,
  compatibility = vim.env.ASTRO_TUI_COMPAT,
  installed_patch_version = version,
  root = root,
  uis = api.nvim_list_uis(),
  dimensions = { columns = vim.o.columns, lines = vim.o.lines },
  windows = {},
  active_pickers = 0,
  picker_windows = 0,
  error = vim.v.errmsg,
  messages = api.nvim_exec2("messages", { output = true }).output,
}
for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
  local ft = vim.bo[api.nvim_win_get_buf(win)].filetype
  local entry = {
    win = win, filetype = ft, position = api.nvim_win_get_position(win),
    width = api.nvim_win_get_width(win), height = api.nvim_win_get_height(win),
    relative = api.nvim_win_get_config(win).relative,
    view = api.nvim_win_call(win, vim.fn.winsaveview),
    buffer = api.nvim_win_get_buf(win),
    textoff = vim.fn.getwininfo(win)[1].textoff,
    wrap = vim.wo[win].wrap,
  }
  if ft:match("^snacks_picker") or ft == "snacks_layout_box" then
    report.picker_windows = report.picker_windows + 1
  end
  report.windows[#report.windows + 1] = entry
end
if package.loaded["snacks.picker"] then
  report.active_pickers = #require("snacks.picker").get()
end
if package.loaded.dap and require("dap").session() then
  local session = require("dap").session()
  report.debug = { backend = session.config.type, initialized = session.initialized,
    stopped_thread = session.stopped_thread_id }
end
local directory = root .. "/logs"
vim.fn.mkdir(directory, "p")
local path = directory .. "/ui-report.json"
vim.fn.writefile({ vim.json.encode(report) }, path)
vim.notify("界面诊断已保存: " .. path)
