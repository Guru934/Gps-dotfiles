"""Unit and contract tests for brightness calculation and controller interface.

Authoritative requirements:
- R4: Automated test for percent calculation covering raw 450 of 900 = 50%,
  rounding behavior (191 of 254 = 75%, 221 of 254 = 87%, 0.49 vs 0.50 boundaries),
  and zero max handling (max = 0 produces 0%, avoiding division by zero).
- Contract verification for config/Brightness.qml singleton and config/qmldir.
- Dynamic evaluation of config/Brightness.qml JavaScript via Node.js runtime.
"""

import json
import math
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_DIR = ROOT / "config"
BRIGHTNESS_QML_PATH = CONFIG_DIR / "Brightness.qml"
QMLDIR_PATH = CONFIG_DIR / "qmldir"


def calc_percent(current, max_val):
    """Reference implementation matching JavaScript Math.round((current / max) * 100).

    Semantics:
    1. If max <= 0 or non-numeric/null/NaN, return 0.
    2. If current <= 0 or non-numeric/null/NaN, return 0.
    3. If current >= max, return 100.
    4. Otherwise, compute (current / max) * 100 with standard arithmetic
       half-up rounding (matching JavaScript Math.round), clamped to [0, 100].
    """
    try:
        if current is None or max_val is None:
            return 0
        c = float(current)
        m = float(max_val)
    except (ValueError, TypeError):
        return 0

    if math.isnan(m) or m <= 0:
        return 0
    if math.isnan(c) or c <= 0:
        return 0
    if c >= m:
        return 100

    ratio = (c / m) * 100.0
    # Standard arithmetic half-up rounding (matching JS Math.round)
    pct = int(math.floor(ratio + 0.5))
    return max(0, min(100, pct))


class BrightnessCalculationTests(unittest.TestCase):
    """Pure mathematical unit tests for brightness percentage calculation."""

    def test_raw_450_of_900_is_50_percent(self):
        """Nominal case: exactly half scale produces 50%."""
        self.assertEqual(calc_percent(450, 900), 50)

    def test_nominal_boundaries(self):
        """Zero and full scale under normal positive max."""
        self.assertEqual(calc_percent(0, 900), 0)
        self.assertEqual(calc_percent(900, 900), 100)
        self.assertEqual(calc_percent(1, 2), 50)
        self.assertEqual(calc_percent(100, 100), 100)

    def test_rounding_behavior_real_hardware_values(self):
        """Real hardware values observed during audit on nvidia_wmi_ec_backlight.

        - 191 of 254 = 75.19685% -> 75% (matches brightnessctl -m column 4)
        - 221 of 254 = 87.00787% -> 87% (matches actual_brightness ratio)
        """
        self.assertEqual(calc_percent(191, 254), 75)
        self.assertEqual(calc_percent(221, 254), 87)

    def test_rounding_boundaries_0_49_vs_0_50(self):
        """Boundary test: 0.49% rounds to 0%, 0.50% rounds to 1%."""
        # 49 / 10000 = 0.0049 -> 0.49% -> rounds down to 0%
        self.assertEqual(calc_percent(49, 10000), 0)
        # 50 / 10000 = 0.0050 -> 0.50% -> rounds up to 1%
        self.assertEqual(calc_percent(50, 10000), 1)

        # 1 / 201 = 0.004975 -> 0.4975% -> rounds down to 0%
        self.assertEqual(calc_percent(1, 201), 0)
        # 1 / 200 = 0.005000 -> 0.5000% -> rounds up to 1%
        self.assertEqual(calc_percent(1, 200), 1)

    def test_rounding_half_up_midpoints(self):
        """Standard half-up rounding across various midpoints (.4 vs .5)."""
        # 49.4% -> 49%, 49.5% -> 50%
        self.assertEqual(calc_percent(494, 1000), 49)
        self.assertEqual(calc_percent(495, 1000), 50)

        # 50.4% -> 50%, 50.5% -> 51%
        self.assertEqual(calc_percent(504, 1000), 50)
        self.assertEqual(calc_percent(505, 1000), 51)

        # Eighths: .5 midpoints
        self.assertEqual(calc_percent(1, 8), 13)   # 12.5% -> 13
        self.assertEqual(calc_percent(3, 8), 38)   # 37.5% -> 38
        self.assertEqual(calc_percent(5, 8), 63)   # 62.5% -> 63
        self.assertEqual(calc_percent(7, 8), 88)   # 87.5% -> 88

    def test_zero_max_handling_avoids_division_by_zero(self):
        """When max = 0, calculation safely returns 0% without error or NaN."""
        self.assertEqual(calc_percent(0, 0), 0)
        self.assertEqual(calc_percent(50, 0), 0)
        self.assertEqual(calc_percent(100, 0), 0)
        self.assertEqual(calc_percent(-10, 0), 0)

    def test_negative_max_handling(self):
        """Negative max values must return 0%."""
        self.assertEqual(calc_percent(50, -100), 0)
        self.assertEqual(calc_percent(0, -1), 0)
        self.assertEqual(calc_percent(-50, -50), 0)

    def test_negative_current_clamping(self):
        """Negative current values must be clamped to 0%."""
        self.assertEqual(calc_percent(-1, 100), 0)
        self.assertEqual(calc_percent(-50, 100), 0)
        self.assertEqual(calc_percent(-999, 100), 0)

    def test_out_of_range_overshoot_clamping(self):
        """Values exceeding max brightness must be clamped to 100%."""
        self.assertEqual(calc_percent(101, 100), 100)
        self.assertEqual(calc_percent(150, 100), 100)
        self.assertEqual(calc_percent(1000, 900), 100)
        self.assertEqual(calc_percent(9999, 254), 100)

    def test_string_and_invalid_inputs(self):
        """String numeric inputs (from CSV / brightnessctl output) and invalid tokens."""
        self.assertEqual(calc_percent("450", "900"), 50)
        self.assertEqual(calc_percent("191", "254"), 75)
        self.assertEqual(calc_percent("0", "100"), 0)
        self.assertEqual(calc_percent(None, 100), 0)
        self.assertEqual(calc_percent(50, None), 0)
        self.assertEqual(calc_percent("invalid", 100), 0)
        self.assertEqual(calc_percent(50, "invalid"), 0)
        self.assertEqual(calc_percent(float("nan"), 900), 0)
        self.assertEqual(calc_percent(450, float("nan")), 0)


class BrightnessQmlContractTests(unittest.TestCase):
    """Static checks verifying config/Brightness.qml and config/qmldir conform to architecture."""

    def setUp(self):
        if not BRIGHTNESS_QML_PATH.is_file():
            self.skipTest(f"{BRIGHTNESS_QML_PATH} does not exist yet.")
        self.qml = BRIGHTNESS_QML_PATH.read_text()
        self.qmldir = QMLDIR_PATH.read_text() if QMLDIR_PATH.is_file() else ""

    def test_qmldir_registration(self):
        """config/qmldir must register the Brightness singleton."""
        self.assertIn("singleton Brightness 1.0 Brightness.qml", self.qmldir)

    def test_singleton_declaration(self):
        """Brightness.qml must be declared as a singleton."""
        self.assertIn("pragma Singleton", self.qml)
        self.assertRegex(self.qml, r"Singleton\s*\{")

    def test_public_properties_interface(self):
        """Brightness.qml must expose required properties."""
        self.assertRegex(self.qml, r"property\s+int\s+percent\b")
        self.assertRegex(self.qml, r"property\s+bool\s+available\b")
        self.assertRegex(self.qml, r"property\s+string\s+device\b")
        self.assertRegex(self.qml, r"property\s+int\s+currentBrightness\b")
        self.assertRegex(self.qml, r"property\s+int\s+maxBrightness\b")

    def test_public_methods_interface(self):
        """Brightness.qml must expose calcPercent, setPercent, step, and refresh."""
        self.assertIn("function calcPercent(", self.qml)
        self.assertIn("function setPercent(", self.qml)
        self.assertIn("function step(", self.qml)
        self.assertIn("function refresh(", self.qml)

    def test_no_hardcoded_paths_or_devices(self):
        """Ensure no hardcoded usernames, home directories, or specific device strings."""
        self.assertNotIn("/home/", self.qml)
        self.assertNotIn("nvidia_wmi_ec_backlight", self.qml)
        self.assertNotIn("intel_backlight", self.qml)
        self.assertNotIn("amdgpu_bl", self.qml)

    def test_polling_and_safety_seams(self):
        """Verify periodic polling and failure handling exist."""
        self.assertIn("Timer", self.qml)
        self.assertIn("interval:", self.qml)
        self.assertIn("available", self.qml)


class BrightnessQmlEvaluatorTests(unittest.TestCase):
    """Dynamic tests evaluating the exact JavaScript function extracted from Brightness.qml."""

    @classmethod
    def setUpClass(cls):
        if not BRIGHTNESS_QML_PATH.is_file():
            raise unittest.SkipTest(f"{BRIGHTNESS_QML_PATH} does not exist yet.")
        if not shutil.which("node"):
            raise unittest.SkipTest("Node.js runtime not found; skipping dynamic JS evaluation.")

        qml = BRIGHTNESS_QML_PATH.read_text()
        match = re.search(r"(function\s+calcPercent\s*\([^)]*\)\s*\{(?:[^{}]*|\{[^{}]*\})*\})", qml)
        if not match:
            raise unittest.SkipTest("calcPercent function not found in config/Brightness.qml")
        cls.calc_percent_js = match.group(1)

    def eval_js(self, current, max_val):
        driver = f"""
{self.calc_percent_js}
const res = calcPercent({json.dumps(current)}, {json.dumps(max_val)});
console.log(JSON.stringify(res));
"""
        proc = subprocess.run(["node", "-e", driver], capture_output=True, text=True, check=True)
        return json.loads(proc.stdout.strip())

    def test_js_raw_450_of_900_is_50(self):
        self.assertEqual(self.eval_js(450, 900), 50)

    def test_js_rounding_hardware_values(self):
        self.assertEqual(self.eval_js(191, 254), 75)
        self.assertEqual(self.eval_js(221, 254), 87)

    def test_js_rounding_boundaries(self):
        self.assertEqual(self.eval_js(49, 10000), 0)
        self.assertEqual(self.eval_js(50, 10000), 1)
        self.assertEqual(self.eval_js(1, 201), 0)
        self.assertEqual(self.eval_js(1, 200), 1)
        self.assertEqual(self.eval_js(494, 1000), 49)
        self.assertEqual(self.eval_js(495, 1000), 50)
        self.assertEqual(self.eval_js(504, 1000), 50)
        self.assertEqual(self.eval_js(505, 1000), 51)

    def test_js_zero_and_negative_max(self):
        self.assertEqual(self.eval_js(0, 0), 0)
        self.assertEqual(self.eval_js(50, 0), 0)
        self.assertEqual(self.eval_js(50, -100), 0)

    def test_js_clamping_bounds(self):
        self.assertEqual(self.eval_js(-10, 100), 0)
        self.assertEqual(self.eval_js(150, 100), 100)
        self.assertEqual(self.eval_js(0, 100), 0)
        self.assertEqual(self.eval_js(100, 100), 100)


if __name__ == "__main__":
    unittest.main()
