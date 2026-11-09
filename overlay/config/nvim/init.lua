-- Every persistent editor path is selected by env.sh, relative to its location.
assert(vim.env.ASTRONVIM_ROOT, "Source env.sh and start this portable installation with bin/astronvim")
-- Keep Neovim's embedded loader on ordinary paths. The bundled Lua suffixes
-- need at most 105 encoded bytes; deeper roots need the long-name cache fix.
for _, path in ipairs({ vim.fn.stdpath("data"), vim.fn.stdpath("config"), vim.env.VIMRUNTIME }) do
  if #vim.uri_encode(path, "rfc2396") > 150 then
    local previous_loader = package.loaded["vim.loader"]
    if previous_loader and previous_loader.enabled then previous_loader.enable(false) end
    local portable_loader = assert(loadfile(vim.env.VIMRUNTIME .. "/lua/vim/loader.lua"))()
    package.loaded["vim.loader"], vim.loader = portable_loader, portable_loader
    break
  end
end
vim.g.loaded_python3_provider = 0
vim.g.loaded_python_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
-- OSC 52 copies through the terminal without xclip/Node/Python/desktop dependencies.
vim.g.clipboard = require("editor_actions").clipboard()
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")
require("lazy").setup({
  {
    "AstroNvim/AstroNvim", version = "6.1.0", branch = "main", import = "astronvim.plugins",
    opts = {
      mapleader = " ", maplocalleader = ",",
      icons_enabled = vim.env.ASTRO_ICONS == "1",
      pin_plugins = true, update_notifications = false,
    },
  },
  { import = "plugins" },
}, {
  checker = { enabled = false },
  change_detection = { notify = false },
  install = { missing = false, colorscheme = { "vscode", "habamax" } },
  concurrency = 4,
  git = { timeout = 180 },
  rocks = { enabled = false },
  performance = { rtp = { disabled_plugins = { "gzip", "netrwPlugin", "tarPlugin", "tohtml", "zipPlugin" } } },
})
require("window_labels").setup()
require("workspace_lsp").setup()
