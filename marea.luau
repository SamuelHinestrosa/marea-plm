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
on("set_mic", function(v) sys.call("audio.input", v) end)
--  The keyboard's keys: a step of 5 %. The volume never past 100 % (the
--  service's step stops there); the meter beside her shows it as always.
on("volume_up", function() sys.call("audio.step", 0.05) end)
on("volume_down", function() sys.call("audio.step", -0.05) end)
local function bright_step(d)
    local now = tonumber(fact["display.level"]) or 0.5
    sys.call("brightness.level", math.clamp(now + d, 0.01, 1))
end
on("bright_up", function() bright_step(0.05) end)
on("bright_down", function() bright_step(-0.05) end)

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
--  The Wi-Fi and Bluetooth switches: what the system says, read from
--  pleamar's own services (NetworkManager and BlueZ, spoken to directly), and
--  flipped from what they say rather than from what was assumed.
local net_state, bt_state = {}, {}

on("flip", function(k)
    if k == 1 then
        pcall(sys.call, "network.wifi", not net_state.wifi)
    elseif k == 2 then
        pcall(sys.call, "bluetooth.power", not bt_state.powered)
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
--  The networks and the gadgets come from pleamar's services, which also
--  join, pair and forget. A new network with a password asks for it in place;
--  one already known, or open, joins at once. Whichever is being joined
--  breathes until the system says it is the one in use.
local joining_name, joining_since = nil, 0

local function paint_networks()
    local v = {}
    for _, n in ipairs(net_state.networks or {}) do
        v[#v + 1] = { name = n.ssid, signal = n.strength or 0, current = n.active == true, secure = n.secure == true, known = n.known == true }
    end
    table.sort(v, function(a, b)
        if a.current ~= b.current then return a.current end
        if a.known ~= b.known then return a.known end
        return a.signal > b.signal
    end)
    while #v > 8 do table.remove(v) end
    model.networks = v
    fact["switched_on.1"] = net_state.wifi == true
    --  The one being joined, by its place now (the list moves as it is joined).
    fact.joining = -1
    if joining_name ~= nil then
        for k, n in ipairs(v) do
            if n.name == joining_name then
                if n.current then joining_name = nil else fact.joining = k - 1 end
            end
        end
    end
end

sys.watch("network", function(state)
    net_state = state or {}
    paint_networks()
end)

--  And if it never joins —a wrong password, out of reach— it stops breathing.
every(3000, function()
    if joining_name ~= nil and os.time() - joining_since > 25 then
        log("wi-fi · could not join", joining_name)
        joining_name = nil
        paint_networks()
    end
end)

local function join(name, password)
    joining_name, joining_since = name, os.time()
    local ok, err = pcall(sys.call, "network.connect", name, password)
    if not ok then
        log("wi-fi · joining failed:", err)
        joining_name = nil
    end
    paint_networks()
end

on("pick_network", function(i)
    local r = model.networks[i + 1]
    if r == nil or r.current then return end
    if r.secure and not r.known then
        text["ask.name"] = r.name
        text.wifi_pw = ""
        fact.asking = i
        return
    end
    fact.asking = -1
    join(r.name, nil)
end)

on("join", function()
    local r = model.networks[(fact.asking or -1) + 1]
    local password = text.wifi_pw or ""
    fact.asking = -1
    text.wifi_pw = ""
    if r ~= nil and password ~= "" then join(r.name, password) end
end)
on("forget_ask", function()
    fact.asking = -1
    text.wifi_pw = ""
end)

--  Bluetooth: the paired ones first —the connected at the top— and, while
--  looking, the ones just found, to be paired with a press.
local function paint_gadgets()
    local v = {}
    for _, d in ipairs(bt_state.devices or {}) do
        v[#v + 1] = { name = d.name, current = d.connected == true, paired = d.paired == true, battery = d.battery or -1, address = d.address }
    end
    while #v > 8 do table.remove(v) end
    model.gadgets = v
    fact["switched_on.2"] = bt_state.powered == true
    fact.bt_scanning = bt_state.discovering == true
    local first = v[1]
    text["bt.sub"] = (first and first.current) and first.name or (bt_state.powered and tr("On") or tr("Off"))
end

sys.watch("bluetooth", function(state)
    bt_state = state or {}
    paint_gadgets()
end)

on("pick_gadget", function(i)
    local c = model.gadgets[i + 1]
    if c == nil or c.address == nil then return end
    pcall(sys.call, c.current and "bluetooth.disconnect" or "bluetooth.connect", c.address)
end)

on("bt_scan", function()
    pcall(sys.call, "bluetooth.scan", not bt_state.discovering)
end)

--  Opening a page asks for a fresh look: the networks around, and the gadgets
--  near (it listens while the page is open, and stops when it closes).
on("scan", function(k)
    if k == 1 then pcall(sys.call, "network.scan")
    elseif k == 2 and bt_state.powered and not bt_state.discovering then pcall(sys.call, "bluetooth.scan", true) end
end)
on("fact:page", function(p)
    if p ~= "bluetooth" and bt_state.discovering then pcall(sys.call, "bluetooth.scan", false) end
    if p ~= "wifi" then fact.asking = -1 end
end)


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

--  What is hers, findable by writing: her pages and her tricks. Each one with
--  the words it answers to, in both languages whatever the one she speaks —you
--  think «cupos» even with her in English—, the little face it shows in the
--  list (1 plain, 2 happy, 3 angry, 4 waves) and what opening it does. Whatever
--  is built for her from now on goes in here, and it can be found.
local function open_page(page, section)
    return function()
        fact.open = true
        fact.page = page
        if section then fact.section = section end
    end
end
--  What is written further down and opened from here: filled in there.
local hooks = {}
local OWN = {
    { "Calendar", "calendar calendario agenda events eventos evento cita citas reminder recordatorio meeting reunion", 1,
      function() if hooks.calendar then hooks.calendar() end; open_page("calendar")() end },
    { "Talk with Marea", "chat hablar habla conversar conversacion conversación pregunta preguntar ia ai agente agent asistente assistant marea pi", 2,
      function() if hooks.chat then hooks.chat() end end },
    { "Updates", "updates update upgrade actualizaciones actualizar actualizacion actualización sistema system pacman yay paru aur paquetes packages", 1,
      function() if hooks.software then hooks.software("updates") end end },
    { "Install programs", "install instalar programas programs apps aplicaciones paquetes packages software catalogue catalogo catálogo tienda store aur pacman", 1,
      function() if hooks.software then hooks.software("catalogue") end end },
    { "Agents", "agents agentes claude codex quota quotas cupos cupo reservas limits limites usage uso ia ai tokens", 4,
      function() open_page("agents")(); emit("agents_refresh") end },
    { "What she remembers", "memory memoria recuerdos recuerda remember recordar olvidar forget notas notes aprendido learned historial history conversaciones conversations", 2,
      open_page("settings", "memory") },
    { "Settings", "settings ajustes preferences preferencias configuracion configuration", 1, open_page("settings", "menu") },
    { "Where she lives", "monitor pantalla screen casa home follow seguir sigueme sígueme donde vive", 1, open_page("settings", "home") },
    { "Language", "language idioma lengua english ingles inglés español spanish", 1, open_page("settings", "language") },
    { "Appearance", "appearance apariencia skin piel theme tema glass cristal lens lente look aspecto", 1, open_page("settings", "look") },
    { "Her sky", "sky cielo weather tiempo clima temperatura temperature lluvia rain ciudad city ubicacion ubicación location", 1,
      function() open_page("calendar")(); fact["sky.editing"] = true end },
    { "Her wardrobe", "wardrobe armario ropa clothes hat hats sombrero gorro accesorios accessories headphones cascos auriculares", 2, open_page("wardrobe") },
    { "Wi-Fi", "wifi wi-fi red network internet", 1, open_page("wifi") },
    { "Bluetooth", "bluetooth auriculares headphones", 1, open_page("bluetooth") },
    { "Sound", "sound sonido audio volume volumen output salida microfono microphone", 1, open_page("sound") },
    { "Focus", "focus concentracion concentración pomodoro haven refugio", 1, open_page("concentration") },
    { "Session", "session sesion sesión apagar power poweroff reiniciar reboot restart logout salir suspend suspender", 1, open_page("session") },
    { "Lock the screen", "lock bloquear bloqueo pantalla screen", 1, function() emit("lock") end },
    { "Sleep", "sleep dormir siesta nap", 1, function() emit("sleep") end },
    { "Screenshot of a region", "screenshot captura region región recorte shot", 1, function() emit("shot_region") end },
    { "Screenshot of the screen", "screenshot captura pantalla screen shot", 1, function() emit("shot_screen") end },
    { "Screenshot of a window", "screenshot captura ventana window shot", 1, function() emit("shot_window") end },
    { "Record the screen", "record grabar grabacion grabación video vídeo screencast", 1, function() emit("record_toggle") end },
    --  Only in pleamar-wm's own session: its window manager.
    { "Tiled or free windows", "windows ventanas libres free tiled mosaico tiling floating flotantes modo mode", 1,
      function() if hooks.wm_free then hooks.wm_free() end end, "wm" },
    { "Bring back every window", "minimized minimizadas recoger restore restaurar devolver traer windows ventanas", 1,
      function() if hooks.wm_restore then hooks.wm_restore() end end, "wm" },
    { "Rain on the windows", "rain lluvia llover llueve water agua drops gotas weather tiempo shader windows ventanas", 1,
      function() if hooks.wm_rain then hooks.wm_rain() end end, "wm" },
    { "Rain intensity", "rain lluvia intensity intensidad light suave medium media heavy fuerte drizzle llovizna downpour chaparron chaparrón gotas drops", 1,
      function() if hooks.wm_rain_level then hooks.wm_rain_level() end end, "wm" },
    { "Snow on the windows", "snow nieve nevar nieva winter invierno frost escarcha hielo ice weather tiempo shader windows ventanas", 1,
      function() if hooks.wm_snow then hooks.wm_snow() end end, "wm" },
    { "Ride a window", "ride montar subir súbete subete sit sentarse ventana window marea viaje", 1,
      function() if hooks.wm_ride then hooks.wm_ride() end end, "wm" },
    { "Wallpapers", "wallpaper wallpapers fondo fondos pantalla escritorio desktop background imagen tema theme", 1, function() emit("show_walls") end },
    { "Deriva", "deriva drift biblioteca library guardado saved kept enlaces links recortes bookmarks marcadores", 1, function() emit("show_drift") end },
    { "Do not disturb", "do not disturb no molestar dnd silencio silence quiet callar avisos notices notificaciones notifications", 1,
      function() if hooks.dnd then hooks.dnd() end end },
    { "Notices", "notices avisos notificaciones notifications silenciar mute muted apps posponer snooze later luego grabar recording", 1, open_page("settings", "notices") },
    { "Notice history", "history historial avisos notificaciones notices notifications pasados old viejos marea oleaje swell", 1, function() emit("show_history") end },
    { "Celebrate", "celebrate celebrar fiesta party fireworks cohetes fuegos", 2, function() emit("celebrate") end },
    { "Rage", "rage enfado enfadada angry pistola gun disparar shoot", 3, function() emit("rage") end },
    { "Adventure", "adventure aventura alas wings volar fly saltar", 2, function() emit("adventure") end },
}

--  The windows open right now (the `window` service, further down, keeps
--  this): the finder finds them too, and choosing one goes to it —in
--  pleamar-wm, to the workspace it is on—.
local open_windows = {}

--  Hers first, when what is written starts one of her words or is in her
--  name: typing «cla» finds the agents before any application.
local function own_matches(q)
    local found = {}
    if #q < 2 then return found end
    for k, o in ipairs(OWN) do
        if o[5] == "wm" and not hooks.in_wm then continue end
        local name = tr(o[1])
        local hit = name:lower():find(q, 1, true) ~= nil
        if not hit then
            for w in string.gmatch(o[2], "%S+") do
                if w:sub(1, #q) == q then hit = true; break end
            end
        end
        if hit and #found < 3 then
            found[#found + 1] = { name = name, kind_label = "Marea", icon = "", glyph = o[3], own = k }
        end
    end
    return found
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
    local list = own_matches(q)
    --  Then the windows already open whose program or title it names: going
    --  to one is quicker than opening another.
    if #q >= 2 then
        local shown = 0
        for _, w in ipairs(open_windows) do
            local class, title = tostring(w.class or ""), tostring(w.title or "")
            if shown < 2 and (class:lower():find(q, 1, true) or title:lower():find(q, 1, true)) then
                shown = shown + 1
                list[#list + 1] = { name = title ~= "" and title or class, kind_label = tr("Window") .. (class ~= "" and " · " .. class or ""), icon = class, window_id = w.id }
            end
        end
    end
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
    --  A program that is not installed and is named like that: from the
    --  catalogue, to install it. Only while there is room left.
    if hooks.packages and #list < 6 then
        hooks.packages(q, function(rows)
            if mine ~= generation then return end
            for _, r in ipairs(rows) do
                if #list < 7 then list[#list + 1] = r end
            end
            paint(q, list)
        end)
    end
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
                    path = clean,
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
    if h.own then
        log("opening, of hers:", h.name)
        text.query = ""
        --  The finder is closing as this arrives; the card opens a moment
        --  later, so the two do not cross.
        after(180, OWN[h.own][4])
        return
    end
    if h.package then
        log("to the catalogue:", h.package)
        text.query = ""
        after(180, function() if hooks.install then hooks.install(h.package) end end)
        return
    end
    if h.window_id then
        log("going to the window", h.name)
        pcall(sys.call, "window.activate", h.window_id)
    elseif h.exec then
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
    { id = "desk.walls",    group = "Desktop", title = "Wallpapers" },
    { id = "drift.open",    group = "Drift", title = "Her library" },
    { id = "drift.paste",   group = "Drift", title = "Keep what is copied" },
    { id = "swell.history", group = "Swell", title = "History" },
}

--  In pleamar-wm's own session its window manager answers to `wm`: her menu
--  and her finder can switch it between tiled and free windows, and bring
--  back every window put away.
local in_wm = false
do
    local ok, where = pcall(sys.ask, "env", "PLEAMAR_SOCKETS")
    in_wm = ok and type(where) == "string" and where:find("pleamar%-pleamar") ~= nil
end
local function wm_toggle_free()
    run("pleamar-wm", { "--say", "wm", "emit toggle_free" }, nil, { output = false })
end
--  Rain on the windows, as if they were glass: the window manager's shader.
--  While it rains, her menu has one more entry: how hard, from a drizzle to a
--  downpour, a press going round the three.
--  While it rains, her control center has a fourth level: how hard, from a
--  drizzle to a downpour. Dragging it sends the window manager a new amount
--  every few percent, not every pixel: each one is a process.
local raining = false
local rain_amount = 1
local rain_sent = -1
local function wm_rain_level_send(force)
    if not force and math.abs(rain_amount - rain_sent) < 0.04 and rain_amount > 0.1 and rain_amount < 1 then return end
    rain_sent = rain_amount
    run("pleamar-wm", { "--say", "wm", "emit rain_level " .. string.format("%.2f", rain_amount) }, nil, { output = false })
end
local function refresh_rain()
    fact.rain_on = in_wm and raining
    fact.rain_amount = rain_amount
end
local function wm_toggle_rain()
    run("pleamar-wm", { "--say", "wm", "emit toggle_rain" }, nil, { output = false })
    raining = not raining
    if raining then wm_rain_level_send(true) end
    refresh_rain()
end
on("set_rain", function(v)
    rain_amount = math.max(0.1, math.min(1, v))
    fact.rain_amount = rain_amount
    wm_rain_level_send(false)
end)
--  From her finder: it rains (if it was not already), and her control center
--  opens with the level to drag.
local function wm_rain_level()
    if not raining then wm_toggle_rain() end
    fact.open = true
    fact.page = "none"
end
--  Or snow: frost on the glass and snow piled on top (the rain stops).
local function wm_toggle_snow()
    run("pleamar-wm", { "--say", "wm", "emit toggle_snow" }, nil, { output = false })
    raining = false
    refresh_rain()
end
--  She rides the window with the keyboard: she leaves by the top edge and the
--  window manager draws her on its title bar (see `ride` in its scene). Asked
--  again while she is out, she comes home.
local riding = false
local function wm_ride()
    if riding then
        run("pleamar-wm", { "--say", "wm", "emit unride" }, nil, { output = false })
        return
    end
    riding = true
    emit("ride_out")
end
on("gone", function()
    if fact.purpose ~= "ride" then return end
    run("pleamar-wm", { "--say", "wm", "emit ride" }, nil, { output = false })
end)
on("ride_back", function() riding = false end)
local function wm_restore_all()
    if hooks.restore_all then hooks.restore_all() end
end
hooks.in_wm = in_wm
hooks.wm_free = wm_toggle_free
hooks.wm_restore = wm_restore_all
hooks.wm_rain = wm_toggle_rain
hooks.wm_rain_level = wm_rain_level
hooks.wm_snow = wm_toggle_snow
hooks.wm_ride = wm_ride
if in_wm then
    table.insert(plugin_entries, 1, { id = "wm.free", group = "Windows", title = "Tiled or free windows" })
    table.insert(plugin_entries, 2, { id = "wm.restore", group = "Windows", title = "Bring back every window" })
    table.insert(plugin_entries, 3, { id = "wm.rain", group = "Windows", title = "Rain on the windows" })
    table.insert(plugin_entries, 4, { id = "wm.snow", group = "Windows", title = "Snow on the windows" })
    table.insert(plugin_entries, 5, { id = "wm.ride", group = "Windows", title = "Ride a window" })
end

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
    if e ~= nil and e.id == "wm.free" then wm_toggle_free(); return end
    if e ~= nil and e.id == "wm.restore" then wm_restore_all(); return end
    if e ~= nil and e.id == "wm.rain" then wm_toggle_rain(); return end
    if e ~= nil and e.id == "wm.snow" then wm_toggle_snow(); return end
    if e ~= nil and e.id == "swell.history" then emit("show_history"); return end
    if e ~= nil and e.id == "drift.open" then emit("show_drift"); return end
    if e ~= nil and e.id == "desk.walls" then emit("show_walls"); return end
    if e ~= nil and e.id == "drift.paste" then if hooks.keep_copied then hooks.keep_copied() end; return end
    if e ~= nil and e.id == "wm.ride" then wm_ride(); return end
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

--  The actions of the notice that arrives, for its chips: its own ones, not
--  the default (that is «Open»), two at most.
local arriving_actions = {}

--  What the arriving card shows besides the words: its icon, whether it is
--  urgent, and what can be done with it without opening anything. Called for
--  the one that arrives, and again for the next one of the pile when the one
--  in front is done.
local function show_front(n)
    text.who = shown(n, n.title)
    text.line = shown(n, n.detail)
    model.notice_face = { { icon = n.icon or "" } }
    fact["notice.icon"] = (n.icon or "") ~= ""
    fact.reading_urgent = n.urgent == true
    arriving_actions = {}
    for _, a in ipairs(n.actions or {}) do
        if a.key ~= "default" and #arriving_actions < 2 then arriving_actions[#arriving_actions + 1] = a end
    end
    text["act.1"] = arriving_actions[1] and arriving_actions[1].label or ""
    text["act.2"] = arriving_actions[2] and arriving_actions[2].label or ""
    fact.acts = #arriving_actions
end

--  Whether a notice comes in quietly —straight to its drop, no card—: with
--  the screen locked, while a recording is going on (unless that is turned
--  off), and with «do not disturb», which an urgent one gets through.
local function quiet_for(n)
    if fact.locked == true then return true end
    if (fact.taping == true or fact.sharing == true) and fact.quiet_rec ~= false then return true end
    return fact.dnd == true and not n.urgent
end

local function arrive(n)
    n.cat = CATEGORY_OF[n.app] or classify(n.app)
    table.insert(rows, 1, n)
    while #rows > 5 do table.remove(rows) end
    render()
    fact.cat = n.cat
    show_front(n)
    fact.hush = quiet_for(n)
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
-- ── what has washed up: the history ───────────────────────────────
--  Every real notice once it is dealt with —done, thrown away, opened, or
--  closed by its own application— goes here, newest first, and to disk
--  (`history.json` in her folder), so a restart does not wash it away. The
--  page shows a window of it, a row for each day and the notices under it.
local history = {}
do
    local ok, loaded = pcall(sys.ask, "files.read", "history.json", "json")
    if ok and type(loaded) == "table" and type(loaded.items) == "table" then history = loaded.items end
end
local history_offset = 0
local history_saving = false
local function save_history()
    if history_saving then return end
    history_saving = true
    after(1000, function()
        history_saving = false
        pcall(sys.call, "files.write", "history.json", { items = history })
    end)
end
local DAY_NAMES = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local function day_label(t)
    local now = os.date("*t")
    local midnight = os.time({ year = now.year, month = now.month, day = now.day, hour = 0 })
    if t >= midnight then return tr("Today") end
    if t >= midnight - 86400 then return tr("Yesterday") end
    local d = os.date("*t", t)
    return string.format("%s %d", tr(DAY_NAMES[d.wday]), d.day)
end
local function paint_history()
    local rows, last_day = {}, nil
    for k = history_offset + 1, #history do
        local h = history[k]
        local day = day_label(h.time or 0)
        if day ~= last_day then
            if #rows >= 8 then break end
            rows[#rows + 1] = { head = true, day = day, app = "", title = "", detail = "", when = "", cat = 4, age = 0 }
            last_day = day
        end
        if #rows >= 9 then break end
        rows[#rows + 1] = { head = false, day = "", app = h.app or "", title = h.title or "", detail = h.detail or "",
                            when = os.date("%H:%M", h.time or 0), cat = h.cat or 4,
                            age = math.min(1, (os.time() - (h.time or 0)) / 604800) }
    end
    model.past = rows
end
local function remember(f)
    if f == nil or f.id == nil or f.remembered then return end
    f.remembered = true
    table.insert(history, 1, { app = f.app, title = f.title, detail = f.detail, cat = f.cat, time = os.time() })
    while #history > 300 do table.remove(history) end
    save_history()
    if fact.page == "history" then paint_history() end
end
on("history_open", function()
    history_offset = 0
    paint_history()
end)
--  The wheel: up, newer; down, older. Three at a time.
on("history_scroll", function(w)
    local step = (w or 0) > 0 and -3 or 3
    history_offset = math.max(0, math.min(history_offset + step, math.max(#history - 1, 0)))
    paint_history()
end)
on("clear_history", function()
    history = {}
    history_offset = 0
    save_history()
    paint_history()
end)

-- ── Deriva: what is dropped on her, kept, and found again ──────────
--  Her library is `deriva-worker`, the same one the Quickshell Marea used: a
--  local SQLite with the files kept by their hash, which saves, searches and
--  gives back. It answers a line of JSON. What is let go on her goes in —the
--  inbox, or «Read later» / «Inspiration» if it was let go on their drops—, and
--  the page shows it again as cards.
local DRIFT = "deriva-worker"
local drift_items, drift_offset, drift_blobs = {}, 0, nil

local function drift_run(args, done)
    run(DRIFT, args, function(out, code)
        local ok, v = pcall(json.decode, tostring(out or ""))
        if code ~= 0 or not ok or type(v) ~= "table" then
            log("deriva ·", args[1], "did not answer", code)
            if done then done(nil) end
            return
        end
        --  Its answers come wrapped (`{ ok, result }`); `where` does not.
        if v.ok == false then
            log("deriva ·", args[1], "said no:", v.error and v.error.message or "?")
            if done then done(nil) end
            return
        end
        if done then done(v.result or v) end
    end)
end
--  Where it keeps the files. No answer at all: the library is not there, or
--  not yet (her launcher builds it the first time, in the background).
local function drift_where(done)
    drift_run({ "where" }, function(r)
        if r then drift_blobs = r.blobs end
        fact["drift.missing"] = r == nil
        if done then done() end
    end)
end
drift_where()

local function host_of(u) return tostring(u or ""):match("^%a+://([^/]+)") or "" end
local function blob_path(it)
    local h = it.blob_hash
    if drift_blobs == nil or type(h) ~= "string" or #h < 4 then return "" end
    return drift_blobs .. "/" .. h:sub(1, 2) .. "/" .. h:sub(3, 4) .. "/" .. h
end
local function link_of(it)
    if type(it.source_url) == "string" and it.source_url ~= "" then return it.source_url end
    return blob_path(it)
end

local function show_drift()
    local cards = {}
    for k = drift_offset + 1, math.min(drift_offset + 4, #drift_items) do
        local it = drift_items[k]
        local title = (it.title ~= nil and it.title ~= "") and it.title or it.blob_name or it.excerpt or "…"
        local source = (it.source ~= nil and it.source ~= "" and it.source ~= "web") and it.source or host_of(it.source_url)
        local preview = type(it.preview_path) == "string" and it.preview_path or ""
        cards[#cards + 1] = { title = tostring(title):gsub("%s+", " "), source = source, kind = string.upper(tostring(it.type or "")),
                              date = day_label(math.floor((it.captured_at or 0) / 1000)), preview = preview,
                              has_preview = preview ~= "", link = link_of(it) }
    end
    model.drift = cards
end

local function drift_load()
    local q = text.drift_q or ""
    local args = q == "" and { "list", "--limit", "60" } or { "search", "--query", q, "--limit", "60" }
    drift_run(args, function(r)
        drift_items = (r and r.items) or {}
        drift_offset = 0
        if q == "" then fact["drift.kept"] = #drift_items end
        show_drift()
    end)
end
on("drift_open", function()
    if fact["drift.missing"] then drift_where(drift_load) else drift_load() end
end)
--  Typing searches, a moment after the last key.
local drift_typed = 0
on("text:drift_q", function()
    drift_typed = drift_typed + 1
    local mine = drift_typed
    after(260, function() if mine == drift_typed then drift_load() end end)
end)
on("drift_scroll", function(w)
    local step = (w or 0) > 0 and -2 or 2
    drift_offset = math.max(0, math.min(drift_offset + step, math.max(#drift_items - 2, 0)))
    drift_offset = drift_offset - drift_offset % 2
    show_drift()
end)
on("drift_pick", function(i)
    local it = drift_items[drift_offset + i + 1]
    if it == nil then return end
    local link = link_of(it)
    if link ~= "" then run("xdg-open", { link }, function() end) end
end)

--  What a file is, by its extension: it decides its icon and its filters.
local KINDS = {
    image = { "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "avif", "heic" },
    video = { "mp4", "mkv", "webm", "mov", "avi" },
    audio = { "mp3", "ogg", "flac", "wav", "m4a", "opus" },
    document = { "pdf", "odt", "doc", "docx", "txt", "md", "epub", "rtf", "ods", "xlsx", "odp", "pptx" },
    code = { "rs", "py", "js", "ts", "lua", "luau", "c", "h", "cpp", "go", "java", "sh", "json", "toml", "yaml", "yml", "plm", "qml", "html", "css" },
}
local function kind_of(path)
    local ext = tostring(path):match("%.([%w]+)$")
    ext = ext and ext:lower() or ""
    for kind, list in pairs(KINDS) do
        for _, e in ipairs(list) do if e == ext then return kind end end
    end
    return "file"
end
local function url_decode(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

local SPACES = { drift_drop = nil, drift_later = "leer-luego", drift_insp = "inspiracion" }
local PLACES = { drift_drop = "Deriva", drift_later = "Read later", drift_insp = "Inspiration" }

local function keep(data, mime, zone)
    local urls, groups, words = {}, {}, {}
    for line in tostring(data or ""):gmatch("[^\r\n]+") do
        local l = line:match("^%s*(.-)%s*$")
        if l:match("^file://") then
            local p = url_decode(l:gsub("^file://[^/]*", ""))
            local k = kind_of(p)
            groups[k] = groups[k] or {}
            table.insert(groups[k], p)
        elseif l:match("^https?://%S+$") then
            urls[#urls + 1] = l
        elseif l ~= "" and not l:match("^#") then
            words[#words + 1] = l
        end
    end
    local requests = {}
    for _, u in ipairs(urls) do requests[#requests + 1] = { type = "url", source_url = u } end
    for k, paths in pairs(groups) do requests[#requests + 1] = { type = k, paths = paths } end
    if #words > 0 and mime ~= "text/uri-list" then requests[#requests + 1] = { type = "text", text = table.concat(words, "\n") } end
    if #requests == 0 then return end
    local space = SPACES[zone]
    local saved, duplicates, failed, left = 0, 0, 0, #requests
    local function finished()
        if saved > 0 then
            fact["drift.result"] = 1
            text["drift.toast"] = string.format(tr("Kept in %s"), tr(PLACES[zone] or "Deriva"))
        elseif duplicates > 0 then
            fact["drift.result"] = 2
            text["drift.toast"] = tr("It was already there")
        else
            fact["drift.result"] = 3
            text["drift.toast"] = tr("Could not keep it")
        end
        emit("drift_saved")
        if fact.page == "drift" then drift_load() end
    end
    for _, req in ipairs(requests) do
        if space then req.space = space end
        drift_run({ "ingest", "--request", json.encode(req) }, function(r)
            if r then
                saved = saved + (r.saved or 0)
                duplicates = duplicates + (r.duplicates or 0)
            else
                failed = failed + 1
            end
            left = left - 1
            if left == 0 then finished() end
        end)
    end
end
for zone in pairs(PLACES) do
    on("drop:" .. zone, function(data, mime) keep(data, mime, zone) end)
end
--  And what is copied, from her menu or the finder: kept without carrying it.
local function keep_copied()
    local ok, copied = pcall(sys.ask, "clipboard")
    if ok and type(copied) == "string" and copied ~= "" then keep(copied, "text/plain", "drift_drop") end
end
hooks.keep_copied = keep_copied

local seen = {}
--  The ones already dealt with here, while the service has not yet said they
--  are gone: they must not come back to fill a gap.
local finished = {}

local function remove_done()
    for k = #rows, 1, -1 do
        if rows[k].done then
            if rows[k].id then finished[rows[k].id] = true end
            table.remove(rows, k)
        end
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
--  The ones sent «later»: out of sight and out of the counts until their
--  time comes. And the apps muted: their notices go straight to the history.
local snoozed = {}
local muted_apps = {}
local function cap_counts()
    if live == nil then return end
    local gone = {}
    for _, f in ipairs(rows) do
        if f.id and f.done and not f.flying then gone[f.id] = true end
    end
    for id in pairs(snoozed) do gone[id] = true end
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

--  A row made from one of the service's notices, without arriving again.
local function row_of(n)
    local app = string.upper(n.app ~= "" and n.app or tr("notice"))
    return { id = n.id, app = app, title = n.title, detail = n.body, urgent = (n.urgency or 1) >= 2,
             actions = n.actions, icon = n.icon, cat = CATEGORY_OF[app] or classify(app) }
end

--  What hovering over her shows: the newest one still pending. Not while a
--  card is being read: that one is using the same words.
local function refresh_preview()
    if (fact.phase or 0) ~= 0 then return end
    for _, f in ipairs(rows) do
        if not f.done then
            show_front(f)
            fact.cat = f.cat
            return
        end
    end
end

--  The tray shows five, and the service may keep more: the ones that did not
--  fit waited there, counted beside her, and with no row they could never be
--  dealt with. Whatever room there is gets filled from the service's list,
--  newest first. Only with the tray closed: rows do not move under the pointer.
local function refill()
    if live == nil or fact.tray_open then return end
    --  A drop still flying home counts by its row: that row stays where it is.
    for _, f in ipairs(rows) do
        if f.flying then return end
    end
    remove_done()
    local inrow = {}
    for _, f in ipairs(rows) do
        if f.id then inrow[f.id] = true end
    end
    for _, n in ipairs(live) do
        if #rows >= 5 then break end
        if not inrow[n.id] and not finished[n.id] and not snoozed[n.id] then
            rows[#rows + 1] = row_of(n)
        end
    end
    table.sort(rows, function(a, b) return (a.id or 0) > (b.id or 0) end)
    render()
    refresh_preview()
end
on("fact:tray_open", refill)

--  In pleamar-wm, the shore shows what is unread on each program's icon: it
--  is told how many notices each one has, whenever that changes.
local sent_badges = nil
local function tell_badges(list)
    if not in_wm then return end
    local counts, order = {}, {}
    for _, n in ipairs(list or {}) do
        local a = (tostring(n.app or ""):lower():gsub("%s+", "_"))
        if a ~= "" then
            if counts[a] == nil then order[#order + 1] = a end
            counts[a] = (counts[a] or 0) + 1
        end
    end
    local parts = {}
    for _, a in ipairs(order) do parts[#parts + 1] = a .. ":" .. counts[a] end
    local text = table.concat(parts, " ")
    if text == sent_badges then return end
    sent_badges = text
    run("pleamar-wm", { "--say", "wm", "text win.badges " .. text }, nil, { output = false })
end

local function from_service(list)
    local present = {}
    for _, n in ipairs(list) do present[n.id] = n end
    --  What the service no longer has needs no remembering.
    for id in pairs(finished) do
        if present[id] == nil then finished[id] = nil end
    end
    local changed = false
    for k = #rows, 1, -1 do
        local f = rows[k]
        if f.id and not f.done then
            local n = present[f.id]
            if n == nil then
                --  Whoever sent it closed it: the row goes and its drop comes down.
                remember(f)
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
        if not seen[n.id] and muted_apps[string.upper(n.app ~= "" and n.app or tr("notice"))] then
            --  A muted app: kept in the history, and gone.
            seen[n.id] = true
            finished[n.id] = true
            remember(row_of(n))
            sys.call("notifications.dismiss", n.id)
        elseif not seen[n.id] then
            seen[n.id] = true
            --  The resolved ones waited in their place so as not to move the
            --  rows mid-animation; when a new one comes in everything is
            --  rearranged, and they go.
            remove_done()
            arrive({ id = n.id, app = string.upper(n.app ~= "" and n.app or tr("notice")), title = n.title, detail = n.body,
                     urgent = (n.urgency or 1) >= 2, actions = n.actions, icon = n.icon })
        end
    end
    refill()
    tell_badges(live)
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
    after(1000, function() f.flying = nil; refill() end)
    if f.id then
        after(5400, function()
            if f.done then
                remember(f)
                sys.call("notifications.dismiss", f.id)
            end
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
    remember(f)
    if f.id then sys.call("notifications.dismiss", f.id) end
end)
--  A tap opens it where it lives: its default action, if it brings one. If it
--  brings none, tapping it can do no more than mark it as seen.
local function open_row(k)
    local f = rows[k]
    if f == nil or f.id == nil then return end
    local can_open = false
    for _, a in ipairs(f.actions or {}) do can_open = can_open or a.key == "default" end
    remember(f)
    if can_open then sys.call("notifications.invoke", f.id, "default") else sys.call("notifications.dismiss", f.id) end
end
on("open_notice", open_row)
--  The arriving card's chips: 0 open it, 1 done with it, 2 and 3 its own
--  actions, 9 done with the whole pile. They act on the one in front: the
--  newest of the pile that is not done yet.
local function front_row()
    local pile = math.max(1, math.floor(fact.burst or 1))
    for k = 1, math.min(pile, #rows) do
        if not rows[k].done then return k end
    end
    return 1
end
local function done_with(f)
    if f == nil or f.done then return end
    f.done = true
    remember(f)
    if f.id then sys.call("notifications.dismiss", f.id) end
end
on("notice_act", function(i)
    i = math.floor(i or 0)
    if i == 9 then
        local pile = math.max(1, math.floor(fact.burst or 1))
        for k = 1, math.min(pile, #rows) do done_with(rows[k]) end
        return
    end
    local k = front_row()
    local f = rows[k]
    if f == nil then return end
    if i == 10 or i == 11 then
        if i == 10 then hooks.snooze(f) else hooks.mute(f.app) end
        local next_k = front_row()
        if rows[next_k] and not rows[next_k].done then show_front(rows[next_k]) end
        return
    end
    if i == 0 then
        open_row(k)
    elseif i == 1 then
        done_with(f)
        --  And the next one of the pile comes to the front.
        local next_k = front_row()
        if rows[next_k] and not rows[next_k].done then show_front(rows[next_k]) end
    else
        local a = arriving_actions[i - 1]
        if a and f.id then sys.call("notifications.invoke", f.id, a.key) end
    end
end)
on("tray", function() log("the tray would open at the newest one") end)
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
--  Who says how the desktop is —the monitors, which one has the focus, where
--  the active window is—: Hyprland when she lives on it; else pleamar-wm's own
--  session, which says it in the same words (`pleamar-wm hyprctl …`).
local on_hyprland = (sys.ask("env", "HYPRLAND_INSTANCE_SIGNATURE") or "") ~= ""
local function hyprctl(what, done)
    if on_hyprland then
        run("hyprctl", { what }, done)
    else
        run("pleamar-wm", { "hyprctl", what }, done)
    end
end

--  In the pictures folder the session names —`~/Pictures` in English,
--  `~/Imágenes` in Spanish—, as the videos do.
local PHOTOS = home_dir .. "/Imágenes/Marea"
local FRAME = (sys.ask("env", "XDG_RUNTIME_DIR") or "/tmp") .. "/marea-plm-frame.png"
run("xdg-user-dir", { "PICTURES" }, function(d)
    if d and d ~= "" then PHOTOS = d .. "/Marea" end
    run("mkdir", { "-p", PHOTOS })
end)

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
        hyprctl("activewindow", function(window)
            hyprctl("monitors", function(mons)
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
    hyprctl("monitors", function(mons)
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

--  Only the `swaybg` of HER desktop (her `WAYLAND_DISPLAY`): one painting
--  another session's —Hyprland's, beside a pleamar-wm on another TTY— is not hers.
local OUR_DISPLAY = "WAYLAND_DISPLAY=" .. tostring(sys.ask("env", "WAYLAND_DISPLAY") or "")
run("pgrep", { "-x", "swaybg", "--env", OUR_DISPLAY }, function(_, code)
    if code == 0 then return end                        -- someone is already painting it
    hyprctl("monitors", function(mons)
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
local pointed = nil                  -- pleamar-wm: the monitor the mouse is on, by name

--  In pleamar-wm's session, where she is is also where a window put away
--  flies to: its window manager is told by number, in its own order of the
--  monitors (the one `pleamar-wm hyprctl monitors` gives).
local told_island = nil
local function tell_island()
    if not in_wm then return end
    local name = nil
    for k = 0, 1 do
        if fact["hosts." .. k] == true then name = monitors[k + 1] end
    end
    if name == nil or name == told_island then return end
    told_island = name
    run("pleamar-wm", { "hyprctl", "monitors" }, function(out)
        for n, id in tostring(out or ""):gmatch("Monitor (%S+) %(ID (%d+)%)") do
            if n == name then
                run("pleamar-wm", { "--say", "wm", "fact island.screen " .. id }, nil, { output = false })
            end
        end
    end)
end

local function decide()
    --  In pleamar-wm's session she follows the mouse; elsewhere, the focus.
    local wanted = pointed or focused
    for k = 0, 1 do
        local name = monitors[k + 1]
        local hers
        if fact.following == true then
            hers = name ~= nil and name == wanted
            --  With no focus on any —the empty desktop—, home.
            if wanted == "" then hers = k == fact.home end
        else
            hers = k == fact.home
        end
        fact["hosts." .. k] = hers
    end
    tell_island()
end

--  Her wardrobe's pieces, as the scene names them (`wears.hat`…).
local PIECES = { "hat", "glasses", "mug", "phones" }

local function save_settings()
    settings.home = monitors[(fact.home or 0) + 1] or settings.home
    settings.follow = fact.following == true
    settings.room = fact.taking_room == true
    settings.skin = fact.skin
    settings.language = fact.language
    settings.wallpaper = WALLPAPER
    settings.dnd = fact.dnd == true
    settings.quiet_rec = fact.quiet_rec ~= false
    settings.snooze = math.floor(fact.snooze_k or 1)
    settings.chat_free = fact["chat.free"] == true
    --  What she has on: it stays on through a restart.
    settings.wears = {}
    for _, piece in ipairs(PIECES) do settings.wears[piece] = fact["wears." .. piece] == true end
    local list = {}
    for app in pairs(muted_apps) do list[#list + 1] = app end
    table.sort(list)
    settings.muted = list
    pcall(sys.call, "files.write", "settings.json", settings)
end

-- ── quiet notices: do not disturb, later, muted apps ──────────────
local function say(words)
    fact["drift.result"] = 1
    text["drift.toast"] = words
    emit("say_toast")
end
local function paint_muted()
    local list = {}
    for app in pairs(muted_apps) do list[#list + 1] = app end
    table.sort(list)
    local shown_list = {}
    for k = 1, math.min(#list, 6) do shown_list[k] = { app = list[k] } end
    model.muted = shown_list
    return list
end
fact.dnd = settings.dnd == true
fact.quiet_rec = settings.quiet_rec ~= false
fact.snooze_k = math.clamp(tonumber(settings.snooze) or 1, 0, 2)
for _, app in ipairs(type(settings.muted) == "table" and settings.muted or {}) do muted_apps[tostring(app)] = true end
paint_muted()
on("fact:dnd", function() save_settings() end)
on("fact:quiet_rec", function() save_settings() end)
on("fact:snooze_k", function() save_settings() end)

--  «Later»: the notice leaves, without going to the history, and comes back
--  —as if it had just arrived— once its time is up, if it is still there.
local SNOOZE_MINUTES = { 15, 60, 180 }
local SNOOZE_WORDS = { "Back in 15 minutes", "Back in an hour", "Back in three hours" }
hooks.snooze = function(f)
    f.done = true
    local k = math.floor(fact.snooze_k or 1) + 1
    say(tr(SNOOZE_WORDS[k]))
    if f.id == nil then return end
    local id = f.id
    snoozed[id] = true
    cap_counts()
    after(SNOOZE_MINUTES[k] * 60000, function()
        snoozed[id] = nil
        for _, n in ipairs(live or {}) do
            if n.id == id then
                remove_done()
                arrive(row_of(n))
                return
            end
        end
    end)
end
--  «Mute»: that app's notices, the ones there and the ones to come, go
--  straight to the history.
hooks.mute = function(app)
    if app == nil or app == "" then return end
    muted_apps[app] = true
    for _, r in ipairs(rows) do
        if r.app == app and not r.done then
            r.done = true
            remember(r)
            if r.id then finished[r.id] = true; sys.call("notifications.dismiss", r.id) end
        end
    end
    paint_muted()
    save_settings()
    say(string.format(tr("%s muted"), app))
end
on("unmute", function(i)
    local list = paint_muted()
    local app = list[math.floor(i or 0) + 1]
    if app == nil then return end
    muted_apps[app] = nil
    paint_muted()
    save_settings()
end)
hooks.dnd = function()
    fact.dnd = not (fact.dnd == true)
    say(tr(fact.dnd and "Do not disturb: on" or "Do not disturb: off"))
end

-- ── the wallpapers, and the tide that brings a new one ────────────
--  The ones there are: in the usual folders, not the screenshots. Small
--  copies of them are made with `magick` into the cache as they are seen, a
--  few at a time; and picking one makes two more, the old and the new one at
--  the monitor's size and cut the way `swaybg -m fill` cuts them, so that
--  when the tide has passed and `swaybg` takes over nothing moves.
local WALL_CACHE = home_dir .. "/.cache/marea/walls"
run("mkdir", { "-p", WALL_CACHE }, function() end)
local wall_list, wall_offset, wall_thumbs, wall_making = {}, 0, {}, {}
local wall_busy = false

local function cache_name(path, tag)
    return WALL_CACHE .. "/" .. tag .. "-" .. tostring(path):gsub("[^%w]", "_"):sub(-120) .. ".jpg"
end

local function show_walls()
    local cards = {}
    for k = wall_offset + 1, math.min(wall_offset + 9, #wall_list) do
        local path = wall_list[k]
        local name = tostring(path):match("([^/]+)$") or path
        cards[#cards + 1] = { name = name:gsub("%.%w+$", ""):gsub("[_%-]", " "), thumb = wall_thumbs[path] or "",
                              ready = wall_thumbs[path] ~= nil, current = path == WALLPAPER }
    end
    model.walls = cards
end

--  The small copies of what is on the page, three at a time.
local function make_thumbs()
    local going = 0
    for _ in pairs(wall_making) do going = going + 1 end
    for k = wall_offset + 1, math.min(wall_offset + 9, #wall_list) do
        if going >= 3 then return end
        local path = wall_list[k]
        if wall_thumbs[path] == nil and not wall_making[path] then
            local thumb = cache_name(path, "thumb")
            wall_making[path] = true
            going = going + 1
            run("test", { "-s", thumb }, function(_, exists)
                local function done()
                    wall_making[path] = nil
                    wall_thumbs[path] = thumb
                    show_walls()
                    make_thumbs()
                end
                if exists == 0 then return done() end
                run("magick", { path .. "[0]", "-thumbnail", "320x180^", "-gravity", "center", "-extent", "320x180", "-quality", "85", thumb }, function(_, code)
                    if code ~= 0 then wall_making[path] = nil; log("wallpapers · no small copy of", path); return end
                    done()
                end)
            end)
        end
    end
end

--  The one on now, for her wardrobe: its small copy, made if it is not there.
local function show_wall_now()
    local path = WALLPAPER
    local name = (tostring(path):match("([^/]+)$") or path):gsub("%.%w+$", ""):gsub("[_%-]", " ")
    local thumb = cache_name(path, "thumb")
    model.wallnow = { { name = name, thumb = wall_thumbs[path] or "", ready = wall_thumbs[path] ~= nil } }
    if wall_thumbs[path] ~= nil then return end
    run("test", { "-s", thumb }, function(_, exists)
        local function done()
            wall_thumbs[path] = thumb
            if path == WALLPAPER then model.wallnow = { { name = name, thumb = thumb, ready = true } } end
        end
        if exists == 0 then return done() end
        run("magick", { path .. "[0]", "-thumbnail", "320x180^", "-gravity", "center", "-extent", "320x180", "-quality", "85", thumb }, function(_, code)
            if code == 0 then done() end
        end)
    end)
end
on("customize", show_wall_now)

local WALL_DIRS = { home_dir .. "/Imágenes", home_dir .. "/Pictures", home_dir .. "/Wallpapers", home_dir .. "/Fondos",
                    "/usr/share/wallpapers", "/usr/share/backgrounds" }
on("walls_open", function()
    local args = { "--type", "f", "--max-depth", "3", "--color", "never",
                   "-e", "png", "-e", "jpg", "-e", "jpeg", "-e", "webp",
                   "--exclude", "Capturas", "--exclude", "Screenshots", "--exclude", "Marea", "--exclude", "pokes", ".", }
    for _, d in ipairs(WALL_DIRS) do args[#args + 1] = d end
    run("fd", args, function(out)
        local list, seen_walls = {}, {}
        for line in tostring(out or ""):gmatch("[^\n]+") do
            if not seen_walls[line] then seen_walls[line] = true; list[#list + 1] = line end
        end
        table.sort(list, function(a, b) return (a:match("([^/]+)$") or a):lower() < (b:match("([^/]+)$") or b):lower() end)
        --  The one on now, first.
        for k, path in ipairs(list) do
            if path == WALLPAPER then table.remove(list, k); table.insert(list, 1, path); break end
        end
        wall_list = list
        wall_offset = 0
        show_walls()
        make_thumbs()
    end)
end)
on("walls_scroll", function(w)
    local step = (w or 0) > 0 and -3 or 3
    wall_offset = math.max(0, math.min(wall_offset + step, math.max(#wall_list - 3, 0)))
    wall_offset = wall_offset - wall_offset % 3
    show_walls()
    make_thumbs()
end)

--  The picture the tide carries: cut as `swaybg -m fill` cuts it for the
--  monitor, and squeezed into the 16:9 the scene holds it in (it is drawn back
--  at the monitor's shape). Always the same file: a new version of it, `?n`,
--  takes the place of the last one, and the atlas does not fill up.
local TIDE_PIC = WALL_CACHE .. "/tide.jpg"
local tide_version = 0
local function cover(path, done)
    local w = math.floor(fact["screen.0.width"] or 0)
    local h = math.floor(fact["screen.0.height"] or 0)
    if w < 100 or h < 100 then w, h = 1920, 1080 end
    run("magick", { path .. "[0]", "-resize", w .. "x" .. h .. "^", "-gravity", "center", "-extent", w .. "x" .. h,
        "-resize", "1280x720!", "-quality", "90", TIDE_PIC }, function(_, code)
        tide_version = tide_version + 1
        done(code == 0 and (TIDE_PIC .. "?" .. tide_version) or nil)
    end)
end

local tide_new = nil
on("wall_pick", function(i)
    local path = wall_list[wall_offset + i + 1]
    if path == nil or path == WALLPAPER or wall_busy then return end
    wall_busy = true
    tide_new = path
    cover(path, function(pic)
        if pic == nil then
            log("wallpapers · the picture for the tide could not be made; straight to it")
            emit("tide_done")
            return
        end
        model.tidepics = { { pic = pic } }
        fact["tide.home"] = fact["hosts.1"] == true and 1 or 0
        emit("tide_start")
    end)
end)

--  The water has settled: `swaybg` with the new one, and the old one goes a
--  moment later, when the new one is surely painted underneath.
on("tide_done", function()
    local path = tide_new
    if path == nil then return end
    tide_new = nil
    --  Without `-o`, one swaybg paints every monitor there is.
    run("pgrep", { "-x", "swaybg", "--env", OUR_DISPLAY }, function(old_pids)
        run("swaybg", { "-i", path, "-m", "fill" }, nil, { output = false })
        WALLPAPER = path
        save_settings()
        show_wall_now()
        after(700, function()
            local pids = {}
            for pid in tostring(old_pids or ""):gmatch("%d+") do pids[#pids + 1] = pid end
            if #pids > 0 then run("kill", pids, function() end) end
            emit("tide_away")
            wall_busy = false
            if fact.page == "walls" then show_walls() end
        end)
    end)
end)

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
    fact.taking_room = settings.room == true
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

-- ── the stones: windows put away ───────────────────────────────────
--  pleamar-wm's session lists every window through the `window` service, and
--  says which are put away (minimized): each one gets a slot of its own —the
--  first free— and keeps it until it comes back, so a stone never changes
--  face while the others close ranks. Its face is its application's icon,
--  found by the window's app id (the `.desktop` file's name, or its X11
--  class); without one, the initial.
local stone_slots = {}                -- slot (1..6) → window id
local stone_seq = 0                   -- how many have been put away: the newest sits next to her
local stone_faces = {}                -- slot → the record shown
local function face_of(class)
    local c = (class or ""):lower()
    if c == "" then return "" end
    for _, a in ipairs(apps) do
        local id = (a.id or ""):lower()
        local wm = (a.wmclass or ""):lower()
        local bin = ((a.exec or ""):match("^(%S+)") or ""):match("([^/]+)$") or ""
        if id == c or wm == c or id:sub(-#c - 1) == "." .. c or bin:lower() == c then
            return a.icon or ""
        end
    end
    return ""
end
local function set_stones(list)
    local away = {}
    for _, w in ipairs(list or {}) do
        if w.minimized then away[w.id] = w end
    end
    for k = 1, 6 do
        local id = stone_slots[k]
        if id ~= nil and away[id] == nil then
            stone_slots[k] = nil
            if stone_faces[k] then stone_faces[k].present = false end
        end
    end
    for id, w in pairs(away) do
        local has = false
        for k = 1, 6 do if stone_slots[k] == id then has = true end end
        if not has then
            for k = 1, 6 do
                if stone_slots[k] == nil then
                    stone_slots[k] = id
                    local icon = face_of(w.class)
                    local name = (w.title ~= "" and w.title) or w.class or ""
                    stone_seq = stone_seq + 1
                    stone_faces[k] = { title = name, icon = icon, letter = icon == "" and name:sub(1, 1):upper() or "", present = true, seq = stone_seq }
                    break
                end
            end
        end
    end
    local out = {}
    for k = 1, 6 do
        out[k] = stone_faces[k] or { title = "", icon = "", letter = "", present = false, seq = 0 }
    end
    model.stones = out
end
hooks.restore_all = function()
    for k = 1, 6 do
        local id = stone_slots[k]
        if id ~= nil then pcall(sys.call, "window.restore", id) end
    end
end
on("restore_stone", function(k)
    local id = stone_slots[(k or 0) + 1]
    if id ~= nil then pcall(sys.call, "window.restore", id) end
end)

if not sys.watch("window", function(v)
    focused = (v and v.monitor) or ""
    open_windows = (v and v.list) or {}
    if fact.following == true then decide() end
    --  In pleamar-wm what is put away floats on the shore of its monitor
    --  (tiled, nothing is): her island keeps no stones there.
    set_stones((not in_wm) and v and v.list or {})
end) then log("this compositor does not say where the focus is: «follow me» will not work") end

--  Its number, in pleamar-wm's order of the monitors, to its name.
local function point_to(id)
    --  Only pleamar-wm's session says it; anywhere else it is someone
    --  else's word about monitors that are not hers.
    if not in_wm then return end
    run("pleamar-wm", { "hyprctl", "monitors" }, function(out)
        for n, k in tostring(out or ""):gmatch("Monitor (%S+) %(ID (%d+)%)") do
            if tonumber(k) == id and pointed ~= n then
                pointed = n
                if fact.following == true then decide() end
            end
        end
    end)
end
on("pointer_monitor", point_to)
--  Born into the session, she asks where the mouse is: it is only told
--  when it changes monitor, and until it did she went home —often the
--  other monitor, with the cursor waiting on this one—.
if in_wm then
    after(300, function()
        run("pleamar-wm", { "--say", "wm", "get mon" }, function(out)
            local id = tonumber((tostring(out or ""):match("%-?%d+")))
            if id ~= nil and id >= 0 then point_to(id) end
        end)
    end)
end

on("fact:home", function() decide(); save_settings() end)
on("fact:following", function() decide(); save_settings() end)
on("fact:taking_room", function() save_settings() end)

--  Her look, as it was left last time. If the file holds something that is not
--  one of the three —another version, a hand edit—, the factory one stays.
if settings.skin == "lens" or settings.skin == "liquid" or settings.skin == "classic" then
    fact.skin = settings.skin
end
on("fact:skin", function() save_settings() end)

-- ── her sky: the weather where you are ─────────────────────────────
--  The city is chosen in the calendar (its strip at the top) and kept in her
--  settings; without one, she guesses it from the time zone (Europe/Madrid:
--  Madrid). Open-Meteo is asked every quarter of an hour —no account, no
--  key— and the scene draws it on the time card.
local WX_WORDS = { [0] = "Clear sky", [1] = "Mostly clear", [2] = "Partly cloudy", [3] = "Overcast",
    [45] = "Fog", [48] = "Fog", [51] = "Drizzle", [53] = "Drizzle", [55] = "Drizzle", [56] = "Drizzle", [57] = "Drizzle",
    [61] = "Rain", [63] = "Rain", [65] = "Heavy rain", [66] = "Rain", [67] = "Rain",
    [71] = "Snow", [73] = "Snow", [75] = "Heavy snow", [77] = "Snow",
    [80] = "Showers", [81] = "Showers", [82] = "Heavy showers", [85] = "Snow showers", [86] = "Snow showers",
    [95] = "Thunderstorm", [96] = "Thunderstorm", [99] = "Thunderstorm" }
local WX_RAIN = { [51] = 0.3, [53] = 0.4, [55] = 0.5, [56] = 0.4, [57] = 0.5, [61] = 0.5, [63] = 0.75, [65] = 1,
    [66] = 0.6, [67] = 0.9, [80] = 0.6, [81] = 0.8, [82] = 1, [95] = 0.9, [96] = 1, [99] = 1 }
local WX_SNOW = { [71] = 0.4, [73] = 0.7, [75] = 1, [77] = 0.3, [85] = 0.6, [86] = 1 }
local sky_place = nil
local sky_code = nil
local function sky_words()
    text["wx.summary"] = sky_code ~= nil and tr(WX_WORDS[sky_code] or "Clear sky") or ""
end
local function url_encode(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end
local function sky_fetch()
    if sky_place == nil then return end
    local url = string.format("https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current=temperature_2m,weather_code,cloud_cover&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto", sky_place.lat, sky_place.lon)
    run("curl", { "-s", "--max-time", "10", url }, function(out)
        local ok, v = pcall(json.decode, tostring(out or ""))
        if not ok or type(v) ~= "table" or type(v.current) ~= "table" then return end
        local c = v.current
        sky_code = tonumber(c.weather_code) or 0
        local rain, snow = WX_RAIN[sky_code] or 0, WX_SNOW[sky_code] or 0
        local cloud = (tonumber(c.cloud_cover) or 0) / 100
        if rain > 0 or snow > 0 then cloud = math.max(cloud, 0.8) end
        fact["wx.temp"] = tonumber(c.temperature_2m) or 0
        fact["wx.cloud"] = cloud
        fact["wx.rain"] = rain
        fact["wx.snow"] = snow
        fact["wx.fog"] = (sky_code == 45 or sky_code == 48) and 1 or 0
        fact["wx.storm"] = sky_code >= 95 and 1 or 0
        if type(v.daily) == "table" then
            fact["wx.hi"] = tonumber((v.daily.temperature_2m_max or {})[1]) or fact["wx.temp"]
            fact["wx.lo"] = tonumber((v.daily.temperature_2m_min or {})[1]) or fact["wx.temp"]
        end
        fact["wx.ok"] = true
        sky_words()
    end)
end
local function sky_find(name)
    local q = tostring(name or ""):match("^%s*(.-)%s*$")
    if q == "" then return end
    local lang = fact.locale == "es" and "es" or "en"
    run("curl", { "-s", "--max-time", "10", "https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&language=" .. lang .. "&name=" .. url_encode(q) }, function(out)
        local ok, v = pcall(json.decode, tostring(out or ""))
        local r = ok and type(v) == "table" and type(v.results) == "table" and v.results[1] or nil
        if r == nil or r.latitude == nil then
            log("her sky · no city called", q)
            return
        end
        sky_place = { name = tostring(r.name), lat = tonumber(r.latitude), lon = tonumber(r.longitude) }
        settings.city = sky_place
        text["wx.place"] = sky_place.name
        save_settings()
        log("her sky ·", sky_place.name)
        sky_fetch()
    end)
end
if type(settings.city) == "table" and tonumber(settings.city.lat) ~= nil then
    sky_place = { name = tostring(settings.city.name or ""), lat = tonumber(settings.city.lat), lon = tonumber(settings.city.lon) }
    text["wx.place"] = sky_place.name
    sky_fetch()
else
    run("timedatectl", { "show", "-p", "Timezone", "--value" }, function(out)
        local city = tostring(out or ""):match("([^/%s]+)%s*$")
        if city then sky_find((city:gsub("_", " "))) end
    end)
end
every(15 * 60 * 1000, sky_fetch)
on("submit:city_q", function(value)
    sky_find(value)
    text.city_q = ""
end)
on("fact:locale", sky_words)

--  And what she had on, as it was left: each piece that is not there, off.
if type(settings.wears) == "table" then
    for _, piece in ipairs(PIECES) do
        if settings.wears[piece] == true then fact["wears." .. piece] = true end
    end
end
for _, piece in ipairs(PIECES) do
    on("fact:wears." .. piece, function() save_settings() end)
end

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

-- ── software: updates, and programs to install ─────────────────────
--  What the system has to update is looked at in the background every three
--  hours with `checkupdates` —a database of its own: nothing of the system's
--  is touched— and the AUR's helper (yay or paru), if there is one. Updating
--  is done here and not in a terminal: her field asks for the password, which
--  goes to `sudo -S` by its input and nowhere else —not a file, not an
--  argument, not the environment, which other programs can read—, and the
--  package manager's lines, read in English, say what it is doing as it does
--  it. Afterwards, whether to restart and which settings files are left to
--  review. The catalogue looks for programs the same way.
--  (In a function of its own: the file's main body has run out of the
--  200 local names Luau gives a function.)
local function software()
    local sw = {
        list = {},          -- { name, old, new, aur, size, skip }
        scroll = 0,
        checked = 0,        -- when it was last looked at (os.time)
        news_at = 0,        -- and the news
        looking = false,
        helper = nil,       -- "yay" or "paru": the AUR's
        job = nil,          -- the package manager at work
        pw = nil,           -- kept only while it works, to be able to stop it
        what = nil,         -- { kind = "update" } or { kind = "install", name, aur }
        before = "ready",   -- the state to go back to if the password is not given
        run = nil,          -- what its lines have said so far
        found = {},
        search_gen = 0,
        installed = nil,    -- name -> true, for the finder
        news = {},
        last_upgrade = 0,
        saved = { seen = {}, told = {}, many_day = "" },
    }
    local SW_ROWS = 7
    local SW_C = { LC_ALL = "C" }
    local SW_DB = (sys.ask("env", "XDG_RUNTIME_DIR") or "/tmp") .. "/marea-checkupdates/"

    do
        local ok, saved = pcall(sys.ask, "files.read", "software.json", "json")
        if ok and type(saved) == "table" then
            sw.saved.seen = type(saved.seen) == "table" and saved.seen or {}
            sw.saved.told = type(saved.told) == "table" and saved.told or {}
            sw.saved.many_day = tostring(saved.many_day or "")
        end
    end
    local function sw_save()
        pcall(sys.call, "files.write", "software.json", sw.saved)
    end

    --  The AUR's helper, if there is one: yay, or paru.
    run("yay", { "--version" }, function(_, code)
        if code == 0 then sw.helper = "yay"; return end
        run("paru", { "--version" }, function(_, c2) if c2 == 0 then sw.helper = "paru" end end)
    end)

    local function sw_trim(s)
        return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end
    --  What a terminal would colour: out.
    local function sw_plain(s)
        return (tostring(s or ""):gsub("\27%[[%d;]*[A-Za-z]", ""):gsub("\r", ""))
    end
    local function sw_human(bytes)
        if bytes >= 1024 ^ 3 then return string.format("%.1f GB", bytes / 1024 ^ 3) end
        if bytes >= 1024 ^ 2 then return string.format("%.0f MB", bytes / 1024 ^ 2) end
        if bytes > 0 then return string.format("%.0f KB", math.max(1, bytes / 1024)) end
        return ""
    end
    local function sw_when()
        if sw.checked == 0 then return "" end
        local d = os.time() - sw.checked
        if d < 90 then return tr("checked just now") end
        if d < 3600 then return string.format(tr("checked %d min ago"), math.floor(d / 60)) end
        return string.format(tr("checked at %s"), os.date("%H:%M", sw.checked))
    end

    local function sw_paint()
        local total, aur, ticked, size = #sw.list, 0, 0, 0
        for _, p in ipairs(sw.list) do
            if p.aur then aur += 1 end
            if not p.skip then
                ticked += 1
                size += p.size or 0
            end
        end
        fact["sw.count"] = total
        fact["sw.aur"] = aur
        fact["sw.ticked"] = ticked
        local parts = { string.format(tr("%d to update"), total) }
        if aur > 0 then parts[#parts + 1] = string.format(tr("%d from the AUR"), aur) end
        if size > 0 then parts[#parts + 1] = string.format(tr("%s to download"), sw_human(size)) end
        text["sw.summary"] = table.concat(parts, " · ")
        text["sw.when"] = sw_when()
        sw.scroll = math.clamp(sw.scroll, 0, math.max(0, total - SW_ROWS))
        local rows = {}
        for i = sw.scroll + 1, math.min(total, sw.scroll + SW_ROWS) do
            local p = sw.list[i]
            rows[#rows + 1] = { name = p.name, versions = p.old .. "  →  " .. p.new, aur = p.aur, skip = p.skip }
        end
        model["sw.rows"] = rows
        fact["sw.more"] = math.max(0, total - sw.scroll - SW_ROWS)
        local n = sw.news[1]
        fact["sw.news"] = #sw.news
        text["sw.news.title"] = n and n.title or ""
        text["sw.news.date"] = n and (os.date("%d/%m", n.time) .. (#sw.news > 1 and " · " .. string.format(tr("%d more"), #sw.news - 1) or "")) or ""
    end

    --  A notice, only when it is worth one: news Arch asks you to read before
    --  updating, or a long list waiting (once a day).
    local function sw_tell()
        local changed = false
        for _, n in ipairs(sw.news) do
            if not sw.saved.told[n.link] then
                sw.saved.told[n.link] = true
                changed = true
                run("notify-send", { "-a", "Marea", tr("Arch news before updating"), n.title }, function() end)
            end
        end
        local today = os.date("%Y-%m-%d")
        if #sw.list >= 40 and sw.saved.many_day ~= today then
            sw.saved.many_day = today
            changed = true
            run("notify-send", { "-a", "Marea", string.format(tr("%d updates waiting"), #sw.list),
                                 tr("Software, in her control center, updates them") }, function() end)
        end
        if changed then sw_save() end
    end

    --  How much each repository package weighs to download, from the same
    --  database `checkupdates` refreshed.
    local SW_UNITS = { B = 1, KiB = 1024, MiB = 1024 ^ 2, GiB = 1024 ^ 3 }
    local function sw_sizes()
        local names = {}
        for _, p in ipairs(sw.list) do
            if not p.aur then names[#names + 1] = p.name end
        end
        if #names == 0 then return end
        local args = { "-Si", "--dbpath", SW_DB, "--" }
        for _, n in ipairs(names) do args[#args + 1] = n end
        run("pacman", args, function(out)
            local sizes, name = {}, nil
            for line in tostring(out):gmatch("[^\n]+") do
                local n = line:match("^Name%s*:%s*(%S+)")
                if n then name = n end
                local v, u = line:match("^Download Size%s*:%s*([%d%.]+)%s*(%a+)")
                if v and name then sizes[name] = (tonumber(v) or 0) * (SW_UNITS[u] or 1) end
            end
            for _, p in ipairs(sw.list) do
                if sizes[p.name] then p.size = sizes[p.name] end
            end
            sw_paint()
        end, { env = SW_C })
    end

    local function sw_check()
        if sw.looking or sw.job then return end
        sw.looking = true
        local st = fact["sw.state"]
        if #sw.list > 0 then fact["sw.looking"] = true
        elseif st == "idle" or st == "broken" or st == "ready" then fact["sw.state"] = "scanning" end
        local repos, aur, waiting = nil, {}, 2
        local function finish()
            waiting -= 1
            if waiting > 0 then return end
            sw.looking = false
            fact["sw.looking"] = false
            local now = fact["sw.state"]
            if repos == nil then
                text["sw.error"] = tr("The repositories did not answer: is there a connection?")
                if now == "scanning" then fact["sw.state"] = "broken" end
                sw_paint()
                return
            end
            --  What was left out stays out until it is ticked again.
            local skip = {}
            for _, p in ipairs(sw.list) do
                if p.skip then skip[p.name] = true end
            end
            local list = {}
            for _, p in ipairs(repos) do p.skip = skip[p.name] == true; list[#list + 1] = p end
            for _, p in ipairs(aur) do p.skip = skip[p.name] == true; list[#list + 1] = p end
            sw.list = list
            sw.checked = os.time()
            if now == "scanning" or now == "idle" or now == "broken" then fact["sw.state"] = "ready" end
            sw_paint()
            sw_sizes()
            sw_tell()
        end
        --  0, there are; 2, there are none; anything else, it could not ask.
        run("checkupdates", { "--nocolor" }, function(out, code)
            if code == 0 or code == 2 then
                repos = {}
                for line in tostring(out):gmatch("[^\n]+") do
                    local name, old, new = sw_plain(line):match("^(%S+) (%S+) %-> (%S+)")
                    if name then repos[#repos + 1] = { name = name, old = old, new = new, aur = false } end
                end
            end
            finish()
        end, { env = { LC_ALL = "C", CHECKUPDATES_DB = SW_DB } })
        if sw.helper then
            run(sw.helper, { "-Qua" }, function(out)
                for line in tostring(out):gmatch("[^\n]+") do
                    local name, old, new = sw_plain(line):match("^(%S+) (%S+) %-> (%S+)")
                    if name then aur[#aur + 1] = { name = name, old = old, new = new, aur = true } end
                end
                finish()
            end, { env = SW_C })
        else
            finish()
        end
    end

    --  Arch's news since the last full update, from its feed: a big change says
    --  there what to do before updating.
    local SW_MONTHS = { Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6, Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12 }
    local function sw_unescape(s)
        s = tostring(s or ""):gsub("^%s*<!%[CDATA%[(.-)%]%]>%s*$", "%1")
        return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", "\""):gsub("&#39;", "'"):gsub("&#x27;", "'"):gsub("&amp;", "&"))
    end
    local function sw_read_news()
        sw.news_at = os.time()
        run("grep", { "-a", "-F", "starting full system upgrade", "/var/log/pacman.log" }, function(out)
            local last = 0
            for y, mo, d, h, mi in tostring(out):gmatch("%[(%d+)%-(%d+)%-(%d+)[T ](%d+):(%d+)") do
                last = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) })
            end
            --  Never further back than three months: a system never updated
            --  from here would have every piece of news ever written.
            sw.last_upgrade = math.max(last, os.time() - 90 * 86400)
            run("curl", { "-fsSL", "--max-time", "15", "https://archlinux.org/feeds/news/" }, function(xml, code)
                if code ~= 0 then return end
                local items = {}
                for item in tostring(xml):gmatch("<item>(.-)</item>") do
                    local title = sw_unescape(item:match("<title>(.-)</title>"))
                    local link = sw_trim(item:match("<link>(.-)</link>"))
                    local d, mon, y, h, mi = tostring(item:match("<pubDate>(.-)</pubDate>") or ""):match("(%d+) (%a+) (%d+) (%d+):(%d+)")
                    if d and SW_MONTHS[mon] and link ~= "" then
                        local t = os.time({ year = tonumber(y), month = SW_MONTHS[mon], day = tonumber(d), hour = tonumber(h), min = tonumber(mi) })
                        if t > sw.last_upgrade and not sw.saved.seen[link] then
                            items[#items + 1] = { title = title, link = link, time = t }
                        end
                    end
                end
                table.sort(items, function(a, b) return a.time > b.time end)
                sw.news = items
                sw_paint()
                sw_tell()
            end)
        end)
    end

    -- ── at work ──
    local SW_OPS = { upgrading = true, installing = true, reinstalling = true, downgrading = true, removing = true }
    local function sw_progress(p)
        local r = sw.run
        if p > r.progress then
            r.progress = p
            fact["sw.progress"] = p
        end
    end
    local function sw_stage(words, item)
        text["sw.stage"] = words
        if item then text["sw.item"] = item end
    end
    --  A package's name from its file's: `firefox-131.0-1-x86_64` → `firefox`.
    local function sw_pkgname(file)
        return (file:gsub("%-[^%-]+%-[^%-]+%-[^%-]+$", ""))
    end
    local function sw_line(raw)
        local r = sw.run
        if r == nil then return end
        local line = sw_plain(raw)
        local clean = sw_trim(line)
        if clean == "" or clean:find("^%[sudo%]") then return end
        r.log[#r.log + 1] = clean
        if #r.log > 6 then table.remove(r.log, 1) end
        text["sw.line"] = table.concat(r.log, "\n", math.max(1, #r.log - 3))
        local n = clean:match("^Packages? %((%d+)%)")
        if n then
            r.total = tonumber(n)
            r.dl, r.ops = 0, 0
            return
        end
        if clean:find("^:: Synchronizing package databases") then
            sw_stage(tr("Refreshing the lists"), "")
            sw_progress(0.03)
        elseif clean:find("^:: Retrieving packages") then
            sw_stage(tr("Downloading"), "")
            sw_progress(0.06)
        elseif line:match("^ (%S+) downloading%.%.%.$") and r.total > 0 then
            local file = line:match("^ (%S+) downloading")
            r.dl += 1
            sw_stage(tr("Downloading"), string.format(tr("%s · %d of %d"), sw_pkgname(file), math.min(r.dl, r.total), r.total))
            sw_progress(r.base + (0.06 + 0.34 * math.min(r.dl, r.total) / r.total) * (1 - r.base))
        elseif clean:find("^checking keyring") or clean:find("^checking package integrity") or clean:find("^loading package files")
            or clean:find("^checking for file conflicts") or clean:find("^checking available disk space") then
            sw_stage(tr("Checking what was downloaded"), "")
            sw_progress(r.base + 0.42 * (1 - r.base))
        elseif clean:find("^:: Processing package changes") then
            --  From here on it is changing the system: it is not stopped halfway.
            sw_stage(r.kind == "install" and tr("Installing") or tr("Updating"), "")
            fact["sw.can_stop"] = false
            sw_progress(r.base + 0.45 * (1 - r.base))
        elseif clean:find("^:: Running post%-transaction hooks") then
            sw_stage(tr("Finishing"), "")
            sw_progress(r.base + 0.9 * (1 - r.base))
        elseif clean:match("^==> Making package: (%S+)") then
            --  An AUR package, built here: that can be stopped.
            local name = clean:match("^==> Making package: (%S+)")
            r.builds += 1
            if r.builds == 1 then r.base = r.progress end
            fact["sw.can_stop"] = true
            sw_stage(string.format(tr("Building %s"), name), r.aur_total > 0 and string.format(tr("%d of %d from the AUR"), math.min(r.builds, r.aur_total), r.aur_total) or "")
            if r.aur_total > 0 then sw_progress(r.base + (0.95 - r.base) * (r.builds - 1) / r.aur_total) end
        else
            local verb, name = clean:match("^(%a+) (%S+)%.%.%.$")
            if verb and SW_OPS[verb] and r.total > 0 then
                r.ops += 1
                r.done += 1
                if verb ~= "removing" then r.changed[name] = true end
                sw_stage(r.kind == "install" and tr("Installing") or tr("Updating"), string.format(tr("%s · %d of %d"), name, math.min(r.ops, r.total), r.total))
                sw_progress(r.base + (0.45 + 0.45 * r.ops / r.total) * (1 - r.base))
            end
            local i, of = clean:match("^%((%d+)/(%d+)%) ")
            if i and text["sw.stage"] == tr("Finishing") then
                sw_progress(r.base + (0.9 + 0.1 * tonumber(i) / math.max(tonumber(of), 1)) * (1 - r.base))
            end
            if clean:match("installed as (%S+%.pacnew)") then r.pacnew += 1 end
            if clean:find("^error:") or clean:find("^ ?%-> ") and clean:find("[Ee]rror") then r.error = clean end
            if clean:find("incorrect password") or clean:find("no password was provided") then r.wrongpw = true end
        end
    end

    --  What only starts at boot: the kernel and its modules, the drivers, the
    --  system's own pieces.
    local SW_BOOT = { "^linux", "^nvidia", "^systemd$", "^glibc$", "^mesa$", "ucode$", "^lib32%-nvidia", "^lib32%-mesa$" }
    local function sw_after(r)
        fact["sw.reboot"] = false
        for name in pairs(r.changed) do
            for _, pat in ipairs(SW_BOOT) do
                if name:find(pat) and not name:find("^linux%-api%-headers") then fact["sw.reboot"] = true end
            end
        end
        --  And the kernel running whose modules are gone: certainly.
        run("uname", { "-r" }, function(rel)
            run("test", { "-d", "/usr/lib/modules/" .. sw_trim(rel) }, function(_, code)
                if code ~= 0 then fact["sw.reboot"] = true end
            end)
        end)
    end

    local function sw_done(_, code)
        local r = sw.run
        sw.job = nil
        sw.pw = nil
        fact["sw.can_stop"] = false
        fact["sw.stopping"] = false
        if r == nil then return end
        if code == 0 then
            sw_progress(1)
            fact["sw.state"] = "finished"
            if r.kind == "install" then
                text["sw.result"] = string.format(tr("%s is installed"), r.name)
            elseif r.done > 0 then
                text["sw.result"] = string.format(tr("Updated %d packages"), r.done)
            else
                text["sw.result"] = tr("There was nothing left to update")
            end
            fact["sw.pacnew"] = r.pacnew
            sw_after(r)
            sw.installed = nil
        else
            fact["sw.state"] = "failed"
            text["sw.result"] = r.stopped and tr("Stopped") or (r.wrongpw and tr("The password was not accepted") or tr("It did not finish"))
            local lines = {}
            if r.error then lines[1] = r.error end
            for i = math.max(1, #r.log - 3), #r.log do
                if r.log[i] ~= r.error then lines[#lines + 1] = r.log[i] end
            end
            text["sw.error"] = table.concat(lines, "\n")
        end
        log("software ·", r.kind, "ended with", code)
        --  And a fresh look, whatever happened.
        after(800, sw_check)
    end

    --  The same thing, asked for by hand in a terminal: for what wanted an answer.
    local function sw_by_hand(w)
        local helper = sw.helper
        if w.kind == "install" then
            if w.aur and helper then return { helper, "-S", w.name } end
            return { "sudo", "pacman", "-S", w.name }
        end
        if helper then return { helper, "-Syu" } end
        return { "sudo", "pacman", "-Syu" }
    end

    local function sw_start(pw)
        local w = sw.what
        local helper = sw.helper
        local cmd, args
        local aur_total = 0
        local function helper_args(a)
            a[#a + 1] = "--noconfirm"
            a[#a + 1] = "--sudoloop"
            a[#a + 1] = "--sudoflags"
            a[#a + 1] = "-S"
            if helper == "yay" then
                for _, x in ipairs({ "--answerclean", "None", "--answerdiff", "None", "--answeredit", "None", "--answerupgrade", "None" }) do a[#a + 1] = x end
            else
                a[#a + 1] = "--skipreview"
            end
            return a
        end
        if w.kind == "update" then
            local ignore = {}
            for _, p in ipairs(sw.list) do
                if p.skip then ignore[#ignore + 1] = p.name
                elseif p.aur then aur_total += 1 end
            end
            if helper and aur_total > 0 then
                cmd, args = helper, helper_args({ "-Syu" })
            else
                cmd, args = "sudo", { "-S", "-p", "", "pacman", "-Syu", "--noconfirm" }
            end
            if #ignore > 0 then
                args[#args + 1] = "--ignore"
                args[#args + 1] = table.concat(ignore, ",")
            end
        elseif w.aur then
            cmd, args = helper, helper_args({ "-S", "--needed" })
            args[#args + 1] = w.name
            aur_total = 1
        else
            cmd, args = "sudo", { "-S", "-p", "", "pacman", "-S", "--needed", "--noconfirm", "--", w.name }
        end
        sw.run = { kind = w.kind, name = w.name, total = 0, dl = 0, ops = 0, done = 0, builds = 0, aur_total = aur_total,
                   base = 0, progress = 0, changed = {}, pacnew = 0, log = {}, error = nil, wrongpw = false, stopped = false }
        sw.pw = pw
        fact["sw.progress"] = 0
        fact["sw.reboot"] = false
        fact["sw.pacnew"] = 0
        fact["sw.can_stop"] = true
        fact["sw.stopping"] = false
        text["sw.line"] = ""
        sw_stage(w.kind == "install" and string.format(tr("Installing %s"), w.name) or tr("Starting"), "")
        fact["sw.state"] = "working"
        log("software ·", cmd, table.concat(args, " "))
        local ok, id = pcall(spawn, cmd, args, sw_line, sw_done, { input = pw .. "\n", errors = true, env = SW_C })
        if ok then
            sw.job = id
        else
            sw.run.error = tostring(id)
            sw_done(nil, -1)
        end
    end

    -- ── what the page asks ──
    local function sw_opened()
        if not sw.looking and not sw.job and os.time() - sw.checked > 30 * 60 then sw_check() end
        if os.time() - sw.news_at > 6 * 3600 then sw_read_news() end
        sw_paint()
    end
    on("sw_open", sw_opened)
    on("sw_check", function()
        sw_check()
        sw_read_news()
    end)
    on("sw_toggle", function(i)
        local p = sw.list[sw.scroll + (i or 0) + 1]
        if p == nil or fact["sw.state"] ~= "ready" then return end
        p.skip = not p.skip
        sw_paint()
    end)
    on("sw_all", function()
        local any = false
        for _, p in ipairs(sw.list) do
            if not p.skip then any = true end
        end
        for _, p in ipairs(sw.list) do p.skip = any end
        sw_paint()
    end)
    on("sw_scroll", function(w)
        sw.scroll += (w or 0) > 0 and -2 or 2
        sw_paint()
    end)
    local function sw_ask(words)
        sw.before = fact["sw.state"]
        text["sw.asking"] = words
        text["sw.pw"] = ""
        fact["sw.state"] = "unlocking"
    end
    on("sw_go", function()
        if fact["sw.state"] ~= "ready" or (fact["sw.ticked"] or 0) < 1 then return end
        sw.what = { kind = "update" }
        sw_ask(string.format(tr("Your password, to update %d packages"), fact["sw.ticked"]))
    end)
    on("sw_install", function(i)
        local f = sw.found[(i or 0) + 1]
        if f == nil or f.installed or sw.job then return end
        if f.aur and not sw.helper then
            say(tr("The AUR needs yay or paru"))
            return
        end
        sw.what = { kind = "install", name = f.name, aur = f.aur }
        sw_ask(string.format(tr("Your password, to install %s"), f.name))
    end)
    on("sw_forget", function()
        if fact["sw.state"] ~= "unlocking" then return end
        text["sw.pw"] = ""
        fact["sw.state"] = (sw.before == "unlocking" or sw.before == "working") and "ready" or sw.before
    end)
    --  The password: checked first, on its own (`-k`, whatever sudo remembers),
    --  so a wrong one is said at once and not after the lists are refreshed.
    on("sw_auth", function()
        if fact["sw.state"] ~= "unlocking" or fact["sw.verifying"] then return end
        local pw = text["sw.pw"] or ""
        text["sw.pw"] = ""
        if pw == "" then return end
        fact["sw.verifying"] = true
        run("sudo", { "-S", "-k", "-p", "", "-v" }, function(_, code)
            fact["sw.verifying"] = false
            if fact["sw.state"] ~= "unlocking" then return end
            if code ~= 0 then
                emit("sw_wrong")
                text["sw.asking"] = tr("That was not it (or this user cannot use sudo)")
                return
            end
            sw_start(pw)
        end, { input = pw .. "\n", env = SW_C })
    end)
    --  Stopping: what it is downloading or building. The package manager runs as
    --  root, so it is asked to stop with the same password.
    on("sw_stop", function()
        if sw.job == nil or not fact["sw.can_stop"] then return end
        fact["sw.stopping"] = true
        if sw.run then sw.run.stopped = true end
        kill(sw.job, "int")
        pcall(run, "pkill", { "-INT", "-x", "makepkg" }, function() end)
        if sw.pw then
            run("sudo", { "-S", "-p", "", "pkill", "-INT", "-x", "pacman" }, function() end, { input = sw.pw .. "\n" })
        end
    end)
    on("sw_back", function()
        if fact["sw.state"] ~= "finished" and fact["sw.state"] ~= "failed" then return end
        fact["sw.state"] = (#sw.list > 0 or sw.checked > 0) and "ready" or "scanning"
        sw_paint()
    end)
    on("sw_news", function()
        local n = sw.news[1]
        if n == nil then return end
        run("xdg-open", { n.link }, function() end)
    end)
    on("sw_skip_news", function()
        local n = table.remove(sw.news, 1)
        if n == nil then return end
        sw.saved.seen[n.link] = true
        sw_save()
        sw_paint()
    end)
    local function sw_terminal(words)
        --  It answers when the terminal is closed; at once, and with −1, if
        --  there is no kitty to open.
        run("kitty", { "--hold", table.unpack(words) }, function(_, code)
            if code == -1 then say(tr("No kitty to open a terminal with")) end
        end, { output = false })
    end
    on("sw_terminal", function()
        if sw.what then sw_terminal(sw_by_hand(sw.what)) end
    end)
    on("sw_review", function()
        sw_terminal({ "sudo", "pacdiff" })
    end)
    on("fact:page", function(p)
        if p ~= "software" and fact["sw.state"] == "unlocking" then
            text["sw.pw"] = ""
            fact["sw.state"] = (sw.before == "unlocking" or sw.before == "working") and "ready" or sw.before
        end
    end)

    -- ── the catalogue ──
    --  The repositories first —their database is here, it answers at once—,
    --  then the AUR, which is asked over the network. The closest names first.
    local function sw_parse_search(out, aur)
        local found, last = {}, nil
        for line in tostring(out):gmatch("[^\n]+") do
            line = sw_plain(line)
            local repo, name, version, rest = line:match("^(%S+)/(%S+) (%S+)(.*)$")
            if repo then
                last = { name = name, repo = repo, version = version, about = "", aur = aur,
                         installed = rest:find("%[installed") ~= nil or rest:find("%(Installed") ~= nil }
                found[#found + 1] = last
            elseif last and line:find("^%s+") then
                last.about = sw_trim(line)
            end
        end
        return found
    end
    local function sw_rank(q, list)
        for k, f in ipairs(list) do
            local n = f.name:lower()
            f.rank = (n == q and 0) or (n:sub(1, #q) == q and 1) or (n:find(q, 1, true) and 2) or 3
            f.order = k
        end
        table.sort(list, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            if a.aur ~= b.aur then return not a.aur end
            return a.order < b.order
        end)
        return list
    end
    local function sw_words(q)
        local args = {}
        for w in q:gmatch("%S+") do
            args[#args + 1] = (w:gsub("([%.%^%$%*%+%?%(%)%[%]%{%}%|\\])", "\\%1"))
        end
        return args
    end
    local function sw_show_found(list)
        local rows = {}
        for k = 1, math.min(#list, 6) do
            local f = list[k]
            rows[k] = { name = f.name, repo = f.aur and "AUR" or f.repo, version = f.version, about = f.about, installed = f.installed, aur = f.aur }
        end
        sw.found = list
        model["sw.found"] = rows
    end
    local function sw_search()
        local q = sw_trim(text["sw.query"]):lower()
        fact["sw.typed"] = #q >= 2
        sw.search_gen += 1
        local mine = sw.search_gen
        if #q < 2 then
            fact["sw.searching"] = false
            sw_show_found({})
            return
        end
        fact["sw.searching"] = true
        after(280, function()
            if mine ~= sw.search_gen then return end
            local args = { "-Ss", "--" }
            for _, w in ipairs(sw_words(q)) do args[#args + 1] = w end
            run("pacman", args, function(out)
                if mine ~= sw.search_gen then return end
                local repo = sw_parse_search(out, false)
                sw_show_found(sw_rank(q, repo))
                if not sw.helper then
                    fact["sw.searching"] = false
                    return
                end
                local aur_args = { "-Ssa", "--" }
                for _, w in ipairs(sw_words(q)) do aur_args[#aur_args + 1] = w end
                run(sw.helper, aur_args, function(out2)
                    if mine ~= sw.search_gen then return end
                    local all = sw_parse_search(out2, true)
                    for _, f in ipairs(repo) do all[#all + 1] = f end
                    sw_show_found(sw_rank(q, all))
                    fact["sw.searching"] = false
                end, { env = SW_C })
            end, { env = SW_C })
        end)
    end
    on("text:sw.query", sw_search)

    --  From the finder: her pages, and a program not installed yet that is
    --  named, which opens the catalogue on it.
    hooks.software = function(tab)
        fact.open = true
        fact.page = "software"
        fact["sw.tab"] = tab or "updates"
        sw_opened()
    end
    hooks.packages = function(q, answer)
        local args = { "-Ss", "--" }
        for _, w in ipairs(sw_words(q)) do args[#args + 1] = w end
        run("pacman", args, function(out)
            local rows = {}
            for _, f in ipairs(sw_rank(q, sw_parse_search(out, false))) do
                if #rows < 2 and not f.installed and f.rank < 3 then
                    rows[#rows + 1] = { name = f.name, kind_label = tr("Install") .. " · " .. f.repo, icon = "", glyph = 5, package = f.name }
                end
            end
            answer(rows)
        end, { env = SW_C })
    end
    hooks.install = function(name)
        hooks.software("catalogue")
        text["sw.query"] = name
        sw_search()
    end

    --  In the background: a first look a minute after starting, and then every
    --  three hours; the text of «when» kept fresh while the page is open.
    after(60 * 1000, function()
        sw_check()
        sw_read_news()
    end)
    every(3 * 3600 * 1000, function()
        sw_check()
        sw_read_news()
    end)
    every(60 * 1000, function()
        if fact.page == "software" then text["sw.when"] = sw_when() end
    end)
end
software()

-- ── the chat: talking to her, and her hands on the desktop ─────────
--  Her AI is the Pi SDK in a sandbox (`agent/`), spoken to in JSON lines.
--  It PROPOSES; this decides. Looking (the windows, a picture of one) is done
--  at once; anything that changes something becomes a card in the thread
--  that you allow or not, and only then is it done, with pleamar-wm's agent
--  hands (`pleamar-wm agent …`): her own pointer and keyboard, never yours.
--  What happened is what this says happened, never what the model says.
-- A platform may supply native desktop tools; the compositor path stays here.
local chat_desktop = nil
local function chat()
    local base = sys.ask("env", "XDG_STATE_HOME")
    if base == nil or base == "" then base = home_dir .. "/.local/state" end
    local STATE = base .. "/marea-plm/agent"
    --  How her hands are run: what they say went wrong comes back too, and
    --  the cursor on the desktop is labelled hers.
    local HANDS = { errors = true, env = { PLEAMAR_AGENT_NAME = "Marea" } }
    local DEFAULT_MODEL = "openai-codex/gpt-5.6-luna"
    local function chosen() return type(settings.chat_model) == "string" and settings.chat_model or DEFAULT_MODEL end
    local PROVIDERS = { ["openai-codex"] = "ChatGPT" }
    local models = {}
    fact["chat.free"] = settings.chat_free == true
    on("fact:chat.free", function() save_settings() end)
    local function show_models()
        local out = {}
        for k, name in ipairs(models) do
            out[k] = { name = name:gsub("^[^/]+/", ""), on = name == chosen() and 1 or 0 }
        end
        model["chat.models"] = out
    end
    local ROWS = 24
    local rows = {}          -- the whole thread: { kind, text, detail, state, id }
    local history = {}       -- what is handed back to a fresh worker: { role, text }
    local worker = nil
    local ready = false
    local queue = {}         -- lines for the worker until it is ready
    local live = nil         -- the row of her answer arriving
    --  What is seen of it: the model hands the whole answer over in about a
    --  second, so it is shown at a reading pace instead —letter by letter,
    --  hurrying when far behind—, and keeps going after the model is done.
    local shown_row = nil
    local shown = 0
    local revealing = false
    local asks = {}          -- proposal id -> { row, tool, args }
    local programs = {}      -- pid -> program, from the last list of windows
    local looks = 0
    local idle_timer = nil
    local stopped_by_pill = false
    local usable = false
    local generation = 0
    local worker_serial = 0
    local closing = false
    local close_timer = nil
    local close_worker

    local function letters(s)
        local ok, n = pcall(utf8.len, s)
        return ok and n or #s
    end

    --  The first `n` letters of a text.
    local function first_letters(s, n)
        local ok, b = pcall(utf8.offset, s, n + 1)
        if ok and b then return s:sub(1, b - 1) end
        return s
    end

    local painting = false
    local function paint()
        if painting then return end
        painting = true
        after(16, function()
            painting = false
            local first = math.max(1, #rows - ROWS + 1)
            local out = {}
            for k = first, #rows do
                local r = rows[k]
                local words = r.text
                if k == shown_row then words = first_letters(words, shown) end
                out[#out + 1] = { kind = r.kind, text = words, detail = r.detail or "", state = r.state or 0 }
            end
            model["chat.rows"] = out
            if shown_row and shown_row >= first then
                fact["chat.live"] = shown_row - first
                fact["chat.letters"] = shown
            else
                fact["chat.live"] = -1
            end
        end)
    end
    --  The last letters shown fade in (the scene's `chat.letters`): past the
    --  end it goes on a little, so the last ones finish fading too.
    local TAIL = 12
    local function reveal()
        if revealing then return end
        revealing = true
        local function tick()
            if not shown_row or not rows[shown_row] then
                revealing = false
                return
            end
            local total = letters(rows[shown_row].text)
            local behind = total - shown
            if behind <= -TAIL then
                --  All of it seen, and the model done with it.
                if shown_row ~= live then
                    shown_row = nil
                    revealing = false
                    paint()
                    return
                end
            else
                shown = shown + math.clamp(math.floor(behind / 12), 2, 10)
                paint()
            end
            after(33, tick)
        end
        after(33, tick)
    end
    local function add(kind, text, detail, state)
        rows[#rows + 1] = { kind = kind, text = text or "", detail = detail or "", state = state or 0 }
        paint()
        --  It falls into the thread (after it is painted).
        after(20, function() emit("chat_landed") end)
        return #rows
    end
    local function status(words)
        text["chat.status"] = words or ""
    end

    local function save()
        local keep = {}
        for k = math.max(1, #rows - 60), #rows do
            local r = rows[k]
            if r.kind ~= 4 or r.state ~= 0 then keep[#keep + 1] = { kind = r.kind, text = r.text, detail = r.detail, state = r.state } end
        end
        pcall(sys.call, "files.write", "chat.json", { rows = keep, history = history })
    end
    do
        local ok, saved = pcall(sys.ask, "files.read", "chat.json", "json")
        if ok and type(saved) == "table" then
            rows = type(saved.rows) == "table" and saved.rows or {}
            history = type(saved.history) == "table" and saved.history or {}
        end
    end

    local function send(m)
        local line = json.encode(m) .. "\n"
        if worker and ready then
            if not write(worker, line) then log("chat · the worker did not hear") end
        else
            queue[#queue + 1] = line
        end
    end
    local function forget_login()
        local pending = {}
        for _, line in ipairs(queue) do
            local ok, message = pcall(json.decode, line)
            if not ok or message.type ~= "login" then pending[#pending + 1] = line end
        end
        queue = pending
    end

    -- ── doing what she proposes ──
    local WORDS = {
        desktop_windows = "Looking at your windows",
        desktop_look = "Looking at %s",
        desktop_click = "Click in %s",
        desktop_type = "Type in %s",
        desktop_key = "A key in %s",
        desktop_hotkey = "Keys in %s",
        desktop_scroll = "Scroll in %s",
        desktop_drag = "Drag in %s",
        desktop_focus = "Bring %s forward",
        desktop_to_monitor = "Move %s to another monitor",
        open_app = "Open %s",
    }
    --  A window as desktop_windows names it: «4521», or «4521.3» for one of
    --  a program's several. Anything else is no window.
    local function window_name(v)
        local name = tostring(v or "")
        if name:match("^%d+$") or name:match("^%d+%.%d+$") then return name end
        return "0"
    end
    local function program(args)
        if args.name then return tostring(args.name) end
        return programs[window_name(args.pid)] or ("the window " .. tostring(args.pid or "?"))
    end
    local function said(tool, args)
        return string.format(tr(WORDS[tool] or tool), program(args))
    end
    local function agent_args(tool, a)
        local pid = window_name(a.pid)
        local n = function(v) return tostring(tonumber(v) or 0) end
        if tool == "desktop_windows" then return { "agent", "windows" } end
        if tool == "desktop_click" then return { "agent", "click", pid, n(a.x), n(a.y), tostring(a.button or "left"), tostring(math.floor(tonumber(a.count) or 1)) } end
        if tool == "desktop_type" then return { "agent", "type", pid, tostring(a.text or "") } end
        if tool == "desktop_key" then return { "agent", "key", pid, tostring(a.key or "") } end
        if tool == "desktop_hotkey" then return { "agent", "hotkey", pid, tostring(a.keys or "") } end
        if tool == "desktop_scroll" then return { "agent", "scroll", pid, n(a.x), n(a.y), tostring(a.direction or "down"), tostring(math.floor(tonumber(a.steps) or 3)) } end
        if tool == "desktop_drag" then return { "agent", "drag", pid, n(a.x1), n(a.y1), n(a.x2), n(a.y2) } end
        if tool == "desktop_focus" then return { "agent", "focus", pid } end
        if tool == "desktop_to_monitor" then return { "agent", "send", pid, tostring(math.floor(tonumber(a.monitor) or 0)) } end
        return nil
    end
    --  A program by what the model calls it: its name, its .desktop id, its
    --  command or its class; or what it is («a file manager», «archivos»),
    --  by the usual ones of that kind that are installed.
    local KINDS = {
        { words = { "file", "files", "archivos", "explorador", "explorer", "file manager", "gestor de archivos", "carpetas", "folders" }, apps = { "dolphin", "nautilus", "thunar", "nemo", "pcmanfm", "caja" } },
        { words = { "terminal", "consola", "console", "shell" }, apps = { "kitty", "alacritty", "foot", "konsole", "gnome-terminal", "wezterm", "ghostty" } },
        { words = { "browser", "navegador", "web", "internet" }, apps = { "zen", "firefox", "chromium", "brave", "chrome", "vivaldi", "librewolf" } },
        { words = { "text editor", "editor", "editor de texto", "notepad", "bloc de notas" }, apps = { "gnome-text-editor", "kate", "gedit", "mousepad", "code", "zed" } },
        { words = { "calculator", "calculadora" }, apps = { "calculator", "calculadora", "kcalc", "qalculate" } },
        { words = { "settings", "ajustes", "configuración", "configuracion" }, apps = { "settings", "systemsettings", "ajustes" } },
    }
    local function app_matches(a, want)
        for _, field in ipairs({ a.name, a.id, a.exec, a.wmclass }) do
            if type(field) == "string" and field:lower():find(want, 1, true) then return true end
        end
        return false
    end
    local function find_app(name)
        local want = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if want == "" then return nil end
        for _, a in ipairs(apps) do
            if a.name:lower() == want then return a end
        end
        for _, a in ipairs(apps) do
            if app_matches(a, want) then return a end
        end
        for _, kind in ipairs(KINDS) do
            for _, w in ipairs(kind.words) do
                if want == w or want:find(w, 1, true) then
                    for _, candidate in ipairs(kind.apps) do
                        for _, a in ipairs(apps) do
                            if app_matches(a, candidate) then return a end
                        end
                    end
                end
            end
        end
        return nil
    end

    local function finish_row(row, ok, denied)
        if row and rows[row] then
            rows[row].state = denied and 3 or (ok and 1 or 2)
            paint()
        end
    end
    local function answer(id, ok, words, extra)
        local m = { type = "result", id = id, ok = ok, text = words or "" }
        if extra then for k, v in pairs(extra) do m[k] = v end end
        send(m)
    end
    local function perform(id, tool, args, row)
        local turn = generation
        local function complete(ok, words, extra)
            if turn ~= generation then return end
            if extra and type(extra.programs) == "table" then programs = extra.programs end
            finish_row(row, ok)
            answer(id, ok, words, extra)
        end
        fact["chat.state"] = "acting"
        status(said(tool, args))
        if chat_desktop and chat_desktop(tool, args, complete) then return end
        if tool == "open_app" then
            local found = find_app(tostring(args.name or ""))
            if found then
                local function ordinary()
                    local function launched(error, code)
                        complete(code == 0, code == 0 and ("Launch requested for " .. found.name .. ". Use desktop_windows to check whether its window appeared.") or tostring(error))
                    end
                    if type(sys.call_async) == "function" then
                        local ok, error = pcall(sys.call_async, "apps.launch", { found.exec }, launched)
                        if not ok then complete(false, tostring(error)) end
                    else
                        local ok, error = pcall(sys.call, "apps.launch", found.exec)
                        launched(error, ok and 0 or -1)
                    end
                end
                if chat_desktop then
                    -- Windows does not yet provide compositor-controlled
                    -- startup placement or an independent keyboard.
                    if args.monitor ~= nil then
                        complete(false, "Opening directly on a selected monitor is not available on Windows yet. No program was launched.")
                    else ordinary() end
                    return
                end
                local exec = tostring(found.exec):gsub("%%%a", ""):gsub("%s+$", "")
                local argv = { "agent", "open" }
                local m = tonumber(args.monitor)
                if m then
                    argv[#argv + 1] = "--monitor"
                    argv[#argv + 1] = tostring(math.floor(m))
                end
                argv[#argv + 1] = "--"
                argv[#argv + 1] = exec
                run("pleamar-wm", argv, function(out, code)
                    if turn ~= generation then return end
                    out = tostring(out)
                    local where = code == 0 and tostring(out):match("on monitor (%d+)")
                    if where then
                        complete(true, "Launch requested for " .. found.name .. " on monitor " .. where .. ", without taking the user's keyboard. Use desktop_windows to check whether its window appeared.")
                    elseif code ~= 0 and args.monitor == nil and (code == 127 or out:find("no agent socket here", 1, true)) then
                        -- No WM session: preserve the ordinary launcher, but
                        -- never retry a stopped or failed WM action this way.
                        ordinary()
                    else complete(false, out ~= "" and out or "The window manager did not confirm the launch.") end
                end, HANDS)
                return
            end
            local names = {}
            for _, a in ipairs(apps) do names[#names + 1] = a.name end
            finish_row(row, false)
            answer(id, false, "No installed program matches that. These are the ones there are: " .. table.concat(names, ", "))
            return
        end
        if tool == "desktop_look" then
            looks += 1
            fact["chat.looking"] = true
            local name = "look-" .. (looks % 3) .. ".png"
            run("pleamar-wm", { "agent", "look", window_name(args.pid), STATE .. "/" .. name }, function(out, code)
                if turn ~= generation then return end
                --  The glass stays on her face a moment: the look is seen.
                after(600, function() fact["chat.looking"] = false end)
                if code == 0 then
                    local w, h = tostring(out):match("(%d+)x(%d+)")
                    finish_row(row, true)
                    answer(id, true, string.format("A picture of %s, %sx%s pixels.", program(args), w or "?", h or "?"), { image = { path = "/state/" .. name } })
                else
                    finish_row(row, false)
                    answer(id, false, tostring(out))
                end
            end, HANDS)
            return
        end
        local argv = agent_args(tool, args)
        if not argv then
            finish_row(row, false)
            answer(id, false, "Marea does not know that tool.")
            return
        end
        if tool == "desktop_windows" then
            run("pleamar-wm", argv, function(out, code)
                if turn ~= generation then return end
                if code ~= 0 then
                    finish_row(row, false)
                    answer(id, false, tostring(out))
                    return
                end
                programs = {}
                for line in tostring(out):gmatch("[^\n]+") do
                    local pid, app = line:match("^%s*([%d%.]+)%s+(%S+)%s+«")
                    if pid then
                        --  A dialog is called by what it is, not by the
                        --  program that draws it (a portal's).
                        if line:find("dialog of", 1, true) then app = tr("a dialog") end
                        programs[pid] = app
                    end
                end
                run("pleamar-wm", { "agent", "monitors" }, function(screens)
                    if turn ~= generation then return end
                    finish_row(row, true)
                    answer(id, true, tostring(out) .. "\n\nMonitors:\n" .. tostring(screens))
                end, HANDS)
            end, HANDS)
            return
        end
        run("pleamar-wm", argv, function(out, code)
            if turn ~= generation then return end
            --  Stopped from the monitor's pill: the whole turn ends, not
            --  only this step.
            if code ~= 0 and tostring(out):find("stopped the agent", 1, true) then
                finish_row(row, false)
                answer(id, false, "The user stopped you from the monitor. Stop now.")
                stopped_by_pill = true
                send({ type = "cancel" })
                return
            end
            finish_row(row, code == 0)
            answer(id, code == 0, code == 0 and (out ~= "" and tostring(out) or "Done.") or tostring(out))
        end, HANDS)
    end

    -- ── her memory ──
    --  What she keeps between conversations, in her folder: facts about you
    --  and notes on how to do things (memory.json), and the conversations
    --  that came before (chat-YYYYMMDD-HHMMSS.json, kept on «new»). She keeps
    --  them herself, without a card: each one is shown in the thread as it
    --  is kept, and Settings › What she remembers forgets any of it.
    local MAX_FACTS, MAX_NOTES, MAX_TALKS = 200, 100, 300
    local memory = { facts = {}, notes = {}, next = 1 }
    do
        local ok, saved = pcall(sys.ask, "files.read", "memory.json", "json")
        if ok and type(saved) == "table" then
            memory.facts = type(saved.facts) == "table" and saved.facts or {}
            memory.notes = type(saved.notes) == "table" and saved.notes or {}
            memory.next = tonumber(saved.next) or (#memory.facts + #memory.notes + 1)
        end
    end
    local shelf = {}         -- what Settings lists, in its order: { kind, id }
    local function talks()
        local ok, names = pcall(sys.ask, "files.list")
        local out = {}
        if ok and type(names) == "table" then
            for _, n in ipairs(names) do
                if type(n) == "string" and n:match("^chat%-%d+%-%d+%.json$") then out[#out + 1] = n end
            end
        end
        table.sort(out, function(a, b) return a > b end)
        return out
    end
    local function show_memory()
        local out = {}
        shelf = {}
        for k = #memory.facts, 1, -1 do
            local f = memory.facts[k]
            out[#out + 1] = { kind = 1, text = tostring(f.text or ""), detail = "" }
            shelf[#shelf + 1] = { kind = 1, id = f.id }
        end
        for k = #memory.notes, 1, -1 do
            local n = memory.notes[k]
            out[#out + 1] = { kind = 2, text = tostring(n.title or ""), detail = tostring(n.when or "") }
            shelf[#shelf + 1] = { kind = 2, id = n.id }
        end
        while #out > 24 do table.remove(out); table.remove(shelf) end
        model["mem.items"] = out
        local n = #talks()
        text["mem.talks"] = n == 0 and tr("None kept yet") or string.format(tr("%d kept on this computer"), n)
        text["mem.summary"] = string.format(tr("%d things, %d notes"), #memory.facts, #memory.notes)
        fact["mem.kept"] = n
    end
    local function keep_memory()
        pcall(sys.call, "files.write", "memory.json", memory)
        show_memory()
    end
    --  What goes to her in every conversation (her worker trims it to fit).
    local function for_her()
        local facts, notes = {}, {}
        for _, f in ipairs(memory.facts) do facts[#facts + 1] = { id = f.id, text = f.text } end
        for _, n in ipairs(memory.notes) do notes[#notes + 1] = { title = n.title, when = n.when } end
        return { facts = facts, notes = notes }
    end
    --  The conversation as it is, kept to look back on, when a new one starts.
    local function keep_talk()
        local said = {}
        for _, r in ipairs(rows) do
            if r.kind == 1 or r.kind == 2 then said[#said + 1] = { kind = r.kind, text = r.text } end
        end
        if #said == 0 then return end
        pcall(sys.call, "files.write", "chat-" .. os.date("%Y%m%d-%H%M%S") .. ".json", { at = os.time(), rows = said })
        local all = talks()
        for k = MAX_TALKS + 1, #all do pcall(sys.call, "files.remove", all[k]) end
    end

    local function trimmed(v, n)
        return first_letters((tostring(v or ""):match("^%s*(.-)%s*$")), n)
    end
    local function words_of(q)
        local out = {}
        for w in string.lower(q):gmatch("[%w\128-\255]+") do
            if #w >= 2 then out[#out + 1] = w end
        end
        return out
    end
    local function hits(s, words)
        local low, n = string.lower(s), 0
        for _, w in ipairs(words) do
            if low:find(w, 1, true) then n += 1 end
        end
        return n
    end
    local function note_named(title)
        local want = string.lower(trimmed(title, 80))
        for k, n in ipairs(memory.notes) do
            if string.lower(tostring(n.title)) == want then return k, n end
        end
        for k, n in ipairs(memory.notes) do
            if string.lower(tostring(n.title)):find(want, 1, true) then return k, n end
        end
        return nil
    end
    --  A turn of a conversation, as a search answers it.
    local function quoted(r)
        local who = r.kind == 1 and "User" or "You"
        return who .. ": " .. first_letters((tostring(r.text or ""):gsub("%s+", " ")), 400)
    end

    local function remember(id, tool, args)
        local function row(words) return add(3, words, "", 0) end
        if tool == "memory_save" then
            local t = trimmed(args.text, 300)
            if t == "" then answer(id, false, "Nothing to keep."); return end
            for _, f in ipairs(memory.facts) do
                if string.lower(tostring(f.text)) == string.lower(t) then answer(id, true, "Already kept, as [" .. f.id .. "]."); return end
            end
            local r = row(tr("Remembered: ") .. t)
            local fid = "f" .. memory.next
            memory.next += 1
            memory.facts[#memory.facts + 1] = { id = fid, text = t, at = os.time() }
            while #memory.facts > MAX_FACTS do table.remove(memory.facts, 1) end
            keep_memory()
            finish_row(r, true)
            answer(id, true, "Kept, as [" .. fid .. "].")
        elseif tool == "memory_forget" then
            local want = trimmed(args.id, 16):gsub("[%[%]]", "")
            for k, f in ipairs(memory.facts) do
                if f.id == want then
                    table.remove(memory.facts, k)
                    keep_memory()
                    finish_row(row(tr("Forgot: ") .. tostring(f.text)), true)
                    answer(id, true, "Forgotten.")
                    return
                end
            end
            answer(id, false, "There is no fact [" .. want .. "].")
        elseif tool == "memory_learn" then
            local title, when, how = trimmed(args.title, 80), trimmed(args.when, 200), trimmed(args.how, 3000)
            if title == "" or how == "" then answer(id, false, "A note needs a title and the steps."); return end
            local r = row(tr("Noted how to: ") .. title)
            local k = note_named(title)
            local note = { id = "n" .. memory.next, title = title, when = when, how = how, at = os.time() }
            memory.next += 1
            if k and string.lower(tostring(memory.notes[k].title)) == string.lower(title) then
                table.remove(memory.notes, k)
            end
            memory.notes[#memory.notes + 1] = note
            while #memory.notes > MAX_NOTES do table.remove(memory.notes, 1) end
            keep_memory()
            finish_row(r, true)
            answer(id, true, "Written down.")
        elseif tool == "memory_recall" then
            local words = words_of(tostring(args.query or ""))
            local found = {}
            for k = #memory.facts, 1, -1 do
                local f = memory.facts[k]
                local n = hits(tostring(f.text), words)
                if n > 0 then found[#found + 1] = { n = n, line = "[" .. f.id .. "] " .. tostring(f.text) } end
            end
            table.sort(found, function(a, b) return a.n > b.n end)
            local lines = {}
            for k = 1, math.min(12, #found) do lines[k] = found[k].line end
            finish_row(row(tr("Remembering: ") .. trimmed(args.query, 60)), true)
            answer(id, true, #lines > 0 and table.concat(lines, "\n") or "Nothing kept about that.")
        elseif tool == "memory_read" then
            local _, n = note_named(tostring(args.title or ""))
            finish_row(row(tr("Reading her note: ") .. trimmed(n and n.title or args.title, 60)), n ~= nil)
            if n then
                answer(id, true, tostring(n.title) .. "\nWhen: " .. tostring(n.when) .. "\n\n" .. tostring(n.how))
            else
                answer(id, false, "There is no note with that title.")
            end
        elseif tool == "memory_search" then
            local q = trimmed(args.query, 200)
            local words = words_of(q)
            local r = row(tr("Looking back: ") .. first_letters(q, 60))
            if #words == 0 then finish_row(r, false); answer(id, false, "Say what to look for."); return end
            local need = math.max(1, math.ceil(#words / 2))
            local found = {}
            --  (Not the question just asked: it is what is being looked for.)
            local asking = nil
            for k = #rows, 1, -1 do
                if rows[k].kind == 1 then asking = rows[k]; break end
            end
            local function look(said, when)
                for k, t in ipairs(said) do
                    if #found >= 8 then return end
                    if t ~= asking and (t.kind == 1 or t.kind == 2) and hits(tostring(t.text), words) >= need then
                        local before = said[k - 1]
                        local s = "— " .. when .. "\n"
                        if before and (before.kind == 1 or before.kind == 2) then s = s .. quoted(before) .. "\n" end
                        found[#found + 1] = s .. quoted(t)
                    end
                end
            end
            look(rows, "this conversation")
            for _, name in ipairs(talks()) do
                if #found >= 8 then break end
                local ok, talk = pcall(sys.ask, "files.read", name, "json")
                if ok and type(talk) == "table" and type(talk.rows) == "table" then
                    local y, mo, d = name:match("^chat%-(%d%d%d%d)(%d%d)(%d%d)")
                    look(talk.rows, string.format("%s-%s-%s", y or "?", mo or "?", d or "?"))
                end
            end
            finish_row(r, true)
            answer(id, true, #found > 0 and table.concat(found, "\n\n") or "Nothing said about that, in this conversation or the ones kept.")
        else
            answer(id, false, "Marea does not know that tool.")
        end
    end
    on("mem_forget", function(i)
        local it = shelf[(tonumber(i) or -1) + 1]
        if not it then return end
        local list = it.kind == 1 and memory.facts or memory.notes
        for k, x in ipairs(list) do
            if x.id == it.id then table.remove(list, k); break end
        end
        keep_memory()
    end)
    --  Pressed once, it asks to be sure; again within four seconds, it deletes.
    local sure, sure_timer = false, nil
    on("mem_clear_talks", function()
        if not sure then
            sure = true
            fact["mem.sure"] = true
            if sure_timer then cancel(sure_timer) end
            sure_timer = after(4000, function() sure_timer = nil; sure = false; fact["mem.sure"] = false end)
            return
        end
        if sure_timer then cancel(sure_timer); sure_timer = nil end
        sure = false
        fact["mem.sure"] = false
        for _, name in ipairs(talks()) do pcall(sys.call, "files.remove", name) end
        show_memory()
    end)
    on("fact:section", function(v)
        if v == "memory" then show_memory() end
    end)
    show_memory()

    -- ── the worker ──
    local function stop_idle()
        if idle_timer then cancel(idle_timer); idle_timer = nil end
    end
    local function rest_later()
        stop_idle()
        if not worker or not ready or closing or fact["chat.signing"] == true then return end
        if fact["chat.state"] ~= "idle" and fact["chat.state"] ~= "offline" then return end
        local visible = fact.chatting == true or (fact.open == true and fact.page == "settings" and fact.section == "talk")
        -- The bundled Windows SDK can retire sooner when both chat surfaces
        -- are closed. The next message restores the saved thread.
        local delay = chat_desktop and not visible and 30000 or (3 * 60 * 1000)
        idle_timer = after(delay, function()
            idle_timer = nil
            if worker and (fact["chat.state"] == "idle" or fact["chat.state"] == "offline") and fact["chat.signing"] ~= true then
                close_worker()
            end
        end)
    end
    local function settle(state)
        fact["chat.state"] = state or "idle"
        status("")
        live = nil
        paint()
        if chat_desktop then chat_desktop("done", {}, function() end)
        else run("pleamar-wm", { "agent", "done" }, function() end, HANDS) end
        save()
        rest_later()
    end
    local function on_event(m)
        local kind = m.type
        if kind == "ready" then
            ready = true
            usable = m.usable == true
            text["chat.model"] = m.model or ""
            models = type(m.models) == "table" and m.models or {}
            show_models()
            fact["chat.signed_in"] = m.reason ~= "signed_out"
            local provider = tostring(m.model or chosen()):match("^([^/]+)/") or ""
            text["chat.account"] = string.format(tr("Signed in with %s"), PROVIDERS[provider] or provider)
            if m.usable then
                if fact["chat.state"] == "offline" or fact["chat.state"] == "starting" then
                    fact["chat.state"] = "idle"
                    status("")
                end
            else
                fact["chat.state"] = "offline"
                --  Signed out, the panel itself says so and offers the way in.
                status(m.reason == "signed_out" and "" or tr("That model cannot be used with her account: choose another in Settings"))
            end
            for _, line in ipairs(queue) do write(worker, line) end
            queue = {}
            rest_later()
        elseif kind == "login_url" then
            if fact["chat.signing"] ~= true then return end
            local url = type(m.url) == "string" and m.url or ""
            local code = type(m.code) == "string" and m.code or ""
            if not url:match("^https://auth%.openai%.com/") or (#code > 0 and (#code > 32 or not code:match("^[%w%-]+$"))) then
                send({ type = "login_cancel" })
                fact["chat.signing"] = false
                status(tr("The sign-in address was not recognized."))
                rest_later()
                return
            end
            text["chat.login_hint"] = code ~= "" and (tr("Enter this code in your browser: ") .. code) or tr("Finish signing in, in your browser")
            run("xdg-open", { url }, function() end)
        elseif kind == "login_done" then
            fact["chat.signing"] = false
            text["chat.login_hint"] = ""
            if not m.ok and m.reason ~= "cancelled" then
                status(tr("The sign-in did not finish: ") .. tostring(m.reason or "?"))
            else
                status("")
            end
            rest_later()
        elseif kind == "delta" then
            if live == nil then
                live = add(2, "")
                shown_row, shown = live, 0
                fact["chat.state"] = "thinking"
                status(tr("Thinking…"))
            end
            rows[live].text = rows[live].text .. (m.text or "")
            reveal()
        elseif kind == "propose" then
            live = nil
            local tool, args = tostring(m.tool), (type(m.args) == "table" and m.args or {})
            local looks_only = tool == "desktop_windows" or tool == "desktop_look"
            --  Her memory: kept in sight, never asked.
            if tool:sub(1, 7) == "memory_" then
                remember(m.id, tool, args)
            --  Free hands: no card, except for a step that is the final one
            --  (it sends, buys, deletes…): that one is always asked.
            elseif looks_only or (fact["chat.free"] == true and args.final ~= true) then
                local row = add(3, said(tool, args), looks_only and "" or tostring(args.why or ""), 0)
                perform(m.id, tool, args, row)
            else
                local detail = said(tool, args)
                local body = tostring(args.why or "")
                if tool == "desktop_type" then body = body .. "\n«" .. tostring(args.text or "") .. "»" end
                if tool == "desktop_hotkey" then body = body .. "  (" .. tostring(args.keys or "") .. ")" end
                if tool == "desktop_key" then body = body .. "  (" .. tostring(args.key or "") .. ")" end
                local row = add(4, body, detail, 0)
                asks[m.id] = { row = row, tool = tool, args = args }
                fact["chat.state"] = "awaiting"
                status(tr("Waiting for you"))
                --  Asked while closed: open, so it is seen.
                if fact.chatting ~= true then fact.chatting = true end
            end
        elseif kind == "done" then
            if live then history[#history + 1] = { role = "assistant", text = rows[live].text } end
            settle("idle")
        elseif kind == "cancelled" then
            add(5, stopped_by_pill and tr("You stopped her from the monitor.") or tr("Stopped."))
            stopped_by_pill = false
            settle("idle")
        elseif kind == "failed" then
            if m.reason == "no_model" or m.reason == "not_started" then
                add(5, tr("She could not hear it: she is not signed in (Settings › Talking with her)."))
            else
                add(5, tr("Something went wrong: ") .. tostring(m.reason or "?"))
            end
            settle(usable and "idle" or "offline")
        end
    end
    local function start_worker()
        if worker then return end
        worker_serial += 1
        local serial = worker_serial
        ready = false
        fact["chat.state"] = "starting"
        status(tr("Waking up…"))
        local partial = ""
        local said_why = nil
        local ok, id = pcall(spawn, "agent/sandbox", {}, function(line)
            if serial ~= worker_serial or closing then return end
            if line:sub(1, 1) ~= "{" then
                log("chat · " .. line)
                --  The sandbox's own words when something it needs is not
                --  there (bubblewrap, node, her packages): those are shown.
                if line:sub(1, 7) == "marea: " then said_why = line:sub(8) end
                return
            end
            local good, m = pcall(json.decode, line)
            if good and type(m) == "table" then on_event(m) end
        end, function(_, code)
            if serial ~= worker_serial then return end
            worker_serial += 1
            generation += 1
            if chat_desktop then chat_desktop("cancel", {}, function() end) end
            log("chat · the worker ended", code)
            worker = nil
            ready = false
            stop_idle()
            queue = {}
            fact["chat.signing"] = false
            text["chat.login_hint"] = ""
            if closing then
                closing = false
                if close_timer then cancel(close_timer); close_timer = nil end
                fact["chat.state"] = "idle"
                status("")
                return
            end
            if said_why then
                fact["chat.state"] = "offline"
                status(tr("Her engine cannot start: ") .. said_why)
                if #rows > 0 and rows[#rows].kind == 1 then add(5, tr("Her engine cannot start: ") .. said_why) end
                return
            end
            if fact["chat.state"] ~= "idle" and fact["chat.state"] ~= "offline" then
                add(5, tr("Her engine stopped."))
                settle("idle")
            end
        end, { stdin = "open", errors = true })
        if not ok then
            fact["chat.state"] = "offline"
            status(tr("Her engine could not start: ") .. tostring(id))
            return
        end
        worker = id
        local recent = {}
        for k = math.max(1, #history - 40), #history do recent[#recent + 1] = history[k] end
        local line = json.encode({ type = "start", model = chosen(), locale = fact.locale, history = recent, memory = for_her() }) .. "\n"
        write(worker, line)
    end
    close_worker = function()
        if not worker or closing then return end
        stop_idle()
        closing = true
        ready = false
        queue = {}
        generation += 1
        fact["chat.signing"] = false
        text["chat.login_hint"] = ""
        fact["chat.state"] = "starting"
        status(tr("Closing the previous conversation…"))
        local id, serial = worker, worker_serial
        write(id, json.encode({ type = "shutdown" }) .. "\n")
        close_timer = after(2000, function()
            if serial ~= worker_serial or not closing then return end
            -- kill forgets this owned helper, so its exit callback is not
            -- required to make the next conversation usable again.
            pcall(kill, id)
            worker_serial += 1
            worker, ready, closing, close_timer = nil, false, false, nil
            fact["chat.state"] = "idle"
            status("")
        end)
    end

    -- ── what the panel asks ──
    on("chat_send", function()
        local words = tostring(text["chat.input"] or "")
        if words:match("^%s*$") then return end
        local state = fact["chat.state"]
        if state == "thinking" or state == "acting" or state == "awaiting" or state == "starting" then return end
        text["chat.input"] = ""
        add(1, words)
        history[#history + 1] = { role = "user", text = words }
        stop_idle()
        start_worker()
        fact["chat.state"] = "thinking"
        status(tr("Thinking…"))
        send({ type = "prompt", text = words })
    end)
    local function decide(i, yes)
        local first = math.max(1, #rows - ROWS + 1)
        local row = first + (i or 0)
        for id, a in pairs(asks) do
            if a.row == row then
                asks[id] = nil
                if yes then
                    rows[row].state = 3
                    local tool_row = add(3, said(a.tool, a.args), tostring(a.args.why or ""), 0)
                    perform(id, a.tool, a.args, tool_row)
                else
                    rows[row].state = 2
                    paint()
                    answer(id, false, "", { denied = true })
                    fact["chat.state"] = "thinking"
                end
                return
            end
        end
    end
    on("chat_allow", function(i) decide(i, true) end)
    on("chat_deny", function(i) decide(i, false) end)
    on("chat_stop", function()
        if closing then return end
        generation += 1
        if chat_desktop then chat_desktop("cancel", {}, function() end) end
        for id, a in pairs(asks) do
            asks[id] = nil
            if rows[a.row] then rows[a.row].state = 2 end
        end
        send({ type = "cancel" })
        status(tr("Stopping…"))
        if not chat_desktop then run("pleamar-wm", { "agent", "done" }, function() end, HANDS) end
    end)
    on("chat_new", function()
        generation += 1
        queue = {}
        if chat_desktop then chat_desktop("cancel", {}, function() end) end
        close_worker()
        keep_talk()
        rows, history, asks, live = {}, {}, {}, nil
        shown_row, shown = nil, 0
        if not closing then fact["chat.state"] = "idle"; status("") end
        paint()
        save()
    end)
    on("chat", function() paint() end)
    --  Opening the chat wakes her engine: whether she is signed in is known
    --  before the first word, and the first answer comes sooner.
    on("fact:chatting", function(v)
        if v == true and not worker then start_worker(); rest_later() end
        if chat_desktop then rest_later() end
    end)
    --  Settings › Talking with her: her engine wakes to say how she is.
    on("fact:section", function(v)
        if v == "talk" and not worker then start_worker(); rest_later() end
        if chat_desktop then rest_later() end
    end)
    on("fact:open", function() if chat_desktop then rest_later() end end)
    on("fact:page", function() if chat_desktop then rest_later() end end)
    on("chat_login", function()
        if closing or fact["chat.signing"] == true then return end
        start_worker()
        if not worker then return end
        stop_idle()
        fact["chat.signing"] = true
        text["chat.login_hint"] = tr("Preparing sign-in…")
        send({ type = "login", provider = (chosen():match("^([^/]+)/") or "openai-codex") })
    end)
    on("chat_login_cancel", function()
        forget_login()
        if worker then write(worker, json.encode({ type = "login_cancel" }) .. "\n") end
        fact["chat.signing"] = false
        text["chat.login_hint"] = ""
        rest_later()
    end)
    on("chat_pick", function(i)
        local name = models[(tonumber(i) or -1) + 1]
        if not name or name == chosen() then return end
        settings.chat_model = name
        save_settings()
        text["chat.model"] = name
        show_models()
        --  The next word starts her with it (the thread goes along).
        if worker and fact["chat.state"] == "idle" then close_worker() end
    end)
    paint()
    hooks.chat = function() fact.chatting = true; paint() end
end
chat()
