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
on("conmutar", function(k)
    if k == 3 then
        fact["puesta.3"] = not fact["puesta.3"]
    else
        log("pleamar only reads the network, and knows nothing of bluetooth yet")
    end
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
