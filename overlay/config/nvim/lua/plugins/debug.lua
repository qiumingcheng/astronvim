return {
  {
    "mfussenegger/nvim-dap",
    init = function() require("breakpoint_store").autoload() end,
    config = function()
      require "astronvim.plugins.configs.nvim-dap"()
      local dap = require "dap"
      require("process_picker").setup()
      require("debug_step_guard").setup(dap)
      require("gdb_backend").setup(dap)
      require("attach_status").setup(dap)
      require("debug_highlight").setup()
      require("breakpoint_store").setup()
      -- Keep the Scopes pane focused on the selected function.  DAP adapters
      -- commonly return Arguments, Locals, Globals and Registers together;
      -- Arguments and Locals are both part of the selected function frame.
      if not dap.listeners.before.scopes.portable_locals_only then
        dap.listeners.before.scopes.portable_locals_only = function(_, err, body)
          if err or not body or type(body.scopes) ~= "table" then return end
          local locals = {}
          for _, scope in ipairs(body.scopes) do
            local name = type(scope.name) == "string" and scope.name:lower() or ""
            if name == "argument" or name == "arguments" or name == "local" or name == "locals"
              or scope.presentationHint == "arguments" or scope.presentationHint == "locals" then
              locals[#locals + 1] = scope
            end
          end
          body.scopes = locals
        end
      end
      dap.adapters.codelldb = {
        type = "server", port = "${port}",
        executable = { command = vim.env.ASTRONVIM_ROOT .. "/bin/codelldb", args = { "--port", "${port}" } },
        enrich_config = function(config, done) require("attach_policy").enrich(config, done) end,
      }
      dap.adapters.lldb = dap.adapters.codelldb
      local configurations = {
        {
          name = "C/C++: Launch executable (CodeLLDB)", type = "codelldb", request = "launch",
          program = function() return vim.fn.input("Executable: ", vim.fn.getcwd() .. "/", "file") end,
          cwd = "${workspaceFolder}", stopOnEntry = false, args = {}, terminal = "integrated",
        },
        {
          name = "C/C++: Attach to process", type = "codelldb", request = "attach",
          pid = require("dap.utils").pick_process, cwd = "${workspaceFolder}",
        },
      }
      dap.configurations.cpp = configurations
      dap.configurations.c = vim.deepcopy(configurations)
      dap.configurations.rust = vim.deepcopy(configurations)
      if require("gdb_backend").available() then
        for _, ft in ipairs { "cpp", "c" } do
          table.insert(dap.configurations[ft], {
            name = "C/C++: Launch executable (GDB / ARM TLS)", type = "gdb", request = "launch",
            program = configurations[1].program, cwd = "${workspaceFolder}", args = {},
          })
          table.insert(dap.configurations[ft], {
            name = "C/C++: Attach to process (GDB / ARM TLS)", type = "gdb", request = "attach",
            pid = require("dap.utils").pick_process, cwd = "${workspaceFolder}",
          })
        end
      end
      local vscode = require "dap.ext.vscode"
      vscode.type_to_filetypes.lldb = { "c", "cpp", "rust" }
      vscode.type_to_filetypes.codelldb = { "c", "cpp", "rust" }
      vscode.type_to_filetypes.gdb = { "c", "cpp" }
    end,
  },
  {
    "rcarriga/nvim-dap-ui",
    opts = {
      layouts = {
        { position = "left", size = 36, elements = {
          { id = "scopes", size = 0.35 }, { id = "watches", size = 0.2 },
          { id = "stacks", size = 0.3 }, { id = "breakpoints", size = 0.15 },
        } },
        { position = "bottom", size = 12, elements = { { id = "repl", size = 0.6 }, { id = "console", size = 0.4 } } },
      },
      icons = { expanded = "v", collapsed = ">", current_frame = ">" },
      controls = { icons = { pause = "||", play = ">", step_into = "v", step_over = ">|", step_out = "^", step_back = "<", run_last = ">>", terminate = "X", disconnect = "x" } },
    },
    config = function(_, opts)
      local dap, ui = require "dap", require "dapui"
      require("debug_variables_mouse").setup(opts)
      ui.setup(opts)
      -- Keep every line returned by the adapter; the pane scrollbars provide
      -- navigation instead of the default 100-line value truncation.
      require("dapui.config").render.max_value_lines = nil
      -- Terminal shrinking can temporarily clamp the bottom DAP layout.  Do
      -- not call ui.open() here: it snapshots the clamped dimensions.  Reapply
      -- each layout's saved proportions after VimResized instead.
      local resize_pending = false
      local resize_group = vim.api.nvim_create_augroup("PortableDapUiResize", { clear = true })
      vim.api.nvim_create_autocmd("VimResized", {
        group = resize_group,
        callback = function()
          if resize_pending then return end
          resize_pending = true
          vim.defer_fn(function()
            resize_pending = false
            local ok, windows = pcall(require, "dapui.windows")
            if not ok or type(windows.layouts) ~= "table" then return end
            for _, layout in ipairs(windows.layouts) do
              if layout:is_open() then pcall(layout.resize, layout) end
            end
          end, 20)
        end,
      })
      require("window_labels").setup_debug()
      local debug_running = false

      -- nvim-dap-ui keeps the last scopes/threads response while the adapter is
      -- running. Guard these two renderers so a continued process never shows
      -- variables or stack frames from an old stopped frame.
      local function clear_element(element)
        local ok, buffer = pcall(element.buffer)
        if not ok or not vim.api.nvim_buf_is_valid(buffer) then return end
        local modifiable = vim.bo[buffer].modifiable
        vim.bo[buffer].modifiable = true
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "" })
        vim.api.nvim_buf_clear_namespace(buffer, require("dapui.render.canvas").namespace, 0, -1)
        vim.bo[buffer].modifiable = modifiable
      end

      for _, name in ipairs { "scopes", "stacks" } do
        local element = ui.elements[name]
        local render = element.render
        element.render = function(...)
          if debug_running then
            clear_element(element)
            return
          end
          return render(...)
        end
      end

      local function refresh_debug_state(running)
        debug_running = running
        if running then
          for _, name in ipairs { "scopes", "stacks" } do clear_element(ui.elements[name]) end
        end
      end

      dap.listeners.after.event_initialized.portable_running_state = function()
        refresh_debug_state(true)
      end
      dap.listeners.after.event_continued.portable_running_state = function()
        refresh_debug_state(true)
      end
      -- GDB's native DAP acknowledges execution requests without emitting a
      -- continued event. Clear the old frame data on its successful responses.
      for _, request in ipairs { "continue", "next", "stepIn", "stepOut" } do
        dap.listeners.after[request].portable_gdb_running_state = function(session, err)
          if session.config.type == "gdb" and not err and not session.stopped_thread_id then refresh_debug_state(true) end
        end
      end
      dap.listeners.after.event_stopped.portable_running_state = function()
        -- Scopes listeners render when the new frame arrives. Do not query the
        -- old scope/variable references at the stopped event itself.
        refresh_debug_state(false)
      end

      local explorer_was_open = false
      dap.listeners.after.event_initialized.portable_ui = function()
        explorer_was_open = false
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then explorer_was_open = true end
        end
        if explorer_was_open then vim.cmd "Neotree close" end
        ui.open()
      end
      local function close()
        debug_running = false
        ui.close()
        if explorer_was_open then
          explorer_was_open = false
          vim.schedule(function() vim.cmd "Neotree show position=left" end)
        end
      end
      dap.listeners.before.event_terminated.portable_ui = close
      dap.listeners.before.event_exited.portable_ui = close
      dap.listeners.after.disconnect.portable_ui = close
    end,
  },
}
