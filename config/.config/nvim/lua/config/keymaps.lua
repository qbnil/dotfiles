vim.keymap.set("n", "<leader>u", function()
	vim.cmd("update")
	vim.cmd("source $MYVIMRC")
end, { silent = true, desc = "Source and update neovim config" })

local session_file = vim.fn.stdpath("state") .. "/Session.vim"
vim.keymap.set("n", "<leader>re", function()
	vim.cmd("mks! " .. vim.fn.fnameescape(session_file))
	vim.cmd("restart source " .. vim.fn.fnameescape(session_file))
end, { silent = true, desc = "Restart nvim and restore session" })

vim.keymap.set({ "n", "v" }, "<leader>", "<nop>", { desc = "Disable leader key default" })

vim.keymap.set("n", "U", "<C-r>", { desc = "Redo" })

vim.keymap.set("n", "<Esc>", ":nohl<CR>", { silent = true, desc = "Clear search highlights" })

-- vim.keymap.set("n", "<C-j>", ":wincmd j<CR>", { silent = true, desc = "Move to below split" })
-- vim.keymap.set("n", "<C-h>", ":wincmd h<CR>", { silent = true, desc = "Move to left split" })
-- vim.keymap.set("n", "<C-k>", ":wincmd k<CR>", { silent = true, desc = "Move to above split" })
-- vim.keymap.set("n", "<C-l>", ":wincmd l<CR>", { silent = true, desc = "Move to right split" })
vim.keymap.set("n", "<leader>rr", ":wincmd r<CR>", { silent = true, desc = "Rotate split buffers" })

vim.keymap.set("n", "<leader>w", ":w<cr>", { silent = true, noremap = true, desc = "Save current file" })
vim.keymap.set({ "n", "t" }, "<leader>q", ":q<cr>", { silent = true, noremap = true, desc = "Quit current buffer" })
vim.keymap.set("n", "<leader>Q", function()
	vim.cmd("wall")
	vim.cmd("qa")
end, { silent = true, desc = "Save all changes and quit Neovim" })

vim.keymap.set(
	"n",
	"<leader>S",
	[[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
	{ silent = false, desc = "Search and replace word under cursor" }
)

vim.keymap.set("n", "<S-l>", ":bnext<CR>", { silent = true, desc = "Next buffer" })
vim.keymap.set("n", "<S-h>", ":bprevious<CR>", { silent = true, desc = "Previous buffer" })

vim.keymap.set("n", "<C-c>", ":bwipeout<CR>", { silent = true, desc = "Close current buffer" })

vim.keymap.set("n", "<S-k>", "<C-u>zz", { desc = "Scroll up and center" })
vim.keymap.set("n", "<S-j>", "<C-d>zz", { desc = "Scroll down and center" })

vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result centered" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous search result centered" })

vim.keymap.set("n", "<leader>p", '"_dP', { desc = "Paste without replacing register" })

vim.keymap.set("n", "<leader>y", '"+y', { desc = "Yank to system clipboard" })
vim.keymap.set("v", "<leader>y", '"+y', { desc = "Yank selection to system clipboard" })
vim.keymap.set("n", "<leader>Y", '"+Y', { desc = "Yank line to system clipboard" })

vim.keymap.set("n", "<leader>v", ":vsplit<CR>", { silent = true, desc = "Vertical split" })
vim.keymap.set("n", "<leader>h", ":split<CR>", { silent = true, desc = "Vertical split" })

vim.keymap.set("v", "<C-j>", ":m '>+1<CR>gv=gv", { silent = true, desc = "Move selection down" })
vim.keymap.set("v", "<C-k>", ":m '<-2<CR>gv=gv", { silent = true, desc = "Move selection up" })

vim.keymap.set("t", "<Esc>", "<C-\\><C-N>", { desc = "Exit terminal mode" })

vim.keymap.set("n", "<leader>oc", function()
	vim.cmd(":e ~/.config/nvim/init.lua")
end, { silent = true, desc = "Open neovim config" })

vim.keymap.set("n", "<leader>i", function()
	vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
	vim.notify(vim.lsp.inlay_hint.is_enabled() and "Inlay Hints Enabled" or "Inlay Hints Disabled")
end, { silent = true, desc = "Toggle inlay hints" })

vim.keymap.set("n", "<leader>tn", ":tabnew<CR>", { silent = true, desc = "New tab" })
vim.keymap.set("n", "<leader>tq", ":tabclose<CR>", { silent = true, desc = "Close tab" })
vim.keymap.set("n", "<leader>ts", ":tab split<CR>", { silent = true, desc = "Split to new tab" })
vim.keymap.set("n", "<leader><Tab>", ":tabnext<CR>", { silent = true, desc = "Next tab" })
vim.keymap.set("n", "<leader><S-Tab>", ":tabprevious<CR>", { silent = true, desc = "Previous tab" })

local function copy_ref(opts)
	local path = vim.fn.expand("%:.")
	local ref = path

	if opts.visual then
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")
		if start_line > end_line then
			start_line, end_line = end_line, start_line
		end
		ref = path .. ":" .. start_line .. ":" .. end_line
	end

	local note = vim.fn.input("Prompt (optional): ")
	if note ~= "" then
		ref = ref .. " " .. note
	end

	vim.fn.setreg("+", ref)
	vim.notify("Copied: " .. ref)
end

vim.keymap.set("n", "<leader>cp", function()
	copy_ref({})
end, { desc = "Copy file path" })

vim.keymap.set("v", "<leader>cp", function()
	copy_ref({ visual = true })
end, { desc = "Copy file path with line range" })

-- Window resizing: Ctrl+Shift+h/j/k/l move the window border in that direction
-- (Ctrl+Shift+l = border goes right, Ctrl+Shift+h = left, ...), whichever side of the window
-- the border is on. <leader>= makes all windows equal. A count multiplies the step
-- (3<C-S-l>).
local function resize(dir, step)
	local count = vim.v.count1
	local cur = vim.fn.winnr()
	local amount = step * count
	if dir == "h" or dir == "l" then
		local has_right = vim.fn.winnr("l") ~= cur
		-- the border we move is the right one when there is a neighbour on the right
		local grow = (dir == "l") == has_right
		if not has_right and vim.fn.winnr("h") == cur then
			return
		end
		vim.cmd(("vertical resize %s%d"):format(grow and "+" or "-", amount))
	else
		local has_below = vim.fn.winnr("j") ~= cur
		local grow = (dir == "j") == has_below
		if not has_below and vim.fn.winnr("k") == cur then
			return
		end
		vim.cmd(("resize %s%d"):format(grow and "+" or "-", amount))
	end
end

vim.keymap.set("n", "<C-h>", function()
	resize("h", 4)
end, { silent = true, desc = "Resize: border left" })
vim.keymap.set("n", "<C-l>", function()
	resize("l", 4)
end, { silent = true, desc = "Resize: border right" })
vim.keymap.set("n", "<C-j>", function()
	resize("j", 2)
end, { silent = true, desc = "Resize: border down" })
vim.keymap.set("n", "<C-k>", function()
	resize("k", 2)
end, { silent = true, desc = "Resize: border up" })
vim.keymap.set("n", "<leader>=", "<C-w>=", { silent = true, desc = "Equalize window sizes" })
