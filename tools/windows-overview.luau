local language = tostring(sys.ask("env", "MAREA_LOCALE") or "en")
fact.locale = language == "es" and "es" or "en"
fact.overview_open = sys.ask("env", "MAREA_OVERVIEW_WARM") ~= "1"
local selected, attempt, idle = nil, 0, 0
local function close()
    if not fact.overview_open then return end
    fact.overview_open = false
    selected = nil
    attempt += 1
    idle += 1
    local mine = idle
    -- Keep the renderer warm for another shortcut, but release it after a minute.
    -- The closed surface owns no keyboard, hit regions, or window captures.
    after(60000, function()
        if mine ~= idle or fact.overview_open then return end
        run("pleamar-wm", {"--say", "windows-overview", "quit"}, function() end)
    end)
end
on("overview_toggle", function()
    if fact.overview_open then close(); return end
    idle += 1
    attempt += 1
    selected = nil
    text.overview_status = ""
    fact.overview_open = true
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
    after(1000, function()
        if attempt == mine and selected == slot and fact.overview_open then
            selected = nil
            text.overview_status = tr("Windows did not activate this window. Try selecting it again.")
        end
    end)
end)
on("fact:win.focus", focused)
if not fact.overview_open then
    local mine = idle
    after(60000, function()
        if mine == idle and not fact.overview_open then
            run("pleamar-wm", {"--say", "windows-overview", "quit"}, function() end)
        end
    end)
end
