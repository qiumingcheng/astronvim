local M = {}

function M.setup()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("AstroLspBufferGuard", { clear = true }),
    once = true,
    callback = function()
      -- The bundled Neovim can receive a folding reply after the buffer or
      -- capability has been destroyed. Its version check accepts nil == nil,
      -- then creates an InsertLeave autocmd for the deleted buffer.
      require("vim.lsp._folding_range")
      local state = require("vim.lsp._capability").all.folding_range
      if not state or state._astro_buffer_guard then return end
      local original = state.multi_handler
      if type(original) ~= "function" then return end
      state._astro_buffer_guard = true
      state.multi_handler = function(self, ...)
        if state.active[self.bufnr] ~= self or not vim.api.nvim_buf_is_loaded(self.bufnr) then return end
        return original(self, ...)
      end
    end,
  })
end

return M
