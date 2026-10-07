return {
	{
		"nvim-neotest/neotest",
		lazy = true,
		keys = {
			{ "<leader>mr", ":Neotest run<cr>", desc = "Run nearest test" },
			{ "<leader>ms", ":Neotest summary<cr>", desc = "Test summary" },
			{ "<leader>mo", ":Neotest output<cr>", desc = "Test output" },
			{ "<leader>mp", ":Neotest output-panel<cr>", desc = "Test output panel" },
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"antoinemadec/FixCursorHold.nvim",
			"nvim-treesitter/nvim-treesitter",
			"nvim-neotest/nvim-nio",
			"fredrikaverpil/neotest-golang",
		},
		config = function()
			require("neotest").setup({
				adapters = {
					require("neotest-golang")(),
				},
			})
		end,
	},
}
