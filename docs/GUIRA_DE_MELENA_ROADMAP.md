# Güira de Melena – Mundo Abierto
## Base técnica y plan de conversión de OpenCity

Este documento separa lo que ya existe de lo que todavía debe construirse. OpenCity es únicamente la base jugable: su ciudad actual es procedural y de geometría provisional. **Todavía no representa el municipio real de Güira de Melena.**

## Objetivo
- Juego nativo Android instalable como APK/AAB; no navegador, PWA ni servidor.
- Mundo explorable inspirado en Güira de Melena, Artemisa, Cuba.
- Funcionamiento offline y progreso guardado en el dispositivo.
- Adaptación a teléfonos de gama baja/media-baja y orientación vertical u horizontal.
- Mundo abierto moderno y realista, sin estética retro.

## Arquitectura visual híbrida
1. **3D cercano:** calles transitables, aceras, edificios importantes, parques, plazas, interiores accesibles, vehículos y personajes.
2. **2D y geometría simplificada distante:** horizonte, campos, vegetación lejana, fachadas de fondo y zonas que no requieren exploración.
3. **Transiciones invisibles:** impostores/atlas para objetos lejanos y sustitución gradual por modelos 3D.
4. **LOD:** varias versiones de edificios, árboles y objetos; colisiones sólo en elementos próximos y relevantes.
5. **Streaming por sectores:** dividir el mapa en celdas; cargar el sector actual y un anillo vecino, liberar sectores lejanos. Los datos permanecen locales.
6. **Presupuestos móviles:** limitar luces dinámicas, sombras, transparencias, densidad de peatones/tráfico y resolución de sombras según el dispositivo.

## Estructura de datos propuesta
- world/manifest.json: límites, tamaño de sector, origen y versión del mapa.
- world/chunks/<x>_<z>.tres: edificios, carreteras, props, puntos de interés y referencias.
- world/poi/: parques, comercios, servicios y lugares reconocibles.
- assets/buildings/, assets/vegetation/, assets/roads/, assets/props/: recursos optimizados.
- Cada entidad tendrá ID estable, posición, orientación, categoría, LOD y datos de colisión.

## Fases
### 1. Base Android
- Controles táctiles para caminar, conducir, saltar/frenar, correr y entrar/salir.
- Cámara orbital mediante arrastre táctil.
- Interfaz adaptable a tamaños y orientaciones.
- Prueba real en Android antes de decidir definitivamente el renderer y la calidad gráfica.

### 2. Mapa real
- Conseguir y verificar una fuente cartográfica utilizable para calles, manzanas y caminos.
- Construir el trazado municipal y dividirlo en sectores.
- Revisar escala, nombres, cruces, barrios y puntos de interés; no presentar la ciudad procedural como si fuera el municipio real.
- Añadir modelos 3D y texturas optimizadas.

### 3. Rendimiento y persistencia
- LOD, culling, carga/descarga de sectores y colisiones por proximidad.
- Perfiles gráficos bajo/medio/alto.
- Guardado local versionado: posición, vehículo, ajustes y progreso; escritura segura y recuperación ante archivos dañados.

### 4. Contenido
- Ciclo día/noche y clima ligero.
- Interiores seleccionados, comercios, parques y actividades.
- Sonido ambiental y de vehículos, misiones y actividades opcionales.

## Estado de esta entrega
- Se incorpora una primera capa de controles táctiles que reutiliza la entrada de teclado existente.
- Se incorpora giro de cámara mediante arrastre táctil.
- Se documenta la arquitectura híbrida y el plan de mapa/streaming.
- Aún no hay mapa municipal real, APK/AAB verificada ni prueba de rendimiento en un teléfono. No debe anunciarse como terminado hasta validar esas partes.
