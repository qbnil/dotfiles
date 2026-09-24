local specs = {}

local modules = {
	"colorscheme",
	"treesitter",
	"lsp",
	"completion",
	"lualine",
	"oil",
	"conform",
	"git",
	"mini",
	"fidget",
	"trouble",
	"testing",
	"coderabbit",
	"tiny",
	"fff",
}

for _, module in ipairs(modules) do
	local plugin_specs = require("plugins." .. module)
	if plugin_specs then
		vim.list_extend(specs, plugin_specs)
	end
end

return specs
