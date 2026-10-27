# Desktop pet (QuickShell 0.3.2, Hyprland)

Copy this folder next to your shell.qml as `pet/`, then:

```qml
import "pet"
// inside ShellRoot:
Pet { id: pet }
```

Settings are saved to `~/.config/quickshell/pet.json`.
Control panel: double-click or right-click the pet, or `qs -p <path> ipc call pet panel`.
Float rule for the panel: match window title `Pet Companion`.

## Files
- Pet.qml            root scope, IPC target `pet`, hooks
- PetBrain.qml       physics + behaviour (tested)
- PetGeometry.js     hyprctl JSON -> ledges (tested)
- PetWorld.qml       polls hyprctl: monitor, windows, cursor
- PetWindow.qml      click-through overlay, dragging, effects
- PetPanel.qml       control panel (+ PetCard/Toggle/Slider/Chip/Theme)
- PetSprites.js, PetSprite.qml   pixel art engine, 7 skins, 11 poses
- PetSettings.qml    JSON persistence
- tests/brain_test.qml

## Hooks into the rest of your shell
- `pet.wave()`            when a notification toast appears
- `pet.alert(true)` / `pet.clear()`   agent permission asked / answered
  (or from your pet-alert script: `qs -p <path> ipc call pet alert true` / `... clear`)
- `pet.perch = { enabled: true, x1: .., x2: .., y: .. }`   island top edge, logical px, optional

## IPC (target `pet`)
panel toggle wave dance hop nap respawn callHere perch alert <bool> clear skin <id> status
Skin ids: cat shadow snow fox robot slime ghost
