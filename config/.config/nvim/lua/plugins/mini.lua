return {
	{
		"nvim-mini/mini.nvim",
		version = false,
		event = { "VeryLazy", "InsertEnter" },
		config = function()
			require("mini.ai").setup()
			require("mini.pairs").setup()
			require("mini.surround").setup()
			require("mini.icons").setup()
			MiniIcons.mock_nvim_web_devicons()
			require("mini.jump").setup()

			-- Which-key style hints: press <leader>, g, z, [, ], <C-w>, ...
			-- and a popup lists the keys that are available next.
			local miniclue = require("mini.clue")
			miniclue.setup({
				triggers = {
					{ mode = { "n", "x" }, keys = "<Leader>" },
					{ mode = "n", keys = "[" },
					{ mode = "n", keys = "]" },
					{ mode = { "n", "x" }, keys = "g" },
					{ mode = { "n", "x" }, keys = "z" },
					-- fff.nvim mappings: ff, fg, fz, fw
					{ mode = { "n", "x" }, keys = "f" },
					{ mode = { "n", "x" }, keys = "'" },
					{ mode = { "n", "x" }, keys = "`" },
					{ mode = { "n", "x" }, keys = '"' },
					{ mode = { "i", "c" }, keys = "<C-r>" },
					{ mode = "i", keys = "<C-x>" },
					{ mode = "n", keys = "<C-w>" },
				},
				clues = {
					miniclue.gen_clues.square_brackets(),
					miniclue.gen_clues.builtin_completion(),
					miniclue.gen_clues.g(),
					miniclue.gen_clues.marks(),
					miniclue.gen_clues.registers(),
					miniclue.gen_clues.windows(),
					miniclue.gen_clues.z(),
					-- Group descriptions for the <leader> menus.
					{ mode = "n", keys = "<Leader>c", desc = "+Copy / config" },
					{ mode = "n", keys = "<Leader>g", desc = "+Git" },
					{ mode = "n", keys = "<Leader>m", desc = "+Tests" },
					{ mode = "n", keys = "<Leader>o", desc = "+Open" },
					{ mode = "n", keys = "<Leader>r", desc = "+Reload / rotate" },
					{ mode = "n", keys = "<Leader>t", desc = "+Tabs / terminal / trouble" },
					{ mode = "n", keys = "<Leader>T", desc = "+Terminal splits" },
					{ mode = "n", keys = "<Leader>z", desc = "+Diff" },
				},
				-- Show the clue window immediately (default is 1000 ms, which
				-- is too slow to be useful while typing quickly).
				window = { delay = 0 },
			})
		end,
	},
}
