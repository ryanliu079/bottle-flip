# Bottle Flip

A native iPhone game controlled with a small wrist flick. Flip a 3D bottle, land it upright, and work through 120 stages across the Everyday World, Water Kingdom and Ice Kingdom. Different liquids, changing fill levels and increasingly precise landings keep each chapter interesting, with scenery, music and haptic feedback to match.

Featured in [OxAIMS — Apps and games](https://oxaims.org/project/app_games#bottle-flip).

## What is in the game?

- Motion controls for flips toward or away from you. Keep hold of your phone throughout.
- Three worlds, twelve chapters and 120 stages, including a guided 20-stage tutorial.
- A live RealityKit bottle with custom Metal shading, liquid visuals and a SpriteKit landing model.
- Water, juice and wine with different gameplay behaviour, plus assistance after repeated misses.
- Coins, unlockable bottle and table finishes, a stage map and saved offline progress.
- 36 bundled soundtrack arrangements, recorded slosh/landing effects and haptic feedback.
- No account, network connection, ads or real-money purchases required during play.

This is an iOS prototype built with SwiftUI, RealityKit, SpriteKit and Core Motion. It is available here as source; there is no App Store release or browser-playable version. The liquid and flight models are gameplay approximations rather than a full fluid simulation.

## Run on an iPhone

Requires a Mac, Xcode with support for your device, and an iPhone running iOS 17 or later.

1. Clone this repository and open `BottleFlip.xcodeproj`.
2. In **Signing & Capabilities**, choose your own Apple development team. No signing credentials are included.
3. Connect and unlock your iPhone, trust the Mac, and enable Developer Mode if requested.
4. Select the iPhone as the destination and press **Run**.
5. Wait for **Ready to flick**, then make a small wrist flick while keeping the phone in your hand.

The bundled music and scenery make the checkout roughly 360 MB. All runtime assets are included; no asset download or music-generation step is needed.

**Music:** turn off the iPhone's Silent Mode, raise its volume, and check **Pause → Music**. Music resumes when you return to the game and stops while paused or in the background.

Debug builds allow unlimited play and include practice controls. Release builds use the daily health system; tutorial stages have free retries.

## Simulator and Mac preview

Choose an iPhone simulator in Xcode and use **Practice controls → Test this throw**. The simulator can exercise the game rules but cannot validate a physical wrist flick.

For the Mac preview:

```sh
zsh scripts/compile-preview-shader.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run BottleFlipPreview
```

Shader compilation requires Xcode's Metal Toolchain component. The Mac preview uses synthetic throws.

## Tests

Run the core rules and progress tests:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Debug launch arguments `--validate-landings`, `--validate-rounds` and `--validate-music` run additional checks and write JSON reports into the app's Documents directory using temporary players. They do not alter normal saved progress. `scripts/create-navigation-test-project.py` generates the simulator UI-test project under `build/`.

## Project layout

- `BottleFlip/Core`: stage rules, flick detection, progress storage and soundtrack mapping.
- `BottleFlip/App`: SwiftUI interface, scene rendering, motion, audio and bundled assets.
- `Tests`: core unit tests and native navigation UI tests.
- `scripts`: optional development and asset utilities.

Local build products, device backups, personal saves and exploratory design studies are excluded from this repository.

## Asset credits

The soundtrack uses VS Chamber Orchestra 2: Community Edition instrument samples. Credits and the CC0 licence are included in `BottleFlip/App/Music/Credits.txt` and `BottleFlip/App/Music/VSCO-2-CE-CC0.txt`. The bundled CAF files are the ready-to-play arrangements; the large original WAV masters are not included. Scenery plates were generated for this project; the live bottle is rendered in code. Landing and slosh effects were edited from a recording supplied for the game.
