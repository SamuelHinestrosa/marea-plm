# Marea, gesto a gesto

Lo que el contrato (`proyecto-marea/docs/ANIMACIONES.md`) pide, y lo que esta
versión hace. Nada se da por bueno a ojo: cada tiempo se mide con
`pleamar --registrar`, que apunta lo que vale cada propiedad **en cada frame**.

```sh
pleamar --escena bolita.plm --segundos 38 --sin-hud --registrar lid,body.y,tilt > reposo.tsv
```

## Reposo vivo

| Lo que pide el contrato | Cómo está | Medido |
| --- | --- | --- |
| Parpadeo breve cada 5,2 s | `blink lid every 5.2s for 120ms` | 5,20 s entre uno y otro, exacto |
| Mirada que sigue al ratón | `look gaze.x, gaze.y … reach 6, 3.5 within 260` | responde con la lógica parada |
| Respiración cada 12–24 s | `every 12s..24s { play breathe }` | a los 17,0 s y a los 36,1 s |
| Dura 1,3 s | gesto de cinco fotogramas: 220 + 320 + 180 + 200 + 380 ms | 1,30 s |
| Los ojos miran **antes** de subir | primer fotograma, `look.y: -1.2` | sí |
| El cuerpo sube **2 px** | `body.y: -2` | −2,00 px exactos |
| Parpadea del todo estando arriba | fotogramas 3 y 4, `lid: 0` → `lid: 1` | el cuerpo arriba 733 ms |
| Se asienta con asimetría mínima | `380ms out_back { tilt: 0.012 }` | 0,0132 rad de pico |
| **Regreso exacto a neutral** | son `pose`: lo que un gesto no nombra vuelve a su base | vuelve a 0 |
| El parpadeo se suspende durante un gesto | un gesto manda sobre lo ambiental, y le para el reloj | 5,20 + 1,30 alrededor de la respiración |

## Modo oculto: el borde y el menisco

| Lo que pide el contrato | Cómo está | Medido |
| --- | --- | --- |
| Hundida, asoma algo menos de la mitad | el centro queda 3 px por encima del borde | asoma 20 de 46 |
| El viaje dura 620 ms | `prop out = 0 ~620ms` | 619 ms al salir, 613 al volver |
| Vuelve a hundirse tras 2,6 s de gracia | `on away cuerpo_zona for 2.6s { needed = false }` | el disparador es el propio contrato, escrito tal cual |
| La unión no es una traslación sino **tensión superficial** | el agua del borde y la bolita son **una sola silueta**, fundidas con `blend` | ver `evidencia/menisco-a-mitad.png` |
| Cuello **cóncavo**, ancho al tocarse, afinándose hasta un hilo | sale de fundir las dos formas: nadie dibuja el cuello | ver `evidencia/menisco-secuencia.png` |
| Rompe al separarse más que su propio tamaño | la fusión se apaga sola: `30 * 4 * out * (1 - out)` | rompe cerca del final |
| El fillet es mínimo en reposo y máximo a mitad | esa campana, exactamente | sí |

**Lo que esto ahorra.** En QtQuick el menisco es `prototype/Meniscus.qml`: 162
líneas que calculan dos curvas Bézier, con sus puntos de control, el ángulo de
enganche a la bolita y el corte con la superficie, más los comentarios que
explican por qué cada tiro va hacia dentro y no hacia fuera. Aquí son dos formas
en el mismo `body` y un número que sube y baja. El cuello no se dibuja: aparece.

## Abrir y cerrar

| Lo que pide el contrato | Cómo está | Medido |
| --- | --- | --- |
| 290 ms al abrir | `card: 1 ~290ms` | 283 ms |
| El contenido entra detrás | `content: 1 ~200ms after 90ms` | empieza 102 ms después, dura 198 |
| Al cerrar, **primero el contenido**: 50 ms | `content: 0 ~50ms` | se va en 50 ms, tres frames |
| **Y luego** la geometría: 210 ms | `card: 0 ~210ms after 50ms` | arranca cuando el contenido ya no está, y tarda 210 |
| Se aparta para presentar la tarjeta | `let cx = 120 + (1 - card) * 240` | viaja con la propia apertura |
| El clic abre; el roce **no** | `on press cuerpo_zona { toggle open }` | acercarse no abre nada |
| Se cierra al salir, con 320 ms de gracia | `on away conjunto for 320ms { open = false }` | el conjunto incluye bolita, puente y tarjeta |

El orden inverso entre abrir y cerrar se escribe con dos reglas y se lee como el
contrato:

```
on change open while open      { card: 1 ~290ms;  content: 1 ~200ms after 90ms }
on change open while not open  { content: 0 ~50ms; card: 0 ~210ms after 50ms }
```

**Dos cosas que se vieron al mirarla, y que no se ven en los números:** la
tarjeta se salía por abajo de la superficie, y el bloque de lo que suena se
montaba encima de los deslizadores. La segunda era maqueta mía; la primera es que
**una superficie no crece con lo que lleva dentro, ni siquiera para una sombra**:
la de la tarjeta necesita 62 px por debajo (18 de desplazamiento y 44 de
difusión), y sin ellos se corta en seco contra el borde.

Que la superficie se declare a mano no es cosa de pleamar: en Marea también se
declara, y su techo subió a mano tres veces —520, 640, 880— con una nota en
`core/Theme.qml` diciendo que el síntoma no señalaba allí en absoluto. Lo que sí
era de pleamar es que no dijera nada. Ahora lo dice:

```
render · a shadow is cut: it needs 30 px below more than this 760 x 520 surface has.
         The shape fits; its shadow does not
```

Una vez, cuando la escena se queda quieta —no al primer píxel, que en una tarjeta
que se abre sería el número equivocado— y solo si la forma flota despegada de ese
borde: una barra pegada arriba tiene la sombra cortada por arriba porque quiere.
Es la segunda vez que construir Marea con pleamar acaba en pleamar y no en la
maqueta.

**Esta pieza no necesitó tocar el lenguaje.** Con `on change` y `while`, los
retrasos de las transiciones y los muelles dichos en tiempo, la coreografía salió
tal cual está escrita en el contrato. La tarjeta, en `evidencia/centro-de-control.png`,
al lado de su lámina (`design/concepts/2026-08-31-centro-y-apps`).

## El nivel en la cara

> «Los dos ojos se tumban y se juntan en una sola barra centrada, del mismo
> grosor que tienen ellos de ancho: es el mismo pill girado 90°. Esa barra es la
> pista de una barra de volumen normal, que se llena de menta de izquierda a
> derecha; el porcentaje aparece en la frente. 180 ms de entrada, se mantiene
> 1,1 s tras el último cambio y devuelve la cara. Se dispara con el deslizador
> del panel **y con la tecla de volumen del teclado**. En gris cuando está
> silenciado.»

![La cara convirtiéndose en barra](evidencia/nivel-secuencia.png)

De izquierda a derecha, la misma cara con `meter` a 0, ¼, ½, ¾ y 1.

| Lo que dice el contrato | Lo medido |
| --- | --- |
| El mismo pill girado 90° | El ojo mide 5 × 13; tumbado, 13 × 5. No nace ninguna forma nueva |
| Una sola barra centrada | Los centros van de ±6,5 a ±2,5. El vuelo total es **18 de pie y 18 tumbados**: los ojos solo se ensanchan y se deslizan, nada pega un salto |
| Sin junta visible | Solapan 8, y las dos puntas redondas suman 5: la unión queda dentro |
| 180 ms de entrada | Muelle `~180ms`. Medido: 0 → 1 en 190 ms, con un 3 % de pasada que no se ve |
| Se mantiene 1,1 s tras el **último** cambio | Medido con tres cambios seguidos del volumen real: vuelve 1 102 ms después del tercero, no del primero |
| Se llena de menta de izquierda a derecha | Sí, y es **la misma pista pintada otra vez y recortada por la izquierda**: la menta tiene la forma exacta de la barra, con sus puntas, sin una geometría más |
| El porcentaje en la frente | `number(volume * 100, 0, " %")`, que sube 3 px mientras aparece |
| En gris cuando está silenciado | `mix(mint, #6b7280, muted)` |
| El deslizador y la tecla se ven igual | Ni una línea de lógica: `service audio { volume: number; muted: bool }`. Comprobado moviendo el volumen del sistema con `wpctl`, que es lo mismo que hace la tecla |

![Silenciado](evidencia/nivel-silenciado.png)

**Lo que aquí gana pleamar, y en QML no cabía.** Los ojos no se solapan: **se
funden**. Antes de tocarse les sale un puente entre medias, igual que a la bolita
con el borde, porque son un `body` y no dos cajas. Es una campana como la del
menisco —se tocan justo a la mitad del viaje, ahí está lo gordo, y a los extremos
no queda nada—, así que de pie son dos ojos limpios y tumbados una barra sin
cintura. En QML, dos `Rectangle` que se acercan se solapan y ya: para esto haría
falta dibujar una tercera forma que nadie mira.

**Lo que cuesta.** El episodio entero —subir, aguantar 1,1 s y volver— son 92
frames, y **683 ms de esos 1,1 s el render está dormido**: en cuanto el muelle se
posa deja de pintar, y la regla que espera no sondea nada, se apunta una cita.

## La cuenta, la cámara y el disco rojo

> **Grabación.** «La cuenta atrás ocurre DENTRO de la bolita: sus ojos se
> convierten en el número, con un rebote decreciente por segundo… con el ojo
> izquierdo convertido en disco rojo y siguiendo al puntero. El disco rojo se
> enciende cuando el grabador está corriendo, no al pulsar: es una afirmación
> sobre el presente.»
>
> **Fotografía.** «…vuelve con los ojos convertidos en cámara.»

![La cuenta atrás](evidencia/cuenta-atras.png)

Y la cámara, con su obturador, y el disco antes y después de que el grabador
arranque de verdad:

![La cámara y el disco](evidencia/camara-y-disco.png)

### Cómo está escrito

Todo esto es **una sola cadena**: el ojo de siempre, y cada estado tirando de
él. No hay formas que se intercambian ni una animación por estado peleando por
los mismos ojos; hay cinco muelles que siguen a un hecho con tipo
(`fact face: eye | count | camera | rec`), y la geometría se dobla hasta ser
otra cosa. Por eso cualquier estado puede interrumpir a otro a mitad de camino y
lo único que se ve es que la forma cambia de idea.

| Lo que dice el contrato | Lo medido |
| --- | --- |
| Tres números, uno por segundo | 1 000 ms, 1 000 ms, 1 000 ms |
| Rebote **decreciente** por segundo | Escala 1,25 · 1,17 · 1,08. Es un empujón a la velocidad del muelle (`impulse pop left * 2.5`), no una animación hasta un tamaño: cada golpe sale de donde estaba el anterior |
| «El último aterriza justo cuando arranca el grabador» | Del último número al disco: **17 ms**, un frame |
| El cero no se enseña | El número es `max(left, 1)`: el cero no es una cuenta, es el momento de empezar |
| El disco se enciende con el grabador, no al pulsar | Dos cosas separadas: `dot` es el disco (sigue a `face == rec`) y `red` es el rojo (sigue a `taping`). Primero el ojo se vuelve disco oscuro; el rojo llega cuando el grabador está |
| El derecho sigue siendo un ojo | Sí, y sigue al puntero: es lo que la mantiene viva mientras dura |
| Los ojos convertidos en cámara | El izquierdo se abre en el objetivo (13 de la lámina, 5 con el obturador) y el derecho se estira hasta el cuerpo (30 × 21, esquina 6). El visor es una marca aparte porque ya no quedan ojos |

### Las dos cosas que aquí son de pleamar y no de QML

**El número sale de los ojos.** Los dos se van al centro, se funden en una gota
—se funden de verdad, que para eso son un cuerpo— y la gota **se abre como un
diafragma**: crece mientras se le come el centro, se queda en un anillo, y
dentro estaba el número.

![El diafragma](evidencia/diafragma.png)

**El agujero es una forma más.** Ni el diafragma ni el cuerpo de la cámara se
dibujan con un borde: se les come el centro con una forma del color de la
bolita. Aquí todo son distancias, así que un hueco no es un caso especial. En
QML el cuerpo de la cámara es un `Rectangle` con `border` y el fondo
transparente, y el diafragma no existe porque un número blanco fundiéndose
sobre una gota blanca sale gris y turbio.

## La fotografía y la esquina de grabar

> **Fotografía.** «Anticipa 70 ms, se estira y sale por el borde superior en
> 150 ms; entonces se oculta, se congela la pantalla y vuelve con los ojos
> convertidos en cámara.»
>
> **Grabación.** «Ya cuenta desde la esquina que va a ocupar. Luego se mete en una
> esquina de la pantalla, asomando el 82 % de ella… La mirada se pliega sobre su
> lado visible.»

![El viaje a la esquina](evidencia/viaje-a-la-esquina.png)

Arriba, su sitio de siempre; abajo, la esquina de la pantalla, que es **otra
superficie**. De izquierda a derecha: se estira para salir, ya no está y cuenta
desde la esquina, graba, y ha vuelto.

| Lo que dice el contrato | Lo medido |
| --- | --- |
| Anticipa 70 ms | Baja 3,3 px y se estira a 0,94 × 1,12 en 70 ms |
| Sale por arriba en 150 ms | A los 220 ms del aviso ya no está en el encuadre |
| Cambia de cara donde nadie la ve | `cam` pasa de 0 a 1 con ella fuera de la superficie |
| 200 ms de margen | 220 antes de volver |
| Vuelve hecha cámara | Cae con un muelle vivo y aterriza 3 px pasada: regresa, no «aparece» |
| El disparo: cierra 80, abre 170 | Un gesto sobre la pose `shut`, con un culatazo del cuerpo (1,05 × 0,95) que en Marea no está |
| Asoma el 82 % | Centro a 14,7 px del ángulo: 46 × 0,82 − 23 |
| Cuenta desde la esquina | La cuenta empieza al llegar arriba, con ella entrando ya por la esquina |
| La mirada se pliega | `min(gaze.x, 0)`, `max(gaze.y, 0)`: nunca mira hacia su mitad escondida |
| Pulsarla para | Y parar a mitad de cuenta la devuelve con sus ojos, no grabando |

**Ella viaja por los bordes.** Marea esconde una ventana y enseña otra. Aquí
sale de verdad por arriba —con el mismo gesto para la foto y para grabar— y
entra de verdad por la esquina, encajándose con un rebote contra el ángulo. La
cara es un `component`, así que en los dos sitios es la misma, con los mismos
muelles. Y la superficie de la esquina se queda abierta mientras quede algo de
ella dentro (`open: tuck > 0.01`), así que al parar se desliza fuera en vez de
desaparecer con la ventana.

### Acercarse saca el reloj y «Detener»

![El panel nace de ella](evidencia/panel-de-la-esquina.png)

En Marea es un rectángulo que se funde en 150 ms a su lado. Aquí **sale de
ella**: es el mismo cuerpo, que se estira hacia dentro de la pantalla como una
gota, hace cuello a mitad de camino y se separa hasta quedar a 8 px. El
contenido entra tarde, cuando el panel ya se ha despegado —antes el botón
quedaba debajo de su cara—. Se recoge con 320 ms de gracia, porque el hueco
entre ella y el panel es real y no puede perderse al cruzarlo.

El reloj lo cuenta el render (`every 1s while taping`) y lo escribe un hueco
nuevo de pleamar: `{secs, time}` → `0:07`. Comprobado con el ratón de mentira:
acercarse lo saca, el botón se enciende al pasar, y pulsar «Detener» la
devuelve arriba.

### Las cuatro esquinas

![En las cuatro esquinas](evidencia/cuatro-esquinas.png)

El contrato dice que la esquina **se elige para que caiga fuera de lo grabado**.
Quien sabe qué se está grabando es la lógica, así que aquí sólo se obedece: un
hecho con tipo, `fact rincon: top_right | top_left | bottom_right | bottom_left`,
y la superficie se pega a ese borde. Se cambia **en marcha**, sin volver a crear
nada: es lo que le faltaba a pleamar y lo que ahora hace `anchor: rincon`.

Todo lo que cuelga de ella sigue al rincón: por qué ángulo entra y sale, hacia
dónde se pliega la mirada, y por qué lado sale el panel del reloj —siempre hacia
dentro de la pantalla, nunca fuera—.

| | Centro de ella | Panel |
| --- | --- | --- |
| `top_right` · `bottom_right` | a 14,7 px del ángulo derecho | a su izquierda |
| `top_left` · `bottom_left` | a 14,7 px del ángulo izquierdo | a su derecha |

**Lo que no se puede todavía:** fuera de su superficie no sabe dónde está el
puntero —Wayland no lo dice, es la limitación S5 de pleamar—, así que en la
esquina solo sigue al ratón cuando lo tiene encima.

## La nota de la hora

> «La nota se despliega desde detrás de la bolita, con la hora y la fecha. Un clic
> en ella abre el calendario. 180 ms de espera antes de salir, 170–190 ms de
> aparición y 300 ms de gracia al salir el puntero, porque el hueco entre bolita y
> nota es real y no puede perderse al cruzarlo. Desaparece si se abre el panel.»

![La nota saliendo de ella](evidencia/nota-de-la-hora.png)

| Lo que dice el contrato | Lo medido |
| --- | --- |
| Sale de detrás de ella | Nace en su centro con ancho cero y se desliza hasta quedar a 14 px. Es una forma más de **su mismo cuerpo**: una sola sombra, un solo borde, y un cuello a mitad de camino |
| 180 ms de espera | `on hover cuerpo_zona for 180ms` |
| 170–190 ms de aparición | Muelle `~190ms` |
| 300 ms de gracia | Medido: el puntero sale a los 3 000 ms y la nota se recoge a los 3 300 |
| La hora y la fecha | `service clock { time; date }`: las trae el sistema, sin lógica, y despierta una vez por minuto |
| Un clic abre el calendario | `emit calendar`, que la lógica oye |
| Desaparece si se abre el panel | `follow nota = if(note and not open and face == eye …)` |

**Y no se hunde con la hora en la mano.** En modo oculto había un `away` de 2,6 s
sobre ella, y salir de ella *hacia la nota* ya contaba. Ahora hay un solo reloj
de gracia para todo lo que la necesita —puntero, nota, tarjeta—, escrito con
`on still`: 2,6 s desde que lo último deja de necesitarla. Medido: la nota se
recoge a los 3 300 ms y ella empieza a hundirse a los 5 900.

## El oleaje de avisos: llega uno

> «Una tarjeta pequeña entra en horizontal a su lado —quién, la primera línea y
> «ahora»— y ella la mira. Se queda lo que hace falta para leerla, y luego se
> estrecha hasta ser una gota del color de su categoría y vuela a su sitio, por
> una curva. Al llegar, un trago pequeño. Entrada 220 ms. Lectura 3,2 s, que el
> puntero encima detiene. Vuelo 220 ms.»
>
> «Hasta cuatro gotas, una por categoría y la más reciente primero, bajando por su
> lado derecho desde el hombro, cada una con su número dentro —«9+» a partir de
> diez—. La gota donde cae algo late una vez. Nada en bucle.»

![Un aviso, de tarjeta a gota](evidencia/aviso-que-llega.png)

| Lo que dice el contrato | Lo medido |
| --- | --- |
| Respingo de 8 px, ojos muy abiertos, aterrizaje elástico | El gesto `alert` de Marea, fotograma a fotograma, por 46/56 |
| Entrada 220 ms | `entra ~220ms`; si está hundida, espera a que haya salido |
| Ella la mira | La mirada deja al ratón y se va a la tarjeta mientras se lee (`atenta`) |
| Lectura 3,2 s, que el puntero detiene | `on still marca for 3.2s while … not sobre`: salir de encima vuelve a contar. Medido: 3 200 ms desde que ella está fuera |
| Se estrecha hasta ser una gota de su color | Una sola forma: ancho, alto, esquina y color van con `mine` |
| Vuela por una curva, 220 ms | De lado a ritmo constante y hacia arriba deprisa: `1 − (1 − mine)²` |
| Al llegar, un trago | Gesto `gulp`, y la gota late una vez con un `impulse` |
| La más reciente primero | El sitio de cada gota es cuántas hay más recientes, y viaja a él **por el arco**: se anima el ángulo, no la x y la y, así que se corren hombro abajo sin atajar por dentro de ella |
| Número dentro, «9+» desde diez | Sí |

**El orden es el de llegada, no el de aterrizaje.** El que se está leyendo
aterriza 3,2 s después que los que llegan mientras tanto, pero llegó antes: cada
aviso guarda su turno. Comprobado con tres seguidos: mensajes, calendario,
sistema → sitios 2, 1 y 0.

**Lo que falta de esta parte:** la ráfaga apilada («tres a la vista y +N más»),
la llegada con ella dormida, la vista previa en abanico y la bandeja entera.

### Lo que esto destapó en pleamar

Haciendo volar la gota, **el render se quedaba parado 300 ms a mitad de vuelo**:
la gota se congelaba y aparecía en su sitio. No era de esta escena. Con el
depurador: parado en `vkAcquireNextImage`, esperando a que el compositor
devolviera una imagen. Dos cosas eran de pleamar —una superficie *cerrada* podía
marcar el ritmo con vsync, y al despertar se presentaban tres frames en 2 ms— y
la tercera es de Hyprland con NVIDIA. Ahora se presenta por buzón y el render se
marca el paso. El frame más largo en vuelo pasó de **300–780 ms a 17**.

Para una alternativa a Quickshell cuyo argumento es la fluidez, esto valía más
que la gota.

## Medidas de la lámina

De `design/concepts/2026-09-12-reposo-vivo/referencia-real-limpia.png`, que
conserva el tamaño real:

| | |
| --- | --- |
| cuerpo | 46 px de diámetro |
| ojos | 5 × 13, puntas redondas (`corner: 2.5`) |
| separación | 13 px entre centros |
| altura de los ojos | 2,5 px por debajo del centro del cuerpo |

## Lo que le faltó al lenguaje, y ya no

Tres cosas, todas arregladas en pleamar en vez de esquivadas aquí:

1. **No había forma de comprobar un tiempo.** Sondear desde fuera cuesta 16 ms
   por lectura, que es un frame entero. Ahora está `--registrar`.
2. **`blink` contaba el periodo desde que abría el ojo**, así que «cada 5,2 s»
   salía 5,33. Ahora cuenta de comienzo a comienzo, y acepta un solo periodo.
3. **No se podían escribir los tiempos.** El contrato está en milisegundos y en
   pleamar solo había muelles, que llegan cuando llegan. Ahora un muelle se puede
   decir en tiempo: **`~620ms`** es el que llega en ese rato sin rebotar. Medido:
   619 ms.
4. **Lo ambiental pisaba a los gestos.** La respiración lleva su propio
   parpadeo, y el de reposo caía encima: dos parpadeos en segundo y medio. Ahora
   un gesto manda, y el reloj de lo ambiental se congela mientras dura.
5. **Una sombra que no cabía se cortaba sin decir nada.** Ahora el render lo
   dice, una vez, cuando la cuenta deja de crecer.
6. **El empujón no podía depender de nada.** `impulse` solo aceptaba un número
   escrito, y el contrato pide un rebote que **decrece** con la cuenta. Ahora es
   una expresión que se evalúa al dispararse: `impulse pop left * 2.5`.
7. **`every … while x` contaba su espera mientras `x` era falso**, así que la
   cuenta atrás daba su primer paso a los 300 ms —lo que quedara del reloj de
   antes—. Ahora el reloj se pone entero mientras no se cumple.
8. **Una regla no podía ver lo que otra acababa de hacer.** Las reglas se miran
   todas antes de aplicar nada, así que un `on change` lo ve al frame siguiente;
   y con nada moviéndose, «el siguiente» era la próxima cita: **un segundo más
   tarde**. La cuenta pasaba al disco rojo un segundo después de su último
   número. Ahora, tras un efecto, hay un frame más garantizado: 17 ms.
9. **No había seno ni coseno**, así que nada podía ir por un arco. Ahora
   `sin(deg)` y `cos(deg)`.
10. **El render se paraba 300 ms en mitad de una animación** (arriba, en «Lo que
    esto destapó»).
11. **Una superficie no podía esperar a lo que lleva dentro.** `open:` solo
   aceptaba un hecho; ahora una cuenta: `open: tuck > 0.01`.
12. **Un `clip` suelto recortaba también la otra ventana**, y no se veía nada sin
    que nada lo dijera. Costó una hora encontrarlo. Ahora los recortes abiertos
    acaban donde empieza una superficie con nombre.
13. **No se podía decir «cuando esto lleve un rato sin cambiar».** El contrato lo
   pide en tres sitios —el nivel aguanta 1,1 s tras el último cambio, la nota de
   la hora 300 ms de gracia, el aviso 700— y en pleamar solo existía `on change`,
   su reverso. Con él, una ráfaga de teclazos salía como un parpadeo por
   escalón. Ahora está **`on still x for 1.1s`**: cada cambio pone el reloj a
   cero, así que la ráfaga es una lectura continua, y lo que dispara ocurre una
   vez al acabar. Medido: 1 102 ms tras el último cambio, y sin gastar un frame
   esperando.

## Lo siguiente

- Del oleaje: la ráfaga apilada, la llegada con ella dormida, la vista previa en
  abanico, y la bandeja («Abre Oleaje», resolver un grupo, el cierre).
