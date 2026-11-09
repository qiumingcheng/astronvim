local M = {}
local root = vim.uv.fs_realpath(vim.fn.getcwd()) or vim.fn.getcwd()
local path = vim.fn.stdpath("state") .. "/breakpoints/" .. vim.fn.sha256(root) .. ".json"
local files, ready, restoring, queued, clear_all = {}, false, false, false, false

local function key(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return end
  if name:sub(1, #root + 1) == root .. "/" then return name:sub(#root + 2) end
  return name
end

local function warn(err)
  vim.notify("Breakpoint persistence: " .. tostring(err), vim.log.levels.WARN)
end

function M.save()
  if not ready or restoring then return end
  -- run_to_cursor temporarily replaces all breakpoints. Never persist those.
  if require("dap").listeners.before.event_stopped["dap.run_to_cursor"] then return end
  if clear_all then files = {}; clear_all = false end
  local bps = require("dap.breakpoints").get()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = key(buf)
    if name and vim.api.nvim_buf_is_loaded(buf) then
      local entries = {}
      for _, bp in ipairs(bps[buf] or {}) do
        entries[#entries + 1] = {
          line = bp.line, condition = bp.condition,
          hitCondition = bp.hitCondition, logMessage = bp.logMessage,
        }
      end
      files[name] = #entries > 0 and entries or nil
    end
  end
  local temp = path .. "." .. vim.fn.getpid() .. ".tmp"
  local ok, err = pcall(function()
    vim.fn.mkdir(vim.fs.dirname(path), "p", 448)
    vim.fn.writefile({ vim.json.encode({ version = 1, root = root, files = files }) }, temp)
    assert(vim.uv.fs_chmod(temp, 384))
    assert(vim.uv.fs_rename(temp, path))
  end)
  if not ok then vim.fn.delete(temp); warn(err) end
end

local function queue_save()
  if restoring or queued then return end
  queued = true
  vim.schedule(function() queued = false; M.save() end)
end

local function restore(buf)
  local name = key(buf)
  if not name or not files[name] then return end
  local bp = require "dap.breakpoints"
  if #(bp.get(buf)[buf] or {}) > 0 then return end
  local was_restoring = restoring
  restoring = true
  for _, entry in ipairs(files[name]) do
    if entry.line <= vim.api.nvim_buf_line_count(buf) then
      bp.set({ condition = entry.condition, hit_condition = entry.hitCondition, log_message = entry.logMessage }, buf, entry.line)
    end
  end
  restoring = was_restoring
end

function M.setup()
  if ready then return end
  if vim.fn.filereadable(path) == 1 then
    local ok, data = pcall(function()
      local data = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
      assert(data.version == 1 and data.root == root and type(data.files) == "table", "invalid store")
      for name, entries in pairs(data.files) do
        assert(type(name) == "string" and type(entries) == "table", "invalid file entry")
        for _, entry in ipairs(entries) do
          assert(type(entry.line) == "number" and entry.line >= 1 and entry.line % 1 == 0, "invalid line")
          for _, field in ipairs { "condition", "hitCondition", "logMessage" } do
            assert(entry[field] == nil or type(entry[field]) == "string", "invalid breakpoint option")
          end
        end
      end
      return data
    end)
    if not ok then warn("Cannot read " .. path .. ": " .. tostring(data)); return end
    files = data.files
  end
  ready, restoring = true, true
  local bp = require "dap.breakpoints"
  -- Wrap the shared mutation entry points, including the DAP UI and mouse paths.
  -- Saving on the next event-loop turn also avoids saving an intermediate toggle.
  for _, method in ipairs { "toggle", "remove", "clear", "remove_by_id" } do
    local original = bp[method]
    bp[method] = function(...)
      local result = original(...)
      queue_save()
      return result
    end
  end
  local dap = require "dap"
  local original_clear = dap.clear_breakpoints
  dap.clear_breakpoints = function(...)
    clear_all = true
    return original_clear(...)
  end
  -- DAP may initialize inside a non-nested VimEnter/FileType autocommand.
  -- Load saved sources on the event loop so BufReadPost and FileType actually
  -- fire; setting filetype alone inside that callback leaves LSP disabled.
  vim.schedule(function()
    for name in pairs(files) do
      local filename = name:sub(1, 1) == "/" and name or root .. "/" .. name
      if vim.fn.filereadable(filename) == 1 then
        local buf = vim.fn.bufadd(filename)
        vim.fn.bufload(buf)
        restore(buf)
      end
    end
    restoring = false
  end)
  local group = vim.api.nvim_create_augroup("PortableBreakpointStore", { clear = true })
  vim.api.nvim_create_autocmd("BufReadPost", { group = group, callback = function(ev) restore(ev.buf) end })
  vim.api.nvim_create_autocmd({ "BufWritePost", "BufUnload", "VimLeavePre" }, { group = group, callback = M.save })
end

function M.autoload()
  -- Load DAP at startup only when this workspace has saved breakpoints.
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      if vim.fn.filereadable(path) == 1 then require "dap" end
    end,
  })
end

return M
