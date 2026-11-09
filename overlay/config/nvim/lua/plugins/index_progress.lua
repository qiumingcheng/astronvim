return {
  {
    "rebelot/heirline.nvim",
    opts = function(_, opts)
      table.insert(opts.statusline, 8, {
        provider = function() return require("workspace_lsp").status():gsub("%%", "%%%%") end,
        hl = { fg = "#dcdcaa" },
      })
      table.insert(opts.statusline, 9, {
        condition = function() return require("workspace_lsp").phase ~= "" end,
        provider = function()
          return require("workspace_lsp").rebuilding and " [重建中] " or " [重建索引] "
        end,
        hl = { fg = "#4fc1ff", bold = true },
        on_click = {
          name = "portable_rebuild_index_click",
          callback = function(_, _, _, button)
            if button == "l" then vim.schedule(function() require("workspace_lsp").rebuild() end) end
          end,
        },
      })
    end,
  },
}
