# Continuación: balística, cristales, natación y tráfico

Se conservaron los cambios de armas, casino e Inés presentes al comenzar esta continuación. Esta entrega avanza sistemas del juego original **Brisa de Poniente**; no completa el objetivo D-017.

## Comportamiento implementado

- `game/scripts/ballistics.gd` resuelve impactos mediante rayos físicos para jugador, policías y enemigos. La cámara elige dónde apuntar, pero el recorrido desde el arma decide el impacto. Un cañón que atraviesa visualmente una pared tampoco permite disparar a través de ella. Las paredes, vehículos, personajes y terreno interceptan la trayectoria; las superficies sólidas reciben marcas.
- `breakable_glass.gd` añade colisión exclusiva para disparos a escaparates, puertas acristaladas, vitrinas de joyería y frentes de boutiques de los locales interactivos. El primer impacto oculta el cristal y emite fragmentos; el disparo continúa con un 20 % menos de daño por cada panel atravesado. Los siguientes disparos atraviesan el hueco. Se conservan los portales de entrada con E y se guarda la destrucción por identificador de nodo. Una partida antigua restaura cristales intactos.
- Los disparos de NPC usan trayectorias con dispersión, en lugar de decidir daño por una tirada independiente de probabilidad. Se respetan cobertura y daños a terceros. Los civiles huyen del tiro o del impacto y los enemigos armados heridos conservan su respuesta de combate. Un impacto causado por un NPC no se atribuye al jugador para subir su nivel policial.
- La natación utiliza brazadas y patadas procedurales sobre el personaje CC0 existente, con inclinación y flotación del torso. Espacio tiene prioridad sobre C para subir incluso manteniendo la tecla de buceo. Al embarcar, salir del agua o reaparecer se limpia la pose y el estado acuático.
- Los coches de IA anticipan obstáculos con una distancia que combina margen de reacción y distancia de frenado según su velocidad. Usan la deceleración del freno del vehículo ante obstáculos.

## Presupuestos del combate

Máximo de 12 emisores de impacto activos, 48 marcas de bala reutilizables y 8 sonidos remotos simultáneos. Los emisores dejan de crearse a más de 80 m del jugador; los efectos no proyectan sombras. Mallas y materiales de partículas son compartidos, los fragmentos no crean cuerpos rígidos y las balas no añaden procesamiento por fotograma. El límite visual no elimina el daño ni la rotura del cristal.

## Verificación

`tests/ballistics.gd` pasa con física de la escena real: dos cristales atravesados en un mismo tiro y daño resultante de 19,2 sobre 30; reacción de la víctima; siguiente tiro sin nueva atenuación; persistencia F5/F9; muro que detiene al jugador y al enemigo; daño del NPC cuando se retira la cobertura; obstrucción de la boca del arma; 180 impactos sin superar los límites.

`tests/water_and_dressing.gd` pasa entrada continua desde la playa, regreso a tierra, estabilización en superficie, pose de natación, consumo de aire, subida manteniendo C y Espacio, limpieza de pose y protección de coches frente al agua profunda.

`tests/traffic_obstacles.gd` pasa una aproximación real a 22 m/s: frena sin perder salud y continúa tras retirar la barrera; separación mínima registrada de 6,07 m entre centros. El recorrido completo de El Recado pasa con controles simulados, persecución, evasión y entrega. La primera ejecución de la validación detectó un fallo de ruta y la prueba de frenado detectó un roce; el ajuste posterior de la distancia y fuerza de frenado pasa ambas pruebas. Los registros finales completos se añaden al finalizar la validación.

## Límites pendientes

Los cristales de los coches y ventanas de edificios no interactivos todavía no se rompen. Las paredes reciben impactos, pero no se derriban. No hay penetración de chapa, rebotes físicos, destrucción estructural ni fragmentos persistentes con colisión. Las poses acuáticas son procedurales y siguen pendientes de revisión humana, animaciones finales y rescate. La IA requiere más pruebas en cruces y con obstáculos laterales. Las misiones mantienen el alcance de capítulo uno; esta entrega comprueba regresiones y no añade nuevos capítulos.

La medición gráfica debe distinguir la ruta en ventana visible de las capturas y muestras estacionarias. Los resultados finales y las limitaciones se registran también en `docs/PERFORMANCE_BUDGET.md`.

Se corrigió un contador de resolución: en pantalla completa la imagen GPU real mide 1920×1080, mientras `ViewportTexture.get_size()` informa 2880×1620 al incorporar el estirado de la interfaz. `capture.gd -- --view seafront --fullscreen` comprueba ambas medidas (`framebuffer.txt`). El [código de Godot para ViewportTexture](https://github.com/godotengine/godot/blob/master/scene/main/viewport.cpp) muestra esa multiplicación por el transform de estirado en Window. `perf_monitor.gd` registra ahora el tamaño de la imagen real una vez al iniciar o cambiar tamaño, conservando la medida anterior como diagnóstico; no cambia la resolución del juego.

La primera pasada visible con vsync completa El Recado. La pasada inicial sin límite registra rendimiento, pero el conductor automatizado acaba detenido por la policía y no completa la entrega. Se conserva ese fallo en `perf_route_uncapped_before_driver_fix.txt`. La prueba ahora usa semilla 7401, inicia la huida al avanzar el objetivo de misión y detecta atasco por desplazamiento real, en lugar de exigir continuar hasta un nodo posterior o confiar en la velocidad de las ruedas. No se han eliminado requisitos de persecución, evasión o entrega, ni se ha alterado la dificultad policial para pasar la prueba.

## Capturas revisadas

Capturas del ejecutable local de Godot, Compatibility / NVIDIA GTX 1650. La prueba de escaparate dispara desde la calle contra el cristal real del Mercado Azul, sin ocultarlo manualmente. Las imágenes verifican integración y legibilidad; no equivalen a aceptación artística final.

![Natación en superficie](../screenshots/combat_water/swimming.png)

![Escaparate tras el impacto](../screenshots/combat_water/broken_glass.png)
