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

			-- The quickfix window is now owned by quicker.nvim (an editable
			-- list), so we no longer redirect every :copen to Trouble. Use
			-- :Trouble qflist if you want Trouble's rendering of the list.
		end,
	},
}
