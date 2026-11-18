import unittest

import build_osm_chunks as importer


class OSMImporterTests(unittest.TestCase):
    def test_safe_number_handles_messy_osm_tags(self):
        self.assertEqual(importer.safe_number("2;3", 1.0), 2.0)
        self.assertEqual(importer.safe_number("12 m", 0.0), 12.0)
        self.assertEqual(importer.safe_number("unknown", 4.0), 4.0)

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
