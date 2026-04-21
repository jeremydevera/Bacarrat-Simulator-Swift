# Bacarrat Simultor Swift

A Baccarat simulator built in SwiftUI, with a lightweight browser port included in the repo.

## Included Apps

- `Bacarrat Sim/`: the native SwiftUI app for iPhone/iPad simulation
- `Bacarrat Sim Web/`: a static web version with no database or persistence

## Native Swift App

The Swift app includes:

- 30 live simulated baccarat tables
- selectable side betting: `Banker`, `Player`, or `Tie`
- `Classic Martingale` and `Mod Martingale`
- configurable starting bet, stop loss, table timer, and warning level
- speed options: `2x`, `50x`, and `100x`
- session controls for play, pause, stop, and auto-continue
- history and analytics views

Main files:

- `Bacarrat Sim/ContentView.swift`
- `Bacarrat Sim/Bacarrat_SimApp.swift`

## Web Version

The web port is a local static app:

- no backend
- no database
- no persistence
- all session state lives in memory

Main files:

- `Bacarrat Sim Web/index.html`
- `Bacarrat Sim Web/styles.css`
- `Bacarrat Sim Web/app.js`

To run it locally, open `Bacarrat Sim Web/index.html` in a browser.

## Xcode

To open the native app:

1. Open `Bacarrat Sim.xcodeproj`
2. Select the `Bacarrat Sim` scheme
3. Build and run on Simulator or device

## Notes

- The web version is intended as a simple browser port of the simulator flow.
- Refreshing the page clears the current web session.
- Generated Xcode files are ignored through `.gitignore`.
