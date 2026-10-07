return {
	{
		"rachartier/tiny-code-action.nvim",
		lazy = true,
		config = function()
			local code_action = require("tiny-code-action")
			code_action.setup({
				picker = "buffer",
			})
		end,
	},
}
