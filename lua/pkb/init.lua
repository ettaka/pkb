local M = {}

local notifier = require("pkb.notifier")

function M.setup(opts)
  -- If you add a config module later, you can pass options here
  notifier.start_timer()
  vim.notify("PKB plugin loaded successfully!", vim.log.levels.INFO)
end

return M
