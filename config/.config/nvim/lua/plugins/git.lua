-- Resolve the branch to diff against: prefer the remote default branch
-- (origin/HEAD), then fall back to the conventional main/master.
local function base_ref()
	local res = vim.system({ "git", "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD" }, { text = true }):wait()
	if res.code == 0 then
		local ref = (vim.trim(res.stdout or "")):gsub("^refs/remotes/origin/", "")
		if ref ~= "" then
			return ref
		end
	end
	for _, ref in ipairs({ "main", "master" }) do
		if vim.system({ "git", "rev-parse", "--verify", "--quiet", ref }, { text = true }):wait().code == 0 then
			return ref
		end
	end
	return "main"
end

--- True when `win` shows a gitsigns revision (diff) buffer.
local function is_revision_win(win)
	local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
	return name:find("^gitsigns://", 1) ~= nil
end

--- True when `buf` is a quickfix/location list buffer.
local function is_qf_buf(buf)
	return vim.bo[buf].buftype == "quickfix"
end

--- Absolute path (and bufnr when known) of the file under the quickfix cursor.
local function qf_cursor_file()
	local items = vim.fn.getqflist()
	if #items == 0 then
		return nil
	end
	local it = items[vim.api.nvim_win_get_cursor(0)[1]]
	if not it then
		it = items[vim.fn.getqflist({ idx = 0 }).idx]
	end
	if not it then
		return nil
	end
	if it.bufnr and it.bufnr > 0 then
		local name = vim.api.nvim_buf_get_name(it.bufnr)
		if name ~= "" then
			return name, it.bufnr
		end
	end
	return it.filename, it.bufnr
end

--- First ordinary (non-quickfix, non-revision) window in this tab.
local function file_win()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if not is_qf_buf(buf) and not is_revision_win(win) then
			return win
		end
	end
	return nil
end

--- Diff the file under the quickfix cursor against `base`.
local function diff_from_quickfix(base)
	local name, bufnr = qf_cursor_file()
	if not name or name == "" then
		vim.notify("No file under the quickfix cursor", vim.log.levels.WARN, { title = "Agent Review" })
		return
	end
	local win = file_win()
	if not win then
		vim.cmd("belowright new")
		win = vim.api.nvim_get_current_win()
	end
	vim.api.nvim_set_current_win(win)
	local buf
	if bufnr and bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified then
		-- Don't clobber unsaved edits; the buffer is already attached.
		vim.api.nvim_win_set_buf(win, bufnr)
		buf = bufnr
	else
		-- A forced read loads the buffer and fires BufRead so gitsigns attaches.
		vim.cmd("edit! " .. vim.fn.fnameescape(name))
		buf = vim.api.nvim_get_current_buf()
	end
	-- gitsigns attaches asynchronously off BufRead; wait for the cache entry
	-- (present once the git object is ready) before diffing.
	local gcache = require("gitsigns.cache").cache
	vim.wait(2000, function()
		return gcache[buf] ~= nil
	end, 20)
	vim.cmd("Gitsigns diffthis " .. base)
end

--- Toggle a gitsigns diff against the base branch. Pressing the mapping again
--- closes the revision window(s) and returns to the original file -- or to the
--- quickfix list when the diff was opened from there.
local function toggle_diff()
	local rev_wins, source_win, qf_win = {}, nil, nil
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if is_revision_win(win) then
			rev_wins[#rev_wins + 1] = win
		elseif is_qf_buf(buf) then
			qf_win = win
		elseif not source_win then
			source_win = win
		end
	end

	if #rev_wins == 0 then
		local base = base_ref()
		if is_qf_buf(vim.api.nvim_get_current_buf()) then
			diff_from_quickfix(base)
		else
			vim.cmd("Gitsigns diffthis " .. base)
		end
		return
	end

	-- Drop the revision windows, turn diff off everywhere, and go back to the
	-- quickfix list if there is one.
	for _, win in ipairs(rev_wins) do
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) then
			vim.wo[win].diff = false
		end
	end
	local back = qf_win or source_win
	if back and vim.api.nvim_win_is_valid(back) then
		vim.api.nvim_set_current_win(back)
	end
end

return {
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		keys = {
			{
				"<leader>gd",
				toggle_diff,
				desc = "Toggle diff vs base branch (quickfix row or current file)",
			},
		},
		config = function()
			require("gitsigns").setup({
				current_line_blame = true,
			})
		end,
	},
	{
		"martindur/zdiff.nvim",
		lazy = true,
		keys = {
			{ "<leader>zd", "<cmd>lua require('zdiff').open()<cr>", desc = "Zdiff (uncommitted)" },
			{
				"<leader>zD",
				function()
					require("zdiff").open(base_ref())
				end,
				desc = "Zdiff (vs base branch)",
			},
		},
		config = function()
			require("zdiff").setup()
		end,
	},
}
