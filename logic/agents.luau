-- Marea's logic, in pieces: the agents' reservoirs.
-- marea.luau loads it, and hands it what it uses of its own.
return function(shared)
    local hooks = shared.hooks
    -- ── the agents' reservoirs ────────────────────────────────────────
    --  What is left of Claude Code's and Codex's windows. `tools/reservas` reads
    --  them —Claude from its server with the token Claude Code already keeps,
    --  Codex from its own session logs— and prints one line per thing. Here they
    --  go into the scene's facts; the countdowns are kept up to date every half
    --  minute without asking anybody again. The rules of the old Marea hold: an
    --  unknown number is not a zero, the percentages of two windows are never
    --  added up, and a window past its renewal is «pending», not full.
    local agents = {}
    local agents_now = 0

    local function span(seconds)
        seconds = math.max(0, math.floor(seconds))
        local d, h, m = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
        if d > 0 then return string.format("%d d %d h", d, h) end
        if h > 0 then return string.format("%d h %02d", h, m) end
        return string.format("%d min", math.max(m, 1))
    end

    local WINDOW_NAMES = { [300] = "5 hours", [10080] = "Weekly" }

    local function paint_agents()
        local now = os.time()
        local worst = 101
        for a = 1, 2 do
            local g = agents[a]
            fact["ag.kind." .. a] = g and (g.id == "claude" and 1 or (g.id == "codex" and 2 or 3)) or 0
            text["ag.name." .. a] = g and g.name or ""
            if g then
                local parts = {}
                if g.plan ~= "" then table.insert(parts, g.plan) end
                if g.origin ~= "" then table.insert(parts, tr(g.origin == "servidor" and "server" or "on this machine")) end
                if g.observed then
                    local ago = now - g.observed
                    table.insert(parts, ago < 90 and tr("just now") or string.format(tr("%s ago"), span(ago)))
                end
                text["ag.sub." .. a] = table.concat(parts, " · ")
            else
                text["ag.sub." .. a] = ""
            end
            --  A reading older than a quarter of an hour is drawn, never trusted
            --  for her face or the little tube.
            local fresh = g and g.observed and now - g.observed < 900
            for l = 1, 3 do
                local w = g and g.limits[l]
                local k = a .. "." .. l
                fact["ag.on." .. k] = w ~= nil
                if w then
                    fact["ag.active." .. k] = w.active
                    local pending = w.renews and w.renews <= now
                    fact["ag.pending." .. k] = pending or false
                    fact["ag.used." .. k] = w.used or -1
                    text["ag.lname." .. k] = w.minutes and WINDOW_NAMES[w.minutes] and tr(WINDOW_NAMES[w.minutes]) or w.name
                    if pending then
                        text["ag.lrenew." .. k] = tr("renewed?")
                    elseif not w.active then
                        text["ag.lrenew." .. k] = tr("not started")
                    elseif w.renews then
                        text["ag.lrenew." .. k] = string.format(tr("in %s"), span(w.renews - now))
                    else
                        text["ag.lrenew." .. k] = ""
                    end
                    if w.renews and w.minutes then
                        fact["ag.elapsed." .. k] = math.clamp(1 - (w.renews - now) / (w.minutes * 60), 0, 1)
                    else
                        fact["ag.elapsed." .. k] = 0
                    end
                    if fresh and w.active and w.used and not pending then worst = math.min(worst, 100 - w.used) end
                else
                    fact["ag.used." .. k] = -1
                    text["ag.lname." .. k] = ""
                    text["ag.lrenew." .. k] = ""
                end
            end
        end
        fact["ag.worst"] = worst
    end

    local reading_agents = false
    local function read_agents()
        if reading_agents then return end
        reading_agents = true
        run("node", { "tools/reservas", "--lines" }, function(out, code)
            reading_agents = false
            if code ~= 0 or out == nil then log("agents · could not read the windows (" .. tostring(code) .. ")"); return end
            local list, by_id = {}, {}
            for line in string.gmatch(out, "[^\n]+") do
                local f = string.split(line, "\t")
                local num = function(i) return tonumber(f[i]) end
                if f[1] == "agent" and #list < 2 then
                    local g = { id = f[2], name = f[3] or "", plan = f[4] or "", origin = f[5] or "", observed = num(6), limits = {} }
                    table.insert(list, g)
                    by_id[g.id] = g
                elseif f[1] == "limit" and by_id[f[2]] and #by_id[f[2]].limits < 3 then
                    local used = num(5)
                    if used and (used < 0 or used > 100) then used = nil end
                    table.insert(by_id[f[2]].limits, { name = f[3] or "", minutes = num(4), used = used,
                        renews = num(6), active = f[7] == "1", pending = f[8] == "1" })
                end
            end
            agents = list
            paint_agents()
            emit("agents_read")
        end)
    end

    on("agents_refresh", read_agents)
    --  Every five minutes in the background, for the little tube by the gear;
    --  the countdowns, every half minute, without asking anybody.
    after(4000, read_agents)
    every(300000, read_agents)
    every(30000, paint_agents)
    return { paint_agents = paint_agents }
end
