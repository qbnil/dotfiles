return {
	{
		"nvim-mini/mini.nvim",
		version = false,
		lazy = false,
		config = function()
			require("mini.ai").setup()
			require("mini.pairs").setup()
			require("mini.surround").setup()
			require("mini.icons").setup()
			MiniIcons.mock_nvim_web_devicons()
			require("mini.jump").setup()
		end,
	},
}
