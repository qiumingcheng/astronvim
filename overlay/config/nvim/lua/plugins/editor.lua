local title_token = vim.env.ASTRO_VSCODE_TITLE_TOKEN
local terminal_title = title_token and title_token:match("^[%w-]+$")
  and ("AstroNvimPortable:active:" .. title_token) or nil

return {
  { "Mofiqul/vscode.nvim", lazy = false, priority = 1000, opts = { style = "dark" } },
  { "AstroNvim/astroui", opts = { colorscheme = "vscode" } },
  {
    "AstroNvim/astrocore",
    opts = {
      options = { opt = { relativenumber = false, number = true, mouse = "a", mousemodel = "extend", wrap = false, scrolloff = 5, winborder = "rounded", clipboard = "", title = true, titlestring = terminal_title, laststatus = 3, fillchars = { vert = "┃", vertleft = "┃", vertright = "┃", verthoriz = "╋", horiz = "━", horizup = "━", horizdown = "━" } } },
      features = { large_buf = { size = 1024 * 1024, lines = 20000 } },
      rooter = { enabled = false },
      treesitter = { auto_install = false, ensure_installed = {} },
      mappings = require "idea_keys",
      autocmds = {
        portable_ui = {
          { event = "VimEnter", callback = function()
            if #vim.api.nvim_list_uis() == 0 then return end
            vim.schedule(function()
              local win = vim.api.nvim_get_current_win()
              vim.cmd "Neotree show position=left"
              if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
            end)
          end },
        },
      },
    },
  },
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = { enabled = false }, image = { enabled = false },
      picker = {
        live_search_delay = 80,
        layout = { preset = "default" },
        sources = {
          -- File navigation includes generated/ignored sources as well. The
          -- compilation index is independent of fd's ignore rules; hiding
          -- these paths here made even indexed files impossible to open.
          -- Alt+I retains the opt-in filtered view for large build trees.
          files = {
            hidden = true, ignored = true, follow = false,
            exclude = { ".git", "**/.cache/clangd/index" },
          },
          grep = { hidden = true, exclude = { ".git" } },
        },
      },
    },
  },
  { "nvim-neo-tree/neo-tree.nvim", config = function(_, opts)
    require("neo-tree").setup(opts)
    local inputs = require "neo-tree.ui.inputs"
    local original_confirm = inputs.confirm
    inputs.confirm = function(message, callback)
      if not callback then return original_confirm(message) end
      vim.ui.select({ "Cancel", "Confirm" }, { prompt = message }, function(choice) callback(choice == "Confirm") end)
    end
  end, opts = {
    popup_border_style = "rounded",
    -- Keep complete names in the buffer so horizontal scrolling can reveal
    -- their suffixes instead of scrolling text already cut by the renderer.
    default_component_configs = { container = { width = "fit_content" } },
    window = { width = 32, position = "left", mappings = {
      ["<LeftMouse>"] = function(state) require("tree_mouse").click(state) end,
      ["<2-LeftMouse>"] = function(state) require("tree_mouse").open(state) end,
      ["<RightMouse>"] = function(state) require("tree_mouse").menu(state) end,
      ["<Esc>"] = function() vim.cmd "wincmd p" end,
    } },
    filesystem = { filtered_items = { hide_dotfiles = false, hide_gitignored = true }, follow_current_file = { enabled = true }, use_libuv_file_watcher = false },
  } },
  { "akinsho/toggleterm.nvim", opts = { direction = "horizontal", size = 12, persist_size = true } },
  { "saghen/blink.cmp", opts = { fuzzy = { implementation = "lua" }, keymap = { ["<C-n>"] = false, ["<C-p>"] = false, ["<C-e>"] = false } } },
  { "L3MON4D3/LuaSnip", build = false },
  { "nvim-treesitter/nvim-treesitter", build = false },
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "WhoIsSethDaniel/mason-tool-installer.nvim", enabled = false },
  { "jay-babu/mason-nvim-dap.nvim", enabled = false },
  { "nvimtools/none-ls.nvim", enabled = false },
  { "folke/lazydev.nvim", enabled = false },
  { "windwp/nvim-ts-autotag", enabled = false },
  { "max397574/better-escape.nvim", enabled = false },
  { "AstroNvim/astrocore", opts = function(_, opts)
    opts.treesitter.ensure_installed = {}
    opts.treesitter.auto_install = false
    opts.treesitter.auto_install_cli = false
  end },
}
