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
--  Solo dos llevan interruptor. Concentración no: es de Marea, se pone desde
--  su página —donde eliges cuánto dura— y la lleva la escena entera, sin pasar
--  por aquí. Wi-Fi y Bluetooth sí, y son del sistema: pleamar sabe LEER la red
--  pero no cambiarla, y de bluetooth no sabe nada todavía. Un interruptor que
--  se mueve sin hacer nada es mentira, así que estos hacen algo.
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
    end
end)

-- ── el sonido: por dónde suena y por dónde escucha ─────────────────
--  pleamar dice qué aparatos hay —`outputs` e `inputs`, cada uno con su id, su
--  nombre y si es el puesto— y acepta `audio.default(id)` para cambiar. Aquí
--  solo se reparten en dos listas y se recorta el nombre, que los de PipeWire
--  vienen con el modelo de la tarjeta entero.
local function corto(nombre)
    --  «TU106 High Definition Audio Controller Estéreo digital (HDMI)» no cabe
    --  en una fila y además lo que distingue está al final.
    local limpio = tostring(nombre):gsub("%s+", " ")
    if #limpio > 42 then limpio = limpio:sub(1, 41) .. "…" end
    return limpio
end

local function aparatos(estado)
    local salidas, micros = {}, {}
    for _, a in ipairs(estado.outputs or {}) do
        salidas[#salidas + 1] = { nombre = corto(a.name), id = a.id, puesta = a.default == true }
    end
    for _, a in ipairs(estado.inputs or {}) do
        micros[#micros + 1] = { nombre = corto(a.name), id = a.id, puesta = a.default == true }
    end
    model.salidas = salidas
    model.micros = micros
end

sys.watch("audio", aparatos)

on("elegir_aparato", function(i)
    --  Las dos listas van juntas: los primeros son salidas y los demás micros,
    --  que es como se ven en la página.
    local salidas = model.salidas or {}
    local elegido = salidas[i + 1]
    if elegido == nil then
        local micros = model.micros or {}
        elegido = micros[i - #salidas + 1]
    end
    if elegido ~= nil then sys.call("audio.default", elegido.id) end
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
on("personalizar", function() log("customize would open here") end)

-- ── el buscador ────────────────────────────────────────────────────
--  «Apps, archivos y carpetas.» Las apps las da el sistema —el servicio `apps`
--  lee los `.desktop`, con su icono y su orden—, y los archivos y carpetas los
--  busca `fd` por debajo de tu casa. La escena no sabe nada de esto: pide una
--  lista y la pinta.
local apps = {}
local casa = sys.ask("env", "HOME") or "."

--  Lo que se escribe cambia en cuanto se teclea, pero `fd` tarda: se apunta la
--  consulta con la que se lanzó y, cuando vuelve, se tira si ya no es la de
--  ahora. Sin esto, escribir deprisa deja la lista de hace tres letras.
local vuelta = 0

local function pinta(q, lista)
    local fuera = {}
    for _, e in ipairs(lista) do
        if #fuera < 7 then fuera[#fuera + 1] = e end
    end
    model.hallazgos = fuera
    fact.escribiendo = q ~= ""
    fact.elegido = 0
    --  Y que la escena sepa que hay lista nueva, para escalonar su entrada.
    emit("pintado")
end

--  «A mano» no es «las primeras por orden alfabético»: son las de siempre.
--  Sin datos de uso, esto es lo más honrado que se puede hacer —una lista
--  corta de las que casi todo el mundo tiene a mano— y el día que haya cuentas
--  de uso, se cambia aquí y ya.
local A_MANO = { "firefox", "zen", "nautilus", "files", "archivos", "kitty", "alacritty", "terminal", "code", "gimp" }

local function prefiere(a, b)
    local function sitio(x)
        local n = x.name:lower()
        for k, v in ipairs(A_MANO) do
            if n:find(v, 1, true) then return k end
        end
        return 99
    end
    local pa, pb = sitio(a), sitio(b)
    if pa ~= pb then return pa < pb end
    return a.name < b.name
end

local function buscar()
    local q = (text.consulta or ""):lower()
    vuelta = vuelta + 1
    local mia = vuelta
    local cabe = {}
    for _, a in ipairs(apps) do
        if q == "" or a.name:lower():find(q, 1, true) then cabe[#cabe + 1] = a end
    end
    table.sort(cabe, prefiere)
    local lista = {}
    for _, a in ipairs(cabe) do
        if #lista < 7 then
            lista[#lista + 1] = { nombre = a.name, clase = "Aplicación", icono = a.icon, exec = a.exec }
        end
    end
    --  Sin consulta, «a mano»: lo que da el sistema de primeras.
    if q == "" then pinta(q, lista); return end
    pinta(q, lista)
    --  Y los archivos y carpetas, que llegan cuando llegan. Con menos de tres
    --  letras no se busca: `fd` con una letra devuelve media casa —miles de
    --  rutas que ni caben ni dicen nada— y lo único que consigue es que la
    --  lista dé un salto por cada tecla.
    if #q < 3 then return end
    run("fd", { "--max-depth", "4", "--max-results", "12", "--hidden",
                "--exclude", ".git", "--exclude", "node_modules", "--exclude", ".cache",
                "--color", "never", q, casa }, function(salida)
        if mia ~= vuelta then return end
        for linea in tostring(salida):gmatch("[^\n]+") do
            if #lista < 7 then
                local carpeta = linea:sub(-1) == "/"
                local limpia = carpeta and linea:sub(1, -2) or linea
                local nombre = limpia:match("([^/]+)$") or limpia
                local donde = limpia:sub(#casa + 2, #limpia - #nombre - 1)
                lista[#lista + 1] = {
                    nombre = nombre,
                    clase = (carpeta and "Carpeta" or "Archivo") .. (donde ~= "" and " · " .. donde or ""),
                    icono = carpeta and "folder" or "text-x-generic",
                }
            end
        end
        if mia == vuelta then pinta(q, lista) end
    end)
end

if not sys.watch("apps", function(lista) apps = lista; buscar() end) then
    log("este sistema no sabe qué aplicaciones tiene")
end
on("text:consulta", buscar)
on("fact:busca", function(abierto) if abierto then buscar() end end)

--  Abrir: una app se lanza; un archivo o una carpeta, a quien sepa abrirlos.
on("abrir_hallazgo", function(i)
    local h = model.hallazgos[i + 1]
    if h == nil then return end
    if h.exec then
        log("abriendo", h.nombre)
        sys.call("apps.launch", h.exec)
    else
        log("abriendo", h.nombre, "(archivo)")
    end
    text.consulta = ""
end)

-- ── su menú ────────────────────────────────────────────────────────
--  Lo que el botón derecho ofrece. Las dos filas de la casa las pone la
--  escena; esto trae lo de los complementos, que es lo único que cambia de una
--  máquina a otra. Aquí no hay catálogo, así que van dichas: lo que importa es
--  que la frontera está escrita y que agrupar es cosa de aquí.
--
--  `primera` dice si abre grupo, y entonces la fila se lleva 16 px más para el
--  nombre de quien la trae. Es una cuenta y no una coordenada: dónde cae cada
--  fila lo reparte la escena, que para eso tiene una columna.
local del_menu = {
    { id = "deriva.prestar",  grupo = "Deriva", titulo = "Prestar algo" },
    { id = "deriva.soltar",   grupo = "Deriva", titulo = "Soltar lo prestado" },
    { id = "oleaje.historial", grupo = "Oleaje", titulo = "Historial" },
}

local function poner_el_menu()
    local grupo, grupos = nil, 0
    for _, e in ipairs(del_menu) do
        e.primera = e.grupo ~= grupo
        if e.primera then
            grupo = e.grupo
            grupos = grupos + 1
        end
    end
    fact.grupos = grupos
    model.entradas = del_menu
end
poner_el_menu()

on("del_menu", function(i)
    local e = del_menu[i + 1]
    log("a plugin entry from her menu", e ~= nil and e.id or i)
end)

-- ── el oleaje, en modo demostración ────────────────────────────────
--  pleamar sabe recibir las notificaciones del escritorio de verdad: se pide
--  el permiso `notifications` y `sys.watch("notifications", …)` da la lista
--  viva, con su aplicación, su título, su cuerpo y su urgencia. Aquí ese
--  permiso NO está dado a propósito: quien ocupa ese sitio en esta máquina es
--  Marea, y el primero que lo pide se lo queda. Un prototipo no le quita los
--  avisos a la barra de verdad.
--
--  Así que esto es lo otro: una tanda inventada que entra sola, para poder ver
--  el oleaje entero —la llegada, la ráfaga, la bandeja y el urgente— sin
--  esperar a que a alguien le escriban. Lo que se manda por la frontera es
--  exactamente lo mismo que mandaría el servicio: `cat`, `who`, `line` y el
--  suceso. El día que se dé el permiso, lo único que cambia es de dónde salen.
--
--  Se para con `pleamar --decir bolita "fact demo false"`.

--  1 mensajes · 2 trabajo · 3 calendario · 4 sistema. Es lo que decide de qué
--  color es la gota, así que un aviso sin categoría conocida es «sistema».
local DE = { TELEGRAM = 1, CORREO = 2, CALENDARIO = 3, SISTEMA = 4 }

local tanda = {
    { app = "TELEGRAM",   que = "Ana Ruiz",             mas = "¿Comemos hoy? Tengo mesa a las dos", en = 1400 },
    { app = "CORREO",     que = "Factura de septiembre", mas = "vence el 30",                        en = 5200 },
    --  Dos seguidos: la ráfaga se apila y sale «+N más» en vez de tres saltos.
    { app = "TELEGRAM",   que = "Grupo de la obra",     mas = "6 mensajes sin leer",                 en = 8600 },
    { app = "TELEGRAM",   que = "Marcos",               mas = "te llamo en cinco",                   en = 9100 },
    { app = "CALENDARIO", que = "Revisión de diseño",   mas = "en 10 minutos · sala grande",         en = 13000 },
    --  Y uno urgente, que no se agrupa: fila propia, arriba y en ámbar.
    { app = "SISTEMA",    que = "Batería al 8 %",       mas = "quedan unos 12 minutos", urgente = true, en = 18000 },
}
--  Lo que va diciendo cada fila de cuándo llegó. No hay reloj aquí: el sitio en
--  la lista ya cuenta la historia, y es lo que hace el contrato.
local EDAD = { "ahora", "2 min", "9 min", "26 min", "1 h" }

local filas = {}

local function pintar()
    for k = 1, 5 do
        local f = filas[k]
        fact["viva." .. k] = f ~= nil
        if f ~= nil then
            text["fila." .. k .. ".app"] = f.app
            text["fila." .. k .. ".que"] = f.que
            text["fila." .. k .. ".mas"] = f.mas
            text["fila." .. k .. ".hora"] = EDAD[k]
            fact["catfila." .. k] = f.cat
            fact["urg." .. k] = f.urgente == true
        end
    end
end

--  Llega uno: primero se dice QUÉ es —la escena lo necesita antes del suceso,
--  porque la tarjeta que vuela ya lleva su nombre escrito— y luego que ha
--  llegado. Un urgente, además, se anuncia como tal.
local function llega(n)
    n.cat = DE[n.app] or 4
    table.insert(filas, 1, n)
    while #filas > 5 do table.remove(filas) end
    pintar()
    fact.cat = n.cat
    text.who = n.que
    text.line = n.mas
    emit("notice")
    if n.urgente then emit("urge") end
end

--  La tanda entera, y otra vez pasados 22 s. Antes de repetir se vacía la
--  bandeja y las cuentas de las gotas: si no, la segunda vuelta empieza con la
--  primera todavía encima y ya no se ve nada.
local function vaciar()
    filas = {}
    pintar()
    for k = 1, 4 do
        fact["n." .. k] = 0
        fact["last." .. k] = 0
    end
end

--  Una tanda y para. En bucle era un pesado: lo que se quiere es verlo una
--  vez y poder repetirlo cuando toque, no que te llueva encima mientras
--  trabajas. Se repite con `pleamar --decir bolita "emit otra_tanda"`, que
--  vacía lo que hubiera y vuelve a empezar.
local function tandaEntera()
    vaciar()
    for _, n in ipairs(tanda) do
        after(n.en, function() if fact.demo ~= false then llega(n) end end)
    end
end

on("otra_tanda", tandaEntera)

log("demo · los avisos son inventados: pleamar cede el sitio a quien ya lo tenga")
log("demo · otra tanda: pleamar --decir bolita \"emit otra_tanda\"")
after(600, tandaEntera)

-- ── el oleaje ──────────────────────────────────────────────────────
--  Resolver una fila es marcarla leída donde de verdad viva. Aquí solo se
--  apunta: lo que se ve —la fila yéndose, la gota volviendo, la cuenta
--  bajando— ya lo ha hecho la escena, sin esperar a esto.
on("resolver", function(k) log("row marked as read", k) end)
--  Lo descartado no vuelve: ni gota, ni deshacer, ni aviso a quien lo mandó
--  hasta que se acabe el plazo. Aquí solo se apunta.
on("descartar", function(k) log("row discarded", k) end)
on("abrir_aviso", function(k) log("would open the notice where it lives", k) end)
on("tray", function() log("the tray would open at the newest one") end)
on("calendar", function() log("the calendar would open here") end)
on("abrir", function(k) log("page", k) end)

-- ── la sesión ──────────────────────────────────────────────────────
--  Lo único de toda la escena que no se deshace, así que lleva dos cinturones.
--  El primero es el de la lámina y vive en la escena: cerrar, reiniciar y
--  apagar abren una pregunta aparte, y la respuesta necesita una pulsación
--  nueva. El segundo es de aquí: con `MAREA_EN_PRUEBAS` puesta se apunta lo
--  que se haría y no se hace, que es lo que deja ensayar el gesto entero sin
--  quedarse sin máquina a mitad de la prueba.
local ordenes = { "session.lock", "session.suspend", "session.logout", "session.reboot", "session.poweroff" }
local pruebas = sys.ask("env", "MAREA_EN_PRUEBAS")

on("sesion", function(k)
    local orden = ordenes[k]
    if orden == nil then
        log("session: there is no action number", k)
        return
    end
    if pruebas ~= nil and pruebas ~= "" then
        log("session · testing: it would call", orden)
        return
    end
    --  Una vez y solo una: «tras confirmar, enviar la petición una sola vez».
    log("session ·", orden)
    sys.call(orden)
end)
