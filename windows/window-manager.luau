-- The native companion reports its actual session. Keep Linux's in_wm false:
-- its dock, rain, ride and agent seat have separate capabilities.
return function(run, hooks, entries, changed, screen, notice, spawn)
    local available, overview, busy, state = false, false, false, nil
    local viewing = false
    local function publish(value)
        state = value
        available = type(value) == "table" and value.running == true and value.automatic_layouts == true
        overview = type(value) == "table" and value.running == true and value.window_overview == true
        for i = #entries, 1, -1 do
            if entries[i].id == "windows.wm.layout" or entries[i].id == "windows.wm.restore" or entries[i].id == "windows.wm.overview" then table.remove(entries, i) end
        end
        if available then
            entries[#entries + 1] = { id = "windows.wm.layout", group = "Windows", title = "Tiled or free windows" }
            entries[#entries + 1] = { id = "windows.wm.restore", group = "Windows", title = "Bring back every window" }
        end
        if overview then entries[#entries + 1] = { id = "windows.wm.overview", group = "Windows", title = "Window overview" } end
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
        return (overview and title == "Window overview") or (available and (title == "Tiled or free windows" or title == "Bring back every window"))
    end
    local function current_screen()
        local name = screen()
        local found = false
        for _, monitor in ipairs(state.monitors or {}) do if monitor.name == name then found = true; break end end
        if not found or type(name) ~= "string" or not name:match("^\\\\%.\\DISPLAY%d+$") then
            notice(tr("The window manager is not managing this screen.")); return nil
        end
        return name
    end
    hooks.wm_free = function()
        if not available then request("status", true); return end
        local name = current_screen()
        if not name then return end
        request("toggle " .. name, true)
    end
    hooks.windows_toggle_layout = function()
        -- The native session resolves the pointer's monitor, independently of Marea's home.
        request("emit toggle_free", true)
    end
    hooks.windows_minimize = function() request("emit minimize", true) end
    hooks.windows_restore_last = function() request("emit restore_last", true) end
    hooks.windows_overview = function()
        if not overview then request("status", true); return end
        if viewing then notice(tr("The window view is already open.")); return end
        local name = current_screen()
        if not name then return end
        viewing = true
        local last_line = ""
        local finished = false
        local function done(output, code)
            if finished then return end
            finished = true
            viewing = false
            if code ~= 0 then notice(tr("The window view could not open.") .. " " .. (output ~= "" and tostring(output) or last_line):sub(1, 180)) end
        end
        local ok, error = pcall(spawn, "pleamar-wm", {"--scene", "tools/windows-overview.plm", "--screen", name,
            "--preview-monitor", name, "--window-actions", "--no-hud", "--stall", "0"},
            function(line) last_line = tostring(line):sub(1, 180) end, done,
            {cwd=".", errors=true, env={MAREA_LOCALE=tostring(fact.locale or "en")}})
        if not ok then done(tostring(error), 1) end
    end
    on("fact:menu_open", function(open) if open then request("status", false) end end)
    on("fact:searching", function(open) if open then request("status", false) end end)
    request("status", false)
end
