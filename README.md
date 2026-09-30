# Brisa de Poniente

Juego original de acción y mundo abierto en tercera persona, ambientado en una recreación a escala 1:1 del centro de **Almuñécar (Granada)**. Está desarrollado con Godot y combina exploración, conducción, combate, policía, actividades y una campaña con personajes propios.

**Está en desarrollo.** El objetivo es un juego completo con varios capítulos y distritos detallados. Lo que hay ahora es una versión jugable del primer capítulo y sistemas que se amplían y prueban por etapas; todavía no tiene el acabado, la profundidad ni la estabilidad de una producción comercial de gran presupuesto. Consulta [alcance](docs/GAME_DESIGN.md), [hoja de ruta](docs/ROADMAP.md) y [tareas y pruebas](TASKS.md).

## Qué puedes hacer ahora

- Explorar el paseo, casco antiguo, San Miguel y San Cristóbal, con 1.252 edificios derivados de OSM, calles a escala real, monumentos, comercios, terrazas, playa y ciclo de día/noche. El relieve sigue siendo provisional.
- Caminar, correr, saltar, nadar y bucear con aire limitado, postura de natación y efecto azul con niebla cuando la cámara está bajo el agua.
- Conducir coches, taxis, deportivos, todoterrenos y embarcaciones; entrar y salir, robar vehículos, reparar en Taller Poniente y participar en actividades. El tráfico sigue carriles y frena ante obstáculos; las colisiones producen daños y atropellos.
- Hablar con civiles, ver patinadores, trabajadores, baile en Discoteca Levante y bañistas adultas con ropa de baño. Los civiles reaccionan a agresiones: huida, defensa y represalias según su carácter.
- Usar puños, bate, pistola, subfusil, escopeta y fusil, apuntar y recargar. Los disparos del jugador, enemigos y policía comparten colisiones: los muros detienen las balas, los cristales de los locales se rompen y reducen el daño al atravesarlos. Algunas sillas se pueden empujar y mover con disparos o coches. La destrucción general del mundo y los cristales de vehículos siguen pendientes.
- Jugar las misiones del primer capítulo, **El Recado**, **La noche de Jaime** y los demás encargos del catálogo. La misión adicional **Cuentas pendientes**, de Inés junto al casino, requiere subir por escaleras, examinar el libro de cuentas y volver; hay también un secreto guardable.
- Provocar una respuesta policial, perder la línea de visión, escapar de la búsqueda o sufrir arresto. Los policías y enemigos armados pueden perseguirte y dispararte; la cobertura física importa.
- Entrar en **21 locales y edificios**, además del taller y cinco chiringuitos: mercado, restaurantes, banco, joyería, iglesia, galería comercial, cafetería, casino con planta superior, armería, discoteca, marisquería, panadería, botica, estudio de estilismo, gimnasio, tienda de discos y moda. Tres residenciales tienen vestíbulo, escaleras y dos apartamentos amueblados cada uno.
- Comprar comida, recuperar salud, cambiar estilo/ropa, escuchar una sesión instrumental original, ingresar y retirar dinero, apostar en el casino y comprar armas/munición. Descansar en un apartamento recupera salud y aire si la policía no te busca.
- Guardar y cargar posición, misiones, dinero, cuenta bancaria, inventario, estilo, secretos y cristales rotos. Usar minimapa, GPS y mapa con destinos.

Los negocios y personajes son ficticios. Los nombres de calles y lugares públicos reales se conservan. Los interiores y actividades añadidos no implican que los demás edificios de la ciudad sean accesibles. El acabado artístico, la navegación compleja de todos los NPC y la campaña completa están abiertos en las tareas.

## Descargar y ejecutar

Necesitas **Git**, **Git LFS** y **Godot para escritorio**. La versión comprobada en este proyecto es **Godot 4.7.2**, renderizador **GL Compatibility**. El ejecutable del motor no se incluye en Git. Descárgalo desde [Godot](https://godotengine.org/download/windows/). En Windows, el lanzador usa PowerShell 7 (`pwsh`); también puedes importar y ejecutar el proyecto desde el editor de Godot.

```powershell
git lfs install
git clone https://github.com/Juancinho/GTA-Almu-car.git
cd GTA-Almu-car
git lfs pull
```

Git LFS descarga los modelos, texturas y sonidos. Si esos archivos aparecen como pequeños ficheros de texto que empiezan por `version https://git-lfs.github.com/spec/v1`, faltan sus contenidos: ejecuta `git lfs pull` antes de abrir Godot.

Opción A: indica la ruta del ejecutable de Godot que has descargado:

```powershell
pwsh -File .\tools\run.ps1 -GodotPath 'C:\Herramientas\Godot\Godot.exe'
```

Opción B: coloca el ejecutable como `.tools/godot/godot.exe` dentro del repositorio y ejecuta:

```powershell
pwsh -File .\tools\run.ps1
```

El lanzador también reconoce la variable `GODOT_EXE` o el comando `godot` si está en PATH. Primero importa el proyecto y registra las clases nuevas, después abre el juego. La primera importación de recursos puede tardar. Para comprobar solamente la importación, añade `-ImportOnly`.

Desde el editor: pulsa **Importar**, elige `game/project.godot`, espera la importación y ejecuta el proyecto con **F5**. Desde una terminal con Godot en PATH:

```powershell
godot --headless --editor --path game --quit
godot --path game
```

No necesitas Blender ni Python para jugar con los recursos incluidos. Las herramientas de regeneración y validación de desarrollo sí los requieren. No se descarga información del mapa durante la partida.

## Controles

| Acción | Tecla / botón |
|---|---|
| Moverse / conducir | WASD |
| Cámara | Ratón |
| Correr | Shift |
| Saltar / subir hacia el aire | Espacio |
| Bucear | Mantener C |
| Interactuar, hablar, entrar/salir de coche o edificio | E |
| Apuntar / atacar | Botón derecho / izquierdo del ratón; F también ataca |
| Elegir puños, bate, pistola, subfusil, escopeta, fusil | 1–6 / rueda |
| Recargar | R |
| Freno de mano | Espacio dentro del coche |
| Mapa / marcar destino | M / clic en el mapa |
| Pausa | Escape |
| Guardar / cargar | F5 / F9 dentro del juego |
| Calidad / volumen | F3 / F4 |
| Rendimiento / informe de sesión | F2 / F6 |
| Pantalla completa | F11 |

Mando: stick izquierdo para moverse, derecho para mirar, A saltar, X interactuar, B frenar, LB correr y Start pausar.

Empiezas junto al paseo: habla con **Alba** para comenzar **El Recado**. Las letras marcan contactos; sigue el GPS amarillo y el marcador del objetivo. **Marina**, junto a Jaime Playa, ofrece **La noche de Jaime**. El mapa muestra los negocios y residenciales. En un local, acércate al mostrador y pulsa E; sal por el acceso marcado. En los residenciales, sube por las escaleras de la derecha y entra por los huecos señalados 01/02.

## Pantalla completa y rendimiento

La configuración inicial es **Media**, con renderizado 3D al 85 % y sombras de alcance limitado; la interfaz conserva su resolución. F3 alterna Baja (67 %), Media (85 %) y Alta (100 %). F2 muestra las mediciones y F6 escribe el informe. La calidad elegida se guarda con la partida; una partida anterior puede conservar Alta.

La pantalla completa puede exigir más trabajo a la GPU al pasar de 1280×720 a la resolución del monitor. Se están comprobando también los tiempos de física y los picos de frame. No se garantiza todavía 60 FPS estables en todas las rutas o equipos; las medidas y limitaciones se documentan en [presupuesto de rendimiento](docs/PERFORMANCE_BUDGET.md). La validación del editor no sustituye las pruebas de una exportación de publicación.

## Validación y desarrollo

```powershell
pwsh -File .\tools\run.ps1 -ImportOnly
pwsh -File .\tools\validate.ps1
pwsh -File .\tools\validate.ps1 -Capture
pwsh -File .\tools\validate.ps1 -Perf
```

`validate.ps1` comprueba dependencias, hashes/licencias de recursos, herramientas Python, importación de Godot y pruebas de movimiento, daños, combate, policía, tráfico, agua, actividades, comercios y recorridos de misión. `-Capture` añade una imagen y `-Perf` recorridos visibles en pantalla completa. Los errores de Godot en stderr hacen fallar la validación aunque el ejecutable GUI devuelva 0.

Los requisitos exactos de herramientas están en [SETUP_STATUS.md](SETUP_STATUS.md) y `tools/bootstrap.ps1`. **Bootstrap comprueba las herramientas; no las instala.** Los informes automáticos y capturas se escriben en `generated/`; la evidencia conservada está en `docs/evidence/` y `docs/screenshots/`.

| Carpeta | Contenido |
|---|---|
| `game/` | Proyecto Godot, sistemas, escenas, datos y recursos incluidos |
| `tools/world/` | Transformaciones geográficas y generación determinista del distrito |
| `tools/blender/` | Fuentes de generación de modelos |
| `tools/audio/` | Generador de sonidos y composición original |
| `source_assets/`, `assets/` | Fuentes, procedencia y licencias |
| `tests/`, `game/tests/` | Validación de herramientas y comportamiento jugable |
| `docs/` | Diseño, alcance, decisiones, arte, presupuestos y evidencia |

Las contribuciones deben seguir [AGENTS.md](AGENTS.md). No edites a mano las salidas de `generated/`: modifica la fuente y regenera.

## Créditos y licencias

Mapa © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), **ODbL**. El relieve diseñado es provisional hasta integrar datos CNIG MDT05 con su atribución correspondiente. Modelos de **Quaternius** y texturas de **ambientCG / Poly Haven** con licencia **CC0**, con URLs, autores, mapas y hashes registrados antes de importarse; consulta [pipeline de recursos](docs/ASSET_PIPELINE.md), [diseño del mundo](docs/WORLD_DESIGN.md) y `assets/third_party/`. Sonidos, patrones de ropa de baño y música de la tienda de discos: fuentes originales del proyecto; las personas usan los rigs adultos CC0 existentes. No se utilizan mapas, insignias, marcas ni recursos propietarios de otros juegos.
