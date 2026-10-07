return {
	{
		"folke/trouble.nvim",
		lazy = true,
		keys = { { "<leader>tr", "<cmd>Trouble diagnostics toggle<cr>", desc = "Trouble diagnostics" } },
		dependencies = { "folke/todo-comments.nvim" },
		config = function()
			require("trouble").setup()
			require("todo-comments").setup()

			vim.keymap.set("n", "<leader>td", "<cmd>Trouble todo toggle<cr>", { silent = true, desc = "Trouble todos" })

			vim.api.nvim_create_autocmd("BufRead", {
				group = vim.api.nvim_create_augroup("TroubleQuickfix", { clear = true }),
				callback = function(ev)
					if vim.bo[ev.buf].buftype == "quickfix" then
						vim.schedule(function()
							pcall(vim.cmd.cclose)
							vim.cmd([[Trouble qflist open]])
						end)
					end
				end,
			})
		end,
	},
}
