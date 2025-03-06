-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

-- Add the datetime insertion mapping correctly
map("n", "<leader>id", function()
  local pos = vim.api.nvim_win_get_cursor(0)
  local row = pos[1] - 1
  local col = pos[2]

  local datetime = vim.fn.system("date"):gsub("[\n\r]", "")
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
  local new_line = line:sub(1, col) .. datetime .. line:sub(col + 1)

  vim.api.nvim_buf_set_lines(0, row, row + 1, false, { new_line })
end, { desc = "󱨰 +insert/datetime" })
