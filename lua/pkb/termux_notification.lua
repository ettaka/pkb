---------------------------------------------------------------
-- TERMUX CONSOLIDATED NOTIFICATION (Single Card)
---------------------------------------------------------------
local M = {}

M.DEVICE_IS_PHONE = false

function M.setup(opts)
  opts = opts or {}
  if opts.DEVICE_IS_PHONE ~= nil then
    M.DEVICE_IS_PHONE = opts.DEVICE_IS_PHONE
  end
end

function M.phone_notify_digest(due_entries)
  if #due_entries == 0 then return end

  local title = string.format("PKB Digest (%d Pending Task%s)", #due_entries, #due_entries > 1 and "s" or "")
  local content = ""

  if #due_entries == 1 then
    local entry = due_entries[1]
    content = string.format("%s\nDue: %s", entry.line, os.date("%H:%M", entry.due_ts))
  else
    local top_entry = due_entries[1]
    content = string.format("Next: %s\n(+ %d more task%s)", top_entry.line, #due_entries - 1, #due_entries > 2 and "s" or "")
  end

  if M.DEVICE_IS_PHONE then
    vim.fn.jobstart({
      "termux-notification",
      "--id", "pkb_digest", -- Fixed ID prevents notification clutter
      "--title", title,
      "--content", content,
    }, {
      detach = true,
    })
  end
end

---------------------------------------------------------------
-- SCAN & PARSING
---------------------------------------------------------------
function M.phone_notify(entry)
  vim.fn.jobstart({
    "termux-notification",
    "--title", "PKB Reminder",
    "--content",
    string.format(
      "%s\nDue: %s",
      entry.line,
      os.date("%H:%M", entry.due_ts)
    ),
  }, {
    detach = true,
  })
end


return M
