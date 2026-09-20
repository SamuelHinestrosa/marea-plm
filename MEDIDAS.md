# Medidas: Marea en Quickshell contra Marea en pleamar

Las dos, en la misma máquina, en el mismo monitor y a la vez. Marea es la que
usa Abel todos los días (`~/Proyectos/proyecto-marea`, 370 ficheros QML);
`marea-plm` es esta carpeta.

Cómo se mide, para que se pueda repetir:

```sh
# CPU, memoria y hilos de un proceso, durante N segundos
medir.sh <pid> 30 "etiqueta"
```

Lee `/proc/<pid>/stat` dos veces separadas por N segundos para el tiempo de CPU,
y `/proc/<pid>/status` y `smaps_rollup` para la memoria. El PSS es lo que de
verdad ocupa: la memoria compartida, repartida entre quienes la comparten.

## 20 de septiembre de 2026 · la bolita

Solo la bolita: su cuerpo, su cara que respira, mira y parpadea, el aura y la
gota de los avisos. Marea, mientras tanto, es ella entera (tiene detrás sus
paneles, sus servicios y su cara con accesorios), así que **esta comparación no
es justa todavía**: es el punto de partida, no el resultado.

| | CPU | RSS | PSS | hilos | primer frame |
| --- | --- | --- | --- | --- | --- |
| Marea (Quickshell) | 12,98 % | 245,8 MB | 204,7 MB | 14 | sin medir |
| marea-plm, animando | 4,93 % | 111,7 MB | 94,1 MB | 13 | 175 ms |
| marea-plm, quieta | 0,32 % | 109,3 MB | 92,2 MB | 13 | 191 ms |

**Lo que dice.** Animando —respirando, parpadeando, mirando— pleamar cuesta la
tercera parte de CPU y menos de la mitad de memoria. Y **quieta baja a 0,3 %**,
porque el render duerme cuando no hay nada que mover: Quickshell sigue en 13 %
aunque no pase nada en la pantalla.

El 4,93 % de animar son unos 0,8 ms de CPU por frame a 60 Hz. De ahí sale la
primera deuda a mirar: la lista de dibujo se recompone entera cada frame, haya
cambiado algo o no (limitación P8 de pleamar).

## 20 de septiembre de 2026 · la tarjeta entera

Ya con todo: la bolita, la tarjeta que le sale del cuerpo, la hora, la fecha, el
volumen, los nueve escritorios con su píldora y el título de la ventana de
delante. Son 62 instrucciones, 14 propiedades animadas y 11 zonas.

| | CPU | RSS | PSS | hilos |
| --- | --- | --- | --- | --- |
| Marea (Quickshell) | 13,15 % | 197,4 MB | 156,5 MB | 14 |
| marea-plm, tarjeta abierta | 5,32 % | 112,9 MB | 96,0 MB | 17 |
| marea-plm, tarjeta cerrada | 5,05 % | 112,9 MB | 96,0 MB | 17 |

**Lo que dice.** Abrir la tarjeta entera cuesta un 0,3 % más que tenerla cerrada.
Dicho de otro modo: **lo que se dibuja casi no importa**. Y eso vale también al
revés, que es lo interesante: pasar de un círculo a una barra completa no movió
la aguja.

## De dónde sale ese 5 %

Con `PLEAMAR_CRONO=1`, pleamar imprime el desglose de cada frame:

```
crono · hueco 16,04 · apuntar 0,10 · cerrar 0,21 · mandar+presentar 0,23 ms
```

Los 16 ms de «pedir el hueco» son la espera del monitor a 60 Hz, y son **sueño**,
no CPU. Lo que se gasta de verdad son los 0,5 ms de apuntar las órdenes, cerrar
el mando y mandarlo: el suelo de wgpu sobre Vulkan, que hay que pagar aunque solo
se mueva un círculo. Queda anotado en pleamar como la limitación P11, con su plan.

Para comparar: Quickshell gasta unos 2 ms de CPU por frame haciendo lo mismo.

## Lo que falta por medir

- **Frames de Marea**: pide relanzarla con `QSG_RENDER_TIMING=1`, y eso deja a
  Abel sin barra un rato. Cuando él diga.
- **Cuánto tarda Marea en su primer frame**: lo mismo.
- **GPU**: `nvidia-smi` da 926 MiB y 7 % para toda la sesión, no por proceso.
- Con la tarjeta abierta y los paneles dentro, que es cuando Quickshell instancia
  de verdad.
