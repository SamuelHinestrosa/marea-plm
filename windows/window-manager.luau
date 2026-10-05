-- The native companion reports its actual session. Keep Linux's in_wm false:
-- its dock, rain, ride and agent seat have separate capabilities.
return function(run, hooks, entries, changed, screen, notice)
    local available, busy, state = false, false, nil
    local function publish(value)
        state = value
        available = type(value) == "table" and value.running == true and value.automatic_layouts == true
        for i = #entries, 1, -1 do
            if entries[i].id == "windows.wm.layout" or entries[i].id == "windows.wm.restore" then table.remove(entries, i) end
        end
        if available then
            entries[#entries + 1] = { id = "windows.wm.layout", group = "Windows", title = "Tiled or free windows" }
            entries[#entries + 1] = { id = "windows.wm.restore", group = "Windows", title = "Bring back every window" }
        end
        changed()
    end
    local function request(command, visible)
        if busy then return end
        busy = true
        local completed = false
        local function done(output, code)
            if completed then return end
            completed = true
            busy = false
            local ok, value = pcall(json.decode, tostring(output or ""))
            if code ~= 0 or not ok or type(value) ~= "table" or value.running ~= true then
                publish(nil)
                if visible then notice(tr("The window manager could not complete the action.") .. " " .. tostring(output or ""):sub(1, 180)) end
                return
            end
            publish(value)
        end
        local ok, error = pcall(run, "pleamar-wm", { "--say", "wm", command }, done)
        if not ok then done(tostring(error), 1) end
    end
    hooks.windows_wm_allowed = function(title)
        return available and (title == "Tiled or free windows" or title == "Bring back every window")
    end
    hooks.wm_free = function()
        if not available then request("status", true); return end
        local name = screen()
        local found = false
        for _, monitor in ipairs(state.monitors or {}) do if monitor.name == name then found = true; break end end
        if not found or type(name) ~= "string" or not name:match("^\\\\%.\\DISPLAY%d+$") then
            notice(tr("The window manager is not managing this screen.")); return
        end
        request("toggle " .. name, true)
    end
    on("fact:menu_open", function(open) if open then request("status", false) end end)
    on("fact:searching", function(open) if open then request("status", false) end end)
    request("status", false)
end
