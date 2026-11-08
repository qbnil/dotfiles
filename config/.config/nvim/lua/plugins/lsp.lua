return {
	{
		"mason.nvim",
		"neovim/nvim-lspconfig",
		"mason-org/mason.nvim",
		"mason-org/mason-lspconfig.nvim",
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		"b0o/SchemaStore.nvim",
	},
	{
		"neovim/nvim-lspconfig",
		-- LSP initialization is deferred until the first UI idle point. This
		-- keeps opening a large document independent of server startup time.
		event = "VeryLazy",
		dependencies = {
			"mason.nvim",
			"mason-lspconfig.nvim",
			"mason-tool-installer.nvim",
			"b0o/SchemaStore.nvim",
		},
		config = function()
			require("mason").setup()
			require("mason-lspconfig").setup({})
			require("mason-tool-installer").setup({
				ensure_installed = {
					"stylua",
					"prettierd",
					"eslint",
					"lua_ls",
					"tailwindcss-language-server",
					"ts_ls",
					"html-lsp",
					"emmet-language-server",
					"gopls",
					"sqls",
					"jsonls",
					"yamlls",
					"biome",
				},
				auto_update = false,
				run_on_start = true,
			})

			-- `htmlangular` is Neovim's filetype for HTML-like templates. The
			-- HTML server provides useful completion/hover/navigation for it,
			-- without requiring the much heavier Angular project server.
			vim.lsp.config("html", {
				filetypes = { "html", "htmlangular" },
			})
			vim.lsp.config("emmet_language_server", {
				filetypes = { "html", "htmlangular", "css", "javascriptreact", "typescriptreact" },
			})

			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("UserLspConfig", {}),
				callback = function(ev)
					vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"

					local opts = function(desc)
						return { buffer = ev.buf, silent = true, desc = desc }
					end
					vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts("Go to definition"))
					vim.keymap.set("n", "gK", vim.lsp.buf.hover, opts("Hover documentation"))
					vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts("Go to implementation"))
					vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts("Go to type definition"))
					vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts("Rename symbol"))
					vim.keymap.set("n", "gr", vim.lsp.buf.references, opts("Find references"))

					vim.keymap.set({ "n", "v" }, "<leader>ca", function()
						require("tiny-code-action").code_action()
					end, opts("Code action"))

					vim.keymap.set("n", "<leader>d", function()
						vim.diagnostic.open_float({
							border = "none",
						})
					end, opts("Show diagnostics float"))
				end,
			})

			-- Trigger setup for a file that was already open when this lazy
			-- plugin loaded, without making the initial file read wait for LSP.
			vim.defer_fn(function()
				local buf = vim.api.nvim_get_current_buf()
				if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype ~= "" then
					vim.api.nvim_exec_autocmds("FileType", { buffer = buf })
				end
			end, 150)

			-- The full HTML server is useful for navigation, completion, hover,
			-- and diagnostics, but it must not repeatedly revalidate a huge
			-- embedded document. Keep it attached; reduce its diagnostic churn.
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("LargeFileLsp", { clear = true }),
				callback = function(ev)
					if not vim.b[ev.buf].bigfile_lsp then
						return
					end
					vim.diagnostic.enable(false, { bufnr = ev.buf })
					vim.b[ev.buf].bigfile_lsp_client = ev.data.client_id
				end,
			})
		end,
	},
}
