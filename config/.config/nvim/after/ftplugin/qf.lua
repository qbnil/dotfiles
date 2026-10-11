-- Quickfix buffer tweaks.
--
-- quicker.nvim makes the list editable, but deleting entries only rebuilds the
-- real quickfix list on write (stevearc/quicker.nvim#60). Until then, <CR> and
-- :cnext jump to the entry that used to be at that position. Apply right after
-- a delete so navigation stays correct.

vim.keymap.set("n", "dd", "dd:w<CR>", { buffer = true, silent = true, desc = "Delete entry and apply" })
vim.keymap.set("x", "d", "d:w<CR>", { buffer = true, silent = true, desc = "Delete entries and apply" })
vim.keymap.set("n", "q", "<cmd>cclose<CR>", { buffer = true, silent = true, desc = "Close quickfix" })
