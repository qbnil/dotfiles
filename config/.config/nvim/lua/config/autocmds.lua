vim.api.nvim_create_autocmd("TextYankPost", {
	group = vim.api.nvim_create_augroup("highlight_yank", { clear = true }),
	pattern = "*",
	desc = "highlight selection on yank",
	callback = function()
		vim.highlight.on_yank({ timeout = 200, visual = true })
	end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
	callback = function(args)
		-- Do not jump into (and center) a huge file: `zz` on a buffer with a
		-- multi-megabyte line forces Neovim to render that line immediately.
		if vim.b[args.buf].bigfile then
			return
		end
		local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
		local line_count = vim.api.nvim_buf_line_count(args.buf)
		if mark[1] > 0 and mark[1] <= line_count then
			vim.api.nvim_win_set_cursor(0, mark)
			vim.schedule(function()
				vim.cmd("normal! zz")
			end)
		end
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	pattern = "help",
	command = "wincmd L",
})

vim.api.nvim_create_autocmd("VimResized", {
	command = "wincmd =",
})

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("no_auto_comment", {}),
	callback = function()
		vim.opt_local.formatoptions:remove({ "c", "r", "o" })
	end,
})

vim.api.nvim_create_autocmd("BufRead", {
	group = vim.api.nvim_create_augroup("dotenv_ft", { clear = true }),
	pattern = { ".env", ".env.*" },
	callback = function()
		vim.bo.filetype = "dosini"
	end,
})

vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
	group = vim.api.nvim_create_augroup("active_cursorline", { clear = true }),
	callback = function()
		-- cursorline forces a redraw on every cursor move, which is painful
		-- on huge lines.
		vim.opt_local.cursorline = not vim.b.bigfile
	end,
})

-- Remove the leftover startup `[No Name]` buffer (and any other unused empty
-- buffer) once a real buffer is entered. Buffers that are displayed in a
-- window, modified, named, or have a special buftype are never touched.
vim.api.nvim_create_autocmd("BufEnter", {
	group = vim.api.nvim_create_augroup("remove_empty_buffers", { clear = true }),
	callback = function()
		vim.schedule(function()
			local current = vim.api.nvim_get_current_buf()
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if
					buf ~= current
					and vim.api.nvim_buf_is_loaded(buf)
					and vim.api.nvim_buf_get_name(buf) == ""
					and vim.bo[buf].buftype == ""
					and not vim.bo[buf].modified
					and #vim.fn.getbufinfo(buf)[1].windows == 0
					and vim.api.nvim_buf_line_count(buf) == 1
					and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
				then
					pcall(vim.api.nvim_buf_delete, buf, { force = true })
				end
			end
		end)
	end,
})
