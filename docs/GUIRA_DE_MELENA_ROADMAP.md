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
- Carreteras y caminos como segmentos 3D.
- Edificios como volúmenes extruidos desde sus huellas OSM, usando altura/número de plantas si existen.
- Materiales compartidos y colisiones sólo en sectores cargados.
- El aspecto de edificios es provisional: no equivale todavía a modelos arquitectónicos realistas, fachadas exactas, interiores ni mobiliario urbano.
- El relieve, vegetación, campos agrícolas, costa y cuerpos de agua requieren capas de datos adicionales y trabajo visual posterior.

## Rendimiento
- Sectores de 1 km, radio inicial de 1.
- Próximas optimizaciones: LOD por distancia, instanciación por lotes, culling, simplificación de geometría y densidad adaptativa.

## Licencias
Los datos se obtienen de OpenStreetMap y deben atribuirse como “© OpenStreetMap contributors” y distribuirse respetando ODbL 1.0. La licencia de los datos es independiente de la licencia MIT del código base.

## Estado comprobable
El cargador y el importador están en el código. El manifiesto inicial marca `boundary_verified: false`, por lo que el mapa OSM no se activa todavía. Para activarlo, el importador debe localizar el límite administrativo y generar los sectores reales. No se debe anunciar el mapa municipal como terminado hasta validar cobertura, escala, calles y edificios.


## Automatización de la generación
El repositorio incluye el workflow `.github/workflows/generate-map-data.yml`. Al incorporarse a `main`, intenta ejecutar el importador y, únicamente si el límite municipal está verificado y hay sectores/calles, guarda los JSON offline generados en el repositorio. También permite ejecución manual desde GitHub Actions. Este proceso genera datos cartográficos; no compila APK ni AAB.


## Capas cartográficas incorporadas al importador
El importador también conserva polígonos OSM de uso del suelo y elementos naturales etiquetados (por ejemplo, áreas agrícolas, vegetación y agua). El streamer los triangula y representa con materiales diferenciados dentro de cada sector. Estas capas dependen de la cobertura real de OSM: una zona sin etiquetas seguirá siendo terreno base, no una reconstrucción inventada. Las huellas de edificios continúan siendo volúmenes provisionales y no fachadas arquitectónicas detalladas.
