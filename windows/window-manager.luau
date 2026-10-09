-- The native companion reports its actual session. Keep Linux's in_wm false:
-- its dock, rain, ride and agent seat have separate capabilities.
return function(run, hooks, entries, changed, screen, notice, spawn, primary_screen, scene_send)
    local available, overview, dock, busy, state = false, false, false, false, nil
    local viewing = nil
    local dock_view = nil
    local navigation = {}
    local layouts = {"free", "left", "right", "columns", "rows", "grid"}
    local function selection()
        fact.windows_wm_available = available
        fact.windows_wm_busy = busy
        fact.windows_wm_layout = -1
        for _, monitor in ipairs(state and state.monitors or {}) do
            if monitor.name == screen() then
                if monitor.tiled == false then fact.windows_wm_layout = 0
                else for i, name in ipairs(layouts) do if monitor.layout == name then fact.windows_wm_layout = i - 1 end end end
            end
        end
    end
    local function publish(value)
        state = value
        available = type(value) == "table" and value.running == true and value.automatic_layouts == true
        overview = type(value) == "table" and value.running == true and value.window_overview == true
        dock = type(value) == "table" and value.running == true and value.application_dock == true
        selection()
        for i = #entries, 1, -1 do
            if entries[i].id == "windows.wm.layout" or entries[i].id == "windows.wm.restore" or entries[i].id == "windows.wm.overview" or entries[i].id == "windows.wm.dock" then table.remove(entries, i) end
        end
        if available then
            entries[#entries + 1] = { id = "windows.wm.layout", group = "Windows", title = "Tiled or free windows" }
            entries[#entries + 1] = { id = "windows.wm.restore", group = "Windows", title = "Bring back every window" }
        end
        if overview then entries[#entries + 1] = { id = "windows.wm.overview", group = "Windows", title = "Window overview" } end
        if dock or dock_view then entries[#entries + 1] = { id = "windows.wm.dock", group = "Windows", title = dock_view and "Hide application dock" or "Show application dock" } end
        changed()
    end
    local function request(command, visible, repeatable)
        if busy then
            if repeatable then
                if #navigation < 16 then navigation[#navigation + 1] = command
                else notice(tr("Too many pending window shortcuts.")) end
            end
            return
        end
        busy = true
        selection()
        local completed = false
        local function done(output, code)
            if completed then return end
            completed = true
            busy = false
            local ok, value = pcall(json.decode, tostring(output or ""))
            if code ~= 0 or not ok or type(value) ~= "table" or value.running ~= true then
                navigation = {}
                publish(nil)
                if visible then notice(tr("The window manager could not complete the action.") .. " " .. tostring(output or ""):sub(1, 180)) end
                return
            end
            publish(value)
            if #navigation > 0 then request(table.remove(navigation, 1), true, true) end
        end
        local ok, error = pcall(run, "pleamar-wm", { "--say", "wm", command }, done)
        if not ok then done(tostring(error), 1) end
    end
    hooks.windows_wm_allowed = function(title)
        return (overview and title == "Window overview") or ((dock or dock_view ~= nil) and title == "Application dock") or (available and (title == "Tiled or free windows" or title == "Bring back every window"))
    end
    local function managed_screen(name, quiet)
        local found = false
        for _, monitor in ipairs((state and state.monitors) or {}) do if monitor.name == name then found = true; break end end
        if not found or type(name) ~= "string" or not name:match("^\\\\%.\\DISPLAY%d+$") then
            if not quiet then notice(tr("The window manager is not managing this screen.")) end
            return nil
        end
        return name
    end
    local function current_screen() return managed_screen(screen()) end
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
    hooks.windows_focus_next = function() request("emit focus_next", true, true) end
    hooks.windows_focus_previous = function() request("emit focus_previous", true, true) end
    hooks.windows_close = function() request("emit close", true) end
    hooks.windows_fullscreen = function() request("emit fullscreen", true) end
    local lock_generation = 0
    local function exclusive(active)
        -- Clear both on entry and exit: requests received while hidden must
        -- never reopen a panel when the switcher releases ownership.
        for _, key in ipairs({"open", "menu_open", "searching", "chatting", "tray_open", "reel_open", "note"}) do fact[key] = false end
        fact.windows_overview_active = active
        lock_generation += 1
        if active then
            local mine = lock_generation
            after(6000, function()
                if mine ~= lock_generation or (viewing and viewing.active) then return end
                exclusive(false)
            end)
        end
    end
    local function send(child, command, done)
        if scene_send then
            return scene_send(child.endpoint, "windows-overview", command, done)
        end
        return run("pleamar-wm", {"--say", "windows-overview", command}, done, {env={PLEAMAR_SOCKET_DIR=child.endpoint}})
    end
    local open_overview
    open_overview = function(name, warm, prepare_cycle)
        if viewing then
            local child = viewing
            if child.retiring then child.next_screen, child.next_warm = name, warm; return end
            if child.screen ~= name then
                if warm and not prepare_cycle then return end
                child.next_warm = warm
                child.retiring, child.next_screen = true, name
                local problem = ""
                -- A quit acknowledgement may precede process teardown. Only
                -- the owned child's exit callback may start its replacement.
                after(2000, function()
                    if viewing ~= child or not child.retiring then return end
                    child.retiring, child.next_screen = false, nil
                    notice(tr("The window view could not close.") .. " " .. problem)
                end)
                local ok, error = pcall(send, child, "quit", function(output, code)
                    if code ~= 0 then problem = tostring(output or ""):sub(1, 180) end
                end)
                if not ok then problem = tostring(error) end
                return
            end
            if warm then return end
            if child.pending then return end
            child.pending = true
            local ok, error = pcall(send, child, "emit overview_toggle", function(output, code)
                if viewing ~= child then return end
                child.pending = false
                if code ~= 0 or tostring(output or ""):sub(1, 1) == "?" then
                    exclusive(false)
                    notice(tr("The window view could not open.") .. " " .. tostring(output or ""):sub(1, 180))
                end
            end)
            if not ok then child.pending = false; exclusive(false); notice(tostring(error)) end
            return
        end
        local child = {screen=name, endpoint="marea-overview-" .. tostring(os.time()) .. "-" .. tostring(math.random(1, 2147483647))}
        viewing = child
        local last_line = ""
        local finished = false
        local function done(output, code)
            if finished then return end
            finished = true
            if viewing ~= child then return end
            viewing = nil
            exclusive(false)
            if child.next_screen then
                if not child.next_warm then exclusive(true) end
                open_overview(child.next_screen, child.next_warm)
            elseif code ~= 0 and not warm then notice(tr("The window view could not open.") .. " " .. (output ~= "" and tostring(output) or last_line):sub(1, 180)) end
        end
        local ok, error = pcall(spawn, "pleamar-wm", {"--scene", "tools/windows-overview.plm", "--screen", name,
            "--preview-monitor", "all", "--preview-project", "--window-actions", "--no-hud", "--stall", "0"},
            function(line)
                if viewing ~= child then return end
                last_line = tostring(line):sub(1, 180)
                if last_line:find("windows preview:", 1, true) == 1 or last_line:find("marea-overview-activation:", 1, true) then log("overview · " .. last_line) end
                if last_line == "luau   · marea-overview-state:open" then child.active = true; exclusive(true)
                elseif last_line == "luau   · marea-overview-state:closed" and child.active then child.active = false; exclusive(false) end
            end, done,
            {cwd=".", errors=true, env={MAREA_LOCALE=tostring(fact.locale or "en"), PLEAMAR_SOCKET_DIR=child.endpoint,
                MAREA_OVERVIEW_WARM=warm and "1" or "0", MAREA_OVERVIEW_KEEP_WARM="1"}})
        if not ok then done(tostring(error), 1) end
    end
    local resolving = false
    hooks.windows_overview = function(warm)
        if resolving then
            if not warm then resolving.warm = false; exclusive(true) end
            return
        end
        if warm and (viewing or not overview) then return end
        if not overview then request("status", true); return end
        if not warm then exclusive(true) end
        local lookup = {warm=warm}
        resolving = lookup
        local completed = false
        local function resolved(name, problem)
            if completed then return end
            completed, resolving = true, false
            local warm = lookup.warm
            if problem then
                if not warm then exclusive(false); notice(tr("The window view could not open.") .. " " .. tostring(problem):sub(1, 180)) end
                return
            end
            name = managed_screen(name, warm)
            if name then open_overview(name, warm) elseif not warm then exclusive(false) end
        end
        local ok, error = pcall(primary_screen, resolved)
        if not ok then resolved(nil, error) end
        if not completed then after(2000, function() resolved(nil, tr("Primary monitor lookup timed out.")) end) end
    end
    -- One ordered stream per held-Win gesture. The primary monitor is resolved
    -- once; a slow lookup, cold renderer or IPC reply must not drop Tab presses.
    local cycle_session = nil
    local function cycle_fail(session, problem)
        if cycle_session ~= session then return end
        cycle_session = nil
        exclusive(false)
        notice(tr("The window view could not open.") .. " " .. tostring(problem or ""):sub(1, 180))
    end
    local pump_cycle
    pump_cycle = function(session)
        if cycle_session ~= session or session.pending or not session.screen then return end
        local child = viewing
        if not child or child.retiring or child.screen ~= session.screen then
            session.waits += 1
            if session.waits > 50 then cycle_fail(session, "Window view startup timed out."); return end
            after(100, function() pump_cycle(session) end)
            return
        end
        local command = session.queue[1]
        if not command then return end
        session.pending = true
        local probe = not (session.ready or child.ready)
        local ok, error = pcall(send, child, probe and "get overview_open" or command, function(output, code)
            if cycle_session ~= session then return end
            session.pending = false
            if code ~= 0 or tostring(output or ""):sub(1, 1) == "?" then
                if probe and session.waits < 50 then
                    session.waits += 1
                    after(100, function() pump_cycle(session) end)
                else cycle_fail(session, output) end
                return
            end
            if probe then session.ready = true; child.ready = true
            else
                table.remove(session.queue, 1)
                if #session.queue == 0 and session.ending then cycle_session = nil; return end
            end
            pump_cycle(session)
        end)
        if not ok then session.pending = false; cycle_fail(session, error) end
    end
    hooks.windows_overview_cycle = function(direction)
        local session = cycle_session
        if session then
            if #session.queue >= 128 then cycle_fail(session, "Too many pending window shortcuts."); return end
            session.ending = false
        else
            if not overview then request("status", true); return end
            exclusive(true)
            session = {queue={}, waits=0, pending=false, ready=false}
            cycle_session = session
        end
        session.queue[#session.queue + 1] = direction == -1 and "emit overview_cycle_backward" or "emit overview_cycle_forward"
        if session.screen then pump_cycle(session); return end
        if session.resolving then return end
        session.resolving = true
        local function resolved(name, problem)
            if cycle_session ~= session or not session.resolving then return end
            session.resolving = false
            if problem then cycle_fail(session, problem); return end
            name = managed_screen(name, true)
            if not name then cycle_fail(session, "Primary screen is unavailable."); return end
            session.screen = name
            open_overview(name, true, true)
            pump_cycle(session)
        end
        local ok, error = pcall(primary_screen, resolved)
        if not ok then resolved(nil, error) end
        after(2000, function() if session.resolving then resolved(nil, "Primary monitor lookup timed out.") end end)
    end
    local function finish_cycle(command)
        local session = cycle_session
        if not session or session.ending then return end
        session.ending = true
        session.queue[#session.queue + 1] = command
        pump_cycle(session)
    end
    hooks.windows_overview_commit = function() finish_cycle("emit overview_commit") end
    hooks.windows_overview_cancel = function() finish_cycle("emit overview_close") end
    on("windows_to_layouts", function() request("status", true) end)
    on("windows_choose_layout", function(index)
        if not available or busy or type(index) ~= "number" or index % 1 ~= 0 or index < 0 or index > 5 then return end
        local name = current_screen()
        if not name then return end
        request(index == 0 and ("free " .. name) or ("layout " .. name .. " " .. layouts[index + 1]), true)
    end)
    hooks.windows_dock = function()
        if dock_view then
            local child = dock_view
            if child.closing then return end
            child.closing = true
            child.close_attempt = (child.close_attempt or 0) + 1
            local attempt, problem = child.close_attempt, ""
            -- A quit reply can race process teardown. The owned process callback
            -- decides whether it closed; a still-running child remains retryable.
            after(2000, function()
                if dock_view ~= child or not child.closing or child.close_attempt ~= attempt then return end
                child.closing = false
                notice(tr("The application dock could not close.") .. " " .. problem)
            end)
            local completed = false
            local function done(output, code)
                if completed or dock_view ~= child then return end
                completed = true
                if code ~= 0 or tostring(output or ""):sub(1, 1) == "?" then
                    problem = tostring(output or ""):sub(1, 180)
                end
                -- The process callback, not an IPC acknowledgement, releases ownership.
            end
            local ok, error = pcall(run, "pleamar-wm", {"--say", "windows-dock", "quit"}, done, {env={PLEAMAR_SOCKET_DIR=child.endpoint}})
            if not ok then done(tostring(error), 1) end
            return
        end
        if not dock then request("status", true); return end
        local name = current_screen()
        if not name then return end
        local child = {closing=false, last_line="", endpoint="marea-dock-" .. tostring(os.time()) .. "-" .. tostring(math.random(1, 2147483647))}
        dock_view = child
        publish(state)
        local function done(output, code)
            if dock_view ~= child then return end
            dock_view = nil
            publish(state)
            if code ~= 0 then notice(tr("The application dock could not open.") .. " " .. (output ~= "" and tostring(output) or child.last_line):sub(1, 180)) end
        end
        local ok, error = pcall(spawn, "pleamar-wm", {"--scene", "tools/windows-dock.plm", "--screen", name,
            "--preview-monitor", name, "--window-actions", "--no-hud", "--stall", "0"},
            function(line)
                if dock_view ~= child then return end
                child.last_line = tostring(line):sub(1, 180)
                if child.last_line:find("windows dock:", 1, true) then notice(tr("The dock action failed.") .. " " .. child.last_line) end
            end, done, {cwd=".", errors=true, env={MAREA_LOCALE=tostring(fact.locale or "en"), MAREA_DOCK_MONITOR=name, PLEAMAR_SOCKET_DIR=child.endpoint}})
        if not ok then done(tostring(error), 1) end
    end
    on("fact:menu_open", function(open) if open then request("status", false) end end)
    on("fact:searching", function(open) if open then request("status", false) end end)
    request("status", false)
end
