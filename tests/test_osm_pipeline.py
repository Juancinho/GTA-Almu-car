import importlib.util
import math
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location("osm_pipeline", Path(__file__).resolve().parents[1] / "tools/world/osm_pipeline.py")
osm = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(osm)


class CoordinateTests(unittest.TestCase):
    def test_origin_and_axis_direction(self):
        self.assertEqual(osm.to_local(osm.ORIGIN_LAT, osm.ORIGIN_LON), (0.0, -0.0))
        self.assertGreater(osm.to_local(osm.ORIGIN_LAT, osm.ORIGIN_LON + 0.001)[0], 80)
        self.assertLess(osm.to_local(osm.ORIGIN_LAT + 0.001, osm.ORIGIN_LON)[1], -100)

    def test_roundtrip_and_metric_scale(self):
        lat, lon = 36.7323, -3.6912
        x, z = osm.to_local(lat, lon)
        recovered = osm.to_geo(x, z)
        self.assertLess(math.dist((lat, lon), recovered), 1e-10)

    def test_conversion_categories_and_simplification(self):
        raw = {"osm3s": {"timestamp_osm_base": "2026-09-29T00:00:00Z"}, "elements": [
            {"type": "way", "id": 1, "tags": {"highway": "residential", "name": "Test"}, "geometry": [
                {"lat": 36.731, "lon": -3.691}, {"lat": 36.731, "lon": -3.6909}, {"lat": 36.731, "lon": -3.6908}]},
            {"type": "way", "id": 2, "tags": {"building": "yes"}, "geometry": [
                {"lat": 36.731, "lon": -3.691}, {"lat": 36.731, "lon": -3.6909},
                {"lat": 36.7311, "lon": -3.6909}, {"lat": 36.7311, "lon": -3.691},
                {"lat": 36.731, "lon": -3.691}]},
        ]}
        result = osm.convert(raw, "abc")
        self.assertEqual(result["counts"], {"road": 1, "building": 1})
        self.assertEqual(len(result["features"][0]["points_xz_m"]), 2)
        self.assertTrue(result["features"][1]["closed"])
        self.assertGreaterEqual(len(result["features"][1]["points_xz_m"]), 3)


if __name__ == "__main__":
    unittest.main()
