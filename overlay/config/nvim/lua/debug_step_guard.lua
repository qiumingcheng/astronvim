-- Do not let repeated execution controls fall back to another stopped thread.
local M = {}

function M.setup(dap)
  if M.installed then return end
  M.installed = true
  for _, name in ipairs { "step_over", "step_into", "step_out", "step_back", "reverse_continue", "continue" } do
    local original = dap[name]
    dap[name] = function(opts)
      local session = dap.session()
      -- Keep the normal launch/configuration chooser and explicit new sessions.
      if name == "continue" and (not session or (opts and opts.new)) then
        return original(opts)
      end
      if not session or session.closed then return end
      local thread_id = session.stopped_thread_id
      local thread = thread_id and session.threads[thread_id]
      if not thread or not thread.stopped then return end
      -- nvim-dap clears stopped_thread_id synchronously before sending a step.
      -- Use that state directly: repeated clicks are dropped, never queued, and
      -- the next stopped event automatically enables the controls again.
      return original(opts)
    end
  end
end

return M
