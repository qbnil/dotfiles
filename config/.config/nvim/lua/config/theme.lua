-- Color theme switcher.
--
--   <leader>ct   pick a theme (saved across restarts)
--   :Theme       same picker from the command line
--
-- Floating windows (hover, diagnostics, completion menu/documentation) run
-- without borders.  To keep them easy to spot, the NormalFloat/Pmenu
-- background is brightened after every ColorScheme change.

local M = {}

M.themes = {
	{ name = "rose-pine", label = "Rose Pine" },
	{ name = "tokyonight-night", label = "Tokyonight Night" },
	{ name = "gruvbox", label = "Gruvbox" },
}

M.default = "rose-pine"

local state_dir = vim.fn.stdpath("state")
local state_file = state_dir .. "/theme"

local function is_valid(name)
	for _, theme in ipairs(M.themes) do
		if theme.name == name then
			return true
		end
	end
	return false
end

local function read_saved()
	local ok, lines = pcall(vim.fn.readfile, state_file)
	if ok and type(lines) == "table" and is_valid(lines[1]) then
		return lines[1]
	end
	return M.default
end

local function save(name)
	pcall(vim.fn.mkdir, state_dir, "p")
	pcall(vim.fn.writefile, { name }, state_file)
end

-- Blend a 24-bit color toward white.  `amount` is 0..1.
local function lighten(color, amount)
	local r = math.floor(color / 65536) % 256
	local g = math.floor(color / 256) % 256
	local b = color % 256
	local function channel(value)
		return math.min(255, math.floor(value + (255 - value) * amount))
	end
	return channel(r) * 65536 + channel(g) * 256 + channel(b)
end

-- Set the background of a highlight group, keeping every other attribute the
-- colorscheme defined (foreground, bold, italic, ...).
local function set_bg(name, bg)
	local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
	hl.bg = bg
	hl.link = nil
	vim.api.nvim_set_hl(0, name, hl)
end

function M.highlight_floats()
	local normal_float = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false })
	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local base = normal_float.bg or normal.bg
	if not base then
		return
	end

	local float_bg = lighten(base, 0.08)
	local selection_bg = lighten(float_bg, 0.12)

	set_bg("NormalFloat", float_bg)
	set_bg("FloatBorder", float_bg)
	set_bg("Pmenu", float_bg)
	set_bg("PmenuSel", selection_bg)
	set_bg("PmenuSbar", float_bg)
	set_bg("PmenuThumb", lighten(float_bg, 0.30))
end

function M.current()
	return vim.g.colors_name
end

function M.set(name)
	if not is_valid(name) then
		vim.notify("Unknown theme: " .. tostring(name), vim.log.levels.WARN, { title = "Theme" })
		return
	end
	local ok, err = pcall(vim.cmd.colorscheme, name)
	if not ok then
		vim.notify(err, vim.log.levels.ERROR, { title = "Theme" })
		return
	end
	save(name)
end

function M.load()
	local ok = pcall(vim.cmd.colorscheme, read_saved())
	if not ok then
		pcall(vim.cmd.colorscheme, M.default)
	end
end

function M.pick()
	local current = vim.g.colors_name
	vim.ui.select(M.themes, {
		prompt = "Select theme",
		format_item = function(theme)
			local marker = current == theme.name and "  (current)" or ""
			return theme.label .. marker
		end,
	}, function(choice)
		if choice then
			M.set(choice.name)
		end
	end)
end

function M.setup()
	vim.api.nvim_create_user_command("Theme", function()
		M.pick()
	end, { desc = "Switch color theme" })

	vim.keymap.set("n", "<leader>ct", M.pick, { silent = true, desc = "Change theme" })

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("theme_float_visibility", { clear = true }),
		callback = function()
			M.highlight_floats()
		end,
	})
end

return M
