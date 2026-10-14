# GPS Desktop

A custom CachyOS + Hyprland desktop shell built with QuickShell 0.3.2, Qt Quick and QML.

## Current Status

**Phase 0 complete** — Working starter panel committed at `140e10c`.
- GPS brand mark, tagline, live clock and date
- Loads under QuickShell 0.3.2 without Qt mismatch warning
- Manual launch only; no autostart configured

## Quick Start

```bash
cd ~/Projects/my-rice
qs -p shell.qml
```

## Development Workflow

### Run with Logs
```bash
qs -p shell.qml 2>&1 | tee ~/gps-dev.log
```

### Hot Reload
Edit any `.qml` file and save — QuickShell reloads automatically.

### Memory Check
```bash
ps -o rss= -p $(pgrep -f "qs.*shell.qml")
```

### Git Checkpoint (per task)
```bash
git diff --check          # verify no whitespace errors
git diff                  # review changes
git add -A
git commit -m "type(scope): description"
```

### Rollback
```bash
git reset --hard HEAD~1   # undo last commit
git stash list            # preserved WIP battery experiment (do not pop)
```

## Environment

| Component | Version |
|-----------|---------|
| QuickShell | 0.3.2 (AUR `quickshell-git`) |
| Hyprland | 0.56.2 |
| Qt | 6.x (system) |
| Shell | Fish 4.9.3 |
| Display | 1920×1200 @ 1.5 scale (1280×800 logical) |

## Constraints

- Develop as unprivileged `rice` user only
- No sudo, no system package changes
- Do not modify `guru` account or shared Hyprland config
- Preserve existing git stash (`WIP: unreviewed GPS battery card experiment`)
- GPS remains manually launched until recovery tested

## Project Structure (completed)

The following components have been extracted from `shell.qml` into the `components/` directory:

- `GpsPanel.qml` — `PanelWindow` with `BrandMark` + `ClockCard` composition (extracted in commit `194df20`)
- `BrandMark.qml` — GPS emblem + tagline (extracted in commit `641bb75`)
- `ClockCard.qml` — clock (hh:mm) + date (ddd, dd MMM) (extracted in commit `5865ca6`)

The root `shell.qml` now instantiates `GpsPanel` only.

```
my-rice/
├── shell.qml              # entry point: imports qs.components; instantiates GpsPanel
├── README.md
├── CHANGELOG.md
├── ROADMAP.md
├── TODO.md
├── WIREFRAME.md
├── config/
│   └── Theme.qml          # design tokens (Singleton)
└── components/
    ├── GpsPanel.qml
    ├── BrandMark.qml
    └── ClockCard.qml
```

## References

- [QuickShell Documentation](https://quickshell.outfoxxed.me/)
- [ROADMAP.md](./ROADMAP.md) — full project plan
- [TODO.md](./TODO.md) — immediate checklist
- [WIREFRAME.md](./WIREFRAME.md) — visual layout (draft)