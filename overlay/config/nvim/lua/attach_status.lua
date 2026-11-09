-- Report a completed attach only after the adapter and configuration succeed.
local M = {}
local states = setmetatable({}, { __mode = "k" })
local namespace = vim.api.nvim_create_namespace "portable_attach_status"

local function state(session)
  if not states[session] then states[session] = {} end
  return states[session]
end

local function append(session, message)
  local ui = require "dapui"
  local buf = ui.elements.console.buffer()
  local lines = vim.split(message, "\n", { plain = true })
  if vim.bo[buf].buftype == "terminal" then
    -- Never send status text to a terminal channel: that would be program input.
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    local virtual = {}
    for _, line in ipairs(lines) do virtual[#virtual + 1] = { { line, "DiagnosticInfo" } } end
    vim.api.nvim_buf_set_extmark(buf, namespace, 0, 0, { virt_lines = virtual, virt_lines_above = true })
    return
  end
  if session.config.type == "gdb" then
    require("debug_console").append(session, message .. "\n", true)
    return
  else
    local old = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if #old == 1 and old[1] == "" then old = {} end
    vim.list_extend(old, lines)
    lines = old
  end
  local modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  -- Console output is generated text, not an unsaved user edit.
  -- Clear the internal changed flag before a later runInTerminal reuse.
  vim.bo[buf].modified = false
  vim.bo[buf].modifiable = modifiable
end

local function is_attach(session) return session.config.request == "attach" end

local function failed(session, err)
  local s = state(session)
  if s.done then return end
  s.done = true
  append(session, "[Attach 失败] " .. tostring(err))
end

local function complete(session)
  local s = state(session)
  if s.done or not s.attached or not s.configured or session.closed then return end
  if s.pid or s.verified then
    s.done = true
    local name = session.config.type == "gdb" and "GDB" or "CodeLLDB"
    append(session, string.format("[Attach 完成] PID=%s | %s", tostring(session.config.pid or s.pid or "?"), name))
  elseif not s.checking then
    -- GDB 17.2 can swallow an attach error and still answer success. Check the
    -- live target, not merely configurationDone or the attach response.
    s.checking = true
    session:request("threads", nil, function(err, response)
      if s.done or session.closed then return end
      if err or not response or not next(response.threads or {}) then
        failed(session, err or "未连接到目标进程（PID 不存在或无权 attach）")
      else
        s.verified = true
        complete(session)
      end
    end)
  end
end

function M.setup(dap)
  dap.listeners.after.event_process.portable_attach_status = function(session, body)
    if is_attach(session) then state(session).pid = body.systemProcessId; complete(session) end
  end
  -- CodeLLDB 1.12.3 reports failed attach responses with command="". nvim-dap
  -- dispatches listeners by that response command, while the original request
  -- remains available as the fourth argument.
  dap.listeners.before[""].portable_attach_status = function(session, err, _, request)
    if err and request and request.request == "attach" then failed(session, err) end
  end
  dap.listeners.before.attach.portable_attach_status = function(session, err)
    if not is_attach(session) then return end
    if err then failed(session, err) else state(session).attached = true; complete(session) end
  end
  dap.listeners.after.configurationDone.portable_attach_status = function(session, err)
    if not is_attach(session) then return end
    if err then failed(session, err) else state(session).configured = true; complete(session) end
  end
  dap.listeners.after.event_initialized.portable_attach_status = function(session)
    if is_attach(session) and not session.capabilities.supportsConfigurationDoneRequest then
      state(session).configured = true
      complete(session)
    end
  end
  dap.listeners.before.disconnect.portable_attach_status = function(session)
    if is_attach(session) and not state(session).done then
      state(session).done = true
      append(session, "[Attach 取消] 连接尚未完成")
    end
  end
end
return M
