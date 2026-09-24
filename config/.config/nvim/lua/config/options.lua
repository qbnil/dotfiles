vim.g.mapleader = " "

vim.o.termguicolors = true
vim.o.updatetime = 200
vim.o.swapfile = false
vim.o.backup = false
vim.o.autoread = true
vim.o.undofile = true
vim.o.number = true
vim.o.relativenumber = true

vim.o.completeopt = "menu,menuone,noselect,preview"
vim.o.pumheight = 10
vim.o.winborder = "rounded"
vim.o.showmode = false

vim.o.cursorline = true
vim.o.signcolumn = "yes"
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.incsearch = true

vim.o.tabstop = 2
vim.o.softtabstop = 2
vim.o.shiftwidth = 2
vim.o.expandtab = true
vim.o.smartindent = true
vim.o.autoindent = true
vim.o.scrolloff = 8

vim.o.splitbelow = true
vim.o.splitright = true

vim.o.wrap = false
vim.o.breakindent = true
vim.opt.fillchars = { eob = " " }
vim.opt.guicursor = "n-v-c-i:block"
vim.o.laststatus = 3

vim.diagnostic.config({ virtual_text = true })
vim.o.cmdheight = 1
