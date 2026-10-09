local language = tostring(sys.ask("env", "MAREA_LOCALE") or "en")
fact.locale = language == "es" and "es" or "en"
fact.overview_open = sys.ask("env", "MAREA_OVERVIEW_WARM") ~= "1"
local keep_warm = sys.ask("env", "MAREA_OVERVIEW_KEEP_WARM") == "1"
local function report_state() log("marea-overview-state:" .. (fact.overview_open and "open" or "closed")) end
report_state()
local repair_selection = function() end
local function catalogue()
    local place = 0
    for i = 0, 31 do
        local open = fact["win." .. i .. ".open"] == true
        fact["overview_place." .. i] = open and place or -1
        if open then place += 1 end
    end
    fact.overview_count = place
    repair_selection()
end
for i = 0, 31 do on("fact:win." .. i .. ".open", catalogue) end
catalogue()
local selected, attempt, idle = nil, 0, 0
local cycling, pending_steps, cycle_generation = false, {}, 0
local function close()
    if not fact.overview_open then cycle_generation += 1; return end
    fact.overview_open = false
    report_state()
    fact.keyboard_slot = -1
    cycling, pending_steps = false, {}
    cycle_generation += 1
    selected = nil
    attempt += 1
    idle += 1
    local mine = idle
    -- Keep the renderer warm for another shortcut, but release it after a minute.
    -- The closed surface owns no keyboard, hit regions, or window captures.
    if not keep_warm then after(60000, function()
        if mine ~= idle or fact.overview_open then return end
        run("pleamar-wm", {"--say", "windows-overview", "quit"}, function() end)
    end) end
end
local function open()
    idle += 1
    attempt += 1
    selected = nil
    text.overview_status = ""
    fact.overview_open = true
    report_state()
end
on("overview_toggle", function()
    if fact.overview_open then close(); return end
    open()
end)
local function slots()
    local result = {}
    for i = 0, 31 do if fact["win." .. i .. ".open"] then result[#result + 1] = i end end
    return result
end
local function highlight(slot)
    fact.keyboard_slot = slot or -1
    if slot then fact.requested_page = math.floor((fact["overview_place." .. slot] or 0) / 4) end
end
repair_selection = function()
    if not cycling or fact.keyboard_slot == nil or fact.keyboard_slot < 0 then return end
    if fact["win." .. tostring(fact.keyboard_slot) .. ".open"] then
        highlight(fact.keyboard_slot)
    else
        highlight(slots()[1])
    end
end
local function drain(remaining)
    local list = slots()
    -- The cold catalogue arrives asynchronously. Do not consume the first Tab
    -- against a partial list, or lose a release that arrives before startup.
    if #list == 0 or #list ~= fact["win.count"] then
        if remaining == 0 then close(); return end
        local mine = cycle_generation
        after(50, function() if mine == cycle_generation and cycling then drain(remaining - 1) end end)
        return
    end
    for _, direction in ipairs(pending_steps) do
        local position = nil
        local current = fact.keyboard_slot
        if current == nil or current < 0 then current = fact["win.focus"] end
        for at, slot in ipairs(list) do if slot == current then position = at; break end end
        if not position then position = direction == 1 and 0 or 1 end
        highlight(list[(position - 1 + direction) % #list + 1])
    end
    pending_steps = {}
end
local function cycle(direction)
    if not cycling then
        cycling = true
        fact.keyboard_slot = -1
        open()
    end
    pending_steps[#pending_steps + 1] = direction
    cycle_generation += 1
    drain(40)
end
on("overview_cycle_forward", function() cycle(1) end)
on("overview_cycle_backward", function() cycle(-1) end)
on("overview_commit", function()
    if not cycling then return end
    local steps, current = pending_steps, fact.keyboard_slot
    if current == nil or current < 0 then current = fact["win.focus"] end
    -- Releasing Win always dismisses the switcher, even if Windows denies
    -- foreground activation. Preserve the target independently of the highlight.
    close()
    local mine = cycle_generation
    local function confirm(remaining)
        if mine ~= cycle_generation or fact.overview_open then return end
        local list = slots()
        if #list == 0 or #list ~= fact["win.count"] then
            if remaining > 0 then after(50, function() confirm(remaining - 1) end) end
            return
        end
        local position = nil
        for at, slot in ipairs(list) do if slot == current then position = at; break end end
        for _, direction in ipairs(steps) do
            if not position then position = direction == 1 and 0 or 1 end
            position = (position - 1 + direction) % #list + 1
        end
        emit("overview_accept", list[position or 1])
    end
    confirm(40)
end)
local function focused()
    if selected ~= nil and fact["win.focus"] == selected then close() end
end
on("overview_close", close)
on("overview_select", function(slot)
    if not fact.overview_open or type(slot) ~= "number" or slot % 1 ~= 0 or slot < 0 or slot >= 32 then return end
    if fact["win." .. slot .. ".open"] ~= true then return end
    selected = slot
    attempt += 1
    local mine = attempt
    text.overview_status = ""
    focused()
    after(3000, function()
        if attempt == mine and selected == slot and fact.overview_open then
            selected = nil
            text.overview_status = tr("Window activation has not been confirmed. Try selecting it again.")
        end
    end)
end)
on("fact:win.focus", focused)
if not fact.overview_open and not keep_warm then
    local mine = idle
    after(60000, function()
        if mine == idle and not fact.overview_open then
            run("pleamar-wm", {"--say", "windows-overview", "quit"}, function() end)
        end
    end)
end
