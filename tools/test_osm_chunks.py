import unittest
import json
from pathlib import Path
import urllib.error
from unittest.mock import MagicMock, patch

import build_osm_chunks as importer


class OSMImporterTests(unittest.TestCase):
    def test_cuban_story_starts_at_hospital_and_has_safe_mission_paths(self):
        config_path = Path(__file__).resolve().parents[1] / "world" / "cuba_life_config.json"
        config = json.loads(config_path.read_text(encoding="utf-8"))
        missions = config["story"]["missions"]
        self.assertEqual(missions[0]["id"], "hospital_news")
        self.assertEqual(missions[1]["id"], "friend_arrives")
        self.assertEqual(missions[2]["id"], "rental_motorbike")
        self.assertTrue(config["story"]["branches"])

    def test_power_outages_are_configured_at_block_scale(self):
        config_path = Path(__file__).resolve().parents[1] / "world" / "cuba_life_config.json"
        config = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(config["world"]["outage_block_size_m"], 100)
        self.assertGreaterEqual(config["world"]["outage_share_of_blocks"], 0.0)

    def test_cuban_life_config_has_local_economy_and_currency(self):
        config_path = Path(__file__).resolve().parents[1] / "world" / "cuba_life_config.json"
        config = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(config["world"]["municipality"], "Güira de Melena")
        self.assertEqual(config["economy"]["currency"], "CUP")
        self.assertGreater(config["world"]["base_exchange_cup_per_usd"], 0)
        self.assertTrue(config["economy"]["jobs"])
        self.assertTrue(config["economy"]["products"])

    def test_cuban_life_config_includes_house_vehicle_and_story_choices(self):
        config_path = Path(__file__).resolve().parents[1] / "world" / "cuba_life_config.json"
        config = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(config["houses"]), 3)
        vehicle_names = {item["name"] for item in config["vehicles"]}
        self.assertIn("Lada 2107", vehicle_names)
        self.assertIn("Kia Picanto", vehicle_names)
        self.assertIn("Bicicleta", vehicle_names)
        self.assertTrue(config["story"]["intro"])
        self.assertGreaterEqual(len(config["story"]["missions"]), 4)

    def test_fetch_osm_retries_temporary_http_errors(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.read.return_value = b'{"elements": []}'
        temporary_error = urllib.error.HTTPError(
            importer.OVERPASS, 502, "Bad Gateway", None, None
        )
        with patch.object(
            importer.urllib.request, "urlopen", side_effect=[temporary_error, response]
        ), patch.object(importer.time, "sleep") as sleep:
            self.assertEqual(importer.fetch_osm(), {"elements": []})
        sleep.assert_called_once_with(2)

    def test_private_residential_names_are_not_exported(self):
        for kind in ("house", "residential", "detached", "semidetached_house", "bungalow"):
            self.assertEqual(
                importer.public_building_label({"building": kind, "name": "Nombre privado"}),
                "",
            )

    def test_public_names_fall_back_to_spanish_and_official_names(self):
        self.assertEqual(
            importer.preferred_public_name({"name:es": "Escuela de Güira"}),
            "Escuela de Güira",
        )
        self.assertEqual(
            importer.preferred_public_name({"official_name": "Nombre Oficial"}),
            "Nombre Oficial",
        )
        self.assertEqual(
            importer.preferred_public_name({"short_name": "Centro"}),
            "Centro",
        )
        self.assertEqual(importer.preferred_public_name({"operator": "Persona particular"}), "")

    def test_named_public_buildings_are_exported(self):
        self.assertEqual(
            importer.public_building_label({
                "building": "yes", "amenity": "school", "name": "Escuela Pública"
            }),
            "Escuela Pública",
        )
        self.assertEqual(
            importer.public_building_label({
                "building": "school", "name": "Centro Escolar"
            }),
            "Centro Escolar",
        )

    def test_public_place_categories_include_healthcare_and_workplaces(self):
        self.assertEqual(importer.public_place_category({"healthcare": "clinic"}), "healthcare")
        self.assertEqual(importer.public_place_category({"office": "government"}), "office")
        self.assertEqual(importer.public_place_category({"craft": "carpenter"}), "craft")

    def test_public_place_categories_include_education_and_community_services(self):
        self.assertEqual(importer.public_place_category({"education": "school"}), "education")
        self.assertEqual(importer.public_place_category({"public_transport": "platform"}), "public_transport")
        self.assertEqual(importer.public_place_category({"social_facility": "day_care"}), "social_facility")
        self.assertEqual(importer.public_place_category({"emergency": "fire_station"}), "emergency")

    def test_overpass_query_requests_public_service_categories(self):
        query = importer.overpass_query()
        for tag in ("education", "public_transport", "social_facility", "emergency"):
            self.assertIn(f'["{tag}"]', query)

    def test_safe_number_handles_messy_osm_tags(self):
        self.assertEqual(importer.safe_number("2;3", 1.0), 2.0)
        self.assertEqual(importer.safe_number("12 m", 0.0), 12.0)
        self.assertEqual(importer.safe_number("3.5 m", 0.0), 3.5)
        self.assertEqual(importer.safe_number("2.75", 0.0), 2.75)
        self.assertEqual(importer.safe_number("unknown", 4.0), 4.0)

    def test_point_features_are_added_to_the_correct_chunk(self):
        x, z = importer.local_xy(importer.ORIGIN_LON, importer.ORIGIN_LAT)
        self.assertEqual(importer.chunk_key(x, z), "0_0")

    def test_polygon_poi_uses_centroid_in_expected_sector(self):
        points = [[100, 100], [200, 100], [200, 200], [100, 200]]
        centre = [sum(p[0] for p in points) / len(points),
                  sum(p[1] for p in points) / len(points)]
        self.assertEqual(centre, [150.0, 150.0])
        self.assertEqual(importer.chunk_key(*centre), "0_0")

    def test_area_polygon_is_clipped_into_each_overlapped_chunk(self):
        polygon = [[900, 100], [1100, 100], [1100, 300], [900, 300]]
        west = importer.clip_polygon_to_rect(polygon, 0, 0, 1000, 1000)
        east = importer.clip_polygon_to_rect(polygon, 1000, 0, 2000, 1000)
        self.assertEqual(len(west), 4)
        self.assertEqual(len(east), 4)
        self.assertEqual(min(p[0] for p in west), 900)
        self.assertEqual(max(p[0] for p in west), 1000)
        self.assertEqual(min(p[0] for p in east), 1000)
        self.assertEqual(max(p[0] for p in east), 1100)

    def test_polygon_outside_sector_is_empty(self):
        polygon = [[1100, 100], [1200, 100], [1200, 200], [1100, 200]]
        self.assertEqual(
            importer.clip_polygon_to_rect(polygon, 0, 0, 1000, 1000), []
        )

    def test_point_in_polygon(self):
        square = [(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0), (0.0, 0.0)]
        self.assertTrue(importer.point_in_polygon(1.0, 1.0, square))
        self.assertFalse(importer.point_in_polygon(3.0, 1.0, square))

    def test_local_origin_is_zero(self):
        self.assertEqual(importer.local_xy(importer.ORIGIN_LON, importer.ORIGIN_LAT), (0.0, 0.0))

    def test_chunk_key_handles_negative_coordinates(self):
        self.assertEqual(importer.chunk_key(-0.1, -1000.1), "-1_-2")
        self.assertEqual(importer.chunk_key(1000.0, 0.0), "1_0")

    def test_stitch_outer_rings_joins_reversed_segments(self):
        relation = {
            "members": [
                {"type": "way", "role": "outer", "geometry": [
                    {"lon": 1.0, "lat": 0.0}, {"lon": 1.0, "lat": 1.0}
                ]},
                {"type": "way", "role": "outer", "geometry": [
                    {"lon": 0.0, "lat": 0.0}, {"lon": 1.0, "lat": 0.0}
                ]},
                {"type": "way", "role": "outer", "geometry": [
                    {"lon": 0.0, "lat": 1.0}, {"lon": 0.0, "lat": 0.0}
                ]},
                {"type": "way", "role": "outer", "geometry": [
                    {"lon": 1.0, "lat": 1.0}, {"lon": 0.0, "lat": 1.0}
                ]},
            ]
        }
        rings = importer.stitch_outer_rings(relation)
        self.assertEqual(len(rings), 1)
        self.assertEqual(rings[0][0], rings[0][-1])
        self.assertEqual(len(rings[0]), 5)


if __name__ == "__main__":
    unittest.main()
