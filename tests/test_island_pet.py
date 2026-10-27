import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
ISLAND = (ROOT / "island/Island.qml").read_text()
STATES = {
    name: (ROOT / "island/states" / f"{name}.qml").read_text()
    for name in ("Idle", "Music", "Notify", "Alert")
}


class IslandPetContractTests(unittest.TestCase):
    """Static seams for the island mascot; pose playback is tested in JavaScript."""

    def test_core_owns_skin_source_and_one_shared_clock(self):
        self.assertIn('readonly property string petConfigPath', ISLAND)
        self.assertIn("/quickshell/pet.json", ISLAND)
        self.assertIn('property string petSkin: "cat"', ISLAND)
        self.assertIn("property double petTick: 0", ISLAND)
        self.assertIn("readonly property bool petAnimating", ISLAND)
        self.assertEqual(ISLAND.count("interval: 125"), 1)
        self.assertIn("running: root.petAnimating", ISLAND)
        self.assertIn("root.petTick += 1", ISLAND)

    def test_states_use_existing_data_without_desktop_pet_components(self):
        self.assertIn('pose: "sleep"', STATES["Idle"])
        self.assertIn("st.visible ? st.core.petTick : 0", STATES["Idle"])
        self.assertIn('st.core.playing ? "groove" : "sit"', STATES["Music"])
        self.assertIn("st.visible && !st.expanded && st.core.playing ? st.core.petTick : 0",
                      STATES["Music"])
        self.assertIn("PetFx.waving", STATES["Notify"])
        self.assertIn("item.ts === wavedTs", STATES["Notify"])
        self.assertIn("st.visible && st.petWaving ? st.core.petTick : 0", STATES["Notify"])
        self.assertIn("PetFx.jumping", STATES["Alert"])
        self.assertIn("PetFx.lift", STATES["Alert"])
        self.assertIn("st.visible && st.petJumping ? st.core.petTick : 0", STATES["Alert"])
        self.assertIn("firstKey", STATES["Alert"])

    def test_pet_is_present_in_every_target_view(self):
        self.assertIn("Canvas {", STATES["Idle"])
        self.assertGreaterEqual(STATES["Music"].count("PixelPet {"), 1)
        self.assertGreaterEqual(STATES["Notify"].count("PixelPet {"), 2)
        self.assertGreaterEqual(STATES["Alert"].count("PixelPet {"), 3)

    def test_no_duplicate_pet_runtime_or_notification_server(self):
        combined = "\n".join(STATES.values())
        for forbidden in ("PetWindow", "PetBrain", "PetSprite.qml", "Pet.qml",
                          "NotificationServer", "../../pet/"):
            self.assertNotIn(forbidden, combined)
        self.assertNotIn("interval: 125", combined)

    def test_sprite_mirror_is_local_and_same_engine(self):
        mirror = (ROOT / "island/states/PetSprites.js").read_text()
        source = (ROOT / "pet/PetSprites.js").read_text()
        self.assertIn("Island-local mirror", mirror)
        self.assertEqual(mirror.split("// Pixel sprite engine", 1)[1],
                         source.split("// Pixel sprite engine", 1)[1])


if __name__ == "__main__":
    unittest.main()
