return {
  'ThePrimeagen/harpoon',
  branch = 'harpoon2',
  dependencies = { 'nvim-lua/plenary.nvim', 'folke/which-key.nvim' },
  config = function()
    local harpoon = require 'harpoon'
    local whichkey = require 'which-key'
    harpoon:setup {}

    whichkey.add {
      {
        mode = { 'n' },
        { '<leader>la', group = 'Harpoon [L]ist' },
      },
    }

    vim.keymap.set('n', '<leader>la', function()
      harpoon:list():add()
    end, { desc = 'Harpoon: [L]ist [A]dd' })

    vim.keymap.set('n', '<M-l>', function()
      harpoon.ui:toggle_quick_menu(harpoon:list())
    end, { desc = 'Harpoon: Show [l]ist' })

    vim.keymap.set('n', '<M-1>', function()
      harpoon:list():select(1)
    end, { desc = 'Harpoon: Select file 1' })
    vim.keymap.set('n', '<M-2>', function()
      harpoon:list():select(2)
    end, { desc = 'Harpoon: Select file 2' })
    vim.keymap.set('n', '<M-3>', function()
      harpoon:list():select(3)
    end, { desc = 'Harpoon: Select file 3' })
    vim.keymap.set('n', '<M-4>', function()
      harpoon:list():select(4)
    end, { desc = 'Harpoon: Select file 4' })

    -- Toggle previous & next buffers stored within Harpoon list
    vim.keymap.set('n', '<m-k>', function()
      harpoon:list():prev()
    end)
    vim.keymap.set('n', '<m-j>', function()
      harpoon:list():next()
    end)
  end,
}