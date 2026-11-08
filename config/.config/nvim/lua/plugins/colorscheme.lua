return {
	{
		"rose-pine/neovim",
		name = "rose-pine",
		lazy = false,
		priority = 1000,
		dependencies = {
			"folke/tokyonight.nvim",
			"ellisonleao/gruvbox.nvim",
		},
		config = function()
			require("rose-pine").setup({
				styles = {
					bold = false,
					italic = false,
					transparency = false,
				},
				highlight_groups = {
					LspInlayHint = { bg = "base", fg = "muted", italic = true },
					NotificationInfo = { bg = "none", fg = "text" },
					NotificationWarning = { bg = "none", fg = "subtle" },
					NotificationError = { bg = "none", fg = "love" },
				},
			})

			require("tokyonight").setup({
				style = "night",
				transparent = false,
				styles = {
					bold = false,
					italic = false,
				},
			})

			require("gruvbox").setup({
				contrast = "hard",
				transparent_mode = false,
				italic = {
					strings = false,
					comments = false,
					operators = false,
					folds = false,
				},
				bold = false,
			})

			-- Applies the saved theme, falling back to Rose Pine.
			require("config.theme").load()
		end,
	},
}
