return {
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		lazy = false,
		config = function()
			local ok, ts_config = pcall(require, "nvim-treesitter.configs")
			if not ok then
				vim.schedule(function()
					pcall(function()
						require("nvim-treesitter.configs").setup({
							ensure_installed = {
								"bash",
								"css",
								"diff",
								"go",
								"gomod",
								"gowork",
								"gosum",
								"graphql",
								"html",
								"javascript",
								"jsdoc",
								"json",
								"json5",
								"lua",
								"luadoc",
								"luap",
								"markdown",
								"markdown_inline",
								"query",
								"tsx",
								"typescript",
								"vim",
								"vimdoc",
								"yaml",
							},
							highlight = {
								enable = true,
								disable = function(lang, buf)
									local max_filesize = 100 * 1024
									local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
									if ok and stats and stats.size > max_filesize then
										return true
									end
								end,
							},
							indent = { enable = true },
						})
					end)
				end)
				return
			end

			ts_config.setup({
				ensure_installed = {
					"bash",
					"css",
					"diff",
					"go",
					"gomod",
					"gowork",
					"gosum",
					"graphql",
					"html",
					"javascript",
					"jsdoc",
					"json",
					"json5",
					"lua",
					"luadoc",
					"luap",
					"markdown",
					"markdown_inline",
					"query",
					"tsx",
					"typescript",
					"vim",
					"vimdoc",
					"yaml",
				},
				highlight = {
					enable = true,
					disable = function(lang, buf)
						local max_filesize = 100 * 1024
						local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
						if ok and stats and stats.size > max_filesize then
							return true
						end
					end,
				},
				indent = { enable = true },
			})

			vim.api.nvim_create_autocmd("FileType", {
				callback = function()
					pcall(vim.treesitter.start)
				end,
			})
		end,
	},
}
