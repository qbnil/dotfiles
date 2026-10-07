return {
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			require("gitsigns").setup({
				current_line_blame = true,
			})
		end,
	},
	{
		"martindur/zdiff.nvim",
		lazy = true,
		keys = { { "<leader>zd", "<cmd>lua require('zdiff').open()<cr>", desc = "Zdiff (uncommitted)" } },
		config = function()
			require("zdiff").setup()
			vim.keymap.set("n", "<leader>zD", function()
				require("zdiff").open("main")
			end, { desc = "Zdiff (vs main)" })
			vim.keymap.set(
				"n",
				"<leader>gm",
				":Gitsigns diffthis main<cr>",
				{ silent = true, desc = "Diff against main" }
			)
		end,
	},
}
