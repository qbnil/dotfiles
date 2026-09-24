return {
	{
		"stevearc/oil.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons", "refractalize/oil-git-status.nvim" },
		lazy = true,
		keys = { { "<leader>e", "<cmd>Oil<cr>", desc = "Open Oil" } },
		config = function()
			local oil = require("oil")
			local oil_git_status = require("oil-git-status")

			oil.setup({
				skip_confirm_for_simple_edits = true,
				win_options = {
					signcolumn = "yes:2",
				},
				view_options = {
					show_hidden = true,
				},
				watch_for_changes = true,
			})

			oil_git_status.setup({
				show_ignored = false,
			})
		end,
		vim.keymap.set("n", "<leader>E", function()
			vim.cmd("vsplit | vertical resize -50 | wincmd l")
			require("oil").open()
		end),
	},
}
