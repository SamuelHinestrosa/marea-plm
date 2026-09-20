-- La lógica de la bolita.
--
-- La escena dibuja y reacciona sola: el resalte al pasar por encima, los
-- muelles, los gestos y las reglas los lleva el render, y si esto se queda
-- atascado la pantalla no se entera. Lo único que hay aquí es lo que una regla
-- NO puede hacer: pedirle algo a un servicio.

-- ── los dos niveles ────────────────────────────────────────────────
--  La escena manda a dónde ha ido el dedo, de 0 a 1. No se guarda el valor: lo
--  sigue diciendo el servicio, así que subir el volumen con la tecla del
--  teclado mueve esta misma pista sin que nadie lo cuente dos veces.
on("mover_volumen", function(v) sys.call("audio.volume", v) end)
on("mover_brillo", function(v) sys.call("brightness.level", v) end)
on("mute_salida", function() sys.call("audio.mute") end)
on("mute_micro", function() sys.call("audio.input_mute") end)

-- ── lo que suena ───────────────────────────────────────────────────
on("tocar_pausa", function() sys.call("media.toggle") end)
on("anterior", function() sys.call("media.previous") end)
on("siguiente", function() sys.call("media.next") end)

-- ── las tres tarjetas ──────────────────────────────────────────────
--  Concentración es de Marea, así que se enciende y se apaga aquí. Wi-Fi y
--  Bluetooth no: pleamar sabe LEER la red pero no cambiarla, y de bluetooth no
--  sabe nada todavía. Un interruptor que se mueve sin hacer nada es mentira,
--  así que no se mueve.
--  El interruptor de verdad. Se lee primero y se pone lo contrario, en vez de
--  suponer: si alguien lo ha cambiado por fuera, esto sigue acertando. Y apagar
--  la radio se puede deshacer desde el mismo sitio, que es lo mínimo que se le
--  pide a un interruptor.
on("conmutar", function(k)
    if k == 1 then
        run("nmcli", { "radio", "wifi" }, function(salida)
            local puesta = tostring(salida):match("enabled") ~= nil
            run("nmcli", { "radio", "wifi", puesta and "off" or "on" }, function() end)
        end)
    elseif k == 2 then
        run("bluetoothctl", { "show" }, function(salida)
            local puesta = tostring(salida):match("Powered: yes") ~= nil
            run("bluetoothctl", { "power", puesta and "off" or "on" }, function() end)
        end)
    else
        fact["puesta.3"] = not fact["puesta.3"]
    end
end)

-- ── las páginas ────────────────────────────────────────────────────
--  Pulsar una tarjeta abre su página, y entonces hay que averiguar qué hay.
--  pleamar sabe LEER la red y no listarla ni cambiarla —es su B15—, así que
--  esto se lo pregunta a las herramientas del sistema. Es justo para lo que
--  está la lógica: la escena no manda nada, cuenta lo que le dicen.
local paginas = { "wifi", "bluetooth", "concentracion" }

local function mirar_redes()
    run("nmcli", { "-t", "-f", "IN-USE,SIGNAL,SSID", "dev", "wifi" }, function(salida)
        local mejor, orden = {}, {}
        for linea in tostring(salida):gmatch("[^\n]+") do
            local uso, senal, ssid = linea:match("^(.-):(%d+):(.*)$")
            --  Una misma red sale una vez por antena: se queda la que mejor llega.
            if ssid and ssid ~= "" then
                local s = tonumber(senal) / 100
                if not mejor[ssid] then orden[#orden + 1] = ssid end
                if not mejor[ssid] or s > mejor[ssid].senal then
                    mejor[ssid] = { nombre = ssid, senal = s, puesta = uso == "*" }
                end
            end
        end
        local v = {}
        for _, ssid in ipairs(orden) do v[#v + 1] = mejor[ssid] end
        table.sort(v, function(a, b)
            if a.puesta ~= b.puesta then return a.puesta end
            return a.senal > b.senal
        end)
        while #v > 8 do table.remove(v) end
        model.redes = v
    end)
end

local function mirar_bluetooth()
    run("bluetoothctl", { "devices", "Connected" }, function(conectados)
        local puestos = {}
        for mac in tostring(conectados):gmatch("Device (%S+)") do puestos[mac] = true end
        run("bluetoothctl", { "devices", "Paired" }, function(emparejados)
            local v = {}
            for mac, nombre in tostring(emparejados):gmatch("Device (%S+) ([^\n]+)") do
                --  El `mac` va en el registro aunque la escena no lo declare: es
                --  donde la lógica guarda lo que la escena no necesita saber.
                v[#v + 1] = { nombre = nombre, mac = mac, puesta = puestos[mac] == true }
            end
            table.sort(v, function(a, b) return a.puesta and not b.puesta end)
            while #v > 8 do table.remove(v) end
            model.cacharros = v
        end)
    end)
end

--  Pulsar una red la pone, y pulsar un auricular lo conecta o lo suelta. Solo
--  redes ya guardadas: `connection up` no se inventa una contraseña, así que
--  esto no se mete en la red del vecino. Una nueva pide su clave, y eso es una
--  conversación, no un clic.
on("elegir_red", function(i)
    local r = model.redes[i + 1]
    if r == nil or r.puesta then return end
    run("nmcli", { "connection", "up", "id", r.nombre }, function(_, codigo)
        if codigo ~= 0 then log("that network is not saved; it would need its password", r.nombre) end
        mirar_redes()
    end)
end)

on("elegir_cacharro", function(i)
    local c = model.cacharros[i + 1]
    if c == nil or c.mac == nil then return end
    run("bluetoothctl", { c.puesta and "disconnect" or "connect", c.mac }, function()
        mirar_bluetooth()
    end)
end)

on("mirar", function(k)
    fact.pagina = paginas[k] or "ninguna"
    if k == 1 then mirar_redes() elseif k == 2 then mirar_bluetooth() end
end)

on("ajustes", function() log("settings would open here") end)

-- ── el oleaje ──────────────────────────────────────────────────────
--  Resolver una fila es marcarla leída donde de verdad viva. Aquí solo se
--  apunta: lo que se ve —la fila yéndose, la gota volviendo, la cuenta
--  bajando— ya lo ha hecho la escena, sin esperar a esto.
on("resolver", function(k) log("row marked as read", k) end)
on("tray", function() log("the tray would open at the newest one") end)
on("calendar", function() log("the calendar would open here") end)
on("abrir", function(k) log("page", k) end)
