-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  -- Angular navigation extras
  {
    'joeveiga/ng.nvim',
    config = function()
      local ng = require('ng')
      vim.keymap.set('n', '<leader>nt', ng.goto_template_for_component, { desc = 'goto template' })
      vim.keymap.set('n', '<leader>nc', ng.goto_component_with_template_file, { desc = 'goto component' })
      vim.keymap.set('n', '<leader>nT', ng.get_template_tcb, { desc = 'show TCB' })
    end,
  },
}
