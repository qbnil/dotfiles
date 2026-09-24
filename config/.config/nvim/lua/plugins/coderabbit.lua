return {
	{
		"smnatale/coderabbit.nvim",
		lazy = true,
		cmd = { "CodeRabbitChat" },
		config = function()
			require("coderabbit").setup()
		end,
	},
}
