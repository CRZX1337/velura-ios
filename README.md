# Velura

Velura is a native iOS speedometer and driving companion. It combines a live GPS speed display with drive recording, route review, acceleration timing, and an adaptable dashboard.

## Features

- **Live speed and GPS status** — View speed in km/h or mph, with clear searching, stale-fix, and unreliable-data states. Stale, inaccurate, and implausible GPS samples are filtered before they can affect measurements.
- **Drive recording** — Record duration, distance, top speed, and route for drives you start. Browse saved drives, search and filter history, inspect route maps, share a route summary, and review driving insights.
- **Acceleration testing** — Time 0–20, 0–50, 0–100 km/h runs or choose a custom target. Review recent attempts and best results.
- **Driver controls** — Configure overspeed warnings, choose from multiple speedometer dials and themes, and customize the dashboard layout and display scale.
- **Live Activity** — Keep an active drive summary and GPS freshness visible on the Lock Screen and Dynamic Island on supported devices.

## Requirements

- iOS 26.0 or later
- Xcode with the iOS 26 SDK or later
- An iPhone with Location Services for live GPS measurements; route maps and drive recording are most useful on a real device

## Build

1. Clone the repository and open `Velura.xcodeproj` in Xcode.
2. Select the `Velura` scheme and an iOS Simulator or registered device.
3. Build and run the app.

To build from the command line for a simulator SDK:

```sh
xcodebuild -project Velura.xcodeproj \
  -scheme Velura \
  -destination 'generic/platform=iOS Simulator' \
  build
```

The project includes unit and UI test targets. To run them, choose an installed iOS Simulator destination in Xcode or pass that destination to `xcodebuild test`.

## Location and privacy

Velura requests When In Use location access. Location is used for speed, distance, and route recording during drives the driver explicitly starts. The app may continue location updates in the background while a drive is active, subject to iOS behavior and permissions. Force-quitting the app or system termination may stop tracking; uninterrupted recording is not guaranteed.

Drive history and route data are stored on the device. Review or delete saved drives in the app. Background location is enabled only to support a user-started active drive; Velura does not start passive automatic tracking.

## Automated builds

The GitHub Actions workflow in `.github/workflows/build-ipa.yml` builds an **unsigned** IPA on pushes and publishes it as a GitHub pre-release. The artifact must be signed before it can be installed on a device. Workflow artifacts are retained for 14 days.

## Project structure

- `Velura/` — SwiftUI app, GPS and drive models, settings, and app resources
- `VeluraLiveActivity/` — Live Activity extension
- `VeluraTests/` — Unit tests
- `VeluraUITests/` — UI tests

## License

No open-source license is included at this time. Making this repository public does not grant permission to use, modify, or redistribute its contents.
