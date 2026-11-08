-- Fast path for large buffers.
--
-- Neovim is fast on big files by itself. What is slow is anything that walks
-- the whole buffer on every redraw: regex syntax highlighting, tree-sitter,
-- LSP servers, gitsigns, cursorline/relativenumber, signs, undo files, and --
-- for files with one huge line -- filetype detection itself (it scans the
-- first 100 lines for patterns).
--
-- This module detects "big" buffers and turns those features off *for that
-- buffer only*. Normal files keep every feature.

local M = {}

-- Tune these two values if you like.
local MAX_SIZE = 2 * 1024 * 1024 -- bytes: file bigger than 2 MiB is "big"
local MAX_LINE = 100 * 1024 -- bytes: any single line longer than 100 KiB is "big"
local MAX_SYNTAX_COLUMN = 200 -- highlight only the useful beginning of huge lines

local uv = vim.uv or vim.loop

-- Cheap extension -> filetype map, used instead of the expensive content scan.
local EXT = {
	html = "html",
	htm = "html",
	json = "json",
	lua = "lua",
	js = "javascript",
	mjs = "javascript",
	cjs = "javascript",
	ts = "typescript",
	tsx = "typescript",
	css = "css",
	md = "markdown",
	markdown = "markdown",
	py = "python",
	sh = "sh",
	bash = "sh",
	zsh = "zsh",
	go = "go",
	yml = "yaml",
	yaml = "yaml",
	xml = "xml",
	txt = "text",
	conf = "conf",
	ini = "dosini",
}

local function buf_size(buf)
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then
		return 0
	end
	local stat = uv.fs_stat(name)
	return stat and stat.size or 0
end

--- True when the buffer contains a line longer than MAX_LINE bytes.
--- Uses Vim's regex engine (C), so it is cheap even on large files.
local function has_long_line(buf)
	return vim.api.nvim_buf_call(buf, function()
		-- \%>Nc. matches any character after column N, i.e. a line longer than N.
		return vim.fn.search("\\%>" .. MAX_LINE .. "c.", "nw") > 0
	end)
end

local function is_big(buf)
	if vim.b[buf].bigfile then
		return true
	end
	if vim.b[buf].bigfile_checked then
		return false
	end
	vim.b[buf].bigfile_checked = true
	local size = buf_size(buf)
	if size > MAX_SIZE then
		return true
	end
	-- Only scan small files; large ones are already caught above.
	return size > 0 and has_long_line(buf)
end

local function infer_filetype(buf)
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then
		return ""
	end
	local ext = vim.fn.fnamemodify(name, ":e"):lower()
	return EXT[ext] or ""
end

local function set_window_options(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	vim.wo[win].cursorline = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "auto"
	vim.wo[win].number = true
	vim.wo[win].foldmethod = "manual"
	vim.wo[win].foldenable = false
	vim.wo[win].wrap = false
	vim.wo[win].list = false
	vim.wo[win].spell = false
	vim.wo[win].conceallevel = 0
	vim.wo[win].colorcolumn = ""
end

local function disable_features(buf)
	vim.b[buf].bigfile = true

	-- Filetype detection was skipped for this buffer (it scans content and is
	-- very slow for files with a single huge line). Infer it cheaply from the
	-- extension so ftplugins, syntax and LSP still work.
	if vim.bo[buf].filetype == "" then
		vim.bo[buf].filetype = infer_filetype(buf)
	end

	-- Keep basic regex syntax highlighting, but never scan an entire huge line.
	-- Set the syntax only once (setting 'syntax' reloads its file every time).
	if vim.bo[buf].filetype ~= "" and vim.bo[buf].syntax == "" then
		vim.bo[buf].synmaxcol = MAX_SYNTAX_COLUMN
		vim.bo[buf].syntax = vim.bo[buf].filetype == "htmlangular" and "html" or vim.bo[buf].filetype
	end
	-- Let lightweight language servers run, but cap diagnostics and completion
	-- work to the visible/useful part of this unusually large document.
	vim.b[buf].bigfile_lsp = true

	-- Features that load extra state or walk the whole buffer.
	if vim.bo[buf].undofile then
		vim.bo[buf].undofile = false
	end
	if vim.bo[buf].swapfile then
		vim.bo[buf].swapfile = false
	end
	vim.bo[buf].modeline = false
	vim.bo[buf].textwidth = 0
	vim.bo[buf].complete = ""
	vim.bo[buf].omnifunc = ""
	vim.bo[buf].tagfunc = ""
	vim.bo[buf].formatexpr = ""
	vim.bo[buf].indentexpr = ""

	-- Window decorations, for every window that shows this buffer.
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		set_window_options(win)
	end

	-- nvim-ts-autotag attaches on insert and would create a tree-sitter parser
	-- for this buffer. Detach it only if the plugin happens to be loaded already;
	-- do not pay its load cost just to disable it.
	local autotag = package.loaded["nvim-ts-autotag.internal"]
	if autotag and autotag.detach then
		pcall(autotag.detach, buf)
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("BigFile", { clear = true })

	-- Runs before the file is read: stop undo/swap files from being loaded and
	-- mark the buffer so filetype detection is skipped.
	vim.api.nvim_create_autocmd("BufReadPre", {
		group = group,
		callback = function(args)
			if buf_size(args.buf) > MAX_SIZE then
				vim.b[args.buf].bigfile = true
				-- Make the runtime's `syntaxset` autocmd skip regex syntax.
				vim.b[args.buf].ts_highlight = true
				vim.bo[args.buf].undofile = false
				vim.bo[args.buf].swapfile = false
			end
		end,
	})

	-- Skip the expensive content-based filetype scan for big buffers. The
	-- filetype is inferred from the extension instead (see infer_filetype).
	local orig_match = vim.filetype.match
	vim.filetype.match = function(args)
		local buf = args and args.buf
		if buf and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].bigfile then
			return nil
		end
		return orig_match(args)
	end

	-- FileType fires after the content is loaded and before most plugins act.
	-- BufReadPost and BufWinEnter are extra passes: BufWinEnter runs after the
	-- runtime's `syntaxset` autocmd, so it is where we finally clear syntax.
	vim.api.nvim_create_autocmd({ "FileType", "BufReadPost", "BufWinEnter" }, {
		group = group,
		callback = function(args)
			if is_big(args.buf) then
				disable_features(args.buf)
			end
		end,
	})
end

return M
