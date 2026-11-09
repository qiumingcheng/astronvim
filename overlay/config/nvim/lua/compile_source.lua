-- Locate a usable translation unit without decoding the entire compilation
-- database on the UI thread. Each scheduled turn examines at most 64 KiB.
local M = {}
local uv = vim.uv
function M.find(database, root, accept, callback)
  local fd, done, offset = nil, false, 0
  local opened, depth, quoted, escaped, need_value = false, 0, false, false, true
  local parts = {}
  local function finish(path)
    if done then return end
    done = true
    if fd then uv.fs_close(fd); fd = nil end
    callback(path)
  end
  local function consume(chunk)
    local first = depth > 0 and 1 or nil
    for i = 1, #chunk do
      local b = chunk:byte(i)
      if depth > 0 then
        if quoted then
          if escaped then escaped = false
          elseif b == 92 then escaped = true
          elseif b == 34 then quoted = false end
        elseif b == 34 then quoted = true
        elseif b == 123 or b == 91 then depth = depth + 1
        elseif b == 125 or b == 93 then
          depth = depth - 1
          if depth == 0 then
            parts[#parts + 1] = chunk:sub(first, i)
            local ok, entry = pcall(vim.json.decode, table.concat(parts))
            parts, first, need_value = {}, nil, false
            if not ok or type(entry) ~= "table" then finish(); return end
            if type(entry.file) == "string" then
              local directory = type(entry.directory) == "string" and entry.directory or root
              local file = vim.fs.normalize(entry.file:sub(1, 1) == "/" and entry.file or directory .. "/" .. entry.file)
              if accept(file) then finish(file); return end
            end
          end
        end
      elseif b ~= 32 and b ~= 9 and b ~= 10 and b ~= 13 then
        if not opened then
          if b ~= 91 then finish(); return end
          opened = true
        elseif b == 93 then finish(); return
        elseif b == 44 and not need_value then need_value = true
        elseif b == 123 and need_value then depth, first = 1, i
        else finish(); return end
      end
    end
    if first then parts[#parts + 1] = chunk:sub(first) end
  end
  local function pump()
    if done then return end
    uv.fs_read(fd, 65536, offset, vim.schedule_wrap(function(err, chunk)
      if done then return end
      if err or not chunk or #chunk == 0 then finish(); return end
      offset = offset + #chunk
      consume(chunk)
      if not done then pump() end
    end))
  end
  uv.fs_open(database, "r", 438, vim.schedule_wrap(function(err, descriptor)
    if done then if descriptor then uv.fs_close(descriptor) end; return end
    if err then finish(); return end
    fd = descriptor
    pump()
  end))
  return function()
    done = true
    if fd then uv.fs_close(fd); fd = nil end
  end
end
return M
