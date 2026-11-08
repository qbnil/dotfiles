-- Basic indentation fallback for filetypes that do not ship an indent script
-- and whose language has no tree-sitter `indents` query.
--
-- Neovim already ships indent scripts for most common languages, and filetypes
-- with an indent query get nvim-treesitter's indenter from plugins/treesitter.lua.
-- This module only fills the remaining gap so that Enter at least indents
-- brackets and common block keywords instead of doing nothing.

local M = {}

-- Plain-text-ish buffers where adding bracket indentation would be wrong.
local text_like = {
	text = true,
	markdown = true,
	gitcommit = true,
	gitrebase = true,
	help = true,
	qf = true,
	man = true,
	oil = true,
	markdown_inline = true,
}

local openers = { "then", "do", "begin", "repeat", "try", "else", "where" }
local closers = { "end", "else", "elseif", "until", "catch", "finally", "fi", "done" }

local function matches_keyword(line, keywords)
	for _, keyword in ipairs(keywords) do
		-- Whole word, possibly followed by punctuation and trailing spaces.
		if line:match("%f[%w_]" .. keyword .. "%f[^%w_]%s*$") then
			return true
		end
	end
	return false
end

--- indentexpr used for filetypes without a dedicated indent script.
--- @return integer
function M.expr()
	local lnum = vim.v.lnum
	local prev = vim.fn.prevnonblank(lnum - 1)
	if prev == 0 then
		return 0
	end

	local shiftwidth = vim.fn.shiftwidth()
	local indent = vim.fn.indent(prev)
	local prevline = vim.fn.getline(prev)
	local thisline = vim.fn.getline(lnum)

	-- A line that closes a block is one level less indented.
	if thisline:match("^%s*[%)}%]]") or matches_keyword((thisline:gsub("^%s*", "")), closers) then
		indent = indent - shiftwidth
	end

	-- A line that opens a block is one level more indented.
	if prevline:match("[%({%[]%s*$") or matches_keyword((prevline:gsub("%s*$", "")), openers) then
		indent = indent + shiftwidth
	end

	return math.max(indent, 0)
end

function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("BasicIndent", { clear = true }),
		callback = function(args)
			-- Schedule so the filetype's own ftplugin/indent script and the
			-- tree-sitter FileType callback run first.
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(args.buf) then
					return
				end
				local ft = vim.bo[args.buf].filetype
				if text_like[ft] or vim.bo[args.buf].indentexpr ~= "" then
					return
				end
				vim.bo[args.buf].indentexpr = "v:lua.require'config.indent'.expr()"

				-- Re-indent when a closing keyword is typed at the start of a line.
				local indentkeys = vim.bo[args.buf].indentkeys
				for _, key in ipairs({
					"0=end",
					"0=else",
					"0=elseif",
					"0=until",
					"0=catch",
					"0=finally",
					"0=fi",
					"0=done",
				}) do
					if not indentkeys:find(key, 1, true) then
						indentkeys = indentkeys .. "," .. key
					end
				end
				vim.bo[args.buf].indentkeys = indentkeys
			end)
		end,
	})
end

return M
