# Güira de Melena – Mundo Abierto
## Arquitectura de mapa real y streaming offline

El objetivo es representar el municipio completo, no sólo el casco urbano. La referencia cartográfica de búsqueda ofrece un rectángulo aproximado para localizar datos; ese rectángulo **no se considera un límite administrativo**. El importador exige encontrar una relación administrativa OSM coincidente con Güira de Melena antes de generar sectores.

## Sistema de coordenadas
- Origen local: centro urbano (22.7933, -82.5073).
- X: este positivo; Z: sur positivo; unidades Godot en metros.
- Tamaño de sector: 1.000 × 1.000 metros.
- Identificadores: `x_z`.
- Radio inicial: 1 sector alrededor del jugador (hasta 3 × 3 sectores cargados).

## Generación de los datos
Desde la raíz del repositorio, durante el desarrollo y con conexión:
```bash
python3 tools/build_osm_chunks.py
```
El script consulta OpenStreetMap una vez, localiza la relación administrativa, reconstruye su contorno, filtra calles y edificios por el polígono municipal y genera `world/manifest.json` más archivos independientes en `world/chunks/`. Si no encuentra el contorno, se detiene en vez de presentar un rectángulo aproximado como si fuera el municipio.

## Streaming dentro del juego
`scripts/osm_chunk_streamer.gd` carga los JSON locales según la posición del jugador, construye el terreno base, segmentos de carretera con colisión y volúmenes de edificios, y libera sectores lejanos. La ejecución del juego no necesita red. Si no hay datos importados y verificados, conserva la ciudad procedural como fallback.

## Alcance visual de esta primera iteración
- Carreteras y caminos OSM como segmentos 3D con colisión.
- Edificios como volúmenes extruidos desde sus huellas OSM, usando altura/número de plantas cuando existen.
- Áreas OSM de uso del suelo y elementos naturales triangulados con materiales diferenciados (agricultura, vegetación, agua y otras categorías etiquetadas).
- Materiales compartidos y colisiones sólo en sectores cargados.
- El aspecto de edificios es provisional: no equivale todavía a modelos arquitectónicos realistas, fachadas exactas, interiores ni mobiliario urbano.
- El relieve detallado, vegetación individual, costa y cuerpos de agua requieren más datos y trabajo visual.

## Rendimiento
- Sectores de 1 km, radio inicial de 1.
- Próximas optimizaciones: LOD por distancia, instanciación por lotes, culling, simplificación de geometría y densidad adaptativa.

## Licencias
Los datos se obtienen de OpenStreetMap y deben atribuirse como “© OpenStreetMap contributors” y distribuirse respetando ODbL 1.0. La licencia de los datos es independiente de la licencia MIT del código base.

## Estado comprobable — datos generados
La importación municipal ya se ejecutó correctamente. El manifiesto de `main` confirma el límite administrativo OSM 2576652, contrastado con la referencia de Wikimedia Commons, y contiene 158 sectores offline de 1 km, 2.972 segmentos de carretera, 386 edificios y 171 polígonos de uso del suelo/elementos naturales. Los 158 archivos JSON están presentes en `world/chunks/` (aprox. 654 KB en total).

El streamer ya puede cargar esos sectores desde archivos locales y desactivar la ciudad procedural de respaldo cuando detecta el manifiesto verificado. La importación de datos está completada; todavía falta probar el proyecto en Godot, revisar visualmente la cobertura y el encaje de los sectores, optimizar geometría/LOD y validar el rendimiento en Android. No existe todavía una APK/AAB verificada. Tampoco se debe confundir el mapa OSM generado con una reconstrucción visual de máxima fidelidad: los edificios son volúmenes básicos y la cobertura depende de las etiquetas existentes en OSM.

## Automatización de la generación
El repositorio incluye el workflow `.github/workflows/generate-map-data.yml`. Al incorporarse a `main`, intenta ejecutar el importador y, únicamente si el límite municipal está verificado y hay sectores/calles, guarda los JSON offline generados en el repositorio. También permite ejecución manual desde GitHub Actions. Este proceso genera datos cartográficos; no compila APK ni AAB.


## Capas cartográficas incorporadas al importador
El importador también conserva polígonos OSM de uso del suelo y elementos naturales etiquetados (por ejemplo, áreas agrícolas, vegetación y agua). El streamer los triangula y representa con materiales diferenciados dentro de cada sector. Estas capas dependen de la cobertura real de OSM: una zona sin etiquetas seguirá siendo terreno base, no una reconstrucción inventada. Las huellas de edificios continúan siendo volúmenes provisionales y no fachadas arquitectónicas detalladas.


## Puntos de interés y vegetación puntual
El importador consulta también nodos OSM etiquetados como servicios (amenity), comercios (shop), turismo (tourism), ocio (leisure) y árboles individuales (natural=tree). Los guarda dentro del sector local correspondiente. El streamer dibuja marcadores sencillos para los puntos de interés y modelos de árbol de bajo coste geométrico. Los contadores `points_of_interest` y `trees` del manifiesto permiten medir la cobertura real; no se inventan ubicaciones donde OSM no tenga datos.

La lectura de alturas y plantas acepta ahora correctamente decimales como `3.5 m`, con pruebas unitarias específicas.
