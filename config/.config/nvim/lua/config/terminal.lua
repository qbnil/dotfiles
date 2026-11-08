-- One shared terminal that can be shown in a split on any side.
--
--   <leader>th  terminal on the left
--   <leader>tl  terminal on the right
--   <leader>tj  terminal at the bottom
--   <leader>tk  terminal at the top
--
-- Pressing the same key while the terminal is focused hides it again, so it
-- also works as a toggle. The shell keeps running while the window is hidden.

local M = {}

local state = { buf = nil }

local function valid_terminal(buf)
	return buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal"
end

local function ensure_buffer()
	if valid_terminal(state.buf) then
		return state.buf
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.api.nvim_buf_call(buf, function()
		vim.fn.termopen(vim.o.shell)
	end)
	state.buf = buf
	return buf
end

local function find_window(buf)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_buf(win) == buf then
			return win
		end
	end
	return nil
end

local split_commands = {
	left = "leftabove vsplit",
	right = "rightbelow vsplit",
	top = "leftabove split",
	bottom = "rightbelow split",
}

function M.toggle(direction)
	local buf = ensure_buffer()
	local win = find_window(buf)

	if win then
		if win == vim.api.nvim_get_current_win() then
			-- Hide the terminal, but never leave an empty tab behind.
			if #vim.api.nvim_tabpage_list_wins(0) > 1 then
				vim.cmd("close")
			else
				vim.cmd("enew")
			end
		else
			vim.api.nvim_set_current_win(win)
			vim.cmd("startinsert")
		end
		return
	end

	vim.cmd(split_commands[direction] or split_commands.bottom)
	local new_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(new_win, buf)

	if direction == "left" or direction == "right" then
		local width = math.min(70, math.max(30, math.floor(vim.o.columns * 0.30)))
		vim.api.nvim_win_set_width(new_win, width)
	else
		vim.api.nvim_win_set_height(new_win, 12)
	end

	vim.cmd("startinsert")
end

return M
