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


def norm(value: str) -> str:
    import unicodedata
    value = unicodedata.normalize("NFKD", value.casefold())
    return "".join(ch for ch in value if not unicodedata.combining(ch))


def overpass_query() -> str:
    bbox = f"{SOUTH},{WEST},{NORTH},{EAST}"
    return (
        '[out:json][timeout:180];('
        f'relation["boundary"="administrative"]["admin_level"~"5|6|7"]({bbox});'
        f'way["highway"]({bbox});'
        f'way["building"]({bbox});'
        f'way["landuse"]({bbox});'
        f'way["natural"~"water|wood|scrub"]({bbox});'
        f'way["waterway"]({bbox});'
        ');out geom;'
    )


def fetch_osm() -> dict:
    data = urllib.parse.urlencode({"data": overpass_query()}).encode()
    request = urllib.request.Request(
        OVERPASS,
        data=data,
        headers={"User-Agent": "GuiraDeMelenaWorldBuilder/1.0 (offline game map import)"},
    )
    with urllib.request.urlopen(request, timeout=240) as response:
        return json.loads(response.read().decode("utf-8"))


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


def local_xy(lon: float, lat: float) -> tuple[float, float]:
    x = (lon - ORIGIN_LON) * 111320.0 * math.cos(math.radians(ORIGIN_LAT))
    z = (ORIGIN_LAT - lat) * 111320.0
    return round(x, 2), round(z, 2)


def chunk_key(x: float, z: float) -> str:
    return f"{math.floor(x / CHUNK_SIZE)}_{math.floor(z / CHUNK_SIZE)}"


def main() -> int:
    print("Consultando OpenStreetMap para Güira de Melena...")
    try:
        osm = fetch_osm()
    except Exception as exc:
        print(f"No se pudo descargar OSM: {exc}", file=sys.stderr)
        return 2

    elements = osm.get("elements", [])
    relations = [
        e for e in elements
        if e.get("type") == "relation"
        and e.get("tags", {}).get("boundary") == "administrative"
        and "guira de melena" in norm(e.get("tags", {}).get("name", ""))
    ]
    boundary = None
    boundary_relation_id = None
    if relations:
        relations.sort(key=lambda r: int(r.get("tags", {}).get("admin_level", "99")))
        for relation in relations:
            rings = stitch_outer_rings(relation)
            if rings:
                boundary = max(rings, key=lambda ring: abs(sum(
                    ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1]
                    for i in range(len(ring) - 1)
                )))
                boundary_relation_id = relation["id"]
                break

    if boundary is None:
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
        if element.get("type") != "way":
            continue
        tags = element.get("tags", {})
        geometry = element.get("geometry", [])
        if len(geometry) < 2:
            continue
        highway = tags.get("highway")
        building = tags.get("building")
        if not highway and not building:
            continue
        coords = [(float(p["lon"]), float(p["lat"])) for p in geometry]
        if building:
            centre_lon = sum(p[0] for p in coords[:-1] or coords) / len(coords[:-1] or coords)
            centre_lat = sum(p[1] for p in coords[:-1] or coords) / len(coords[:-1] or coords)
            if not point_in_polygon(centre_lon, centre_lat, boundary):
                continue
            points = [list(local_xy(lon, lat)) for lon, lat in coords]
            xs = [p[0] for p in points]
            zs = [p[1] for p in points]
            key = chunk_key(sum(xs) / len(xs), sum(zs) / len(zs))
            feature = {
                "kind": "building", "osm_id": element["id"], "points": points,
                "building": building,
                "levels": float(tags.get("building:levels", 1) or 1),
                "height": float(re.sub(r"[^0-9.]", "", tags.get("height", "0")) or 0),
            }
            if feature["height"] <= 0:
                feature["height"] = feature["levels"] * 3.2
            chunks[key].append(feature)
        elif highway:
            for index in range(len(coords) - 1):
                a, b = coords[index], coords[index + 1]
                midpoint = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
                if not point_in_polygon(midpoint[0], midpoint[1], boundary):
                    continue
                pa, pb = local_xy(*a), local_xy(*b)
                mx, mz = (pa[0] + pb[0]) * 0.5, (pa[1] + pb[1]) * 0.5
                key = chunk_key(mx, mz)
                signature = (element["id"], index)
                if signature in seen:
                    continue
                seen.add(signature)
                chunks[key].append({
                    "kind": "road", "osm_id": element["id"],
                    "points": [list(pa), list(pb)], "highway": highway,
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
        "boundary_source": "OpenStreetMap administrative relation",
        "boundary_relation_id": boundary_relation_id,
        "data_source": "© OpenStreetMap contributors",
        "licence": "ODbL 1.0",
        "feature_counts": {
            "chunks": len(chunks),
            "roads": sum(1 for fs in chunks.values() for f in fs if f["kind"] == "road"),
            "buildings": sum(1 for fs in chunks.values() for f in fs if f["kind"] == "building"),
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
