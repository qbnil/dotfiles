-- Quickfix buffer tweaks.
--
-- quicker.nvim makes the list editable, but deleting entries only rebuilds the
-- real quickfix list on write (stevearc/quicker.nvim#60). Until then, <CR> and
-- :cnext jump to the entry that used to be at that position. Apply right after
-- a delete so navigation stays correct.

vim.keymap.set("n", "dd", "dd:w<CR>", { buffer = true, silent = true, desc = "Delete entry and apply" })
vim.keymap.set("x", "d", "d:w<CR>", { buffer = true, silent = true, desc = "Delete entries and apply" })
vim.keymap.set("n", "q", "<cmd>cclose<CR>", { buffer = true, silent = true, desc = "Close quickfix" })

-- <CR> opens the entry under the cursor as usual. In the agent-review list the
-- "Commits" section header does nothing, and a commit row opens `git show` for
-- that commit instead of trying to jump to a file. Rows are tagged via
-- user_data, so ordinary quickfix lists keep their default behaviour.
vim.keymap.set("n", "<CR>", function()
	local item = vim.fn.getqflist()[vim.api.nvim_win_get_cursor(0)[1]]
	local ud = item and item.user_data
	if type(ud) == "table" then
		if ud.agent == "commit" and ud.sha then
			require("config.agent_review").show_commit(ud.sha)
			return
		elseif ud.agent == "header" then
			return
		end
	end
	vim.cmd("normal! \r")
end, { buffer = true, silent = true, desc = "Open entry / view commit" })
