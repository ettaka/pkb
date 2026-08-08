local M = {}

-- Store line-to-notification mapping per buffer if needed, or return/attach it
M._line_map = M._line_map or {}

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
  local line_map = {}
  local current_date = nil

  for _, n in ipairs(items) do
    local item_date = os.date("%Y-%m-%d", n.due_ts)

    if item_date ~= current_date then
      current_date = item_date
      if #lines > 0 then
        table.insert(lines, "")
      end
      table.insert(lines, "## " .. current_date)
    end

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
        os.date("%H:%M", n.due_ts)
      )
    )
    -- Map 1-based buffer line number to the notification object
    line_map[#lines] = n
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"

  -- Save line_map for this buffer so your action/picker handler can look it up
  M._line_map[buf] = line_map
end

function M.get_notification_at_cursor(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] -- 1-based line number

  local line_map = M._line_map[buf]
  if line_map then
    return line_map[row]
  end
  return nil
end

return M
