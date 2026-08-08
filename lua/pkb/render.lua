local M = {}

function M.render_inbox(notifications, inbox_show_all, buf)
  local items = {}

  for _, n in pairs(notifications) do
    if not n.line:match("^%s*%- %[[xX]%]") then
      if inbox_show_all or not n.dismissed then
        table.insert(items, n)
      end
    end
  end

  table.sort(items, function(a, b)
    return a.due_ts < b.due_ts
  end)

  local lines = {}
  for _, n in ipairs(items) do
    local status =
      n.dismissed and "[x]" or
      n.triggered and "[!]" or
      "[ ]"

    table.insert(lines,
      string.format(
        "%s %s | %s | due %s",
        status,
        n.line,
        n.file,
        os.date("%Y-%m-%d %H:%M", n.due_ts)
      )
    )
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

return M
