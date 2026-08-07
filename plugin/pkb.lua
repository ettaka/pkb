vim.api.nvim_create_user_command("PKBHello", function()
  require("pkb").setup()
end, {})
