-- Review AI-agent changes in a searchable picker, push them into the quickfix
-- list, and commit/push when you're happy.
--
--   <leader>gs  searchable picker of ALL changes, including deleted files
--               (type to fuzzy filter, status words match too: "deleted foo")
--               <Tab> select, <CR> open (deleted -> HEAD content in a split),
--               <C-q> send selected (or all listed) to quickfix, <Esc> close
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
-- Below the changed files the list grows a "Commits" section: every commit
-- reachable from HEAD, newest first, with an up-arrow mark (↑) on the ones that
-- are not pushed yet. <CR> on a commit row opens `git show` for it in a split;
-- committed files drop out of the file section after a commit and on <leader>gr.
--
-- Review helpers that already exist: <leader>zd (zdiff uncommitted),
-- <leader>zD (zdiff vs main) and the per-file gitsigns hunks.

local M = {}

-- Repo the "Agent changes" list was most recently built from. While a quickfix
-- window is current (its buffer has no path of its own) this keeps commit,
-- stage, show_commit and refresh pinned to the same repository.
M.last_root = nil

-- Forward declarations so functions defined earlier in the file can use them.
local file_items, commit_items

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

--- Git root for the current context, in order of preference:
--- 1. the repository the active "Agent changes" quickfix was built from;
--- 2. the repository containing the current file (follows buffers across
---    repos/repos nested inside dotfiles, and works when nvim started outside
---    any repository);
--- 3. the repository of the working directory.
--- @return string|nil
local function git_root()
	local buf = vim.api.nvim_get_current_buf()
	if vim.bo[buf].buftype == "quickfix" and M.last_root then
		return M.last_root
	end

	local dirs = {}
	local path = vim.fn.expand("%:p")
	if path ~= "" and path:find("/", 1, true) then
		dirs[#dirs + 1] = vim.fn.fnamemodify(path, ":h")
	end
	dirs[#dirs + 1] = vim.fn.getcwd()

	for _, dir in ipairs(dirs) do
		local res = git({ "rev-parse", "--show-toplevel" }, dir)
		if res.code == 0 then
			local root = vim.trim(res.stdout or "")
			if root ~= "" then
				M.last_root = root
				return root
			end
		end
	end
	return nil
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
local PICKER_NS = vim.api.nvim_create_namespace("agent_review_picker")
local qf_augroup = vim.api.nvim_create_augroup("AgentReviewQf", { clear = true })

--- Marks a commit that has not been pushed yet.
local UNPUSHED_MARK = "↑"

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
	link_hl("AgentReviewUnpushed", { "Special", "DiagnosticWarn" })
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
			local base = qpos + qlen - 1 -- 0-based col where the row text starts
			-- Unpushed-commit marker.
			if text:sub(1, #UNPUSHED_MARK) == UNPUSHED_MARK then
				vim.api.nvim_buf_set_extmark(buf, QF_NS, i - 1, base, {
					hl_group = "AgentReviewUnpushed",
					end_col = base + #UNPUSHED_MARK,
					priority = 120,
				})
			end
			local label = text:match("^(%a+)")
			if label and LABEL_HL[label] then
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
	local function is_special(it)
		local ud = it.user_data
		return type(ud) == "table" and (ud.agent == "commit" or ud.agent == "header")
	end
	local n = 0
	local needs = false
	for _, it in ipairs(items) do
		if not is_special(it) then
			n = n + 1
			if it.lnum ~= n then
				needs = true
			end
		end
	end
	if not needs then
		return
	end
	n = 0
	for _, it in ipairs(items) do
		if not is_special(it) then
			n = n + 1
			it.lnum = n
		end
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

	-- Already an agent list (rebuilt by us)? Leave it alone.
	for _, it in ipairs(items) do
		if type(it.user_data) == "table" and it.user_data.agent then
			return false
		end
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
			user_data = { agent = "file" },
		}
	end
	vim.list_extend(new_items, commit_items())

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

--- Every commit reachable from HEAD (newest first), each flagged `unpushed`
--- when it is not on the upstream branch. With no upstream every commit counts
--- as unpushed (nothing has been pushed).
--- @return { sha: string, short: string, subject: string, unpushed: boolean }[]
function M.commit_list()
	local root = git_root()
	if not root then
		return {}
	end

	local has_upstream = git({ "rev-parse", "--verify", "--quiet", "@{u}" }, root).code == 0
	local unpushed = {}
	if has_upstream then
		local res = git({ "rev-list", "@{u}..HEAD" }, root)
		if res.code == 0 then
			for line in vim.gsplit(res.stdout or "", "\n", { plain = true }) do
				if line ~= "" then
					unpushed[line] = true
				end
			end
		end
	end

	local res = git({ "log", "--format=%H%x1f%h%x1f%s" }, root)
	if res.code ~= 0 then
		return {}
	end
	local commits = {}
	for line in vim.gsplit(res.stdout or "", "\n", { plain = true }) do
		local parts = vim.split(line, "\31", { plain = true })
		if parts[1] and parts[1] ~= "" then
			commits[#commits + 1] = {
				sha = parts[1],
				short = parts[2] or "",
				subject = parts[3] or "",
				unpushed = (not has_upstream) or unpushed[parts[1]] == true,
			}
		end
	end
	return commits
end

--- Quickfix rows for the changed files. `lnum` doubles as the file number in
--- quicker's left column, and the `agent = "file"` marker lets us tell these
--- rows apart from the commits section.
--- @param entries table[]
--- @return table[]
file_items = function(entries)
	local items = {}
	for i, e in ipairs(entries) do
		items[#items + 1] = {
			filename = e.abs,
			lnum = i, -- drawn as the file number in quicker's left column
			col = 1,
			text = string.format("%-10s %s", e.label, churn(e.added, e.deleted)),
			user_data = { agent = "file" },
		}
	end
	return items
end

--- Quickfix rows for the commits section: a header followed by one row per
--- commit (newest first), with a marker on the ones not pushed yet. Commit rows
--- carry the full sha in user_data so <CR> can open `git show` for them.
--- @return table[]
commit_items = function()
	local commits = M.commit_list()
	if #commits == 0 then
		return {}
	end
	local items = {
		{
			text = "Commits",
			valid = 1,
			bufnr = 0,
			lnum = 0,
			col = 0,
			user_data = { header = "hard", agent = "header" },
		},
	}
	for _, c in ipairs(commits) do
		items[#items + 1] = {
			text = (c.unpushed and (UNPUSHED_MARK .. " ") or "") .. c.subject,
			valid = 1,
			bufnr = 0,
			lnum = 0,
			col = 0,
			module = c.short,
			user_data = { agent = "commit", sha = c.sha, unpushed = c.unpushed or false },
		}
	end
	return items
end

--- Build the full agent quickfix list: changed files, then the commits section.
--- @return table[] items
local function build_items()
	local entries = M.changed_files() or {}
	local items = file_items(entries)
	vim.list_extend(items, commit_items())
	return items
end

--- Push all changed files into the quickfix list and open it.
function M.quickfix_all()
	local root = git_root()
	if not root then
		notify("Not inside a git repository", vim.log.levels.WARN)
		return
	end

	local items = build_items()
	if #items == 0 then
		notify("No uncommitted changes", vim.log.levels.WARN)
		return
	end

	vim.fn.setqflist({}, "r", { title = "Agent changes", items = items })
	vim.cmd("copen")
	attach_qf(vim.api.nvim_get_current_buf())
	local nfiles, ncommits = 0, 0
	for _, it in ipairs(items) do
		local agent = type(it.user_data) == "table" and it.user_data.agent
		if agent == "file" then
			nfiles = nfiles + 1
		elseif agent == "commit" then
			ncommits = ncommits + 1
		end
	end
	local parts = {}
	if nfiles > 0 then
		parts[#parts + 1] = string.format("%d changed file%s", nfiles, nfiles == 1 and "" or "s")
	end
	if ncommits > 0 then
		parts[#parts + 1] = string.format("%d commit%s", ncommits, ncommits == 1 and "" or "s")
	end
	notify("Added " .. table.concat(parts, " and ") .. " to quickfix")
end

--- Rebuild the agent quickfix list in place (changed files + commits). Used
--- after a commit so the committed files drop out and the new commit appears.
--- Only touches the list titled "Agent changes".
function M.rebuild()
	if vim.fn.getqflist({ title = 0 }).title ~= "Agent changes" then
		return
	end
	vim.fn.setqflist({}, "r", { title = "Agent changes", items = build_items() })
end

--- Refresh git status everywhere that displays it, and rebuild the agent
--- quickfix list so committed/removed files drop out and new commits appear.
--- @param opts? { silent?: boolean }
function M.refresh(opts)
	opts = opts or {}
	pcall(function()
		require("fff.file_picker").refresh_git_status()
	end)
	pcall(function()
		require("gitsigns").refresh()
	end)
	M.rebuild()
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

		local subject = vim.trim((git({ "log", "-1", "--format=%s" }, root).stdout or ""))
		notify("Committed: " .. (subject ~= "" and subject or msg))
		-- Rebuild: committed files drop out and the new commit tops the section.
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

--- Window currently showing a commit view buffer, if any.
--- @return integer|nil
local function commit_view_win()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
		if name:find("^agentcommit://", 1) then
			return win
		end
	end
	return nil
end

--- Show a commit's changes (`git show`) in a split below the current window.
--- Reuses an existing commit view window when one is open. Press q to close it.
--- @param sha string
function M.show_commit(sha)
	local root = git_root()
	if not root then
		notify("Not inside a git repository", vim.log.levels.WARN)
		return
	end

	local res = git({ "show", "--stat", "--patch", "--no-color", sha }, root)
	if res.code ~= 0 then
		notify("git show failed: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
		return
	end

	local lines = vim.split(res.stdout or "", "\n", { plain = true })

	local win = commit_view_win()
	if win then
		vim.api.nvim_set_current_win(win)
	else
		vim.cmd("botright split")
	end

	local buf = vim.api.nvim_get_current_buf()
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "diff"
	local name = "agentcommit://" .. sha
	if vim.api.nvim_buf_get_name(buf) ~= name then
		pcall(vim.api.nvim_buf_set_name, buf, name)
	end
	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = true, silent = true, desc = "Close commit view" })
end

--- Show a deleted file's last committed content (HEAD) in a read-only scratch
--- split below the current window. Press q to close it.
--- @param root string
--- @param rel string
local function show_deleted(root, rel)
	local res = git({ "show", "HEAD:" .. rel }, root)
	if res.code ~= 0 then
		notify("git show failed: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
		return
	end
	vim.cmd("botright split")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(res.stdout or "", "\n", { plain = true }))
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	local ft = vim.filetype.match({ filename = rel })
	if ft then
		vim.bo[buf].filetype = ft
	end
	pcall(vim.api.nvim_buf_set_name, buf, "agentdeleted://" .. rel)
	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true, desc = "Close" })
end

--- Searchable floating list of ALL changes (modified, new, deleted, ...).
---   type to filter (fuzzy, multiple words allowed, status words match too:
---   "deleted foo")   <C-n>/<C-p>/<Down>/<Up> move   <Tab> select
---   <CR> open (deleted files show their HEAD content)
---   <C-q> send selected (or all listed) to the quickfix list   <Esc> close
function M.changes_picker()
	local root = git_root()
	if not root then
		notify("Not inside a git repository", vim.log.levels.WARN)
		return
	end
	local entries = M.changed_files() or {}
	if #entries == 0 then
		notify("No uncommitted changes", vim.log.levels.WARN)
		return
	end
	for _, e in ipairs(entries) do
		e.search = e.label .. " " .. e.path
	end

	local ui_w, ui_h = vim.o.columns, vim.o.lines
	local w = math.min(math.max(60, math.floor(ui_w * 0.6)), ui_w - 4)
	local h = math.min(math.max(#entries, 5), math.max(5, math.floor(ui_h * 0.6)))
	local row = math.max(0, math.floor((ui_h - (h + 4)) / 2))
	local col = math.max(0, math.floor((ui_w - w) / 2))

	local list_buf = vim.api.nvim_create_buf(false, true)
	local prompt_buf = vim.api.nvim_create_buf(false, true)
	for _, b in ipairs({ list_buf, prompt_buf }) do
		vim.bo[b].buftype = "nofile"
		vim.bo[b].bufhidden = "wipe"
	end

	local list_win = vim.api.nvim_open_win(list_buf, false, {
		relative = "editor",
		row = row,
		col = col,
		width = w,
		height = h,
		style = "minimal",
		border = "rounded",
		focusable = false,
		title = " Agent changes ",
		title_pos = "left",
	})
	local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
		relative = "editor",
		row = row + h + 2,
		col = col,
		width = w,
		height = 1,
		style = "minimal",
		border = "rounded",
	})
	vim.wo[list_win].cursorline = true
	vim.wo[list_win].wrap = false

	local filtered, idx, selected, closed = entries, 1, {}, false

	local function render()
		local q = vim.trim(vim.api.nvim_buf_get_lines(prompt_buf, 0, 1, false)[1] or "")
		filtered = (q == "") and entries or vim.fn.matchfuzzy(entries, q, { key = "search" })
		idx = math.min(math.max(idx, 1), math.max(#filtered, 1))

		local lines = {}
		for i, e in ipairs(filtered) do
			local head = string.format("%s %-10s %s  ", selected[e.path] and "*" or " ", e.label, e.path)
			lines[i] = head .. churn(e.added, e.deleted)
		end
		if #lines == 0 then
			lines = { "  no matches" }
		end

		vim.bo[list_buf].modifiable = true
		vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
		vim.bo[list_buf].modifiable = false

		vim.api.nvim_buf_clear_namespace(list_buf, PICKER_NS, 0, -1)
		for i, e in ipairs(filtered) do
			local line = lines[i]
			vim.api.nvim_buf_set_extmark(list_buf, PICKER_NS, i - 1, 2, {
				hl_group = LABEL_HL[e.label] or "AgentReviewChanged",
				end_col = 2 + #e.label,
			})
			local init = 2 + 10 + 1 + #e.path + 2
			while true do
				local s, f = line:find("[+-]%d+", init)
				if not s then
					break
				end
				vim.api.nvim_buf_set_extmark(list_buf, PICKER_NS, i - 1, s - 1, {
					hl_group = line:sub(s, s) == "+" and "AgentReviewAdd" or "AgentReviewDel",
					end_col = f,
				})
				init = f + 1
			end
		end
		if #filtered > 0 then
			vim.api.nvim_win_set_cursor(list_win, { idx, 0 })
		end
	end

	local function close()
		if closed then
			return
		end
		closed = true
		vim.cmd("stopinsert")
		for _, win in ipairs({ prompt_win, list_win }) do
			if vim.api.nvim_win_is_valid(win) then
				pcall(vim.api.nvim_win_close, win, true)
			end
		end
	end

	local function move(d)
		if #filtered == 0 then
			return
		end
		idx = math.min(math.max(idx + d, 1), #filtered)
		vim.api.nvim_win_set_cursor(list_win, { idx, 0 })
	end

	local function toggle()
		local e = filtered[idx]
		if not e then
			return
		end
		selected[e.path] = (not selected[e.path]) or nil
		local keep = idx
		render()
		idx = keep
		move(1)
		render()
	end

	local function open_current()
		local e = filtered[idx]
		close()
		if not e then
			return
		end
		vim.schedule(function()
			if e.label == "deleted" then
				show_deleted(root, e.path)
			else
				vim.cmd("edit " .. vim.fn.fnameescape(e.abs))
			end
		end)
	end

	local function to_quickfix()
		local picked = {}
		for _, e in ipairs(filtered) do
			if selected[e.path] then
				picked[#picked + 1] = e
			end
		end
		if #picked == 0 then
			picked = filtered
		end
		if #picked == 0 then
			return
		end
		close()
		vim.schedule(function()
			local items = file_items(picked)
			vim.list_extend(items, commit_items())
			vim.fn.setqflist({}, "r", { title = "Agent changes", items = items })
			vim.cmd("copen")
			attach_qf(vim.api.nvim_get_current_buf())
		end)
	end

	local function m(keys, fn)
		for _, k in ipairs(keys) do
			vim.keymap.set({ "i", "n" }, k, fn, { buffer = prompt_buf, nowait = true, silent = true })
		end
	end
	m({ "<Esc>", "<C-c>" }, close)
	m({ "<C-n>", "<Down>", "<C-j>" }, function()
		move(1)
	end)
	m({ "<C-p>", "<Up>", "<C-k>" }, function()
		move(-1)
	end)
	m({ "<Tab>" }, toggle)
	m({ "<CR>" }, open_current)
	m({ "<C-q>" }, to_quickfix)

	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, { buffer = prompt_buf, callback = render })
	vim.api.nvim_create_autocmd("WinLeave", { buffer = prompt_buf, once = true, callback = close })

	render()
	vim.cmd("startinsert")
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

	map("<leader>gs", M.changes_picker, "Agent changes (searchable, incl. deleted)")
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

	vim.api.nvim_create_user_command(
		"AgentChanges",
		M.changes_picker,
		{ desc = "Search all agent changes (incl. deleted)" }
	)
	vim.api.nvim_create_user_command("AgentQuickfix", M.quickfix_all, { desc = "Send agent changes to quickfix" })
	vim.api.nvim_create_user_command("AgentStage", M.stage_all, { desc = "Stage all changes" })
	vim.api.nvim_create_user_command("AgentCommit", function()
		M.commit()
	end, { desc = "Stage and commit all changes" })
	vim.api.nvim_create_user_command("AgentPush", M.push, { desc = "Push current branch" })
end

return M
