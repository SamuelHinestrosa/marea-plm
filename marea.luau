-- The ball's logic.
--
-- The scene draws and reacts on its own: the highlight on hover, the springs,
-- the gestures and the rules are all carried by the renderer, and if this gets
-- stuck the screen never finds out. The only thing here is what a rule CANNOT
-- do: ask a service for something.

-- ── the two levels ─────────────────────────────────────────────────
--  The scene sends where the finger has gone, from 0 to 1. The value is not
--  kept: the service keeps saying it, so raising the volume with the keyboard
--  key moves this same track without anyone counting it twice.
on("set_volume", function(v) sys.call("audio.volume", v) end)
on("set_brightness", function(v) sys.call("brightness.level", v) end)
on("mute_output", function() sys.call("audio.mute") end)
on("mute_mic", function() sys.call("audio.input_mute") end)

-- ── what is playing ────────────────────────────────────────────────
on("play_pause", function() sys.call("media.toggle") end)
on("previous", function() sys.call("media.previous") end)
on("next", function() sys.call("media.next") end)

-- ── the three cards ────────────────────────────────────────────────
--  Only two carry a switch. Concentration does not: it is Marea's, it is set
--  from its page —where you choose how long it lasts— and the whole scene
--  carries it, without going through here. Wi-Fi and Bluetooth do, and they
--  are the system's: pleamar knows how to READ the network but not how to
--  change it, and it knows nothing about bluetooth yet. A switch that moves
--  without doing anything is a lie, so these do something.
--  The real switch. It is read first and set to the opposite, instead of
--  assuming: if someone has changed it from outside, this still gets it right.
--  And turning the radio off can be undone from the same place, which is the
--  least you can ask of a switch.
on("flip", function(k)
    if k == 1 then
        run("nmcli", { "radio", "wifi" }, function(output)
            local enabled = tostring(output):match("enabled") ~= nil
            run("nmcli", { "radio", "wifi", enabled and "off" or "on" }, function() end)
        end)
    elseif k == 2 then
        run("bluetoothctl", { "show" }, function(output)
            local enabled = tostring(output):match("Powered: yes") ~= nil
            run("bluetoothctl", { "power", enabled and "off" or "on" }, function() end)
        end)
    end
end)

-- ── sound: where it plays and where it listens ─────────────────────
--  pleamar says which devices there are —`outputs` and `inputs`, each with its
--  id, its name and whether it is the current one— and accepts
--  `audio.default(id)` to change. Here they are only split into two lists and
--  the name is trimmed, since PipeWire's come with the whole card model in it.
local function shorten(name)
    --  «TU106 High Definition Audio Controller Estéreo digital (HDMI)» does not
    --  fit in a row, and besides, what tells them apart is at the end.
    local clean = tostring(name):gsub("%s+", " ")
    if #clean > 42 then clean = clean:sub(1, 41) .. "…" end
    return clean
end

local function devices(state)
    local outputs, mics = {}, {}
    for _, a in ipairs(state.outputs or {}) do
        outputs[#outputs + 1] = { name = shorten(a.name), id = a.id, current = a.default == true }
    end
    for _, a in ipairs(state.inputs or {}) do
        mics[#mics + 1] = { name = shorten(a.name), id = a.id, current = a.default == true }
    end
    model.outputs = outputs
    model.mics = mics
end

sys.watch("audio", devices)

on("pick_device", function(i)
    --  The two lists go together: the first ones are outputs and the rest
    --  mics, which is how they are seen on the page.
    local outputs = model.outputs or {}
    local chosen = outputs[i + 1]
    if chosen == nil then
        local mics = model.mics or {}
        chosen = mics[i - #outputs + 1]
    end
    if chosen ~= nil then sys.call("audio.default", chosen.id) end
end)

-- ── the pages ──────────────────────────────────────────────────────
--  Pressing a card opens its page, and then you have to find out what there
--  is. pleamar knows how to READ the network, not how to list it or change it
--  —that is its B15—, so this asks the system's tools. That is exactly what
--  the logic is for: the scene commands nothing, it tells what it is told.

local function scan_networks()
    run("nmcli", { "-t", "-f", "IN-USE,SIGNAL,SSID", "dev", "wifi" }, function(output)
        local best, order = {}, {}
        for line in tostring(output):gmatch("[^\n]+") do
            local in_use, signal, ssid = line:match("^(.-):(%d+):(.*)$")
            --  The same network shows up once per antenna: the one that reaches best stays.
            if ssid and ssid ~= "" then
                local s = tonumber(signal) / 100
                if not best[ssid] then order[#order + 1] = ssid end
                if not best[ssid] or s > best[ssid].signal then
                    best[ssid] = { name = ssid, signal = s, current = in_use == "*" }
                end
            end
        end
        local v = {}
        for _, ssid in ipairs(order) do v[#v + 1] = best[ssid] end
        table.sort(v, function(a, b)
            if a.current ~= b.current then return a.current end
            return a.signal > b.signal
        end)
        while #v > 8 do table.remove(v) end
        model.networks = v
    end)
end

local function scan_bluetooth()
    run("bluetoothctl", { "devices", "Connected" }, function(connected)
        local connected_macs = {}
        for mac in tostring(connected):gmatch("Device (%S+)") do connected_macs[mac] = true end
        run("bluetoothctl", { "devices", "Paired" }, function(paired)
            local v = {}
            for mac, name in tostring(paired):gmatch("Device (%S+) ([^\n]+)") do
                --  The `mac` goes in the record even though the scene does not
                --  declare it: it is where the logic keeps what the scene does
                --  not need to know.
                v[#v + 1] = { name = name, mac = mac, current = connected_macs[mac] == true }
            end
            table.sort(v, function(a, b) return a.current and not b.current end)
            while #v > 8 do table.remove(v) end
            model.gadgets = v
        end)
    end)
end

--  Pressing a network switches to it, and pressing a headset connects it or
--  lets it go. Only networks already saved: `connection up` does not make up a
--  password, so this does not get into the neighbour's network. A new one asks
--  for its password, and that is a conversation, not a click.
on("pick_network", function(i)
    local r = model.networks[i + 1]
    if r == nil or r.current then return end
    run("nmcli", { "connection", "up", "id", r.name }, function(_, code)
        if code ~= 0 then log("that network is not saved; it would need its password", r.name) end
        scan_networks()
    end)
end)

on("pick_gadget", function(i)
    local c = model.gadgets[i + 1]
    if c == nil or c.mac == nil then return end
    run("bluetoothctl", { c.current and "disconnect" or "connect", c.mac }, function()
        scan_bluetooth()
    end)
end)

on("scan", function(k)
    if k == 1 then scan_networks() elseif k == 2 then scan_bluetooth() end
end)

on("customize", function() log("customize would open here") end)

-- ── the finder ─────────────────────────────────────────────────────
--  «Apps, files and folders.» The apps come from the system —the `apps`
--  service reads the `.desktop` files, with their icon and their order—, and
--  the files and folders are searched by `fd` under your home. The scene knows
--  nothing of this: it asks for a list and paints it.
local apps = {}
local home_dir = sys.ask("env", "HOME") or "."

--  What is written changes as soon as a key is pressed, but `fd` takes its
--  time: the query it was launched with is noted down and, when it comes back,
--  it is thrown away if it is no longer the current one. Without this, typing
--  fast leaves the list from three letters ago.
local generation = 0

local function paint(q, list)
    local out = {}
    for _, e in ipairs(list) do
        if #out < 7 then out[#out + 1] = e end
    end
    model.results = out
    fact.typing = q ~= ""
    fact.selected = 0
    --  And let the scene know there is a new list, to stagger its entrance.
    emit("list_ready")
end

--  «At hand» is not «the first ones in alphabetical order»: it is the usual
--  ones. With no usage data, this is the most honest thing that can be done —a
--  short list of the ones almost everybody has at hand— and the day there are
--  usage counts, it is changed here and that is it.
local AT_HAND = { "firefox", "zen", "nautilus", "files", "archivos", "kitty", "alacritty", "terminal", "code", "gimp" }

local function prefer(a, b)
    local function rank(x)
        local n = x.name:lower()
        for k, v in ipairs(AT_HAND) do
            if n:find(v, 1, true) then return k end
        end
        return 99
    end
    local pa, pb = rank(a), rank(b)
    if pa ~= pb then return pa < pb end
    return a.name < b.name
end

local function search()
    local q = (text.query or ""):lower()
    generation = generation + 1
    local mine = generation
    local matches = {}
    for _, a in ipairs(apps) do
        if q == "" or a.name:lower():find(q, 1, true) then matches[#matches + 1] = a end
    end
    table.sort(matches, prefer)
    local list = {}
    for _, a in ipairs(matches) do
        if #list < 7 then
            list[#list + 1] = { name = a.name, kind_label = tr("Application"), icon = a.icon, exec = a.exec }
        end
    end
    --  With no query, «at hand»: what the system gives first.
    if q == "" then paint(q, list); return end
    paint(q, list)
    --  And the files and folders, which arrive when they arrive. With fewer
    --  than three letters there is no search: `fd` with one letter returns
    --  half your home —thousands of paths that neither fit nor say anything—
    --  and all it achieves is making the list jump with every key.
    if #q < 3 then return end
    run("fd", { "--max-depth", "4", "--max-results", "12", "--hidden",
                "--exclude", ".git", "--exclude", "node_modules", "--exclude", ".cache",
                "--color", "never", q, home_dir }, function(output)
        if mine ~= generation then return end
        for line in tostring(output):gmatch("[^\n]+") do
            if #list < 7 then
                local is_folder = line:sub(-1) == "/"
                local clean = is_folder and line:sub(1, -2) or line
                local name = clean:match("([^/]+)$") or clean
                local where = clean:sub(#home_dir + 2, #clean - #name - 1)
                list[#list + 1] = {
                    name = name,
                    kind_label = (is_folder and tr("Folder") or tr("File")) .. (where ~= "" and " · " .. where or ""),
                    icon = is_folder and "folder" or "text-x-generic",
                    filepath = clean,
                }
            end
        end
        if mine == generation then paint(q, list) end
    end)
end

if not sys.watch("apps", function(list) apps = list; search() end) then
    log("this system does not know which applications it has")
end
on("text:query", search)
on("fact:searching", function(opened) if opened then search() end end)

--  Opening: an app is launched; a file or a folder, to whoever knows how to open it.
on("open_result", function(i)
    local h = model.results[i + 1]
    if h == nil then return end
    if h.exec then
        log("opening", h.name)
        sys.call("apps.launch", h.exec)
    else
        --  To whoever knows how to open it: the desktop decides that, not this bar.
        log("opening", h.filepath or h.name)
        if h.filepath then run("xdg-open", { h.filepath }, function() end) end
    end
    text.query = ""
end)

-- ── her menu ───────────────────────────────────────────────────────
--  What the right button offers. The two rows of the house are put by the
--  scene; this brings the plugins' ones, which is the only thing that changes
--  from one machine to another. There is no catalogue here, so they are
--  spelled out: what matters is that the border is written down and that
--  grouping is this side's business.
--
--  `first` says whether it opens a group, and then the row takes 16 px more
--  for the name of whoever brings it. It is a count and not a coordinate:
--  where each row falls is shared out by the scene, which has a column for
--  exactly that.
--  Their visible names go through `tr()` each time the menu is set, so that a
--  change of language reaches them too (see `fact:locale` at the end).
local plugin_entries = {
    { id = "drift.lend",    group = "Drift", title = "Lend something" },
    { id = "drift.release", group = "Drift", title = "Release what was lent" },
    { id = "swell.history", group = "Swell", title = "History" },
}

local function set_menu()
    local group, groups = nil, 0
    local entries = {}
    for _, e in ipairs(plugin_entries) do
        e.first = e.group ~= group
        if e.first then
            group = e.group
            groups = groups + 1
        end
        entries[#entries + 1] = { id = e.id, group_name = tr(e.group), title = tr(e.title), first = e.first }
    end
    fact.groups = groups
    model.entries = entries
end
set_menu()

on("menu_entry", function(i)
    local e = plugin_entries[i + 1]
    log("a plugin entry from her menu", e ~= nil and e.id or i)
end)

-- ── the swell, in demo mode ────────────────────────────────────────
--  pleamar knows how to receive the desktop's real notifications: you ask for
--  the `notifications` permission and `sys.watch("notifications", …)` gives the
--  live list, with its application, its title, its body and its urgency. Here
--  that permission is NOT given on purpose: whoever holds that place on this
--  machine is Marea, and the first one to ask for it keeps it. A prototype does
--  not take the notices away from the real bar.
--
--  So this is the other thing: an invented batch that comes in on its own, to
--  be able to see the whole swell —the arrival, the burst, the tray and the
--  urgent one— without waiting for someone to write to you. What is sent
--  across the border is exactly what the service would send: `cat`, `who`,
--  `line` and the event. The day the permission is given, the only thing that
--  changes is where they come from.
--
--  It is stopped with `pleamar --say marea "fact demo false"`.

--  1 messages · 2 work · 3 calendar · 4 system. It is what decides the colour
--  of the drop, so a notice with no known category is «system».
local CATEGORY_OF = { TELEGRAM = 1, MAIL = 2, CALENDAR = 3, SYSTEM = 4 }

--  Written in English and shown through `tr()` when it arrives: they are
--  Marea's own words, not someone else's notification. A real one has an `id`;
--  an invented one does not, and that is how `shown()` tells them apart.
local batch = {
    { app = "TELEGRAM", title = "Ana Ruiz",            detail = "Lunch today? I have a table at two", delay = 1400 },
    { app = "MAIL",     title = "September invoice",   detail = "due on the 30th",                    delay = 5200 },
    --  Two in a row: the burst stacks up and «+N more» shows instead of three jumps.
    { app = "TELEGRAM", title = "Building site group", detail = "6 unread messages",                  delay = 8600 },
    { app = "TELEGRAM", title = "Marcos",              detail = "I'll call you in five",              delay = 9100 },
    { app = "CALENDAR", title = "Design review",       detail = "in 10 minutes · big room",           delay = 13000 },
    --  And an urgent one, which is not grouped: its own row, on top and in amber.
    { app = "SYSTEM",   title = "Battery at 8 %",      detail = "about 12 minutes left", urgent = true, delay = 18000 },
}
--  What each row keeps saying about when it arrived. There is no clock here:
--  the place in the list already tells the story, and it is what the contract
--  does.
local AGES = { "now", "2 min", "9 min", "26 min", "1 h" }

local rows = {}

--  What a row shows: Marea's own words in the language of the moment; what
--  comes from another application, as it came.
local function shown(f, s)
    if f.id == nil then return tr(s) end
    return s
end

local function render()
    for k = 1, 5 do
        local f = rows[k]
        fact["alive." .. k] = f ~= nil
        if f ~= nil then
            text["row." .. k .. ".app"] = shown(f, f.app)
            text["row." .. k .. ".title"] = shown(f, f.title)
            text["row." .. k .. ".detail"] = shown(f, f.detail)
            text["row." .. k .. ".age"] = tr(AGES[k])
            fact["row_cat." .. k] = f.cat
            fact["row_urgent." .. k] = f.urgent == true
        end
    end
end

--  One arrives: first it is said WHAT it is —the scene needs it before the
--  event, because the card that flies already carries its name written on it—
--  and then that it has arrived. An urgent one, besides, is announced as such.
--  What a real notice is about, by who sends it. It is what decides the colour
--  of its drop, so whatever is not recognised is «system» and nothing is made up.
local CATEGORIES = {
    { 1, { "telegram", "whatsapp", "signal", "discord", "element", "fractal", "mensaj", "chat" } },
    { 2, { "thunderbird", "mail", "correo", "geary", "evolution", "outlook", "slack", "teams", "github" } },
    { 3, { "calendar", "calendario", "khal", "reminder", "recordatorio", "agenda" } },
}
local function classify(app)
    local a = string.lower(app or "")
    for _, c in ipairs(CATEGORIES) do
        for _, fragment in ipairs(c[2]) do
            if string.find(a, fragment, 1, true) then return c[1] end
        end
    end
    return 4
end

local function arrive(n)
    n.cat = CATEGORY_OF[n.app] or classify(n.app)
    table.insert(rows, 1, n)
    while #rows > 5 do table.remove(rows) end
    render()
    fact.cat = n.cat
    text.who = shown(n, n.title)
    text.line = shown(n, n.detail)
    emit("notice")
    if n.urgent then emit("urge") end
end

--  The whole batch, and again after 22 s. Before repeating, the tray and the
--  drops' counts are emptied: otherwise, the second round starts with the
--  first one still on top and nothing can be seen any more.
local function clear()
    rows = {}
    render()
    for k = 1, 4 do
        fact["n." .. k] = 0
        fact["last." .. k] = 0
    end
end

--  One batch and stop. In a loop it was a nuisance: what you want is to see it
--  once and be able to repeat it when it suits you, not have it rain on you
--  while you work. It is repeated with `pleamar --say marea "emit another_batch"`,
--  which empties whatever there was and starts again.
local function playBatch()
    clear()
    for _, n in ipairs(batch) do
        after(n.delay, function() if fact.demo ~= false then arrive(n) end end)
    end
end

on("another_batch", playBatch)

-- ── the real notices ───────────────────────────────────────────────
--  The service gives the whole live list every time it changes, the newest
--  first. Three things have to be got out of it: the ones that are new —which
--  come in through the same `arrive()` as the demo, because it is the same
--  swell—, the ones that have changed while still being the same one —a
--  download that moves forward— and the ones that are no longer there without
--  us having removed them: their application closed them, which is what
--  happens when you read the message in Telegram.
local seen = {}

local function remove_done()
    for k = #rows, 1, -1 do
        if rows[k].done then table.remove(rows, k) end
    end
end

--  And no drop can count more than there are left of its kind: whatever
--  path removed one —resolved, dismissed, closed by its application—, the
--  number beside her comes down to what is really pending. Only down: a drop
--  flying back is counted by the scene when it lands. Counted from the
--  service's list, not from the rows: the tray keeps five and there may be
--  more. A resolved one still counts while its drop flies home; a dismissed
--  one no. With made-up notices there is no list, and nothing is capped.
local live = nil
local function cap_counts()
    if live == nil then return end
    local gone = {}
    for _, f in ipairs(rows) do
        if f.id and f.done and not f.flying then gone[f.id] = true end
    end
    local left = { 0, 0, 0, 0 }
    for _, n in ipairs(live) do
        if not gone[n.id] then
            local app = string.upper(n.app ~= "" and n.app or tr("notice"))
            local c = CATEGORY_OF[app] or classify(app)
            if left[c] then left[c] = left[c] + 1 end
        end
    end
    for k = 1, 4 do
        local c = "n." .. k
        if (fact[c] or 0) > left[k] then fact[c] = left[k] end
    end
end
--  The scene counts on its own when a drop sinks in, which can be seconds
--  after the notice came —she was asleep and the drop had to fall—: by then
--  it may already be closed.
for k = 1, 4 do on("fact:n." .. k, cap_counts) end

local function from_service(list)
    local present = {}
    for _, n in ipairs(list) do present[n.id] = n end
    local changed = false
    for k = #rows, 1, -1 do
        local f = rows[k]
        if f.id and not f.done then
            local n = present[f.id]
            if n == nil then
                --  Whoever sent it closed it: the row goes and its drop comes down.
                local c = "n." .. f.cat
                if (fact[c] or 0) > 0 then fact[c] = fact[c] - 1 end
                table.remove(rows, k)
                changed = true
            elseif n.title ~= f.title or n.body ~= f.detail then
                f.title, f.detail = n.title, n.body
                changed = true
            end
        end
    end
    if changed then render() end
    live = list
    cap_counts()
    for i = #list, 1, -1 do
        local n = list[i]
        if not seen[n.id] then
            seen[n.id] = true
            --  The resolved ones waited in their place so as not to move the
            --  rows mid-animation; when a new one comes in everything is
            --  rearranged, and they go.
            remove_done()
            arrive({ id = n.id, app = string.upper(n.app ~= "" and n.app or tr("notice")), title = n.title, detail = n.body,
                     urgent = (n.urgency or 1) >= 2, actions = n.actions })
        end
    end
end

if sys.watch("notifications", from_service) then
    --  This is a notice CENTRE, not a bar of bubbles: «everything arrives, you
    --  decide». If they expired on their own after six seconds, their
    --  application would stop listening and they could no longer be opened
    --  from here.
    sys.call("notifications.keep", true)
    fact.demo = false
    log("notifications · the real ones: this is who receives them now")
else
    log("demo · the notices are made up: pleamar gives up the place to whoever already has it")
    log("demo · another batch: pleamar --say marea \"emit another_batch\"")
    after(600, playBatch)
end

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

-- ── glances ─────────────────────────────────────────────────────
--  Every 7 to 16 s she looks for a moment at where the mouse is, wherever it
--  is. The scene does the looking; here it is only decided when.
local function glance_later()
    after(math.random(7000, 16000), function()
        fact.glancing = true
        after(math.random(1200, 2200), function()
            fact.glancing = false
            glance_later()
        end)
    end)
end
glance_later()

-- ── the swell ──────────────────────────────────────────────────────
--  Resolving a row is marking it read wherever it really lives. Here it is
--  only noted down: what is seen —the row leaving, the drop going back, the
--  count going down— the scene has already done, without waiting for this.
--  Resolved is not closed yet: the scene gives five seconds to change your
--  mind, and a closed notification does not come back. It is really closed
--  once the fuse has gone out, if nobody undid it.
on("resolve", function(k)
    local f = rows[k]
    if f == nil then return end
    f.done = true
    f.flying = true
    after(1000, function() f.flying = nil end)
    if f.id then
        after(5400, function()
            if f.done then sys.call("notifications.dismiss", f.id) end
        end)
    end
end)
on("undone", function(k)
    local f = rows[k]
    if f then f.done = false end
end)
--  What is dismissed does not come back: no drop, no undo.
on("dismiss", function(k)
    local f = rows[k]
    if f == nil then return end
    f.done = true
    if f.id then sys.call("notifications.dismiss", f.id) end
end)
--  A tap opens it where it lives: its default action, if it brings one. If it
--  brings none, tapping it can do no more than mark it as seen.
on("open_notice", function(k)
    local f = rows[k]
    if f == nil or f.id == nil then return end
    local can_open = false
    for _, a in ipairs(f.actions or {}) do can_open = can_open or a.key == "default" end
    if can_open then sys.call("notifications.invoke", f.id, "default") else sys.call("notifications.dismiss", f.id) end
end)
on("tray", function() log("the tray would open at the newest one") end)
on("calendar", function() log("the calendar would open here") end)
on("open_page", function(k) log("page", k) end)

-- ── the session ────────────────────────────────────────────────────
--  The only thing in the whole scene that cannot be undone, so it wears two
--  belts. The first one is the sheet's and lives in the scene: logging out,
--  rebooting and powering off open a separate question, and the answer needs
--  a new press. The second one is from here: with `MAREA_TESTING` set, what
--  would be done is noted down and not done, which is what lets you rehearse
--  the whole gesture without being left without a machine halfway through the
--  test.
-- ── the lock ──────────────────────────────────────────────────────
--  Marea locks the door herself —the scene, with `kind: lock`—; here it is
--  only asked whether the password is the right one. Who gets in is decided by
--  PAM, and it takes its time on purpose when it is not: meanwhile, the scene
--  stays alive and says it is checking.
--  The emergency exit is its own thing, not the testing mode's: `MAREA_TESTING`
--  makes powering off and rebooting only be noted down, and that has no reason
--  to go together with the lock opening with Esc. The first real locks carry
--  the exit; when the variable is removed, it stops being there.
fact.with_exit = (sys.ask("env", "MAREA_LOCK_WITH_EXIT") or "") ~= "" or (sys.ask("env", "MAREA_TESTING") or "") ~= ""
--  A rule cannot touch a text, so emptying the box is this side's business:
--  when the lock goes on and when it comes off, let nothing be left written.
on("fact:locked", function() text.password = "" end)
on("submit:password", function(value)
    if fact.locked ~= true or fact.checking == true then return end
    if value == nil or value == "" then return end
    fact.checking = true
    --  Whatever happens with the check, «checking» does not stay on: with it
    --  on you cannot try again, and a lock screen that does not let you try
    --  again is a broken lock screen.
    after(8000, function() fact.checking = false end)
    local ok, valid = pcall(sys.ask, "auth.check", value)
    text.password = ""
    fact.checking = false
    if ok and valid == true then
        fact.locked = false
    else
        if not ok then log("lock · the password could not be checked:", valid) end
        emit("wrong_password")
    end
end)

local commands = { "session.lock", "session.suspend", "session.logout", "session.reboot", "session.poweroff" }
local testing = sys.ask("env", "MAREA_TESTING")

on("session", function(k)
    local command = commands[k]
    if command == nil then
        log("session: there is no action number", k)
        return
    end
    if testing ~= nil and testing ~= "" then
        log("session · testing: it would call", command)
        return
    end
    --  Once and only once: «after confirming, send the request a single time».
    log("session ·", command)
    sys.call(command)
end)

-- ── the system tray ────────────────────────────────────────────────
--  Which icons there are is said by pleamar; here it is decided what happens
--  when they are touched. A menu is a tree, and a submenu is ENTERED: `path` is
--  the way down so far, and the first row goes back. That way everything fits
--  on the same page.
local owner = nil                 -- whose menu is being shown
local root, path = {}, {}

local function show_menu(list)
    local rows = #path > 0 and { { back = true, label = tr("‹  Back") } } or {}
    for _, it in ipairs(list) do rows[#rows + 1] = it end
    model.options = rows
end

if not sys.watch("tray", function(list) model.icons = list end) then
    log("this system has no tray")
end

on("systray_activate", function(i)
    local it = model.icons[i + 1]
    if it then sys.call("tray.activate", it.key) end
end)

on("systray_menu", function(i)
    local it = model.icons[i + 1]
    if it == nil then return end
    model.options = {}
    text["systray.title"] = it.title ~= "" and it.title or it.id
    local ok, menu = pcall(sys.ask, "tray.menu", it.key)
    if not ok or menu == nil or #menu == 0 then
        --  There is no menu to read: let it show it itself, if it knows how,
        --  and no empty page is left here acting as a waiting room.
        pcall(sys.call, "tray.context", it.key)
        fact.page = "none"
        return
    end
    owner, root, path = it, menu, {}
    show_menu(menu)
end)

on("systray_pick", function(i)
    local r = model.options[i + 1]
    if r == nil or owner == nil then return end
    if r.back then
        table.remove(path)
        show_menu(#path > 0 and path[#path].children or root)
    elseif r.children and #r.children > 0 then
        path[#path + 1] = r
        show_menu(r.children)
    else
        sys.call("tray.menu_click", owner.key, r.id)
        fact.page = "none"
    end
end)

-- ── the photograph ─────────────────────────────────────────────────
--  The whole design rests on a decision that comes from Marea: you do not
--  frame the live desktop, you frame a FROZEN one. She leaves the frame, a
--  photo of everything is taken, and that photo is what gets cropped. That way
--  a menu that closes on the first click, a video that keeps playing or a
--  notice that arrives mid-selection cannot spoil anything: what comes out was
--  already done.
--
--  The scene says `gone` when she is no longer there; here the screen is
--  frozen, she is told `frozen` so that she comes back —turned into a camera—,
--  the crop is worked out according to what was asked for, and `shoot` is the
--  shutter's click.
local PHOTOS = home_dir .. "/Imágenes/Marea"
local FRAME = (sys.ask("env", "XDG_RUNTIME_DIR") or "/tmp") .. "/marea-plm-frame.png"
run("mkdir", { "-p", PHOTOS })

--  The monitors: where the plane starts —`grim` photographs it whole and its
--  corner is the one of the monitor furthest up and to the left— and which one
--  has the focus.
local function parse_monitors(txt)
    local minx, miny, focused = 0, 0, nil
    for block in (txt .. "\n\n"):gmatch("(Monitor .-)\n\n") do
        local w, h, x, y = block:match("(%d+)x(%d+)@[%d%.]+ at (%-?%d+)x(%-?%d+)")
        if w then
            x, y = tonumber(x), tonumber(y)
            minx, miny = math.min(minx, x), math.min(miny, y)
            if block:find("focused: yes") then focused = { x = x, y = y, w = tonumber(w), h = tonumber(h) } end
        end
    end
    return minx, miny, focused
end

local function save(x, y, w, h)
    if w == nil or w < 2 or h < 2 then emit("shot_cancelled"); return end
    local dest = PHOTOS .. "/marea-" .. os.date("%Y%m%d-%H%M%S") .. ".png"
    run("magick", { FRAME, "-crop", string.format("%dx%d+%d+%d", w, h, x, y), "+repage", dest }, function(_, code)
        if code ~= 0 then log("photo · could not be cropped"); emit("shot_cancelled"); return end
        emit("shoot")
        --  To the clipboard too. `wl-copy` stays in the background serving what
        --  was copied, so there is no waiting for what it writes.
        run("wl-copy", { "--type", "image/png" }, nil, { stdin = dest, output = false })
        log("photo ·", dest)
    end)
end

on("gone", function()
    if fact.purpose ~= "shot" then return end
    local scope = fact.scope
    --  A breather so the compositor can take away whatever was closing.
    after(140, function()
        --  The active window is asked BEFORE freezing: it is the one that was there.
        run("hyprctl", { "activewindow" }, function(window)
            run("hyprctl", { "monitors" }, function(mons)
                local minx, miny, focused = parse_monitors(mons or "")
                run("grim", { FRAME }, function(_, code)
                    if code ~= 0 then log("photo · grim could not freeze the screen"); emit("shot_cancelled"); return end
                    emit("frozen")
                    if scope == "display" and focused then
                        save(focused.x - minx, focused.y - miny, focused.w, focused.h)
                    elseif scope == "active_window" then
                        local ax, ay = (window or ""):match("at: (%-?%d+),(%-?%d+)")
                        local aw, ah = (window or ""):match("size: (%d+),(%d+)")
                        if ax then save(tonumber(ax) - minx, tonumber(ay) - miny, tonumber(aw), tonumber(ah))
                        else emit("shot_cancelled") end
                    else
                        --  `slurp` gives «X,Y WxH» on the whole plane; Esc leaves with nothing.
                        run("slurp", {}, function(sel, c2)
                            local x, y, w, h = (sel or ""):match("(%-?%d+),(%-?%d+) (%d+)x(%d+)")
                            if c2 ~= 0 or x == nil then emit("shot_cancelled"); return end
                            save(tonumber(x) - minx, tonumber(y) - miny, tonumber(w), tonumber(h))
                        end)
                    end
                end)
            end)
        end)
    end)
end)

-- ── the recording ──────────────────────────────────────────────────
--  Marea already learned the hard part, and here it is copied as it is:
--  · The countdown happens BEFORE starting the recorder: three seconds to move
--    the mouse out of the way, and none of them in the video because there is
--    no video yet.
--  · Constant frame rate (`-r 60 -D`). Without it `wf-recorder` only emits a
--    frame when something changes and the video's clock stops being the real one.
--  · Stopping is SIGINT and never killing: an MP4 writes its index at the end,
--    and without an index nobody can open it. That is why the recording is not
--    considered finished when «Stop» is pressed, but when the recorder HAS EXITED.
local VIDEOS = home_dir .. "/Vídeos/Marea"
run("xdg-user-dir", { "VIDEOS" }, function(d)
    if d and d ~= "" then VIDEOS = d .. "/Marea" end
    run("mkdir", { "-p", VIDEOS })
end)
local nvenc = false
run("test", { "-e", "/proc/driver/nvidia/version" }, function(_, code) nvenc = code == 0 end)
--  With the system's sound —what is playing, not the microphone, which is not
--  opened—, which is how Marea recorded. It is asked when going to record,
--  because the current output may have changed since it started.

local recorder, video = nil, nil
--  The last one saved, for the card's buttons.
local last_video = nil
on("reel_watch", function() if last_video then run("xdg-open", { last_video }, function() end) end end)
on("reel_folder", function() run("xdg-open", { VIDEOS }, function() end) end)
on("reel_copy", function() if last_video then run("wl-copy", { last_video }, function() end) end end)

on("fact:face", function(face)
    if face ~= "rec" or recorder ~= nil then return end
    run("pactl", { "get-default-sink" }, function(sound_sink, sink_code)
    if sink_code ~= 0 or sound_sink == "" then sound_sink = nil end
    run("hyprctl", { "monitors" }, function(mons)
        if fact.face ~= "rec" then return end          -- she changed her mind during the countdown
        local monitor = nil
        for block in ((mons or "") .. "\n\n"):gmatch("(Monitor .-)\n\n") do
            if block:find("focused: yes") then monitor = block:match("Monitor (%S+)") end
        end
        video = VIDEOS .. "/marea-" .. os.date("%Y%m%d-%H%M%S") .. ".mp4"
        local args = { "-f", video }
        local codec = nvenc and { "-c", "h264_nvenc", "-p", "preset=p5", "-p", "rc=vbr", "-p", "cq=23" }
                            or { "-c", "libx264", "-p", "preset=veryfast", "-p", "crf=23" }
        for _, a in ipairs(codec) do args[#args + 1] = a end
        for _, a in ipairs({ "-r", "60", "-D" }) do args[#args + 1] = a end
        if monitor then args[#args + 1] = "-o"; args[#args + 1] = monitor end
        --  `--audio=DEVICE` with the value attached: that is how `wf-recorder`
        --  documents it, and separated it silently takes it as «the default
        --  device», which is the microphone.
        if sound_sink then args[#args + 1] = "--audio=" .. sound_sink .. ".monitor" end
        local this_one
        --  Whether it got to record: kept here, not read from `taping`, which the
        --  scene switches off the moment «stop» is pressed —long before the
        --  recorder has finished—, so a finished recording never had its party.
        local reached = false
        local this_video = video
        this_one = spawn("wf-recorder", args, function() end, function(_, code)
            --  Now it really has finished, with its index written.
            if recorder == this_one then recorder = nil end
            local recorded = reached
            fact.taping = false
            log("recording · saved", video, "· exit", code)
            --  If it left on its own —it could not start—, let her not stay in
            --  the corner recording nothing.
            if fact.face == "rec" then emit("stop") end
            --  A video really made —it was recording, and the recorder closed it
            --  cleanly— deserves a party. Once she is back from her corner: she
            --  comes down 300 ms after `stop`, and the fireworks are hers.
            --  And the card that comes out of her: watch it, its folder, or its path.
            if recorded and (code == nil or code == 0) then
                last_video = this_video
                text["reel.name"] = this_video:match("[^/]+$") or this_video
                after(700, function()
                    emit("celebrate")
                    emit("recorded")
                end)
            end
        end)
        recorder = this_one
        --  «Really running»: if it is still alive after 400 ms, the red is its own.
        after(400, function()
            if recorder == this_one then
                fact.taping = true
                reached = true
            end
        end)
    end)
    end)
end)

on("stop", function()
    if recorder ~= nil then kill(recorder, "int") end
end)

-- ── the desktop wallpaper ──────────────────────────────────────────
--  Whoever paints it is not her: it is `swaybg`, and that is the reason the
--  wallpaper stays on when she is not there. If Marea drew it, closing her
--  would leave the desktop black, which is making worse something that
--  worked. Here it is only checked at startup whether someone is painting it;
--  if not —a fresh login—, the saved one is put on.
--
--  Two things learned in Marea, both about `swaybg`: ONE single call with all
--  the screens —starting it twice leaves the second one without the first
--  image—, and the PATH is saved, not a copy of anybody's file.
--
--  The settings live in `settings.json`: `home`, `follow`, `wallpaper`,
--  `skin` and `language`. They used to live in `ajustes.json`, with Spanish keys (`casa`,
--  `sigue`, `fondo`, `piel`) and Spanish skins (`lente`, `liquido`, `normal`):
--  if there is no new file yet, the old one is read and translated, and from
--  then on only the new one is written. The old one is left where it was.
local settings = {}
do
    local ok, loaded = pcall(sys.ask, "files.read", "settings.json", "json")
    if ok and type(loaded) == "table" then
        settings = loaded
    else
        local old_ok, old = pcall(sys.ask, "files.read", "ajustes.json", "json")
        if old_ok and type(old) == "table" then
            local OLD_SKINS = { lente = "lens", liquido = "liquid", normal = "classic" }
            settings = {
                home = old.casa,
                follow = old.sigue,
                wallpaper = old.fondo,
                skin = OLD_SKINS[old.piel] or old.piel,
            }
            log("settings · read from the old ajustes.json; from now on they go to settings.json")
        end
    end
end
local WALLPAPER = settings.wallpaper or "/usr/share/wallpapers/cachyos-wallpapers/GreenFeathers.png"

run("pgrep", { "-x", "swaybg" }, function(_, code)
    if code == 0 then return end                        -- someone is already painting it
    run("hyprctl", { "monitors" }, function(mons)
        local args = {}
        for name in (mons or ""):gmatch("Monitor (%S+)") do
            for _, a in ipairs({ "-o", name, "-i", WALLPAPER, "-m", "fill" }) do args[#args + 1] = a end
        end
        if #args == 0 then return end
        --  With `run` and without collecting its output: that way it does not
        --  die with her, which is exactly what you want from a wallpaper.
        run("swaybg", args, nil, { output = false })
        log("wallpaper ·", WALLPAPER)
    end)
end)

-- ── her home: which monitor she lives on ───────────────────────────
--  One copy per monitor, and here it is decided which one is seen. Two ways: a
--  fixed home, or «follow me» —she goes wherever the window with the focus is,
--  which the `window` service tells—. The home is saved by NAME (`DP-3`):
--  monitors change number when another one is plugged in, and a name does not.
local monitors = {}                  -- in the compositor's order: name
local focused = ""

local function decide()
    for k = 0, 1 do
        local name = monitors[k + 1]
        local hers
        if fact.following == true then
            hers = name ~= nil and name == focused
            --  With no focus on any —the empty desktop—, home.
            if focused == "" then hers = k == fact.home end
        else
            hers = k == fact.home
        end
        fact["hosts." .. k] = hers
    end
end

local function save_settings()
    settings.home = monitors[(fact.home or 0) + 1] or settings.home
    settings.follow = fact.following == true
    settings.skin = fact.skin
    settings.language = fact.language
    settings.wallpaper = WALLPAPER
    pcall(sys.call, "files.write", "settings.json", settings)
end

--  Which monitor each copy is, pleamar says, not `hyprctl`: the order of the
--  copies is its own (`screen.0.name`, `screen.1.name`), and it does not match
--  the compositor's. They arrive as each surface is put up, so the home is
--  picked up as soon as both are known.
local function place()
    fact.home = 0
    for k, name in ipairs(monitors) do
        if name == settings.home then fact.home = k - 1 end
    end
    fact.following = settings.follow == true
    decide()
end
for k = 0, 1 do
    on("text:screen." .. k .. ".name", function(name)
        if name == nil or name == "" then return end
        monitors[k + 1] = name
        place()
    end)
end
--  When only the logic is reloaded, the names no longer arrive again: the ones
--  there are are read.
for k = 0, 1 do
    local name = text["screen." .. k .. ".name"]
    if name ~= nil and name ~= "" then monitors[k + 1] = name end
end

if not sys.watch("window", function(v)
    focused = (v and v.monitor) or ""
    if fact.following == true then decide() end
end) then log("this compositor does not say where the focus is: «follow me» will not work") end

on("fact:home", function() decide(); save_settings() end)
on("fact:following", function() decide(); save_settings() end)

--  Her look, as it was left last time. If the file holds something that is not
--  one of the three —another version, a hand edit—, the factory one stays.
if settings.skin == "lens" or settings.skin == "liquid" or settings.skin == "classic" then
    fact.skin = settings.skin
end
on("fact:skin", function() save_settings() end)

-- ── the language ───────────────────────────────────────────────────
--  What the scene writes changes language by itself; what this logic wrote
--  stays in the language it was written in until it is written again. So when
--  `locale` changes, the texts that are Marea's own words are written again:
--  the rows of the swell, her menu and the finder's list (only if it is open:
--  otherwise it is filled again when it opens).
on("fact:locale", function()
    render()
    set_menu()
    if fact.searching == true then search() end
end)

--  Which one. «System» is what the session says —`LC_ALL`, `LC_MESSAGES`,
--  `LANG`, the first one that says something, as pleamar reads it—, asked here
--  and not remembered from the `locale` it started with: if only the logic is
--  reloaded, `locale` may already be one chosen by hand. Anything that is not
--  Spanish is English, which is the language the scene is written in.
local function system_locale()
    for _, v in ipairs({ "LC_ALL", "LC_MESSAGES", "LANG" }) do
        local ok, value = pcall(sys.ask, "env", v)
        if ok and type(value) == "string" and value ~= "" and value ~= "C" and value ~= "POSIX" then
            return value:sub(1, 2):lower() == "es" and "es" or "en"
        end
    end
    return "en"
end
local LOCALES = { english = "en", spanish = "es" }
local function speak()
    fact.locale = LOCALES[fact.language] or system_locale()
end
if settings.language == "system" or settings.language == "english" or settings.language == "spanish" then
    fact.language = settings.language
end
speak()
on("fact:language", function() speak(); save_settings() end)
