return {
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		-- Basic syntax is immediate. Tree-sitter is loaded after the first UI
		-- frame, so it cannot delay opening a large HTML document.
		event = "VeryLazy",
		config = function()
			-- This is the `main` branch of nvim-treesitter: there is no
			-- `nvim-treesitter.configs` module. Highlighting is enabled per
			-- buffer with vim.treesitter.start().
			--
			-- Angular templates are plain HTML for tree-sitter purposes. Without
			-- this mapping, filetype `htmlangular` asks for an `angular` parser
			-- that is usually not installed.
			vim.treesitter.language.register("html", "htmlangular")

			vim.api.nvim_create_autocmd("FileType", {
				callback = function(args)
					-- config/bigfile.lua turns tree-sitter off for huge buffers.
					if vim.b[args.buf].bigfile then
						return
					end
					-- pcall: no parser installed for this filetype is not an error.
					if not pcall(vim.treesitter.start, args.buf) then
						return
					end
					-- Only replace the filetype's indenting when the language
					-- really has an `indents` query. Without it nvim-treesitter's
					-- indentexpr returns 0 for every line, so a new line loses
					-- the current indentation (this is what broke Enter in Lua
					-- files: Neovim ships a Lua parser, but no Lua indents query).
					-- In that case keep the built-in indentexpr / autoindent.
					local filetype = vim.bo[args.buf].filetype
					local lang = vim.treesitter.language.get_lang(filetype) or filetype
					if vim.treesitter.query.get(lang, "indents") then
						vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					end
				end,
			})
			-- The current buffer may have emitted FileType before this lazy
			-- plugin loaded. Re-run it after the first frame for normal files.
			vim.defer_fn(function()
				local buf = vim.api.nvim_get_current_buf()
				if vim.api.nvim_buf_is_valid(buf) and not vim.b[buf].bigfile and vim.bo[buf].filetype ~= "" then
					vim.api.nvim_exec_autocmds("FileType", { buffer = buf })
				end
			end, 100)
		end,
	},
}
