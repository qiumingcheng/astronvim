-- Native DAP output is a stream: append each chunk, not the session history.
local M = {}
local states = setmetatable({}, { __mode = "k" })
local owners = setmetatable({}, { __mode = "v" })

function M.reset(session)
  states[session] = { chunks = {}, last = "" }
end

function M.append(session, text, separate_line)
  if text == "" then return end
  local s = states[session]
  if not s then M.reset(session); s = states[session] end
  if separate_line and s.last ~= "" and s.last ~= "\n" then text = "\n" .. text end
  local buf = require("dapui").elements.console.buffer()
  local modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  local ok, err = pcall(function()
    if owners[buf] ~= s then
      -- Only rebuild when changing sessions or recreating a wiped Console.
      -- Chunks also retain output while the Console is hidden.
      vim.api.nvim_buf_set_lines(buf, 0, -1, false,
        vim.split(table.concat(s.chunks), "\n", { plain = true }))
      owners[buf] = s
    end
    local row = vim.api.nvim_buf_line_count(buf) - 1
    local col = #vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    vim.api.nvim_buf_set_text(buf, row, col, row, col, vim.split(text, "\n", { plain = true }))
    s.chunks[#s.chunks + 1] = text
    s.last = text:sub(-1)
    -- This is generated output, not an unsaved edit. A later CodeLLDB session
    -- must be able to reuse this buffer for runInTerminal.
    vim.bo[buf].modified = false
  end)
  vim.bo[buf].modifiable = modifiable
  if not ok then error(err, 0) end
end

return M
