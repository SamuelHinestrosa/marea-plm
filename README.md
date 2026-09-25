# marea-plm

Marea, escrita con **pleamar** en vez de Quickshell: el mismo escritorio, el mismo
carácter, y a ver cuánto cuesta cada uno.

Esto no vive dentro del repo de pleamar a propósito. Es lo que tendría cualquiera
que use pleamar: unos `.plm`, sus `.luau` al lado, y el programa ya compilado.

```sh
pleamar --scene marea.plm
```

## Lo que se mide

Contra `~/Proyectos/proyecto-marea` corriendo en Quickshell, con el mismo rasero:
CPU y memoria en reposo, con la barra animándose, hilos, y cuánto tarda en pintar
el primer frame. Los números están en `MEDIDAS.md`.

## De diario

Desde el 22 de septiembre de 2026 es la Marea que corre en esta máquina; la de
Quickshell (`~/Proyectos/proyecto-marea`) está parada, no borrada.

```sh
./marea start           # la pone en marcha; el log va a ~/.local/state/marea-plm/marea.log
./marea status
./marea shot_region     # cualquier otra palabra es un suceso que se le dice
./marea stop
```

La arranca Hyprland (`~/.config/hypr/config/marea.lua`), que es también donde
están las teclas: `SUPER+Space` buscar, `SUPER+L` bloquear, `Impr` / `SUPER+C`
foto de región, `MAYÚS+Impr` de pantalla, `CTRL+Impr` de ventana,
`SUPER+MAYÚS+C` grabar. La config de antes está al lado, entera:
`marea.lua.antes-de-marea-plm`. Volver es copiarla encima y `hyprctl reload`.

Dos variables, y no son lo mismo:

- `MAREA_LOCK_WITH_EXIT=1` — el bloqueo se abre también con Esc y solo al
  minuto, y lo dice en pantalla. Está puesta en el autoarranque mientras el
  bloqueo sea nuevo: aquí no hay otro bloqueador que releve a uno que se quede
  echado. Se quita cuando haya confianza.
- `MAREA_TESTING=1` — bloquear, salir, reiniciar y apagar solo se apuntan en
  el log. Para ensayar; nunca en la de diario.

Lo que la otra hacía y esta no: hablarle por voz, el chat con el modelo y la
vista de ventanas (`SUPER+Tab`). Eran del agente, no de la barra.

Para ensayar sin pisar a la de diario: `--screen HDMI-A-1 --margin 390`, y una
copia de la escena con otro nombre si se le va a hablar con `--say`.
