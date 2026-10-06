-- Marea's logic, in pieces: the calendar.
-- marea.luau loads it, and hands it what it uses of its own.
return function(shared)
    local hooks = shared.hooks
    -- ── the calendar ───────────────────────────────────────────────────
    --  Her own: events kept in `calendar.json`, a month on screen (six weeks,
    --  Monday first) and the day that is chosen. Writing «10:30 Dentist» makes an
    --  event at that time; without a time it is for the whole day. When its time
    --  comes, a notification goes out —with `notify-send`, to whoever receives
    --  them, which on this machine is her— and it lands in the swell like any
    --  other, as a calendar one.
    local cal = { events = {}, year = 0, month = 0, sel = nil, rows = {} }
    local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
                     "August", "September", "October", "November", "December" }
    local WEEKDAYS = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
    local LETTERS = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }

    local function days_in(y, m)
        local d = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
        if m == 2 and (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) then return 29 end
        return d[m]
    end
    --  0 Monday … 6 Sunday.
    local function weekday(y, m, d)
        return (os.date("*t", os.time({ year = y, month = m, day = d, hour = 12 })).wday + 5) % 7
    end
    local function key(y, m, d) return string.format("%04d-%02d-%02d", y, m, d) end
    local function today()
        local t = os.date("*t")
        return t.year, t.month, t.day
    end
    local function parse_key(k)
        local y, m, d = k:match("^(%d+)-(%d+)-(%d+)$")
        return tonumber(y), tonumber(m), tonumber(d)
    end
    local function on_day(k)
        local list = {}
        for _, e in ipairs(cal.events) do
            if e.date == k then list[#list + 1] = e end
        end
        --  The whole-day ones first, then by time.
        table.sort(list, function(a, b) return (a.time or "") < (b.time or "") end)
        return list
    end

    local function save_calendar()
        pcall(sys.call, "files.write", "calendar.json", { events = cal.events })
    end
    do
        local ok, loaded = pcall(sys.ask, "files.read", "calendar.json", "json")
        if ok and type(loaded) == "table" and type(loaded.events) == "table" then cal.events = loaded.events end
    end

    local function paint_calendar()
        local y, m = cal.year, cal.month
        text["cal.month"] = string.format(tr("%s %d"), tr(MONTHS[m]), y)
        for w = 1, 7 do text["cal.wd." .. w] = tr(LETTERS[w]) end
        --  The grid starts on the Monday of the week the 1st falls in.
        local py, pm = y, m - 1
        if pm < 1 then py, pm = y - 1, 12 end
        local lead = weekday(y, m, 1)
        local ty, tm, td = today()
        local d, cy_, cm = days_in(py, pm) - lead + 1, py, pm
        if lead == 0 then d, cy_, cm = 1, y, m end
        local counts = {}
        for _, e in ipairs(cal.events) do counts[e.date] = (counts[e.date] or 0) + 1 end
        for k = 0, 41 do
            local kk = key(cy_, cm, d)
            fact["cal.day." .. k] = d
            fact["cal.in." .. k] = cm == m
            fact["cal.today." .. k] = cy_ == ty and cm == tm and d == td
            fact["cal.n." .. k] = counts[kk] or 0
            if kk == cal.sel then fact["cal.sel"] = k end
            d = d + 1
            if d > days_in(cy_, cm) then
                d, cm = 1, cm + 1
                if cm > 12 then cm, cy_ = 1, cy_ + 1 end
            end
        end
        local sy, sm, sd = parse_key(cal.sel)
        text["cal.sel_day"] = tostring(sd)
        text["cal.sel_title"] = string.format("%s · %s", tr(WEEKDAYS[weekday(sy, sm, sd) + 1]), tr(MONTHS[sm]))
        local list = on_day(cal.sel)
        text["cal.sel_sub"] = #list == 0 and tr("Free day") or (#list == 1 and tr("1 event") or string.format(tr("%d events"), #list))
        local rows = {}
        cal.rows = {}
        for i, e in ipairs(list) do
            if i <= 6 then
                rows[#rows + 1] = { time = e.time ~= "" and e.time or tr("all day"), title = e.title }
                cal.rows[#cal.rows + 1] = e
            end
        end
        model.cal_events = rows
    end

    local function show_month(y, m, sel)
        cal.year, cal.month = y, m
        cal.sel = sel or key(y, m, 1)
        paint_calendar()
    end

    local function open_today()
        local y, m, d = today()
        show_month(y, m, key(y, m, d))
    end
    on("calendar", open_today)
    hooks.calendar = open_today
    table.insert(hooks.language, paint_calendar)
    on("cal_today", function()
        local y, m, d = today()
        local was = cal.year * 12 + cal.month
        show_month(y, m, key(y, m, d))
        if y * 12 + m > was then emit("cal_went_next") elseif y * 12 + m < was then emit("cal_went_prev") end
    end)
    on("cal_prev", function()
        local y, m = cal.year, cal.month - 1
        if m < 1 then y, m = y - 1, 12 end
        show_month(y, m)
        emit("cal_went_prev")
    end)
    on("cal_next", function()
        local y, m = cal.year, cal.month + 1
        if m > 12 then y, m = y + 1, 1 end
        show_month(y, m)
        emit("cal_went_next")
    end)
    --  A day of the grid: chosen; if it belongs to the month before or after, that
    --  month comes in.
    on("cal_pick", function(k)
        k = math.floor(k or 0)
        local lead = weekday(cal.year, cal.month, 1)
        local n = k - lead + 1
        local y, m = cal.year, cal.month
        local went = nil
        if n < 1 then
            m = m - 1
            if m < 1 then y, m = y - 1, 12 end
            n = days_in(y, m) + n
            went = "cal_went_prev"
        elseif n > days_in(y, m) then
            n = n - days_in(y, m)
            m = m + 1
            if m > 12 then y, m = y + 1, 1 end
            went = "cal_went_next"
        end
        show_month(y, m, key(y, m, n))
        if went then emit(went) end
    end)
    --  «10:30 Dentist», «9:05 call», «18h gym», «18.30 dinner»; anything else is
    --  for the whole day.
    on("submit:cal_new", function(value)
        local line = (value or ""):match("^%s*(.-)%s*$")
        if line == "" then return end
        local time, title = "", line
        local h, mi, rest = line:match("^(%d%d?)[:%.h](%d%d)%s+(.+)$")
        if not h then
            h, rest = line:match("^(%d%d?)h%s+(.+)$")
            mi = "00"
        end
        if h and tonumber(h) < 24 and tonumber(mi) < 60 then
            time, title = string.format("%02d:%s", tonumber(h), mi), rest
        end
        table.insert(cal.events, { date = cal.sel, time = time, title = title })
        save_calendar()
        text.cal_new = ""
        paint_calendar()
        emit("cal_added")
    end)
    on("cal_delete", function(i)
        local e = cal.rows[(i or 0) + 1]
        if e == nil then return end
        for k, x in ipairs(cal.events) do
            if x == e then table.remove(cal.events, k); break end
        end
        save_calendar()
        paint_calendar()
    end)
    --  When its time comes: once, and marked so that restarting her does not say
    --  it again.
    every(20000, function()
        local y, m, d = today()
        local t = os.date("*t")
        local now = t.hour * 60 + t.min
        local k = key(y, m, d)
        local changed = false
        for _, e in ipairs(cal.events) do
            if e.date == k and e.time ~= "" and not e.told then
                local eh, em = e.time:match("^(%d+):(%d+)$")
                local at = tonumber(eh) * 60 + tonumber(em)
                if now >= at and now < at + 5 then
                    run("notify-send", { "-a", "Calendar", e.title, e.time }, function() end)
                    e.told = true
                    changed = true
                end
            end
        end
        if changed then save_calendar() end
    end)
    do
        local y, m, d = today()
        show_month(y, m, key(y, m, d))
    end
    on("open_page", function(k) log("page", k) end)
end
