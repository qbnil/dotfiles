return {
	{
		"stevearc/conform.nvim",
		event = "VeryLazy",
		dependencies = { "windwp/nvim-ts-autotag" },
		config = function()
			-- conform runs external formatters by name; mason installs them here.
			-- Make sure that directory is on PATH before conform resolves them.
			local mason_bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
			if vim.fn.isdirectory(mason_bin) == 1 and not (vim.env.PATH or ""):find(mason_bin, 1, true) then
				vim.env.PATH = mason_bin .. ":" .. (vim.env.PATH or "")
			end

			require("conform").setup({
				format_on_save = function(bufnr)
					-- Do not format multi-megabyte buffers on save.
					if vim.b[bufnr].bigfile then
						return nil
					end
					return {
						timeout_ms = 8000,
						lsp_format = "fallback",
					}
				end,
				formatters_by_ft = {
					lua = { "stylua" },
					javascript = { "biome-check", "prettierd" },
					javascriptreact = { "biome-check", "prettierd" },
					typescript = { "biome-check", "prettierd" },
					typescriptreact = { "biome-check", "prettierd" },
					graphql = { "prettierd" },
					go = { "goimports", "gofmt" },
					json = { "biome-check", "prettierd" },
					sql = { "sql_formatter" },
				},
				formatters = {
					sql_formatter = {
						prepend_args = { "--language", "postgresql" },
					},
					prettierd = {
						condition = function(_, ctx)
							return vim.fs.root(ctx.filename, { "biome.json" }) == nil
						end,
					},
				},
			})

			-- <leader>f formats the whole buffer in Normal mode and the selected
			-- lines in Visual mode.
			vim.keymap.set({ "n", "v" }, "<leader>f", function()
				require("conform").format({
					async = true,
					lsp_format = "fallback",
				}, function(err)
					if err then
						vim.notify(err, vim.log.levels.ERROR, { title = "Format" })
					end
				end)
			end, { silent = true, desc = "Format buffer / selection" })

			require("nvim-ts-autotag").setup()
		end,
	},
}
