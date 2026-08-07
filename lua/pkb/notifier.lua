-- ============================================================
-- PKB Notifier — Consolidated Digest & Smart Auto-Snooze
-- ============================================================

local M = {}

---------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------
M.DEVICE_IS_PHONE = false
if DEVICE_IS_PHONE then
  M.PKB_ROOT = "/data/data/com.termux/files/home/pkb"  -- <<< change this
else
  M.PKB_ROOT = "/home/eelis/pkb"  -- <<< change this to your vault/root
end

M.DEFAULT_NOTIFY = "15min"
M.POLL_INTERVAL = 30000        -- Poll every 30 seconds (ms)
M.SNOOZE_INTERVAL = 30 * 60    -- Auto-snooze for 30 minutes (seconds) when closed with [q]

---------------------------------------------------------------
-- STATE
---------------------------------------------------------------
-- Keyed by stable ID: "path/to/file.md:line_num"
M.notifications = {}
M.active_popups = {}
M.popup_queue = {}
M.popup_active = false
M.timer = nil
M.inbox_show_all = false

---------------------------------------------------------------
-- TIMESTAMP PARSER (Z / H / +offset support)
---------------------------------------------------------------

local HOME_TZ = "+02:00"  -- your home timezone

-- convert offset string to seconds
local function offset_to_seconds(sign, hh, mm)
  return (tonumber(hh)*60 + tonumber(mm)) * 60 * (sign == "-" and -1 or 1)
end

local function parse_iso(ts)
  local y,m,d,H,M_,suffix

  y,m,d,H,M_,suffix = ts:match("(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)([ZH])")
  if not y then
    y,m,d,H,M_,suffix =
      ts:match("(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)([%+%-]%d%d:%d%d)")
  end

  if not y then return nil end

  local year  = tonumber(y)
  local month = tonumber(m)
  local day   = tonumber(d)
  local hour  = tonumber(H)
  local min   = tonumber(M_)

  local offset = 0

  if suffix == "Z" then
    offset = 0
  elseif suffix == "H" then
    local sign, hh, mm = HOME_TZ:match("([%+%-])(%d%d):(%d%d)")
    offset = offset_to_seconds(sign, hh, mm)
  else
    local sign, hh, mm = suffix:match("([%+%-])(%d%d):(%d%d)")
    offset = offset_to_seconds(sign, hh, mm)
  end

  -- construct UTC time
  local epoch = os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = 0,
    isdst = false,
  })

  -- system offset at that specific time (handles DST correctly)
  local local_offset = os.difftime(
    os.time(os.date("*t", epoch)),
    os.time(os.date("!*t", epoch))
  )

  epoch = epoch - offset + local_offset

  return epoch
end

local function parse_notify(str)
  local n = tonumber(str:match("(%d+)"))
  if not n then return 0 end
  if str:match("min") then return n * 60 end
  if str:match("h")   then return n * 3600 end
  if str:match("day") then return n * 86400 end
  return 0
end

---------------------------------------------------------------
-- TERMUX CONSOLIDATED NOTIFICATION (Single Card)
---------------------------------------------------------------
local function phone_notify_digest(due_entries)
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
-- POPUP DISPLAY LOGIC (Consolidated Window Support)
---------------------------------------------------------------
local function show_next_popup()
  if M.popup_active or #M.popup_queue == 0 then return end

  M.popup_active = true

  -- Extract all items currently queued into a local list
  local batch = {}
  while #M.popup_queue > 0 do
    table.insert(batch, table.remove(M.popup_queue, 1))
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
        "[Enter] open  |  [d] dismiss  |  [q] snooze (" .. math.floor(M.SNOOZE_INTERVAL / 60) .. "m)",
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
    table.insert(M.active_popups, win)

    vim.api.nvim_set_current_win(win)

    local function close_popup()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      M.popup_active = false
      show_next_popup()
    end

    -- Keybindings
    vim.keymap.set("n", "<CR>", function()
      close_popup()
      if #batch == 1 then
        local entry = batch[1]
        vim.cmd("edit " .. vim.fn.fnameescape(entry.file))
        vim.fn.search(vim.fn.escape(entry.line, "\\/.*$^~[]"), "W")
      else
        M.inbox()
      end
    end, { buffer = buf })

    vim.keymap.set("n", "d", function()
      if #batch == 1 then
        batch[1].dismissed = true
      end
      close_popup()
    end, { buffer = buf })

    vim.keymap.set("n", "q", function()
      -- Snooze active entries for SNOOZE_INTERVAL
      local snooze_until = os.time() + M.SNOOZE_INTERVAL
      for _, entry in ipairs(batch) do
        entry.auto_snoozed_until = snooze_until
      end
      close_popup()
    end, { buffer = buf })
  end)
end

---------------------------------------------------------------
-- SCAN & PARSING
---------------------------------------------------------------
local function phone_notify(entry)
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

---------------------------------------------------------------
-- SCHEDULING
---------------------------------------------------------------
local function schedule_notification(entry)
  local delay = entry.notify_ts - os.time()
  if delay < 0 then delay = 0 end

  vim.defer_fn(function()
    if entry.dismissed then
      return
    end

    entry.triggered = true

    -- Android notification
    phone_notify(entry)

    -- Neovim popup
    table.insert(M.popup_queue, entry)
    show_next_popup()

  end, delay * 1000)
end

---------------------------------------------------------------
-- PARSE LINE
---------------------------------------------------------------
local function parse_line(line, line_num, file, new_state)
  local due_str = line:match("due::([^%s]+)")
  if not due_str then return end

  local notify_str = line:match("notify::([%w]+)") or M.DEFAULT_NOTIFY
  local due_ts = parse_iso(due_str)
  if not due_ts then return end

  local notify_ts = due_ts - parse_notify(notify_str)
  if not line_num then 
      return 
  end
  local id = string.format("%s:%d", file, line_num)

  -- Preserve existing state across rescans
  local existing = M.notifications[id]

  new_state[id] = {
    id = id,
    line = line,
    file = file,
    line_num = line_num,
    due_ts = due_ts,
    notify_ts = notify_ts,
    triggered = existing and existing.triggered or false,
    dismissed = existing and existing.dismissed or false,
    auto_snoozed_until = existing and existing.auto_snoozed_until or nil,
  }
end

local function scan_file(file, new_state)
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok then return end
  for line_num, line in ipairs(lines) do
    parse_line(line, line_num, file, new_state)
  end
end

local function scan_dir(path, new_state)
  local handle = vim.loop.fs_scandir(path)
  if not handle then return end

  while true do
    local name, typ = vim.loop.fs_scandir_next(handle)
    if not name then break end
    local full = path .. "/" .. name

    if typ == "file" and name:match("%.md$") then
      scan_file(full, new_state)
    elseif typ == "directory" then
      scan_dir(full, new_state)
    end
  end
end

---------------------------------------------------------------
-- TIMER TICK / EVALUATION LOGIC
---------------------------------------------------------------
local function check_notifications()
  local now = os.time()
  local pending_due = {}

  for _, entry in pairs(M.notifications) do
    -- Filter out completed markdown checkmarks
    local is_done = entry.line:match("^%s*%- %[[xX]%]")

    if not is_done and not entry.dismissed then
      local is_due = now >= entry.notify_ts
      local snooze_expired = not entry.auto_snoozed_until or (now >= entry.auto_snoozed_until)

      if is_due and snooze_expired then
        entry.auto_snoozed_until = nil
        entry.triggered = true
        table.insert(pending_due, entry)
      end
    end
  end

  if #pending_due > 0 then
    -- Sort by due timestamp
    table.sort(pending_due, function(a, b) return a.due_ts < b.due_ts end)

    -- Send consolidated phone notification
    phone_notify_digest(pending_due)

    -- Queue for Neovim digest/popup
    for _, entry in ipairs(pending_due) do
      table.insert(M.popup_queue, entry)
    end
    show_next_popup()
  end
end

local function start_timer()
  if not M.timer then
    M.timer = vim.loop.new_timer()
    M.timer:start(0, M.POLL_INTERVAL, vim.schedule_wrap(function()
      check_notifications()
    end))
  end
end

---------------------------------------------------------------
-- COMMANDS & PUBLIC API
---------------------------------------------------------------
function M.notify()
  local new_state = {}
  scan_dir(M.PKB_ROOT, new_state)

  M.notifications = new_state

  local count = 0
  for _ in pairs(M.notifications) do count = count + 1 end

  start_timer()
  check_notifications()

  print("PKB notifications rescanned: " .. count)
end

function M.inbox()
  local function get_notification_list()
    local list = {}
    for _, n in pairs(M.notifications) do
      table.insert(list, n)
    end
    return list
  end

  if #get_notification_list() == 0 then
    vim.notify("No PKB notifications", vim.log.levels.INFO)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local function render()
    local items = {}

    for _, n in pairs(M.notifications) do
      if not n.line:match("^%s*%- %[[xX]%]") then
        if M.inbox_show_all or not n.dismissed then
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

  render()
  vim.api.nvim_set_current_buf(buf)

  -- d → dismiss
  vim.keymap.set("n", "d", function()
    local idx = vim.fn.line(".")
    local visible = {}

    for _, n in pairs(M.notifications) do
      if not n.line:match("^%s*%- %[[xX]%]") then
        if M.inbox_show_all or not n.dismissed then
          table.insert(visible, n)
        end
      end
    end

    table.sort(visible, function(a, b) return a.due_ts < b.due_ts end)

    local n = visible[idx]
    if n then
      n.dismissed = true
      render()
    end
  end, { buffer = buf })

  -- <CR> → open task
  vim.keymap.set("n", "<CR>", function()
    local idx = vim.fn.line(".")
    local visible = {}

    for _, n in pairs(M.notifications) do
      if not n.line:match("^%s*%- %[[xX]%]") then
        if M.inbox_show_all or not n.dismissed then
          table.insert(visible, n)
        end
      end
    end

    table.sort(visible, function(a, b) return a.due_ts < b.due_ts end)

    local n = visible[idx]
    if not n then return end

    vim.cmd("edit " .. vim.fn.fnameescape(n.file))
    vim.fn.search(vim.fn.escape(n.line, "\\/.*$^~[]"), "W")
  end, { buffer = buf })

  -- t → toggle view
  vim.keymap.set("n", "t", function()
    M.inbox_show_all = not M.inbox_show_all
    render()
  end, { buffer = buf })

  -- q → close
  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf })
end

---------------------------------------------------------------
-- SETUP
---------------------------------------------------------------
vim.api.nvim_create_user_command("PKBNotify", M.notify, {})
vim.api.nvim_create_user_command("PKBInbox",  M.inbox,  {})

return M
