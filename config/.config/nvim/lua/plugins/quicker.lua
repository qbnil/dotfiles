return {
	{
		"stevearc/quicker.nvim",
		-- Load eagerly so the very first quickfix buffer is already editable.
		-- With `ft = "qf"` the plugin loads during the FileType event, which can
		-- be too late for that first buffer.
		lazy = false,
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
