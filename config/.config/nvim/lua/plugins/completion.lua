return {
	{
		"Saghen/blink.cmp",
		version = "*",
		event = "InsertEnter",
		dependencies = {
			"rafamadriz/friendly-snippets",
			"L3MON4D3/LuaSnip",
		},
		config = function()
			require("luasnip.loaders.from_vscode").lazy_load()

			require("blink.cmp").setup({
				snippets = { preset = "luasnip" },
				keymap = {
					preset = "default",
					-- Show/select the first item, but never insert it automatically.
					-- Accept only when the user explicitly presses Tab.
					["<Tab>"] = { "accept", "fallback" },
					["<CR>"] = { "fallback" },
					-- Cancel this completion word. If no menu is open, keep the
					-- normal Ctrl-D delete-character behavior.
					["<C-d>"] = { "cancel", "fallback" },
					["<S-Tab>"] = { "show" },
					["<S-j>"] = { "select_next", "fallback" },
					["<S-k>"] = { "select_prev", "fallback" },
				},
				completion = {
					list = {
						-- A short list is faster to sort, draw, and navigate.
						max_items = 40,
						selection = { preselect = true, auto_insert = false },
					},
					menu = {
						auto_show = true,
						-- No visible border; the brighter float background keeps
						-- the menu readable (see config/theme.lua).
						border = "none",
						draw = {
							-- Do not run tree-sitter just to draw completion labels.
							columns = { { "kind_icon", "label", gap = 1 } },
						},
					},
					-- Documentation requires extra LSP resolve requests and redraws.
					-- Use the normal completion-documentation command when needed.
					documentation = { auto_show = false, window = { border = "none" } },
				},
				signature = { enabled = false, window = { border = "none" } },
				sources = {
					default = function()
						-- Buffer completion scans the complete buffer. It is useful for
						-- normal files, but disastrous for a 9 MB one-line HTML file.
						if vim.b.bigfile then
							return { "lsp", "path", "snippets" }
						end
						return { "lsp", "path", "snippets", "buffer" }
					end,
					min_keyword_length = function()
						return vim.b.bigfile and 2 or 1
					end,
					per_filetype = {
						sql = { "lsp", "snippets", "buffer" },
					},
					providers = {
						lsp = {
							score_offset = 90,
							max_items = 40,
							timeout_ms = 80,
						},
						path = {
							max_items = 20,
							timeout_ms = 30,
						},
						buffer = {
							max_items = 20,
							timeout_ms = 30,
						},
					},
				},
			})
		end,
	},
}
