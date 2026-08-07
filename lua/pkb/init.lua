local M = {}

local notifier = require("pkb.notifier")

function M.setup(opts)
  opts = opts or {}
  notifier.setup(opts)
  vim.notify("PKB plugin loaded successfully!", vim.log.levels.INFO)
end

return M
