---------------------------------------------------------------
-- TIMESTAMP PARSER (Z / H / +offset support)
---------------------------------------------------------------
local M = {}

local HOME_TZ = "+02:00"  -- your home timezone
M.DEFAULT_NOTIFY = "15min"

function M.setup(opts)
  opts = opts or {}
  if opts.default_notify then
    M.DEFAULT_NOTIFY = opts.default_notify
  end
end

-- convert offset string to seconds
local function offset_to_seconds(sign, hh, mm)
  return (tonumber(hh)*60 + tonumber(mm)) * 60 * (sign == "-" and -1 or 1)
end

function M.parse_iso(ts)
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

function M.parse_notify(str)
  local n = tonumber(str:match("(%d+)"))
  if not n then return 0 end
  if str:match("min") then return n * 60 end
  if str:match("h")   then return n * 3600 end
  if str:match("day") then return n * 86400 end
  return 0
end

---------------------------------------------------------------
-- PARSE LINE
---------------------------------------------------------------
local function parse_line(notifications, line, line_num, file, new_state)
  local due_str = line:match("due::([^%s]+)")
  if not due_str then return end

  local notify_str = line:match("notify::([%w]+)") or M.DEFAULT_NOTIFY
  local due_ts = M.parse_iso(due_str)
  if not due_ts then return end

  local notify_ts = due_ts - M.parse_notify(notify_str)
  if not line_num then 
      return 
  end
  local id = string.format("%s:%d", file, line_num)

  -- Preserve existing state across rescans
  local existing = notifications[id]

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

local function scan_file(notifications, file, new_state)
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok then return end
  for line_num, line in ipairs(lines) do
    parse_line(notifications, line, line_num, file, new_state)
  end
end

function M.scan_dir(notifications, path, new_state)
  local handle = vim.loop.fs_scandir(path)
  if not handle then return end

  while true do
    local name, typ = vim.loop.fs_scandir_next(handle)
    if not name then break end
    local full = path .. "/" .. name

    if typ == "file" and name:match("%.md$") then
      scan_file(notifications, full, new_state)
    elseif typ == "directory" then
      M.scan_dir(notifications, full, new_state)
    end
  end
end

-- In lua/pkb/parser.lua

--- Parse recur::<value> tag from line (e.g. recur::daily, recur::3d, recur::1w, recur::1m)
--- @param line string
--- @return string|nil
function M.parse_recurrence(line)
  line = tostring(line or "")
  return line:match("recur::([%w]+)")
end

--- Calculate the next due epoch timestamp based on recur rule
--- @param current_ts number Epoch timestamp
--- @param recur_str string e.g. "3d", "daily", "1w", "1m"
--- @return number Next epoch timestamp
function M.calculate_next_due(current_ts, recur_str)
  local num, unit = recur_str:match("^(%d*)(%a+)$")
  num = tonumber(num) or 1

  if unit == "daily" then unit = "d" end
  if unit == "weekly" then unit = "w" end
  if unit == "monthly" then unit = "m" end

  local date_tbl = os.date("*t", current_ts)

  if unit == "d" then
    date_tbl.day = date_tbl.day + num
  elseif unit == "w" then
    date_tbl.day = date_tbl.day + (num * 7)
  elseif unit == "m" then
    date_tbl.month = date_tbl.month + num
  end

  return os.time(date_tbl)
end

return M
