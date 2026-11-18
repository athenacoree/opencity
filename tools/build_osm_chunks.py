#!/usr/bin/env python3
"""Build offline Godot map sectors from OpenStreetMap data.

Run from the repository root:
    python3 tools/build_osm_chunks.py

The importer fetches OSM once during development. The exported game reads only
local JSON files and does not need an internet connection.
"""
from __future__ import annotations

import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "world" / "chunks"
MANIFEST = ROOT / "world" / "manifest.json"
OVERPASS = "https://overpass-api.de/api/interpreter"

# Reference crop envelope from the Güira de Melena map index. It is a search
# envelope, not a substitute for the municipality's administrative polygon.
SOUTH, WEST, NORTH, EAST = 22.54789, -82.569185, 22.850679, -82.430933
ORIGIN_LAT, ORIGIN_LON = 22.7933, -82.5073  # town centre
CHUNK_SIZE = 1000.0
OSM_BOUNDARY_RELATION_ID = 2576652  # Güira de Melena, referenced by Wikimedia Commons


def norm(value: str) -> str:
    import unicodedata
    value = unicodedata.normalize("NFKD", value.casefold())
    return "".join(ch for ch in value if not unicodedata.combining(ch))


def overpass_query() -> str:
    bbox = f"{SOUTH},{WEST},{NORTH},{EAST}"
    return (
        '[out:json][timeout:180];('
        f'relation(id:{OSM_BOUNDARY_RELATION_ID});'
        f'relation["boundary"="administrative"]["admin_level"~"5|6|7"]({bbox});'
        f'way["highway"]({bbox});'
        f'way["building"]({bbox});'
        f'way["landuse"]({bbox});'
        f'way["natural"~"water|wood|scrub|wetland"]({bbox});'
        f'way["waterway"]({bbox});'
        f'way["leisure"]({bbox});'
        f'way["amenity"]({bbox});'
        f'way["shop"]({bbox});'
        f'way["tourism"]({bbox});'
        f'node["amenity"]({bbox});'
        f'node["shop"]({bbox});'
        f'node["tourism"]({bbox});'
        f'node["leisure"]({bbox});'
        f'node["natural"="tree"]({bbox});'
        ');out geom;'
    )


def fetch_osm() -> dict:
    data = urllib.parse.urlencode({"data": overpass_query()}).encode()
    request = urllib.request.Request(
        OVERPASS,
        data=data,
        headers={"User-Agent": "GuiraDeMelenaWorldBuilder/1.0 (offline game map import)"},
    )
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=240) as response:
                return json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last_error = exc
            if attempt == 3:
                break
            delay = 2 ** (attempt + 1)
            print(f"Overpass no respondió ({exc}); nuevo intento en {delay}s...", file=sys.stderr)
            time.sleep(delay)
    raise RuntimeError(f"Overpass no estuvo disponible después de 4 intentos: {last_error}")


def stitch_outer_rings(relation: dict) -> list[list[tuple[float, float]]]:
    segments = []
    for member in relation.get("members", []):
        if member.get("type") != "way" or member.get("role") not in ("outer", ""):
            continue
        geom = member.get("geometry", [])
        line = [(float(p["lon"]), float(p["lat"])) for p in geom]
        if len(line) >= 2:
            segments.append(line)
    rings = []
    while segments:
        ring = segments.pop()
        changed = True
        while changed and ring[0] != ring[-1]:
            changed = False
            for i, candidate in enumerate(segments):
                if ring[-1] == candidate[0]:
                    ring.extend(candidate[1:])
                elif ring[-1] == candidate[-1]:
                    ring.extend(reversed(candidate[:-1]))
                elif ring[0] == candidate[-1]:
                    ring = candidate[:-1] + ring
                elif ring[0] == candidate[0]:
                    ring = list(reversed(candidate[1:])) + ring
                else:
                    continue
                segments.pop(i)
                changed = True
                break
        if len(ring) >= 4 and ring[0] == ring[-1]:
            rings.append(ring)
    return rings


def point_in_polygon(lon: float, lat: float, polygon: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(polygon) - 1
    for i, (xi, yi) in enumerate(polygon):
        xj, yj = polygon[j]
        if ((yi > lat) != (yj > lat)) and (
            lon < (xj - xi) * (lat - yi) / ((yj - yi) or 1e-12) + xi
        ):
            inside = not inside
        j = i
    return inside


def safe_number(value: object, default: float = 1.0) -> float:
    """Parse imperfect OSM height/level tags without aborting the whole import."""
    match = re.search(r"[0-9]+(?:\.[0-9]+)?", str(value or ""))
    if not match:
        return default
    try:
        return float(match.group(0))
    except ValueError:
        return default


def local_xy(lon: float, lat: float) -> tuple[float, float]:
    x = (lon - ORIGIN_LON) * 111320.0 * math.cos(math.radians(ORIGIN_LAT))
    z = (ORIGIN_LAT - lat) * 111320.0
    return round(x, 2), round(z, 2)


def chunk_key(x: float, z: float) -> str:
    return f"{math.floor(x / CHUNK_SIZE)}_{math.floor(z / CHUNK_SIZE)}"

def clip_polygon_to_rect(
    points: list[list[float]], min_x: float, min_z: float, max_x: float, max_z: float
) -> list[list[float]]:
    """Clip an X/Z polygon to one sector rectangle (Sutherland-Hodgman)."""
    polygon = [[float(p[0]), float(p[1])] for p in points if len(p) >= 2]
    if len(polygon) > 1 and polygon[0] == polygon[-1]:
        polygon.pop()

    def clip_edge(poly: list[list[float]], inside, intersect) -> list[list[float]]:
        if not poly:
            return []
        output: list[list[float]] = []
        previous = poly[-1]
        previous_inside = inside(previous)
        for current in poly:
            current_inside = inside(current)
            if current_inside:
                if not previous_inside:
                    output.append(intersect(previous, current))
                output.append(current)
            elif previous_inside:
                output.append(intersect(previous, current))
            previous, previous_inside = current, current_inside
        return output

    def vertical(x_edge: float):
        def intersect(a, b):
            dx = b[0] - a[0]
            t = 0.0 if abs(dx) < 1e-12 else (x_edge - a[0]) / dx
            return [x_edge, a[1] + (b[1] - a[1]) * t]
        return intersect

    def horizontal(z_edge: float):
        def intersect(a, b):
            dz = b[1] - a[1]
            t = 0.0 if abs(dz) < 1e-12 else (z_edge - a[1]) / dz
            return [a[0] + (b[0] - a[0]) * t, z_edge]
        return intersect

    polygon = clip_edge(polygon, lambda p: p[0] >= min_x, vertical(min_x))
    polygon = clip_edge(polygon, lambda p: p[0] <= max_x, vertical(max_x))
    polygon = clip_edge(polygon, lambda p: p[1] >= min_z, horizontal(min_z))
    polygon = clip_edge(polygon, lambda p: p[1] <= max_z, horizontal(max_z))
    if len(polygon) < 3:
        return []
    area = abs(sum(
        polygon[i][0] * polygon[(i + 1) % len(polygon)][1]
        - polygon[(i + 1) % len(polygon)][0] * polygon[i][1]
        for i in range(len(polygon))
    )) * 0.5
    return polygon if area > 0.01 else []




def main() -> int:
    print("Consultando OpenStreetMap para Güira de Melena...")
    try:
        osm = fetch_osm()
    except Exception as exc:
        print(f"No se pudo descargar OSM: {exc}", file=sys.stderr)
        return 2

    elements = osm.get("elements", [])
    # Prefer the municipality relation explicitly referenced by Wikimedia,
    # but still verify its OSM tags before trusting the geometry.
    def is_guira_relation(element: dict) -> bool:
        tags = element.get("tags", {})
        names = " ".join(str(tags.get(k, "")) for k in ("name", "official_name", "name:es", "name:en"))
        return (
            element.get("type") == "relation"
            and tags.get("boundary") == "administrative"
            and (
                element.get("id") == OSM_BOUNDARY_RELATION_ID
                or "guira de melena" in norm(names)
                or tags.get("wikidata") == "Q603115"
            )
        )

    relations = [e for e in elements if is_guira_relation(e)]
    relations.sort(key=lambda r: (r.get("id") != OSM_BOUNDARY_RELATION_ID,
                                  int(r.get("tags", {}).get("admin_level", "99"))))
    boundary_rings: list[list[tuple[float, float]]] = []
    boundary_relation_id = None
    for relation in relations:
        rings = stitch_outer_rings(relation)
        if rings:
            # Keep all disconnected outer components rather than discarding
            # smaller coastal/island pieces of the municipality.
            boundary_rings = rings
            boundary_relation_id = relation["id"]
            break

    def inside_boundary(lon: float, lat: float) -> bool:
        return any(point_in_polygon(lon, lat, ring) for ring in boundary_rings)

    if not boundary_rings:
        print(
            "No se encontró una relación administrativa OSM verificable para el municipio. "
            "No se crearán sectores aproximados como si fueran el límite real. "
            "Comprueba la cobertura OSM y vuelve a ejecutar.",
            file=sys.stderr,
        )
        return 3

    chunks: dict[str, list[dict]] = defaultdict(list)
    seen = set()
    for element in elements:
        tags = element.get("tags", {})
        if element.get("type") == "node":
            natural = tags.get("natural")
            category = next((key for key in ("amenity", "shop", "tourism", "leisure") if tags.get(key)), "")
            if natural != "tree" and not category:
                continue
            lat, lon = float(element["lat"]), float(element["lon"])
            if not inside_boundary(lon, lat):
                continue
            kind = "vegetation" if natural == "tree" else "poi"
            key = chunk_key(*local_xy(lon, lat))
            chunks[key].append({
                "kind": kind, "osm_id": element["id"],
                "points": [list(local_xy(lon, lat))],
                "category": natural if kind == "vegetation" else category,
                "name": tags.get("name", ""),
            })
            continue
        if element.get("type") != "way":
            continue
        geometry = element.get("geometry", [])
        if len(geometry) < 2:
            continue
        highway = tags.get("highway")
        building = tags.get("building")
        landuse = tags.get("landuse")
        natural = tags.get("natural")
        leisure = tags.get("leisure")
        amenity = tags.get("amenity")
        shop = tags.get("shop")
        tourism = tags.get("tourism")
        waterway = tags.get("waterway")
        is_area = bool(landuse or natural in ("water", "wood", "scrub", "wetland") or leisure)
        is_poi = bool(amenity or shop or tourism)
        if not highway and not building and not is_area and not is_poi:
            continue
        coords = [(float(p["lon"]), float(p["lat"])) for p in geometry]
        if building or is_area:
            centre_lon = sum(p[0] for p in coords[:-1] or coords) / len(coords[:-1] or coords)
            centre_lat = sum(p[1] for p in coords[:-1] or coords) / len(coords[:-1] or coords)
            if not inside_boundary(centre_lon, centre_lat):
                continue
            points = [list(local_xy(lon, lat)) for lon, lat in coords]
            xs = [p[0] for p in points]
            zs = [p[1] for p in points]
            key = chunk_key(sum(xs) / len(xs), sum(zs) / len(zs))
            if building:
                feature = {
                    "kind": "building", "osm_id": element["id"], "points": points,
                    "building": building,
                    "levels": safe_number(tags.get("building:levels", 1), 1.0),
                    "height": safe_number(tags.get("height", 0), 0.0),
                }
                if feature["height"] <= 0:
                    feature["height"] = feature["levels"] * 3.2
            elif is_area:
                feature = {
                    "kind": "area", "osm_id": element["id"],
                    "category": landuse or natural or leisure,
                }
                min_chunk_x = math.floor(min(xs) / CHUNK_SIZE)
                max_chunk_x = math.floor(max(xs) / CHUNK_SIZE)
                min_chunk_z = math.floor(min(zs) / CHUNK_SIZE)
                max_chunk_z = math.floor(max(zs) / CHUNK_SIZE)
                for chunk_x in range(min_chunk_x, max_chunk_x + 1):
                    for chunk_z in range(min_chunk_z, max_chunk_z + 1):
                        clipped = clip_polygon_to_rect(
                            points,
                            chunk_x * CHUNK_SIZE, chunk_z * CHUNK_SIZE,
                            (chunk_x + 1) * CHUNK_SIZE, (chunk_z + 1) * CHUNK_SIZE,
                        )
                        if clipped:
                            chunks[f"{chunk_x}_{chunk_z}"].append({
                                **feature, "points": clipped,
                            })
                continue
            elif is_poi:
                chunks[key].append({
                    "kind": "poi", "osm_id": element["id"],
                    "points": [[sum(xs) / len(xs), sum(zs) / len(zs)]],
                    "category": "amenity" if amenity else ("shop" if shop else "tourism"),
                    "name": tags.get("name", ""),
                })
                continue
            chunks[key].append(feature)
        elif highway or waterway:
            for index in range(len(coords) - 1):
                a, b = coords[index], coords[index + 1]
                midpoint = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
                if not inside_boundary(midpoint[0], midpoint[1]):
                    continue
                pa, pb = local_xy(*a), local_xy(*b)
                mx, mz = (pa[0] + pb[0]) * 0.5, (pa[1] + pb[1]) * 0.5
                key = chunk_key(mx, mz)
                signature = (element["id"], index)
                if signature in seen:
                    continue
                seen.add(signature)
                chunks[key].append({
                    "kind": "road" if highway else "waterway", "osm_id": element["id"],
                    "points": [list(pa), list(pb)],
                    "highway": highway or "", "waterway": waterway or "",
                    "name": tags.get("name", ""), "surface": tags.get("surface", ""),
                })

    if not chunks:
        print("La relación se encontró, pero no hay calles ni edificios etiquetados dentro del límite.")
        return 4

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("*.json"):
        old.unlink()
    for key, features in chunks.items():
        (OUT_DIR / f"{key}.json").write_text(
            json.dumps({"chunk": key, "features": features}, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )

    manifest = {
        "schema_version": 1,
        "municipality": "Güira de Melena",
        "province": "Artemisa",
        "country": "Cuba",
        "origin": {"latitude": ORIGIN_LAT, "longitude": ORIGIN_LON},
        "chunk_size_m": CHUNK_SIZE,
        "boundary_verified": True,
        "boundary_source": "OpenStreetMap administrative relation, cross-referenced with Wikimedia Commons",
        "boundary_relation_id": boundary_relation_id,
        "boundary_components": len(boundary_rings),
        "data_source": "© OpenStreetMap contributors",
        "licence": "ODbL 1.0",
        "feature_counts": {
            "chunks": len(chunks),
            "roads": sum(1 for fs in chunks.values() for f in fs if f["kind"] == "road"),
            "buildings": sum(1 for fs in chunks.values() for f in fs if f["kind"] == "building"),
            "areas": sum(1 for fs in chunks.values() for f in fs if f["kind"] == "area"),
            "points_of_interest": sum(1 for fs in chunks.values() for f in fs if f["kind"] == "poi"),
            "trees": sum(1 for fs in chunks.values() for f in fs if f["kind"] == "vegetation"),
            "waterway_segments": sum(1 for fs in chunks.values() for f in fs if f["kind"] == "waterway"),
        },
        "generated_unix": int(time.time()),
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Sectores generados correctamente:")
    print(json.dumps(manifest["feature_counts"], ensure_ascii=False))
    print(f"Datos guardados en: {OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
