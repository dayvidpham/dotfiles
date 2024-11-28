if vim.g.neovide == true then
  vim.api.nvim_set_keymap('n', '<C-=>', ':lua vim.g.neovide_scale_factor = math.min(vim.g.neovide_scale_factor + 0.1,  2.0)<CR>', { silent = true })
  vim.api.nvim_set_keymap('n', '<C-->', ':lua vim.g.neovide_scale_factor = math.max(vim.g.neovide_scale_factor - 0.1,  0.1)<CR>', { silent = true })
  vim.api.nvim_set_keymap('n', '<C-0>', ':lua vim.g.neovide_scale_factor = 1.0<CR>', { silent = true })
  -- Below: keybinds for transparency
  --vim.api.nvim_set_keymap('n', '<C-+>', ':lua vim.g.neovide_transparency = math.min(vim.g.neovide_transparency + 0.05, 1.0)<CR>', { silent = true })
  --vim.api.nvim_set_keymap('n', '<C-_>', ':lua vim.g.neovide_transparency = math.max(vim.g.neovide_transparency - 0.05, 0.0)<CR>', { silent = true })
  --vim.api.nvim_set_keymap('n', '<C-)>', ':lua vim.g.neovide_transparency = 0.9<CR>', { silent = true })
end
