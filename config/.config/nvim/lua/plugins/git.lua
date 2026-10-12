--- Run `git` in `dir` when given, otherwise in the directory of the current
--- file (falling back to the working directory), so the right repository is
--- used no matter where nvim was started.
--- @param args string[]
--- @param dir? string
--- @return vim.SystemCompleted
local function git(args, dir)
	local cmd = { "git" }
	vim.list_extend(cmd, args)
	return vim.system(cmd, { cwd = dir, text = true }):wait()
end

--- Best guess for the repository the user is working in.
--- @return string
local function repo_dir()
	local name = vim.fn.expand("%:p")
	if name ~= "" and name:find("/", 1, true) then
		return vim.fn.fnamemodify(name, ":h")
	end
	return vim.fn.getcwd()
end

--- Resolve the branch to diff against: prefer the remote default branch
--- (origin/HEAD), then fall back to the conventional main/master.
--- @param dir? string
local function base_ref(dir)
	dir = dir or repo_dir()
	local res = git({ "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD" }, dir)
	if res.code == 0 then
		local ref = (vim.trim(res.stdout or "")):gsub("^refs/remotes/origin/", "")
		if ref ~= "" then
			return ref
		end
	end
	for _, ref in ipairs({ "main", "master" }) do
		if git({ "rev-parse", "--verify", "--quiet", ref }, dir).code == 0 then
			return ref
		end
	end
	return "main"
end

--- True when `win` shows one of our base-revision diff buffers (or an old
--- gitsigns revision buffer).
local function is_revision_win(win)
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.b[buf].agent_rev_for then
		return true
	end
	return vim.api.nvim_buf_get_name(buf):find("^gitsigns://", 1) ~= nil
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

--- Content of `path` at `base`, as a list of lines. Returns nil + message when
--- the file is not inside a git repository, and an empty list when the file
--- does not exist at `base` (a new file).
--- @return string[]|nil, string?
local function base_lines(path, base)
	local dir = vim.fn.fnamemodify(path, ":h")
	local prefix = git({ "rev-parse", "--show-prefix" }, dir)
	if prefix.code ~= 0 then
		return nil, "not inside a git repository: " .. path
	end
	local rel = vim.trim(prefix.stdout or "") .. vim.fn.fnamemodify(path, ":t")
	local res = git({ "-c", "core.quotepath=off", "show", base .. ":" .. rel }, dir)
	if res.code ~= 0 then
		return {}, nil -- not present at base: everything is an addition
	end
	local text = res.stdout or ""
	if text:sub(-1) == "\n" then
		text = text:sub(1, -2)
	end
	local lines = vim.split(text, "\n", { plain = true })
	for i, l in ipairs(lines) do
		lines[i] = l:gsub("\r$", "")
	end
	return lines, nil
end

--- Turn diff mode off in every window of the tab.
local function diff_off()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) then
			vim.wo[win].diff = false
			vim.w[win].agent_diff = nil
		end
	end
	-- `:diffoff!` also forgets hidden buffers that are still registered as diff
	-- participants (e.g. the previous file after <CR> replaced it in a diff
	-- window); left over, they silently corrupt the next diff's alignment.
	pcall(vim.cmd, "diffoff!")
end

--- Close the revision windows and diff mode. Returns the quickfix window (or the
--- first file window) that the caller may want to go back to.
local function close_diff()
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
	local stored = vim.t.agent_diff_rev
	if stored and vim.api.nvim_win_is_valid(stored) and not vim.tbl_contains(rev_wins, stored) then
		rev_wins[#rev_wins + 1] = stored
	end
	for _, win in ipairs(rev_wins) do
		if vim.api.nvim_win_is_valid(win) and #vim.api.nvim_tabpage_list_wins(0) > 1 then
			vim.api.nvim_win_close(win, true)
		end
	end
	diff_off()
	vim.t.agent_diff_file = nil
	vim.t.agent_diff_rev = nil
	return qf_win or source_win
end

--- No line folding in the diff windows: show every line.
local function no_folds(...)
	for _, w in ipairs({ ... }) do
		if vim.api.nvim_win_is_valid(w) then
			vim.wo[w].foldenable = false
		end
	end
end

--- Show `path` in `win` next to its content at `base`, in diff mode. The base
--- content comes straight from `git show`, so it is always correct for the file
--- at hand, with no waiting for any plugin to attach.
local function open_diff(path, base, win)
	local lines, err = base_lines(path, base)
	if not lines then
		vim.notify(err, vim.log.levels.WARN, { title = "Diff" })
		return
	end
	pcall(vim.cmd, "diffoff!")
	vim.t.agent_diff_file = path -- set first so the BufWinEnter hook below ignores our own buffer switch
	vim.api.nvim_set_current_win(win)
	-- Reuse the buffer when it is loaded (keeps unsaved edits), else load it.
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)
	vim.bo[buf].buflisted = true
	vim.api.nvim_win_set_buf(win, buf)
	vim.w[win].agent_diff = true -- marks the file window of the diff

	vim.cmd("leftabove vsplit")
	local revwin = vim.api.nvim_get_current_win()
	local rev = vim.api.nvim_create_buf(false, true)
	vim.bo[rev].buftype = "nofile"
	vim.bo[rev].bufhidden = "wipe"
	vim.bo[rev].swapfile = false
	vim.api.nvim_buf_set_lines(rev, 0, -1, false, lines)
	vim.bo[rev].modifiable = false
	local ft = vim.filetype.match({ filename = path })
	if ft then
		vim.bo[rev].filetype = ft
	end
	pcall(vim.api.nvim_buf_set_name, rev, ("agentdiff://%s:%s"):format(base, path))
	vim.b[rev].agent_rev_for = path
	vim.api.nvim_win_set_buf(revwin, rev)

	vim.t.agent_diff_rev = revwin
	vim.cmd("diffthis")
	vim.api.nvim_set_current_win(win)
	vim.cmd("diffthis")
	vim.cmd("diffupdate")
	no_folds(win, revwin)
	vim.cmd("normal! gg0")
	vim.cmd("syncbind")
	-- Other plugins react to the buffer switch (filetype, treesitter, lsp, ...)
	-- after we are done; recompute the diff and re-sync the windows once they have.
	vim.schedule(function()
		if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_is_valid(revwin)) then
			return
		end
		if vim.t.agent_diff_file ~= path then
			return
		end
		-- start the diff over from the final buffer contents
		pcall(vim.cmd, "diffoff!")
		for _, w in ipairs({ revwin, win }) do
			vim.api.nvim_win_call(w, function()
				vim.cmd("diffthis")
			end)
		end
		vim.cmd("diffupdate")
		no_folds(win, revwin)
		vim.api.nvim_win_call(win, function()
			vim.cmd("normal! gg0")
		end)
		vim.cmd("syncbind")
		vim.cmd("redraw!")
	end)
end

--- Diff the file under the quickfix cursor against `base`.
local function diff_from_quickfix(base)
	local name = qf_cursor_file()
	if not name or name == "" then
		vim.notify("No file under the quickfix cursor", vim.log.levels.WARN, { title = "Agent Review" })
		return
	end
	local win = file_win()
	if not win then
		vim.cmd("belowright new")
		win = vim.api.nvim_get_current_win()
	end
	open_diff(name, base, win)
end

--- Directory of the quickfix row or of the current file (the repository the
--- diff target belongs to), not nvim's working directory.
local function target_dir()
	if is_qf_buf(vim.api.nvim_get_current_buf()) then
		local name = qf_cursor_file()
		if name and name ~= "" then
			return vim.fn.fnamemodify(name, ":h")
		end
	else
		local name = vim.fn.expand("%:p")
		if name ~= "" and name:find("/", 1, true) then
			return vim.fn.fnamemodify(name, ":h")
		end
	end
end

--- Toggle a diff against the base branch.
---  * no diff open: diff the quickfix row (or the current file)
---  * diff open, cursor on a different quickfix row: switch the diff to that file
---  * otherwise: close the diff and go back to the quickfix list / original file
local function toggle_diff()
	local open = vim.t.agent_diff_file ~= nil
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if is_revision_win(win) then
			open = true
			break
		end
	end

	if open then
		if is_qf_buf(vim.api.nvim_get_current_buf()) then
			local name = qf_cursor_file()
			if name and name ~= "" and name ~= vim.t.agent_diff_file then
				local qf = vim.api.nvim_get_current_win()
				close_diff()
				if vim.api.nvim_win_is_valid(qf) then
					vim.api.nvim_set_current_win(qf)
				end
				diff_from_quickfix(base_ref(target_dir()))
				return
			end
		end
		-- cursor is in a file window showing a different file than the diff
		-- (e.g. opened from the quickfix list with <CR>): diff that file instead
		local cur = vim.api.nvim_get_current_buf()
		local name = vim.api.nvim_buf_get_name(cur)
		if
			not is_qf_buf(cur)
			and vim.bo[cur].buftype == ""
			and not vim.b[cur].agent_rev_for
			and name ~= ""
			and name ~= vim.t.agent_diff_file
		then
			local win = vim.api.nvim_get_current_win()
			close_diff()
			if vim.api.nvim_win_is_valid(win) then
				open_diff(name, base_ref(vim.fn.fnamemodify(name, ":h")), win)
			end
			return
		end
		local back = close_diff()
		if back and vim.api.nvim_win_is_valid(back) then
			vim.api.nvim_set_current_win(back)
		end
		return
	end

	local base = base_ref(target_dir())
	if is_qf_buf(vim.api.nvim_get_current_buf()) then
		diff_from_quickfix(base)
	else
		local name = vim.fn.expand("%:p")
		if name == "" then
			vim.notify("Current buffer has no file", vim.log.levels.WARN, { title = "Diff" })
			return
		end
		open_diff(name, base, vim.api.nvim_get_current_win())
	end
end

-- While a diff is open, loading another file into its file window (quickfix
-- <CR>, :edit, ...) closes the diff and just shows that file. A new diff only
-- opens when <leader>gd is pressed.
local closing = false
vim.api.nvim_create_autocmd("BufWinEnter", {
	group = vim.api.nvim_create_augroup("AgentDiffFollow", { clear = true }),
	callback = function(ev)
		local cur = vim.t.agent_diff_file
		if not cur or closing then
			return
		end
		local buf = ev.buf
		if vim.bo[buf].buftype ~= "" or vim.b[buf].agent_rev_for then
			return
		end
		local name = vim.api.nvim_buf_get_name(buf)
		local win = vim.api.nvim_get_current_win()
		local revw = vim.t.agent_diff_rev
		-- quickfix <CR> may land in the diff's base window (it is the "previous"
		-- window), so react to either diff window, not only the marked one
		local in_diff = vim.w[win].agent_diff or (revw and win == revw)
		if name == "" or name == cur or not in_diff then
			return
		end
		vim.schedule(function()
			if not vim.api.nvim_win_is_valid(win) then
				return
			end
			local landed_in_rev = revw and win == revw
			local nbuf = vim.api.nvim_win_get_buf(win)
			closing = true
			local ok, err = pcall(function()
				local fw
				for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
					if vim.w[w].agent_diff and w ~= win then
						fw = w
					end
				end
				close_diff()
				if landed_in_rev then
					-- the file went into the base window: show it in the file window instead
					if fw and vim.api.nvim_win_is_valid(fw) then
						vim.api.nvim_win_set_buf(fw, nbuf)
						vim.api.nvim_set_current_win(fw)
					end
				elseif vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_set_current_win(win)
				end
			end)
			closing = false
			if not ok then
				vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Diff" })
			end
		end)
	end,
})

--- Jump to the next/previous git hunk (wraps around, shows the hunk preview).
--- @param dir "next"|"prev"
local function hunk(dir)
	local gs = require("gitsigns")
	if gs.nav_hunk then
		gs.nav_hunk(dir, { wrap = true })
	elseif dir == "next" then
		gs.next_hunk()
	else
		gs.prev_hunk()
	end
end

return {
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		keys = {
			{
				"<leader>gn",
				function()
					hunk("next")
				end,
				desc = "Next git hunk",
			},
			{
				"<leader>gN",
				function()
					hunk("prev")
				end,
				desc = "Previous git hunk",
			},
			{
				"[h",
				function()
					hunk("next")
				end,
				desc = "Next git hunk",
			},
			{
				"]h",
				function()
					hunk("prev")
				end,
				desc = "Previous git hunk",
			},
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
