-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- reload current file
-- 20260328: a hack for treesitter/syntax issue
vim.keymap.set("n", "<leader>re", "<cmd>edit<cr>", { desc = "Reload File" })
