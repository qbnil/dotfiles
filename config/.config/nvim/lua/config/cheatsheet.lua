-- A generated keymap cheatsheet: every mapping that has a `desc` is collected
-- from the global maps and from the current buffer, grouped by mode, and shown
-- in a floating window. Open it with <leader>? .

local M = {}

local modes = {
	{ key = "n", title = "Normal" },
	{ key = "v", title = "Visual" },
	{ key = "o", title = "Operator-pending" },
	{ key = "i", title = "Insert" },
	{ key = "t", title = "Terminal" },
	{ key = "c", title = "Command-line" },
}

local function pretty_lhs(lhs)
	local leader = vim.g.mapleader or "\\"
	if leader ~= "" and lhs:sub(1, #leader) == leader then
		return "<leader>" .. lhs:sub(#leader + 1)
	end
	return lhs
end

local function collect(mode, bufnr)
	local maps
	if bufnr then
		maps = vim.api.nvim_buf_get_keymap(bufnr, mode)
	else
		maps = vim.api.nvim_get_keymap(mode)
	end

	local out, seen = {}, {}
	for _, map in ipairs(maps) do
		if map.desc and map.desc ~= "" and map.lhs ~= "" and not seen[map.lhs] then
			seen[map.lhs] = true
			out[#out + 1] = { lhs = pretty_lhs(map.lhs), desc = map.desc }
		end
	end
	table.sort(out, function(a, b)
		return a.lhs < b.lhs
	end)
	return out
end

--- @return string[]
function M.lines()
	local lines = {
		"  Neovim keymaps (generated from mappings with a description)",
		"  Tip: press <leader> (space), f, g, z, [, ] or <C-w> and mini.clue shows what can follow.",
		"  Press q or <Esc> to close.",
	}

	for _, mode in ipairs(modes) do
		local maps = collect(mode.key)
		if #maps > 0 then
			lines[#lines + 1] = ""
			lines[#lines + 1] = "== " .. mode.title .. " =="
			for _, map in ipairs(maps) do
				lines[#lines + 1] = string.format("  %-32s %s", map.lhs, map.desc)
			end
		end
	end

	-- Buffer-local mappings (quickfix, oil, help, ...).
	local bufnr = vim.api.nvim_get_current_buf()
	local buffer_lines = {}
	for _, mode in ipairs(modes) do
		for _, map in ipairs(collect(mode.key, bufnr)) do
			buffer_lines[#buffer_lines + 1] = string.format("  %-10s %-20s %s", mode.title, map.lhs, map.desc)
		end
	end
	if #buffer_lines > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "== Current buffer =="
		vim.list_extend(lines, buffer_lines)
	end

	return lines
end

function M.open()
	local lines = M.lines()

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false

	-- Highlight the section headers.
	vim.api.nvim_set_hl(0, "CheatsheetHeader", { link = "Title", default = true })
	for i, line in ipairs(lines) do
		if line:match("^== ") then
			vim.api.nvim_buf_add_highlight(buf, -1, "CheatsheetHeader", i - 1, 0, -1)
		end
	end

	local width = math.min(100, math.max(40, vim.o.columns - 8))
	local height = math.min(#lines, math.max(10, vim.o.lines - 6))
	local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
	local col = math.max(0, math.floor((vim.o.columns - width) / 2))

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = "rounded",
		title = " Keymaps ",
		title_pos = "center",
	})

	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"

	for _, key in ipairs({ "q", "<Esc>", "<C-c>" }) do
		vim.keymap.set("n", key, "<cmd>close<CR>", { buffer = buf, silent = true, desc = "Close cheatsheet" })
	end
end

return M
