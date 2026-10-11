-- Review AI-agent changes with the fff picker, push them into the quickfix
-- list, and commit/push when you're happy.
--
--   <leader>gs  browse uncommitted changes in the fff picker
--               (<Tab> to select, <C-q> to send ALL listed files to quickfix)
--   <leader>gq  open every changed file in the editable quickfix list
--               (dd removes an entry, :w applies it, q closes)
--   <leader>ga  stage the file under the cursor in the quickfix (or the
--               visually selected rows); stages the current file otherwise
--   <leader>gA  stage everything (git add -A)
--
-- Both <C-q> in the picker and <leader>gq land in the same quickfix pane. Each
-- row is:  <file number>  <name>  <status>  <+/- line counts>, with the status
-- and the counts colour-coded (green added, yellow modified, red deleted,
-- blue renamed).
--   <leader>tl  toggle the quickfix window (show/hide, keeps edits)
--   <leader>gc  stage + commit (prompts for a message)
--   <leader>gC  stage + commit + push
--   <leader>gp  push
--   <leader>gr  refresh git status in fff + gitsigns
--
-- Review helpers that already exist: <leader>zd (zdiff uncommitted),
-- <leader>zD (zdiff vs main) and the per-file gitsigns hunks.

local M = {}

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "Agent Review" })
end

local function split_nul(s)
	local out = {}
	local i = 1
	while true do
		local j = s:find("\0", i, true)
		if not j then
			if i <= #s then
				out[#out + 1] = s:sub(i)
			end
			break
		end
		out[#out + 1] = s:sub(i, j - 1)
		i = j + 1
	end
	return out
end

--- @param args string[]
--- @param cwd? string
--- @return vim.SystemCompleted
local function git(args, cwd)
	local cmd = { "git" }
	vim.list_extend(cmd, args)
	return vim.system(cmd, { cwd = cwd, text = true }):wait()
end

--- @return string|nil
local function git_root()
	local res = git({ "rev-parse", "--show-toplevel" })
	if res.code ~= 0 then
		return nil
	end
	local root = vim.trim(res.stdout or "")
	return root ~= "" and root or nil
end

local STATUS_WORD = {
	M = "modified",
	A = "added",
	D = "deleted",
	R = "renamed",
	C = "copied",
	T = "typechanged",
	U = "conflict",
}

--- @param xy string
--- @return string
local function status_word(xy)
	if xy == "??" then
		return "new"
	end
	local c = xy:sub(1, 1)
	if c == " " or c == "" then
		c = xy:sub(2, 2)
	end
	return STATUS_WORD[c] or "changed"
end

--- Added/deleted line counts per path, including untracked files.
--- @param root string
--- @param entries table[]
--- @return table<string, { added: integer, deleted: integer }>
local function diffstat(root, entries)
	local map = {}

	local function ingest(args)
		local res = git(args, root)
		if res.code ~= 0 then
			return
		end
		for line in vim.gsplit(res.stdout or "", "\n", { plain = true }) do
			local a, d, path = line:match("^(%S+)\t(%S+)\t(.+)$")
			if path then
				local cur = map[path] or { added = 0, deleted = 0 }
				cur.added = cur.added + (tonumber(a) or 0)
				cur.deleted = cur.deleted + (tonumber(d) or 0)
				map[path] = cur
			end
		end
	end

	-- Working tree vs HEAD, so it covers staged and unstaged at once.
	-- --no-renames keeps paths aligned with `git status`.
	ingest({ "diff", "--numstat", "--no-renames", "HEAD" })
	if vim.tbl_isempty(map) then
		-- Repository without any commits yet.
		ingest({ "diff", "--numstat", "--no-renames", "--cached" })
		ingest({ "diff", "--numstat", "--no-renames" })
	end

	for _, e in ipairs(entries) do
		if e.xy == "??" and not map[e.path] then
			local ok, lines = pcall(vim.fn.readfile, e.abs)
			map[e.path] = { added = ok and #lines or 0, deleted = 0 }
		end
	end

	return map
end

--- @param added integer
--- @param deleted integer
--- @return string
local function churn(added, deleted)
	if added == 0 and deleted == 0 then
		return ""
	elseif deleted == 0 then
		return string.format("+%d", added)
	elseif added == 0 then
		return string.format("-%d", deleted)
	end
	return string.format("+%d -%d", added, deleted)
end

--- Colour-coded status words for the quickfix rows.
local LABEL_HL = {
	added = "AgentReviewAdded",
	new = "AgentReviewAdded",
	modified = "AgentReviewModified",
	deleted = "AgentReviewDeleted",
	conflict = "AgentReviewDeleted",
	renamed = "AgentReviewRenamed",
	copied = "AgentReviewRenamed",
	typechanged = "AgentReviewRenamed",
	changed = "AgentReviewChanged",
}

local QF_NS = vim.api.nvim_create_namespace("agent_review_qf")
local qf_augroup = vim.api.nvim_create_augroup("AgentReviewQf", { clear = true })

--- @param name string
--- @param candidates string[]
local function link_hl(name, candidates)
	for _, target in ipairs(candidates) do
		if vim.fn.hlexists(target) == 1 then
			vim.api.nvim_set_hl(0, name, { link = target, default = true })
			return
		end
	end
	vim.api.nvim_set_hl(0, name, { default = true })
end

local function define_highlights()
	link_hl("AgentReviewAdded", { "DiagnosticOk", "DiffAdd", "String" })
	link_hl("AgentReviewModified", { "DiagnosticWarn", "DiffChange", "Constant" })
	link_hl("AgentReviewDeleted", { "DiagnosticError", "DiffDelete", "Error" })
	link_hl("AgentReviewRenamed", { "DiagnosticInfo", "Identifier" })
	link_hl("AgentReviewChanged", { "DiagnosticHint", "Comment" })
	link_hl("AgentReviewAdd", { "DiagnosticOk", "DiffAdd", "String" })
	link_hl("AgentReviewDel", { "DiagnosticError", "DiffDelete", "Error" })
end

--- Paint the status word and the +/- counts in a quickfix row. The row text
--- lives after quicker's EM QUAD separator; the filename is virtual text.
--- @param buf integer
local function colorize_qf(buf)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	local ok, display = pcall(require, "quicker.display")
	local quad = (ok and display.EM_QUAD) or "\u{2003}"
	local qlen = (ok and display.EM_QUAD_LEN) or #quad

	vim.api.nvim_buf_clear_namespace(buf, QF_NS, 0, -1)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	for i, line in ipairs(lines) do
		local qpos = line:find(quad, 1, true)
		if qpos then
			local text = line:sub(qpos + qlen)
			local label = text:match("^(%a+)")
			if label and LABEL_HL[label] then
				local base = qpos + qlen - 1 -- 0-based col where the row text starts
				vim.api.nvim_buf_set_extmark(buf, QF_NS, i - 1, base, {
					hl_group = LABEL_HL[label],
					end_col = base + #label,
					priority = 110,
				})
				local init = #label + 1
				while true do
					local s, e = text:find("[+-]%d+", init)
					if not s then
						break
					end
					vim.api.nvim_buf_set_extmark(buf, QF_NS, i - 1, base + s - 1, {
						hl_group = text:sub(s, s) == "+" and "AgentReviewAdd" or "AgentReviewDel",
						end_col = base + e,
						priority = 110,
					})
					init = e + 1
				end
			end
		end
	end
end

--- After pruning, quicker reuses each item (keeping its old lnum), which would
--- leave gaps in the file-number column. Renumber our list back to 1..N.
--- Only ever touches the "Agent changes" list.
--- @param buf integer
local function renumber_qf(buf)
	if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "qf" then
		return
	end
	if vim.fn.getqflist({ title = 0 }).title ~= "Agent changes" then
		return
	end
	local items = vim.fn.getqflist()
	local needs = false
	for i, it in ipairs(items) do
		if it.lnum ~= i then
			needs = true
			break
		end
	end
	if not needs then
		return
	end
	for i, it in ipairs(items) do
		it.lnum = i
	end
	vim.fn.setqflist({}, "r", { items = items, title = "Agent changes" })
end

--- Keep the colours in sync as quicker re-renders the buffer.
--- @param buf integer
local function attach_qf(buf)
	if vim.b[buf].agent_review_attached then
		colorize_qf(buf)
		return
	end
	vim.b[buf].agent_review_attached = true
	colorize_qf(buf)
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TextChanged" }, {
		group = qf_augroup,
		buffer = buf,
		callback = function()
			colorize_qf(buf)
		end,
	})
	-- quicker rebuilds the list on :w. Renumber and recolour once its own
	-- BufWriteCmd handler has finished (ours runs, then we defer).
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = qf_augroup,
		buffer = buf,
		nested = true,
		callback = function()
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(buf) then
					renumber_qf(buf)
					colorize_qf(buf)
				end
			end)
		end,
	})
	-- quicker populates the buffer asynchronously; re-colour once it settles.
	vim.defer_fn(function()
		if vim.api.nvim_buf_is_valid(buf) then
			colorize_qf(buf)
		end
	end, 80)
end

--- fff's <C-q> drops a plain file list (name duplicated: path as both the
--- filename and the row text). Upgrade it in place to the status + counts rows
--- used by <leader>gq, so both entry points look identical.
--- @return boolean enriched
function M.enrich_quickfix()
	local root = git_root()
	if not root then
		return false
	end
	local items = vim.fn.getqflist()
	if #items == 0 then
		return false
	end

	local files = {}
	for _, it in ipairs(items) do
		if it.bufnr == 0 or it.lnum > 1 or (it.col or 1) > 1 then
			return false
		end
		local name = vim.api.nvim_buf_get_name(it.bufnr)
		if name == "" then
			return false
		end
		local rel = name
		if vim.startswith(name, root .. "/") then
			rel = name:sub(#root + 2)
		end
		local txt = it.text or ""
		if txt ~= rel and txt ~= name and txt ~= vim.fn.fnamemodify(name, ":.") then
			return false
		end
		files[#files + 1] = { name = name, rel = rel }
	end

	local map = {}
	for _, e in ipairs(M.changed_files() or {}) do
		map[e.path] = e
	end

	local new_items = {}
	for i, f in ipairs(files) do
		local e = map[f.rel]
		local label = e and e.label or "changed"
		new_items[#new_items + 1] = {
			filename = f.name,
			lnum = i, -- drawn as the file number in quicker's left column
			col = 1,
			text = string.format("%-10s %s", label, e and churn(e.added, e.deleted) or ""),
		}
	end

	vim.fn.setqflist({}, "r", { title = "Agent changes", items = new_items })
	return true
end

--- List the files changed in the working tree (staged, unstaged, untracked).
--- @return table[]|nil entries
--- @return string|nil root
function M.changed_files()
	local root = git_root()
	if not root then
		return nil, nil
	end

	local res = git({ "status", "--porcelain=v1", "-z", "--untracked-files=all" }, root)
	if res.code ~= 0 then
		notify("git status failed: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
		return nil, root
	end

	local entries = {}
	local fields = split_nul(res.stdout or "")
	local i = 1
	while i <= #fields do
		local line = fields[i]
		if line == nil or line == "" then
			break
		end
		local xy = line:sub(1, 2)
		local path = line:sub(4)
		local orig
		if xy:sub(1, 1) == "R" or xy:sub(1, 1) == "C" then
			orig = fields[i + 1]
			i = i + 1
		end
		entries[#entries + 1] = { xy = xy, path = path, orig = orig, abs = root .. "/" .. path }
		i = i + 1
	end

	local stats = diffstat(root, entries)
	for _, e in ipairs(entries) do
		e.label = status_word(e.xy)
		local s = stats[e.path] or { added = 0, deleted = 0 }
		e.added = s.added
		e.deleted = s.deleted
	end

	return entries, root
end

--- Open the fff picker filtered to uncommitted changes. Press <C-q> in the
--- picker to drop every listed file into the quickfix list.
function M.picker()
	local root = git_root()
	if not root then
		notify("Not inside a git repository", vim.log.levels.WARN)
		return
	end

	local ok, fff = pcall(require, "fff")
	if not ok then
		notify("fff is not available: " .. tostring(fff), vim.log.levels.ERROR)
		return
	end

	fff.find_files({
		cwd = root,
		-- FFF's file search understands git-status constraints. Excluding the
		-- "clean" (unmodified) state leaves exactly the agent's changes.
		query = "!git:clean",
		title = "Agent changes",
	})

	-- Git statuses are applied asynchronously right after indexing. Re-run the
	-- search shortly after so the list reflects anything that landed late.
	vim.defer_fn(function()
		local picker_ok, picker = pcall(require, "fff.picker_ui.picker_ui")
		if not picker_ok or not picker.state or not picker.state.active then
			return
		end
		pcall(function()
			require("fff.file_picker").refresh_git_status()
		end)
		pcall(picker.update_results)
	end, 250)
end

--- Push all changed files into the quickfix list and open it.
function M.quickfix_all()
	local entries, root = M.changed_files()
	if not root then
		notify("Not inside a git repository", vim.log.levels.WARN)
		return
	end
	if not entries or #entries == 0 then
		notify("No uncommitted changes", vim.log.levels.WARN)
		return
	end

	local items = {}
	for i, e in ipairs(entries) do
		items[#items + 1] = {
			filename = e.abs,
			lnum = i, -- drawn as the file number in quicker's left column
			col = 1,
			text = string.format("%-10s %s", e.label, churn(e.added, e.deleted)),
		}
	end

	vim.fn.setqflist({}, "r", { title = "Agent changes", items = items })
	vim.cmd("copen")
	attach_qf(vim.api.nvim_get_current_buf())
	notify(string.format("Added %d changed file%s to quickfix", #items, #items == 1 and "" or "s"))
end

--- Refresh git status everywhere that displays it.
--- @param opts? { silent?: boolean }
function M.refresh(opts)
	opts = opts or {}
	pcall(function()
		require("fff.file_picker").refresh_git_status()
	end)
	pcall(function()
		require("gitsigns").refresh()
	end)
	if not opts.silent then
		notify("Refreshed git status")
	end
end

--- Absolute path for a quickfix item, or nil.
--- @param it table
--- @return string|nil
local function item_path(it)
	if not it then
		return nil
	end
	if it.bufnr and it.bufnr > 0 then
		local name = vim.api.nvim_buf_get_name(it.bufnr)
		if name ~= "" then
			return name
		end
	end
	if it.filename and it.filename ~= "" then
		return it.filename
	end
	return nil
end

--- Resolve the file to act on: the quickfix row under the cursor, or the
--- current buffer when it's a normal file.
--- @return string|nil abs
local function target_path()
	local buf = vim.api.nvim_get_current_buf()
	if vim.bo[buf].buftype == "quickfix" then
		local items = vim.fn.getqflist()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		return item_path(items[line] or items[vim.fn.getqflist({ idx = 0 }).idx])
	end
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" or vim.fn.filereadable(name) == 0 then
		return nil
	end
	return name
end

--- Absolute paths for the quickfix rows in the inclusive 1-based range.
--- @param first integer
--- @param last integer
--- @return string[]
local function qf_paths(first, last)
	local items = vim.fn.getqflist()
	local paths, seen = {}, {}
	for line = first, last do
		local name = item_path(items[line])
		if name and not seen[name] then
			seen[name] = true
			paths[#paths + 1] = name
		end
	end
	return paths
end

--- Stage the given absolute paths (expressed relative to `root`).
--- @param root string
--- @param paths string[]
local function stage_paths(root, paths)
	if #paths == 0 then
		notify("No file to stage", vim.log.levels.WARN)
		return
	end
	local rels = {}
	for _, p in ipairs(paths) do
		rels[#rels + 1] = vim.startswith(p, root .. "/") and p:sub(#root + 2) or p
	end
	local argv = { "add", "--" }
	vim.list_extend(argv, rels)
	local res = git(argv, root)
	if res.code ~= 0 then
		notify("git add failed: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
		return
	end
	M.refresh({ silent = true })
	notify("Staged " .. table.concat(rels, ", "))
end

--- Stage a single file: the quickfix row under the cursor, or the current file.
function M.stage_file()
	local root = git_root()
	if not root then
		notify("Not inside a git repository", vim.log.levels.WARN)
		return
	end
	local path = target_path()
	if not path then
		notify("No file under the cursor to stage", vim.log.levels.WARN)
		return
	end
	stage_paths(root, { path })
end

--- Stage every file in the current visual quickfix selection.
function M.stage_selection()
	local root = git_root()
	if not root then
		notify("Not inside a git repository", vim.log.levels.WARN)
		return
	end
	if vim.bo[vim.api.nvim_get_current_buf()].buftype ~= "quickfix" then
		M.stage_file()
		return
	end
	local first, last = vim.fn.line("'<"), vim.fn.line("'>")
	if first > last then
		first, last = last, first
	end
	stage_paths(root, qf_paths(first, last))
end

function M.stage_all()
	local root = git_root()
	if not root then
		notify("Not inside a git repository", vim.log.levels.WARN)
		return
	end
	local res = git({ "add", "-A" }, root)
	if res.code ~= 0 then
		notify("git add failed: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
		return
	end
	M.refresh({ silent = true })
	notify("Staged all changes")
end

--- Stage everything, prompt for a message, commit, and optionally push.
--- @param opts? { push?: boolean }
function M.commit(opts)
	opts = opts or {}
	local root = git_root()
	if not root then
		notify("Not inside a git repository", vim.log.levels.WARN)
		return
	end

	local entries = M.changed_files()
	if not entries or #entries == 0 then
		notify("No changes to commit", vim.log.levels.WARN)
		return
	end

	vim.ui.input({
		prompt = string.format("Commit message (%d file%s): ", #entries, #entries == 1 and "" or "s"),
	}, function(msg)
		msg = msg and vim.trim(msg) or ""
		if msg == "" then
			return
		end

		local add = git({ "add", "-A" }, root)
		if add.code ~= 0 then
			notify("git add failed: " .. vim.trim(add.stderr or ""), vim.log.levels.ERROR)
			return
		end

		local res = git({ "commit", "-m", msg }, root)
		if res.code ~= 0 then
			notify("Commit failed: " .. vim.trim((res.stderr or "") .. (res.stdout or "")), vim.log.levels.ERROR)
			return
		end

		local first = (res.stdout or ""):match("^(.-)\n") or msg
		notify("Committed: " .. first)
		M.refresh({ silent = true })

		if opts.push then
			M.push()
		end
	end)
end

function M.push()
	local root = git_root()
	if not root then
		notify("Not inside a git repository", vim.log.levels.WARN)
		return
	end

	local upstream = git({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" }, root)
	local cmd = upstream.code == 0 and { "git", "push" } or { "git", "push", "-u", "origin", "HEAD" }

	vim.system(cmd, { cwd = root, text = true }, function(res)
		vim.schedule(function()
			if res.code ~= 0 then
				notify("Push failed: " .. vim.trim((res.stderr or "") .. (res.stdout or "")), vim.log.levels.ERROR)
			else
				notify("Pushed")
			end
		end)
	end)
end

function M.setup()
	define_highlights()

	-- Any quickfix list (fff <C-q>, :copen, <leader>gq) is upgraded + coloured
	-- as soon as its buffer is shown.
	vim.api.nvim_create_autocmd("FileType", {
		group = qf_augroup,
		pattern = "qf",
		callback = function(args)
			local buf = args.buf
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end
				M.enrich_quickfix()
				attach_qf(buf)
			end)
		end,
	})

	local function map(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, { silent = true, desc = desc })
	end

	map("<leader>gs", M.picker, "Agent changes (fff)")
	map("<leader>gq", M.quickfix_all, "Agent changes → quickfix")
	map("<leader>ga", M.stage_file, "Stage file under cursor")
	vim.keymap.set("x", "<leader>ga", M.stage_selection, { silent = true, desc = "Stage selected files" })
	map("<leader>gA", M.stage_all, "Stage all changes")
	map("<leader>tl", function()
		local ok, quicker = pcall(require, "quicker")
		if ok then
			quicker.toggle()
		else
			vim.cmd("copen")
		end
	end, "Toggle quickfix list")
	map("<leader>gc", function()
		M.commit()
	end, "Commit all changes")
	map("<leader>gC", function()
		M.commit({ push = true })
	end, "Commit all and push")
	map("<leader>gp", M.push, "Git push")
	map("<leader>gr", M.refresh, "Refresh git status")

	vim.api.nvim_create_user_command("AgentChanges", M.picker, { desc = "Browse agent changes in fff" })
	vim.api.nvim_create_user_command("AgentQuickfix", M.quickfix_all, { desc = "Send agent changes to quickfix" })
	vim.api.nvim_create_user_command("AgentStage", M.stage_all, { desc = "Stage all changes" })
	vim.api.nvim_create_user_command("AgentCommit", function()
		M.commit()
	end, { desc = "Stage and commit all changes" })
	vim.api.nvim_create_user_command("AgentPush", M.push, { desc = "Push current branch" })
end

return M
