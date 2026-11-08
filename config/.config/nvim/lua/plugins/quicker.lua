return {
	{
		"stevearc/quicker.nvim",
		ft = "qf",
		---@module "quicker"
		---@type quicker.SetupOptions
		opts = {
			-- Edit the quickfix list like a normal buffer. Deleting entries with
			-- `dd` removes them and `:w` rebuilds the real quickfix list. See
			-- after/ftplugin/qf.lua for the auto-apply mapping.
			edit = { enabled = true },
		},
	},
}
