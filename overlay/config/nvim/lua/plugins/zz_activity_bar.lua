return {
  {
    "AstroNvim/astrocore",
    opts = function(_, opts)
      opts.autocmds.portable_activity_bar = {
        { event = "VimEnter", callback = function()
          require("activity_bar").setup()
          require("window_scrollbars").setup()
          require("control_tooltips").setup()
        end },
      }
      for _, mode in ipairs({ "n", "i", "x", "s", "t" }) do
        opts.mappings[mode] = opts.mappings[mode] or {}
        -- Vim treats a third/fourth click as text selection. The rail and run
        -- buttons remain buttons; editor multi-click selection stays native.
        -- Dispatch by the clicked window because mappings resolve in the
        -- previously focused buffer, which is usually the editor.
        for _, key in ipairs({ "<3-LeftMouse>", "<4-LeftMouse>" }) do
          opts.mappings[mode][key] = {
            function()
              if require("window_scrollbars").mouse(key) then return end
              -- A rapid toolbar click followed by a border drag may arrive as
              -- the third/fourth click. Give separators their native press.
              if require("window_mouse").route(key) then return end
              local pos = vim.fn.getmousepos()
              if pos.winid ~= 0 and vim.api.nvim_win_is_valid(pos.winid) then
                local ft = vim.bo[vim.api.nvim_win_get_buf(pos.winid)].filetype
                if ft == "astro_activity_bar" or ft == "astro_run_debug" then
                  require("control_tooltips").hide()
                  require("activity_bar").mouse()
                  return
                end
              end
              vim.api.nvim_feedkeys(vim.keycode(key), "n", false)
            end,
            desc = "Mouse selection / activity buttons",
          }
        end
        for _, key in ipairs({ "<2-LeftDrag>", "<2-LeftRelease>", "<3-LeftDrag>", "<3-LeftRelease>", "<4-LeftDrag>", "<4-LeftRelease>" }) do
          opts.mappings[mode][key] = {
            function()
              if require("window_scrollbars").mouse(key) then return end
              if require("window_mouse").route(key) then return end
              vim.api.nvim_feedkeys(vim.keycode(key), "n", false)
            end,
            desc = "Mouse selection / border drag",
          }
        end
        for _, key in ipairs({ "<LeftMouse>", "<2-LeftMouse>", "<LeftDrag>", "<LeftRelease>", "<MouseMove>" }) do
          local original = opts.mappings[mode][key]
          local callback = original and original[1]
          opts.mappings[mode][key] = {
            function()
              if key == "<MouseMove>" then require("control_tooltips").hover(); return end
              require("control_tooltips").hide()
              if require("portable").picker_mouse(key) then return end
              if require("window_scrollbars").mouse(key) then return end
              if require("window_mouse").route(key) then return end
              if key ~= "<LeftDrag>" and key ~= "<LeftRelease>" and require("activity_bar").mouse() then return end
              if type(callback) == "function" then callback()
              else vim.api.nvim_feedkeys(vim.keycode(key), "n", false) end
            end,
            desc = original and original.desc or "Mouse / activity bar",
          }
        end
      end
    end,
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = function(_, opts)
      for _, key in ipairs({ "<LeftMouse>", "<2-LeftMouse>" }) do
        local original = opts.window.mappings[key]
        opts.window.mappings[key] = function(state)
          require("control_tooltips").hide()
          if require("window_scrollbars").mouse(key) then return end
          if require("window_mouse").route(key) then return end
          if require("activity_bar").mouse() then return end
          -- Buffer mappings resolve in the previously focused tree. Route an
          -- outside press to its actual target instead of consuming it here.
          if vim.fn.getmousepos().winid ~= state.winid then
            local mouse = require("tree_mouse")
            if key == "<2-LeftMouse>" then mouse.route_open() else mouse.route_click() end
            return
          end
          if type(original) == "function" then original(state) end
        end
      end
    end,
  },
}
