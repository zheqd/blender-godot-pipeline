# Contributing

## Development Setup

1. Install [Godot 4.6.0+](https://godotengine.org/download/).
2. Clone this repo and open the project root in Godot.
3. Project Settings → Plugins → enable **glTF Pipeline**.
4. The GUT test framework is vendored in `addons/gut/` — no separate install needed.

## Running Tests

```bash
./run_tests.sh
```

Requires `godot` on `PATH`, or set the `GODOT` env var:

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot ./run_tests.sh
```

All 106 tests (unit + integration) must pass before submitting a PR.

## Authoring Fixtures

Integration tests load `.gltf` fixtures exported from Blender. To add or update a fixture:

1. Install Godot 4.2+ and the paid [Blender-Godot Pipeline addon](https://superhivemarket.com/products/blender-godot-pipeline-addon).
2. Author objects in Blender with the desired `extras` via the addon UI.
3. Export via **File → Export → glTF 2.0**, format: **glTF Separate** (`.gltf` + `.bin`).
4. Commit the `.bin` and `.gltf` files. `.blend` source files are gitignored — they require the paid addon and can be reproduced from the fixture README.
5. Add or update the `README.md` inside the fixture directory documenting the authoring steps.

## Commit Conventions

- Imperative mood: "add", "fix", "remove" — not past tense
- Subject line under 72 characters, no trailing period
- Optional body after a blank line explaining *why*, not what

## Pull Request Requirements

- All tests pass (`./run_tests.sh`)
- Fixtures updated if handler behavior changed
- `CHANGELOG.md` entry added for any user-visible change
- `README.md` behavior table updated if a new extras key is added
