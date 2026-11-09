-- Start project indexing without putting a source file in an editor window.
local M = { phase = "", tasks = {} }
local generation = 0
local method = "workspace/symbol"

local redraw_pending = false
local scan_cancel
local function redraw()
  if redraw_pending then return end
  redraw_pending = true
  vim.defer_fn(function()
    redraw_pending = false
    vim.cmd.redrawstatus()
  end, 50)
end
local function source(path)
  return path:match("%.[cChH]$") or path:match("%.cc$") or path:match("%.cpp$")
    or path:match("%.cxx$") or path:match("%.hpp$") or path:match("%.cu$")
end
local function inside(path, root) return path:sub(1, #root + 1) == root .. "/" end

-- When the launcher receives a deployment directory (for example a directory
-- that contains one extracted source tree), use the only unambiguous child
-- project.  Do not recurse or choose between several projects: starting in a
-- parent such as ~/data must never attach clangd to an arbitrary repository.
local function only_child_project(cwd)
  local candidates = {}
  local ok, iter = pcall(vim.fs.dir, cwd)
  if not ok or not iter then return nil end
  for name, kind in iter do
    if kind == "directory" and name ~= ".git" then
      local child = vim.fs.normalize(cwd .. "/" .. name)
      local marked = false
      for _, marker in ipairs {
        "compile_commands.json", ".clangd", "compile_flags.txt", ".git",
        "CMakeLists.txt", "GNUmakefile", "Makefile",
      } do
        local path = child .. "/" .. marker
        if marker == ".git" then
          marked = vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1
        else
          marked = vim.fn.filereadable(path) == 1
        end
        if marked then break end
      end
      if marked then
        candidates[#candidates + 1] = child
        if #candidates > 1 then return nil end
      end
    end
  end
  return candidates[1]
end

-- The startup source is only an anchor for the project client. Closing its
-- file tab must not hide a client still attached to another project buffer.
-- Reanchor only when needed; statusline redraws keep the cached-client path.
local function attached_buffer(client, exclude)
  local function usable(buf)
    return buf and buf ~= exclude and client.attached_buffers[buf]
      and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
  end
  if usable(M.buf) then return M.buf end
  local current = vim.api.nvim_get_current_buf()
  if usable(current) then return current end
  for buf in pairs(client.attached_buffers) do if usable(buf) then return buf end end
end

function M.client()
  local client = M.client_id and vim.lsp.get_client_by_id(M.client_id)
  if client and not client:is_stopped() then
    if M.buf and client.attached_buffers[M.buf] and vim.api.nvim_buf_is_valid(M.buf) then return client end
    M.buf = attached_buffer(client)
    if M.buf then return client end
  end
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    client = vim.lsp.get_clients({ bufnr = M.buf, name = "clangd" })[1]
    M.client_id = client and client.id or nil
    return client
  end
end

function M.status()
  if M.rebuilding then return " clangd 重建索引：" .. M.rebuilding .. " " end
  if M.phase == "" then return "" end
  if M.phase == "starting" then return " clangd 启动中 [..........] " end
  if M.phase == "error" then return " clangd 启动失败（:messages） " end
  if not M.client() then return " clangd 已停止 " end
  local _, task = next(M.tasks)
  if task then
    local percent = task.percentage
    local bar = "[   ...    ]"
    if percent then
      local filled = math.floor(math.max(0, math.min(100, percent)) / 10)
      bar = "[" .. string.rep("#", filled) .. string.rep(".", 10 - filled) .. "] " .. percent .. "%"
    end
    return " clangd 索引 " .. bar .. (task.message and " " .. task.message or "") .. " "
  end
  return M.phase == "indexed" and " clangd 索引就绪 " or " clangd 已连接 "
end

local function load_source(path, ticket)
  if ticket ~= generation then return end
  local ok, err = pcall(function()
    require("lazy").load({ plugins = { "nvim-lspconfig", "astrolsp" } })
    M.buf = vim.fn.bufadd(path)
    vim.fn.bufload(M.buf)
    -- Also repair a source restored before this module enabled the LSP.
    if vim.bo[M.buf].filetype == "" then
      vim.bo[M.buf].filetype = vim.filetype.match({ buf = M.buf }) or "cpp"
    end
    vim.api.nvim_exec_autocmds("FileType", { buffer = M.buf, modeline = false })
    if M.client() then M.phase = "connected" end
  end)
  if not ok then
    M.phase = "error"
    vim.notify("clangd: " .. tostring(err), vim.log.levels.ERROR)
  end
  redraw()
  vim.defer_fn(function()
    if ticket == generation and M.phase == "starting" and not M.client() then
      M.phase = "error"
      vim.notify("clangd 未能连接项目，请查看 :LspInfo 和 :LspLog", vim.log.levels.WARN)
      redraw()
    end
  end, 30000)
end

function M.start()
  if M.rebuilding then return end
  local cwd = vim.fs.normalize(vim.fn.getcwd())
  if M.cwd == cwd and (M.phase == "starting" or M.client()) then return end
  if scan_cancel then scan_cancel(); scan_cancel = nil end
  generation = generation + 1
  local ticket = generation
  M.cwd, M.buf, M.phase, M.tasks, M.client_id = cwd, nil, "", {}, nil
  -- Equal-priority markers select the nearest project. Otherwise an outer
  -- compile_commands.json can incorrectly outrank an inner CMakeLists.txt.
  local project = vim.fs.root(cwd, { { "compile_commands.json", ".clangd", "compile_flags.txt", ".git",
    "CMakeLists.txt", "GNUmakefile", "Makefile" } })
  if not project then project = only_child_project(cwd) end
  local root = project or cwd
  M.project_root = root
  local database_dir = require("clangd_config").database_dir(root)
  M.database_dir = database_dir
  if database_dir and vim.fn.filereadable(database_dir .. "/compile_commands.json") ~= 1 then
    M.phase = "error"
    vim.notify("ASTRO_CLANGD_CDB_DIR 指定目录中没有可读取的 compile_commands.json：" .. database_dir,
      vim.log.levels.ERROR)
    redraw()
    return
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.bo[buf].buftype == "" and inside(name, root) and source(name) and vim.fn.filereadable(name) == 1 then
      M.phase = "starting"
      load_source(name, ticket)
      return
    end
  end
  local function fallback()
    -- Small projects can use clangd's fallback flags. fd obeys ignore rules and
    -- stops at the first source; it never blocks the editor while traversing.
    local command = { vim.env.ASTRONVIM_ROOT .. "/bin/fd", "--type", "f", "--max-results", "1",
      "-e", "c", "-e", "cc", "-e", "cpp", "-e", "cxx", "-e", "cu" }
    -- Starting in HOME or a parent of many projects must not index an arbitrary
    -- descendant repository. Unmarked directories only inspect direct sources.
    if not project then vim.list_extend(command, { "--max-depth", "1" }) end
    vim.list_extend(command, { ".", root })
    vim.system(command,
      { text = true, timeout = 10000 }, vim.schedule_wrap(function(result)
        if ticket ~= generation then return end
        local path = (result.stdout or ""):match("([^\r\n]+)")
        if path then
          M.phase = "starting"
          load_source(path, ticket)
        else
          M.phase = ""
          redraw()
        end
      end))
  end
  local databases = database_dir and { database_dir .. "/compile_commands.json" }
    or { root .. "/compile_commands.json", root .. "/build/compile_commands.json" }
  local function scan(index)
    if ticket ~= generation then return end
    if not databases[index] then fallback(); return end
    if vim.fn.filereadable(databases[index]) ~= 1 then scan(index + 1); return end
    M.phase = "starting"
    redraw()
    scan_cancel = require("compile_source").find(databases[index], root, function(file)
      return inside(file, root) and source(file) and vim.fn.filereadable(file) == 1
    end, function(file)
      scan_cancel = nil
      if ticket ~= generation then return end
      if file then load_source(file, ticket) else scan(index + 1) end
    end)
  end
  scan(1)
end

function M.rebuild() require("index_rebuild").run(M) end

function M.pick(kinds)
  local buf = vim.api.nvim_get_current_buf()
  if #vim.lsp.get_clients({ bufnr = buf, method = method }) == 0 then
    local client = M.client()
    if not client or not client.initialized then
      M.start()
      vim.notify("clangd 正在启动，请等底部状态栏就绪后再搜索。", vim.log.levels.INFO)
      return
    end
    buf = M.buf
  end
  local progress_event, retry_pending
  local clients = vim.lsp.get_clients({ bufnr = buf, method = method })
  local client_ids = {}
  for _, client in ipairs(clients) do client_ids[client.id] = true end
  return require("snacks").picker.lsp_workspace_symbols {
    filter = {
      default = kinds or true,
      transform = function(_, filter)
        filter.current_buf = buf
        filter.search = filter.search:gsub("%s+", "")
      end,
    },
    on_show = function(picker)
      -- A query issued while cached/background index data is loading may be
      -- empty. Retry on real progress completion, without replacing user input.
      progress_event = vim.api.nvim_create_autocmd("LspProgress", {
        callback = function(ev)
          if client_ids[ev.data.client_id] and ev.data.params.value.kind == "end" and not retry_pending then
            retry_pending = true
            vim.defer_fn(function()
              retry_pending = false
              if not picker.closed and picker:count() == 0 then picker:find() end
            end, 50)
          end
        end,
      })
    end,
    on_close = function() if progress_event then pcall(vim.api.nvim_del_autocmd, progress_event) end end,
  }
end

function M.setup()
  local group = vim.api.nvim_create_augroup("PortableWorkspaceLsp", { clear = true })
  -- Neovim 0.12 moved these to :lsp/checkhealth; retain the documented aliases.
  for name, command in pairs {
    LspRestart = "lsp restart clangd", LspInfo = "checkhealth vim.lsp",
  } do
    if vim.fn.exists(":" .. name) == 0 then
      vim.api.nvim_create_user_command(name, function() vim.cmd(command) end, {})
    end
  end
  if vim.fn.exists(":LspLog") == 0 then
    vim.api.nvim_create_user_command("LspLog", function() vim.cmd.edit(vim.lsp.log.get_filename()) end, {})
  end
  vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, { group = group, callback = function() vim.schedule(M.start) end })
  vim.api.nvim_create_autocmd("LspAttach", { group = group, callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client.name == "clangd" and client.config.root_dir == M.project_root
      and (not M.buf or not vim.api.nvim_buf_is_valid(M.buf) or not vim.api.nvim_buf_is_loaded(M.buf)) then
      M.buf = ev.buf
    end
    if client and client.name == "clangd" and ev.buf == M.buf then
      if M.client_id ~= client.id then M.tasks = {} end
      M.client_id = client.id
      M.phase = "connected"
      redraw()
    end
  end })
  vim.api.nvim_create_autocmd("LspProgress", { group = group, callback = function(ev)
    local client = M.client()
    if not client or ev.data.client_id ~= client.id then return end
    local token, value = ev.data.params.token, ev.data.params.value
    if value.kind == "end" then
      M.tasks[token] = nil
      M.phase = "indexed"
    else
      M.tasks[token] = vim.tbl_extend("force", M.tasks[token] or {}, value)
    end
    redraw()
  end })
  vim.api.nvim_create_autocmd("LspDetach", { group = group, callback = function(ev)
    vim.schedule(function()
      if ev.buf == M.buf and ev.data.client_id == M.client_id then
        local client = vim.lsp.get_client_by_id(M.client_id)
        if client and not client:is_stopped() then M.buf = attached_buffer(client, ev.buf) end
      end
      redraw()
    end)
  end })
end

return M
