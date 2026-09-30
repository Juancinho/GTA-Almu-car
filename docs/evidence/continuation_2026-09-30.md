# Continuación: armas, locales e interior de dos plantas

Se conservaron los seis archivos modificados que había al retomar el proyecto (`hud`, `main`, `venue_catalog`, `venue_interior`, `weapons` y la prueba de locales). El casino, la armería, la discoteca y la marisquería estaban iniciados en esos cambios; no se atribuyen aquí como creaciones desde cero.

## Cambios jugables

- Armas: anclaje al centro de la palma, referencia al hueso del gatillo del modelo importado, dedos cerrados y resolución de ambos brazos conservando su longitud. Las piernas mantienen su animación. Pistola, subfusil, escopeta y fusil usan parámetros de agarre/apoyo/boca en `game/data/weapons.json`. Las armas largas se llevan bajas con ambas manos; las poses se limpian al desequipar, nadar, conducir o morir.
- Casino: vestíbulo, escalera con peldaños visibles y colisión continua, rellano, planta de administración, despacho y archivo escondido. La altura del suelo supera el terreno de todo el interior. La cámara se acorta dentro de los locales.
- **Cuentas pendientes**: Inés aparece junto a la fachada con el indicador I. La misión exige subir físicamente, examinar el libro con E, salir y entregar la copia. Recompensa de 650 €, sin repetir el pago; se reanuda la misión que estuviera suspendida. Los objetivos interiores comprueban también la altura y la interacción se valida por proximidad.
- Archivo oculto: sobre de 125 €, una sola vez; descubrimiento y objeto visible/restaurado se guardan con la partida. Las partidas antiguas sin este campo siguen siendo válidas.
- Locales heredados: comprobación de entradas/salidas, servicios y contención dentro de la huella. Armería reducida de 0,9 a 0,7 para no atravesar el edificio; suelo elevado sobre el terreno en los cuatro locales nuevos. Ruleta europea de un cero: el número sorteado determina el color y el pago. Materiales emisivos repetidos compartidos y personajes de la discoteca animados.

## Verificación reproducible

`pwsh -File tools/validate.ps1` incorpora `game/tests/weapon_grips.gd` y `game/tests/casino_route.gd`, además de las pruebas existentes. Los registros se escriben en `generated/validation/`.

Resultado: **VALIDATION PASS**. Tras los últimos ajustes de cámara/manos se repitieron smoke, armas, agarres, locales y ruta del casino: todos **PASS**, sin errores de Godot en stderr. Se preserva el registro completo y las comprobaciones finales en `docs/evidence/continuation_2026-09-30/*.txt`. `git diff --check` también pasa.

- `weapon_grips.gd`: cuatro armas, tres inclinaciones al apuntar, anclaje de palma, alcance de la mano de apoyo, longitudes de brazos, porte bajo y limpieza al desequipar.
- `casino_route.gd`: rechazo desde la planta equivocada, recorrido con controles por escaleras y puertas, archivo oculto, descubrimiento persistente, guardado/carga en el despacho, interacción con el libro, regreso, recompensa única y reanudación de El Recado. Solo se reposiciona para preparar casos y volver al contacto; la subida, el recorrido interior y la bajada usan movimiento físico.
- `venues.gd`: los doce locales, huellas de los cuatro nuevos, suelo sobre el terreno, cámara interior, compras/curación, doce tiradas reproducibles de ruleta con correspondencia número/pago, falta de fondos, tragaperras, arma y munición; mantiene las pruebas de banco y joyería.
- Capturas con el ejecutable local de Godot y la GTX 1650: cuatro armas al apuntar, fusil bajado, casino, armería, discoteca, marisquería y despacho con misión de día y de noche. Las imágenes seleccionadas están en `docs/screenshots/continuation/`.

Muestra aislada de rendimiento a 1920×1080: exterior **67,9 FPS medios / 39,1 FPS del 1 % más lento**, casino **85,2 / 70,5**; aproximadamente 106,6 MiB de texturas. Son vistas estacionarias de SubViewport, no una prueba humana de estabilidad. El objetivo de 60 FPS estables en exteriores sigue pendiente; detalle y registros en `docs/PERFORMANCE_BUDGET.md`.

![Agarre del fusil](../screenshots/continuation/rifle.png)

![Vestíbulo y escaleras](../screenshots/continuation/casino_lobby.png)

![Despacho de noche](../screenshots/continuation/casino_office_night.png)

## Límites de esta entrega

La geometría y el mobiliario siguen siendo una primera versión procedural. Las capturas prueban legibilidad e integración, no la aceptación artística final exigida en `ART_DIRECTION.md`. Falta revisión humana del nuevo recorrido, combate en movimiento con mando y una animación de recarga específica. Los casinos no son una simulación completa de juegos de mesa y la discoteca aún carece de música propia y animaciones de baile dedicadas.

Esto no completa el producto D-017: siguen pendientes barrios y fachadas de calidad final, más edificios de varias plantas, refugios, una flota amplia, combate y policía completos, campañas adicionales, actividades, audio, accesibilidad y exportación comercial. `TASKS.md` conserva esas obligaciones.
