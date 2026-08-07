require("pkb").setup()

vim.api.nvim_create_user_command("PKBNotify", function()
  require("pkb.notifier").notify()
end, {})

vim.api.nvim_create_user_command("PKBInbox", function()
  require("pkb.notifier").inbox()
end, {})
