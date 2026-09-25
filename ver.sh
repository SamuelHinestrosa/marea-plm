#!/bin/sh
# Abre la bolita en la segunda pantalla, matando la que hubiera.
#
# Hay que usar esto —y no solo guardar el fichero— cuando pleamar cambia de
# lenguaje: un proceso vivo se queda con el compilador con el que nació, así que
# una escena que use algo nuevo no le compila y se queda con la última buena,
# diciéndolo en una banda arriba.
P="$HOME/Proyectos/pleamar/target/release/pleamar"
cd "$(dirname "$0")" || exit 1
[ -x "$P" ] || { echo "no está compilado: cargo build --release en ~/Proyectos/pleamar"; exit 1; }
"$P" --comprobar bolita.plm || exit 1
pkill -x pleamar
sleep 0.5
setsid nohup "$P" --scene bolita.plm --screen "${1:-HDMI-A-1}" --no-hud --stall 0 > /tmp/marea-plm.log 2>&1 &
sleep 1.5
echo "abierta. el log en /tmp/marea-plm.log · clic derecho FUERA de ella para cerrarla (encima abre su menú)"
