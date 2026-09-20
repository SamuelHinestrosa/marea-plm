-- Lo único que hace la lógica: contar los avisos, despertarla, y repartir los
-- escritorios que cuenta el compositor. Nada de esto pinta: lo que se ve lo
-- mueve el render, y sigue moviéndose aunque esto se quede pensando.

local cuantos = 0

local function poner(n)
    cuantos = n
    fact.pending = n
    text.pending_label = n > 9 and "9+" or tostring(n)
end

poner(3)
-- Que se la vea entrar: nace fuera de la pantalla y baja sola con su muelle.
after(120, function() fact.awake = true end)
every(6000, function() poner((cuantos % 12) + 1) end)

-- ── los escritorios ──────────────────────────────────────────────
-- `sys.watch` dice si este sistema los tiene. Si no, la tarjeta sale sin ellos.
sys.watch("workspaces", function(w)
    local hay, con = {}, {}
    for _, d in ipairs(w.list) do
        hay[d.id] = true
        con[d.id] = d.windows > 0
    end
    for i = 1, 9 do
        fact["ws." .. i .. ".there"] = hay[i] or i == w.active
        fact["ws." .. i .. ".busy"] = con[i] or false
    end
    fact["ws.active"] = w.active
end)

-- Pulsar uno lleva allí.
on("go", function(i) sys.call("workspaces.focus", i) end)
