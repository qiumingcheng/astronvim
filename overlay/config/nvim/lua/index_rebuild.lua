-- Rebuild only project-local clangd cache shards. Compilation commands and
-- source files are preserved; unrelated clients/workspaces keep running.
local M = {}
local uv = vim.uv
local function canonical(path) return uv.fs_realpath(path) or vim.fs.normalize(path) end
local function under(path, root) return path:sub(1, #root + 1) == root .. "/" end
local function redraw() vim.cmd.redrawstatus() end

function M.run(workspace)
  if workspace.rebuilding then return end
  local now = uv.hrtime()
  if workspace.rebuild_requested_at and now - workspace.rebuild_requested_at < 1e9 then return end
  local client = workspace.client()
  local root = workspace.project_root or (client and client.config.root_dir)
  if not root then
    vim.notify("请先进入 C/C++ 项目，等待 clangd 启动。", vim.log.levels.INFO)
    return
  end
  root = canonical(root)
  workspace.rebuild_requested_at = now
  workspace.rebuilding = "查找缓存"
  workspace.last_rebuild = { root = root, removed = 0 }
  redraw()

  local saved, seen = {}, {}
  local function restore_clients()
    if #saved > 0 then workspace.tasks = {} end
    for _, item in ipairs(saved) do
      local id = vim.lsp.start(item.config, { attach = false })
      if id then
        for buf in pairs(item.buffers) do
          if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
            vim.lsp.buf_attach_client(buf, id)
          end
        end
      end
    end
  end
  local function fail(message)
    workspace.rebuilding = nil
    workspace.last_rebuild.error = message
    -- Recovery still restores the language service if cache cleanup failed.
    restore_clients()
    redraw()
    vim.notify("重建索引失败：" .. message, vim.log.levels.ERROR)
  end

  -- Include project-local custom build directories, and never follow symlinks
  -- into another project. NUL output also handles spaces in project paths.
  vim.system({ vim.env.ASTRONVIM_ROOT .. "/bin/fd", "--hidden", "--no-ignore",
    "--type", "d", "--full-path", "--prune", "--print0", "--exclude", ".git",
    "/\\.cache/clangd/index$", root }, { timeout = 15000 }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then fail(result.stderr or "无法查找索引缓存"); return end
    local caches, unique = {}, {}
    local function add_cache(path)
      if unique[path] or not uv.fs_stat(path) then return end
      local real = canonical(path)
      assert(under(real, root) and real:sub(-20) == "/.cache/clangd/index", "缓存路径不安全：" .. path)
      unique[path] = true
      caches[#caches + 1] = path
    end
    local ok, err = pcall(function()
      for path in (result.stdout or ""):gmatch("([^%z]+)") do add_cache(path:gsub("/$", "")) end
      -- Explicit checks also catch a symlinked standard cache directory.
      add_cache(root .. "/.cache/clangd/index")
      add_cache(root .. "/build/.cache/clangd/index")
    end)
    if not ok then fail(tostring(err)); return end
    workspace.rebuilding = "停止语言服务"
    redraw()
    local deadline = uv.hrtime() + 30 * 1e9
    local timed_out = false
    local function stop_and_clear()
      -- Files opened during shutdown may start another client. Include it,
      -- and wait for real process exit before touching any cache shards.
      local active = false
      for _, c in ipairs(vim.lsp.get_clients({ name = "clangd", _uninitialized = true })) do
        if canonical(c.config.root_dir or "") == root or c == client then
          active = true
          if not seen[c.id] then
            seen[c.id] = true
            saved[#saved + 1] = { config = c.config, buffers = vim.deepcopy(c.attached_buffers) }
            c:stop(false)
          end
        end
      end
      for id in pairs(seen) do
        if vim.lsp.get_client_by_id(id) then active = true end
      end
      if active then
        if uv.hrtime() > deadline and not timed_out then
          timed_out = true
          workspace.rebuilding = "等待退出（重建已取消）"
          vim.notify("clangd 退出较慢，本次不清理缓存；退出后将自动恢复语言服务。", vim.log.levels.WARN)
          redraw()
        end
        vim.defer_fn(stop_and_clear, 50)
        return
      end
      if timed_out then fail("等待退出超时，已保留缓存并恢复语言服务"); return end
      workspace.rebuilding = "清理缓存"
      redraw()
      local cleaned, cleanup_error = pcall(function()
        for _, cache in ipairs(caches) do
          assert(under(canonical(cache), root), "缓存路径已变化：" .. cache)
          local scan, scan_error = uv.fs_scandir(cache)
          assert(scan, scan_error)
          while true do
            local name, kind = uv.fs_scandir_next(scan)
            if not name then break end
            if name:match("%.idx$") and (kind == "file" or kind == "link") then
              assert(uv.fs_unlink(cache .. "/" .. name))
              workspace.last_rebuild.removed = workspace.last_rebuild.removed + 1
            end
          end
        end
      end)
      if not cleaned then fail(tostring(cleanup_error)); return end
      workspace.rebuilding = nil
      workspace.phase = "starting"
      workspace.tasks = {}
      restore_clients()
      if #saved == 0 then
        workspace.phase = ""
        workspace.start()
      end
      redraw()
      vim.notify("已清理 " .. workspace.last_rebuild.removed .. " 个项目索引缓存，正在重新索引。", vim.log.levels.INFO)
    end
    stop_and_clear()
  end))
end

return M
