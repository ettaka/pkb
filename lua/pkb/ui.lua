local M = {}

---------------------------------------------------------------
-- POPUP DISPLAY LOGIC (Consolidated Window Support)
---------------------------------------------------------------
function M.show_next_popup(popup_active, popup_queue, active_popups, snooz_interval)
  if popup_active or #popup_queue == 0 then return end

  popup_active = true

  -- Extract all items currently queued into a local list
  local batch = {}
  while #popup_queue > 0 do
    table.insert(batch, table.remove(popup_queue, 1))
  end

  vim.schedule(function()
    if vim.fn.mode() ~= "n" then
      vim.cmd("stopinsert")
    end

    local buf = vim.api.nvim_create_buf(false, true)
    local lines = {}

    if #batch == 1 then
      local entry = batch[1]
      lines = {
        "🔔 PKB Task Notification",
        "",
        entry.line,
        "",
        "File: " .. entry.file,
        "Due:  " .. os.date("%Y-%m-%d %H:%M", entry.due_ts),
        "",
        "[Enter] open  |  [d] dismiss  |  [q] snooze (" .. math.floor(snooz_interval / 60) .. "m)",
      }
    else
      lines = {
        string.format("🔔 PKB Digest — %d Tasks Need Attention", #batch),
        "",
      }
      for i, entry in ipairs(batch) do
        table.insert(lines, string.format("%d. %s", i, entry.line))
        table.insert(lines, string.format("   Due: %s | File: %s", os.date("%Y-%m-%d %H:%M", entry.due_ts), entry.file))
        table.insert(lines, "")
      end
      table.insert(lines, "[Enter] open inbox  |  [q] snooze all")
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"

    local width  = math.min(90, vim.o.columns - 4)
    local height = #lines + 2
    local row    = math.floor((vim.o.lines - height) / 2)
    local col    = math.floor((vim.o.columns - width) / 2)

    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      border = "rounded",
      style = "minimal",
    })
    table.insert(active_popups, win)

    vim.api.nvim_set_current_win(win)

    local function close_popup()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      popup_active = false
      M.show_next_popup(popup_active, popup_queue, active_popups, snooz_interval)
    end

    -- Keybindings
    vim.keymap.set("n", "<CR>", function()
      close_popup()
      if #batch == 1 then
        local entry = batch[1]
        vim.cmd("edit " .. vim.fn.fnameescape(entry.file))
        vim.fn.search(vim.fn.escape(entry.line, "\\/.*$^~[]"), "W")
      else
        require("pkb.notifier").inbox()
      end
    end, { buffer = buf })

    vim.keymap.set("n", "d", function()
      if #batch == 1 then
        batch[1].dismissed = true
      end
      close_popup()
    end, { buffer = buf })

    vim.keymap.set("n", "q", function()
      -- Snooze active entries for snooz_interval
      local snooze_until = os.time() + snooz_interval
      for _, entry in ipairs(batch) do
        entry.auto_snoozed_until = snooze_until
      end
      close_popup()
    end, { buffer = buf })
  end)
end

return M
