return {
	{
		"stevearc/oil.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons", "refractalize/oil-git-status.nvim" },
		lazy = true,
		keys = {
			{
				"<leader>e",
				function()
					local path = vim.fn.expand("%:p")
					local directory = vim.bo.filetype == "oil" and require("oil").get_current_dir()
						or (vim.fn.filereadable(path) == 1 and vim.fn.fnamemodify(path, ":h") or vim.fn.getcwd())
					require("oil").open(directory)
				end,
				desc = "Open Oil in current directory",
			},
			{
				"<leader>E",
				function()
					local path = vim.fn.expand("%:p")
					local directory = vim.bo.filetype == "oil" and require("oil").get_current_dir()
						or (vim.fn.filereadable(path) == 1 and vim.fn.fnamemodify(path, ":h") or vim.fn.getcwd())
					vim.cmd("leftabove vsplit | vertical resize 30")
					require("oil").open(directory)
				end,
				desc = "Open Oil in current directory",
			},
		},
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
				keymaps = {
					["<CR>"] = {
						"actions.select",
						opts = { close = false },
					},
					["<C-CR>"] = "actions.select",
					-- Change the tab's working directory to the directory shown by Oil.
					["gd"] = { "actions.cd", opts = { scope = "tab" } },
				},
			})

			oil_git_status.setup({
				show_ignored = false,
			})
		end,
	},
}
