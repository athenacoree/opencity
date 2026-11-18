# Güira de Melena – Mundo Abierto

Proyecto de mundo abierto en Godot 4.7, tomando OpenCity como base técnica inicial. El objetivo es construir una representación explorable de Güira de Melena, Artemisa, Cuba, para Android y con funcionamiento offline.

> **Estado actual:** ya están generados e incorporados 158 sectores cartográficos OSM del municipio (2.972 segmentos de carretera, 386 huellas de edificios y 171 áreas). El mapa real está en su primera iteración geométrica; todavía requiere validación visual y de rendimiento en Godot/Android. No hay una APK/AAB verificada.

## Plataforma y dirección
- Objetivo: aplicación Android nativa, no navegador ni PWA.
- Diseño de mundo: visual moderno y realista; no estética de GTA antiguo.
- Render híbrido previsto: 3D para zonas cercanas/explorables y recursos 2D/LOD para el horizonte y zonas lejanas.
- Mundo dividido en sectores para cargar y liberar contenido según la posición.
- Guardado offline de la última posición controlada en el almacenamiento local del dispositivo.
- Persistencia local prevista; no requiere servidor para jugar.

## Abrir el proyecto
Instala Godot 4.7 estándar (sin C#/.NET) y abre esta carpeta desde el editor. El renderer actual se conserva provisionalmente: antes de escoger definitivamente entre Mobile y Compatibility hay que probarlo en los Android objetivo, porque la compatibilidad y la calidad deben medirse en hardware real.

## Controles
En ordenador se mantienen los controles originales:
- WASD: caminar, conducir y volar.
- SHIFT: correr/boost/descender.
- SPACE: saltar/frenar/subir.
- E: entrar o salir de vehículos.
- Ratón: girar cámara.

En dispositivos táctiles se incorpora una primera interfaz en pantalla con cruceta, correr, salto/freno y entrar/salir. Arrastrar sobre el espacio libre de la pantalla gira la cámara. Los controles se adaptan al tamaño del viewport y a ambas orientaciones.

## Arquitectura y plan
Consulta [docs/GUIRA_DE_MELENA_ROADMAP.md](docs/GUIRA_DE_MELENA_ROADMAP.md) para la arquitectura híbrida 2D/3D, el estado del mapa OSM y el streaming offline. Los 158 sectores municipales ya están incluidos en `world/chunks/`; el juego los carga localmente y no descarga mapas al ejecutarse.

## Licencias
Se conserva la licencia MIT del código base. Los recursos de terceros y sus licencias están identificados en [CREDITS.md](CREDITS.md).


### Nuevas capas en desarrollo
El siguiente importador incorpora nodos OSM de puntos de interés (servicios, comercios, turismo y ocio) y árboles etiquetados. Se representan con marcadores 3D ligeros y sus cantidades quedan registradas en el manifiesto. La cobertura depende de los datos existentes en OpenStreetMap; no se generan negocios o árboles ficticios.

Los datos del mapa más recientes incluyen 65 puntos de interés y 49 árboles etiquetados. La última importación detectó 0 tramos lineales de agua etiquetados en el área consultada. Se está ampliando la cobertura de espacios recreativos y cursos de agua OSM; sus cantidades se registrarán en el manifiesto tras la siguiente importación.
