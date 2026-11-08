-- Interactive buffer manager.
--
-- Open with <leader>b. It lists every listed buffer plus terminal buffers.
--
--   <CR>      open in the current window
--   d         close (bdelete)
--   x         force close (bdelete!)
--   <C-h>     open in a split on the left (manager stays open)
--   <C-l>     open in a split on the right
--   <C-k>     open in a split above
--   <C-j>     open in a split below
--   t         open in a new tab
--   a         add a file (fff file finder)
--   r         refresh the list
--   q / <Esc> close the manager

local M = {}

local ns = vim.api.nvim_create_namespace("config.buffer_manager")

local hint = " <CR> open   d close   x force   t tab   a add   r refresh   q quit"
local hint_splits = " Splits (manager stays open): ^H left   ^L right   ^K top   ^J bottom"
local header = "  #   Flags  Name                                                          Type          Lines"

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
	return buf and vim.api.nvim_buf_is_valid(buf)
end

local function origin_buffer()
	local win = M.state and M.state.origin_win
	if valid_win(win) then
		return vim.api.nvim_win_get_buf(win)
	end
	return vim.api.nvim_get_current_buf()
end

local function display_name(buf)
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then
		return "[No Name]"
	end
	if vim.bo[buf].buftype == "terminal" then
		local cmd = name:match("term://.-//%d+:(.*)$")
		return cmd and ("term: " .. cmd) or name
	end
	local cwd = vim.fn.getcwd() .. "/"
	if name:sub(1, #cwd) == cwd then
		return name:sub(#cwd + 1)
	end
	return vim.fn.fnamemodify(name, ":~:.")
end

local function shorten(text, width)
	if #text <= width then
		return text
	end
	return "…" .. text:sub(-(width - 1))
end

local function collect()
	local ui_buf = M.state and M.state.buf
	local current = origin_buffer()
	local alternate = vim.fn.bufnr("#")

	local infos = vim.fn.getbufinfo({ bufloaded = 1 })
	local items = {}
	for _, info in ipairs(infos) do
		local buf = info.bufnr
		local buftype = vim.bo[buf].buftype
		if buf ~= ui_buf and (info.listed == 1 or buftype == "terminal") then
			local flags = {}
			if buf == current then
				flags[#flags + 1] = "%"
			end
			if buf == alternate then
				flags[#flags + 1] = "#"
			end
			if info.windows and #info.windows > 0 then
				flags[#flags + 1] = "a"
			elseif info.hidden == 1 then
				flags[#flags + 1] = "h"
			end
			if vim.bo[buf].modified then
				flags[#flags + 1] = "+"
			end
			if vim.bo[buf].readonly then
				flags[#flags + 1] = "="
			end

			items[#items + 1] = {
				bufnr = buf,
				flags = table.concat(flags),
				name = shorten(display_name(buf), 60),
				filetype = vim.bo[buf].filetype,
				linecount = info.linecount or 0,
			}
		end
	end
	table.sort(items, function(a, b)
		return a.bufnr < b.bufnr
	end)
	return items
end

local function close_ui()
	local state = M.state
	M.state = nil
	if state and valid_win(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
end

local function selected_buffer()
	local state = M.state
	if not state or not valid_win(state.win) then
		return nil
	end
	local row = vim.api.nvim_win_get_cursor(state.win)[1]
	return state.line_to_buf[row]
end

local function focus_origin(state)
	close_ui()
	if valid_win(state.origin_win) then
		vim.api.nvim_set_current_win(state.origin_win)
	end
end

local function open_current(buf)
	local state = M.state
	focus_origin(state)
	vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
end

local split_commands = {
	left = "leftabove vsplit",
	right = "rightbelow vsplit",
	top = "leftabove split",
	bottom = "rightbelow split",
}

local function open_split(buf, direction)
	local state = M.state
	if not state or not valid_win(state.origin_win) then
		return
	end
	-- Split from the window the manager was opened from, but keep the manager
	-- open so several buffers can be placed on different sides in a row.
	vim.api.nvim_win_call(state.origin_win, function()
		vim.cmd(split_commands[direction])
		vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
	end)
	M.refresh()
end

local function open_tab(buf)
	local state = M.state
	focus_origin(state)
	vim.cmd("tabnew")
	vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
end

local function delete_buffer(force)
	local buf = selected_buffer()
	if not buf then
		return
	end
	local ok, err = pcall(vim.api.nvim_buf_delete, buf, { force = force })
	if not ok then
		vim.notify(err, vim.log.levels.WARN, { title = "Buffers" })
		return
	end
	M.refresh()
end

local function add_file()
	local state = M.state
	close_ui()
	if state and valid_win(state.origin_win) then
		vim.api.nvim_set_current_win(state.origin_win)
	end
	local ok = pcall(function()
		require("fff").find_files()
	end)
	if not ok then
		vim.ui.input({ prompt = "Edit file: " }, function(path)
			if path and path ~= "" then
				vim.cmd("edit " .. vim.fn.fnameescape(path))
			end
		end)
	end
end

local function with_selected(fn)
	local buf = selected_buffer()
	if buf then
		fn(buf)
	end
end

local function set_keymaps(buf)
	local opts = { buffer = buf, silent = true, nowait = true }
	vim.keymap.set("n", "<CR>", function()
		with_selected(open_current)
	end, vim.tbl_extend("force", opts, { desc = "Open buffer" }))
	vim.keymap.set("n", "d", function()
		delete_buffer(false)
	end, vim.tbl_extend("force", opts, { desc = "Close buffer" }))
	vim.keymap.set("n", "x", function()
		delete_buffer(true)
	end, vim.tbl_extend("force", opts, { desc = "Force close buffer" }))
	vim.keymap.set("n", "<C-h>", function()
		with_selected(function(b)
			open_split(b, "left")
		end)
	end, vim.tbl_extend("force", opts, { desc = "Open buffer left" }))
	vim.keymap.set("n", "<C-l>", function()
		with_selected(function(b)
			open_split(b, "right")
		end)
	end, vim.tbl_extend("force", opts, { desc = "Open buffer right" }))
	vim.keymap.set("n", "<C-k>", function()
		with_selected(function(b)
			open_split(b, "top")
		end)
	end, vim.tbl_extend("force", opts, { desc = "Open buffer above" }))
	vim.keymap.set("n", "<C-j>", function()
		with_selected(function(b)
			open_split(b, "bottom")
		end)
	end, vim.tbl_extend("force", opts, { desc = "Open buffer below" }))
	vim.keymap.set("n", "t", function()
		with_selected(open_tab)
	end, vim.tbl_extend("force", opts, { desc = "Open buffer in new tab" }))
	vim.keymap.set("n", "a", add_file, vim.tbl_extend("force", opts, { desc = "Add file" }))
	vim.keymap.set("n", "r", M.refresh, vim.tbl_extend("force", opts, { desc = "Refresh buffer list" }))
	vim.keymap.set("n", "q", close_ui, vim.tbl_extend("force", opts, { desc = "Close buffer list" }))
	vim.keymap.set("n", "<Esc>", close_ui, vim.tbl_extend("force", opts, { desc = "Close buffer list" }))
	vim.keymap.set("n", "<C-c>", close_ui, vim.tbl_extend("force", opts, { desc = "Close buffer list" }))
end

function M.refresh()
	local state = M.state
	if not state or not valid_buf(state.buf) or not valid_win(state.win) then
		return
	end

	local items = collect()
	if #items == 0 then
		close_ui()
		return
	end

	local lines = { hint, hint_splits, header }
	state.line_to_buf = {}
	local current_line
	local current = origin_buffer()
	for _, item in ipairs(items) do
		local lnum = #lines + 1
		state.line_to_buf[lnum] = item.bufnr
		if item.bufnr == current then
			current_line = lnum
		end
		lines[#lines + 1] = string.format(
			"%3d  %-5s  %-60s  %-12s  %d",
			item.bufnr,
			item.flags,
			item.name,
			item.filetype,
			item.linecount
		)
	end

	local previous_row = vim.api.nvim_win_get_cursor(state.win)[1]
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	vim.api.nvim_buf_add_highlight(state.buf, ns, "Comment", 0, 0, -1)
	vim.api.nvim_buf_add_highlight(state.buf, ns, "Comment", 1, 0, -1)
	vim.api.nvim_buf_add_highlight(state.buf, ns, "Title", 2, 0, -1)
	if current_line then
		vim.api.nvim_buf_add_highlight(state.buf, ns, "PmenuSel", current_line - 1, 0, -1)
	end

	local target = state.line_to_buf[previous_row] and previous_row or current_line or 4
	vim.api.nvim_win_set_cursor(state.win, { math.min(target, #lines), 0 })
end

function M.open()
	if valid_win(M.state and M.state.win) then
		vim.api.nvim_set_current_win(M.state.win)
		return
	end

	local origin_win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "buffer-manager"

	local width = math.min(120, math.max(70, vim.o.columns - 10))
	local height = math.min(math.max(10, vim.o.lines - 8), math.max(10, #collect() + 4))
	local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
	local col = math.max(0, math.floor((vim.o.columns - width) / 2))

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = "rounded",
		title = " Buffers ",
		title_pos = "center",
	})

	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"

	M.state = { buf = buf, win = win, origin_win = origin_win, line_to_buf = {} }
	set_keymaps(buf)
	M.refresh()
end

return M
