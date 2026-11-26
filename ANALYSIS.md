# Velura — Liquid Glass analysis

Read-through of the iOS app as it stood at `31590fd` (v1.3.2, build 44), and what changed to
put it on Apple's native Liquid Glass rather than a hand-built imitation of it.

## 1. What the app is

| Layer | Files | Notes |
|---|---|---|
| Shell | `VeluraApp.swift`, `ContentView.swift` (1.5k) | 4 tabs, first-launch gate, overspeed banner, full-screen covers |
| Speed | `SpeedometerModel.swift` (1.4k), `GPSLocationFilter.swift` | `CLLocationManager` delegate, smoothing, session state machine, file-backed recovery |
| Dials | `ContentView.swift` (`SpeedometerGauge`, arcs, ticks, segments), `AppearanceSettings.swift` | 9 dial styles, 6 palettes, 4 appearance modes |
| Driving | `DriveModeView.swift` (1.4k), `ActiveDriveView.swift`, `DriveRouteView.swift` | cockpit HUD, MapKit route, in-app navigation, heatmap |
| History | `DriveHistoryView.swift` (1k), `DriveHistoryStore.swift`, `DriveFileStorage.swift`, `DriveModels.swift` | versioned JSON records, append-only route journal, migration from legacy blobs |
| Insights | `DrivingInsightsCalculator.swift`, `DrivingInsightsView.swift`, `RouteSpeedHeatmap.swift` | period buckets, elevation gain/loss, speed bands |
| Acceleration | `AccelerationTestView.swift` | 0–20/50/100 + custom targets, attempts, best |
| System | `DriveLiveActivityController.swift`, `VeluraLiveActivity/` | Lock Screen + Dynamic Island |
| Media | `DriveMediaController.swift` | MusicKit, Spotify PKCE, now-playing |
| Shared | `VeluraGlass.swift`, `VeluraMotion.swift`, `AdaptiveFont.swift` | design primitives, motion tokens, dynamic-type scaling |

Deployment target is iOS 26.0, so every Liquid Glass API is available unconditionally — there is
no fallback ladder to write and no `#available(iOS 26…)` guard to add.

## 2. What the glass audit found

The app already called `glassEffect` (33 sites) — the material was real. The problem was *where*
it sat and what was layered on top of it.

| Finding | Where | Rule broken |
|---|---|---|
| Content wearing glass | Settings (7 cards), drive rows, insight cards, metric rows, onboarding, accel results | Glass belongs on the control layer; a live sampling region per scroll row also costs GPU per row |
| Hand-added strokes on every glass surface | 27 call sites (`stroke:` argument) | System owns edge treatment and re-adapts it under Increase Contrast |
| Manual frost-out under Reduce Transparency | `VeluraGlassSurfaceModifier` | The system already does this; re-implementing it double-frosts |
| Press feedback faded glass to 92 % alpha | `VeluraGlassPressButtonStyle` | Any ancestor with `opacity < 1` collapses refraction |
| Custom glass chrome where the system provides it | tab bar items, settings title, history header, search field, detail headers | Rebuilding glass the system already renders drifts from the OS |
| Soft-deprecated toolbar API | 13 × `.toolbar(.visible/.hidden, for:)` | Renamed to `toolbarVisibility(_:for:)` |
| `tabItem`/`tag` tab model | `ContentView` | `Tab(_:systemImage:value:)` is the current model |
| Onboarding CTA hand-rolled | gradient capsule + shadow + fade-in | Prominent action = `.glassProminent`; glass materializes, it does not fade |

## 3. What changed

**Material layer (`VeluraGlass.swift`).** One modifier applies `glassEffect(_:in:)` and nothing
else — no stroke, no manual fallback, no opacity. A second modifier,
`VeluraContentSurfaceModifier`, is the deliberate *non*-glass card for content: flat vibrancy
fill, hairline, optional state `tint`. Both keep the silhouette so hierarchy survives the swap.

**Layer separation.** 37 surfaces moved from glass to content fill: settings cards, drive list
rows, insight cards, metric rows, metric tiles, onboarding cards, acceleration results, history
detail actions container. 33 glass sites remain, all on chrome: floating buttons, map HUD,
overspeed banner, cockpit controls, sheet fields.

**System chrome instead of imitations.**

- Tabs: `Tab("Speed", systemImage:value:)`, `toolbarVisibility`, `tabBarMinimizeBehavior(.automatic)`.
- Settings: real `NavigationStack` title (`.large`), `scrollEdgeEffectStyle(.soft, for: .top)`.
- Drives: native large title, `.searchable(text:isPresented:prompt:)` replacing the custom glass
  search field, insights + actions as real toolbar items, custom header deleted (60 lines).
- Drive details / Driving insights: native inline titles and system back button, custom glass
  back buttons deleted.
- Primary actions: `.glassProminent` + `.tint` for the one primary action per screen; `.glass`
  for secondary ones, with colour removed from secondary buttons so tint marks a single action.

**Motion.** Press feedback scales and dims brightness instead of alpha; the first-launch entrance
moves and scales instead of fading, so no glass ancestor is ever partially transparent.

**Model split.** `DriveHistoryStore.swift` → `DriveModels.swift` (Codable value types) +
store/storage. The model layer is now free of Combine/UIKit, which is what makes the portable
test package possible.

## 4. Verified, and how

- `swiftc -frontend -parse` over all 29 Swift files — clean (catches syntax, not APIs).
- Swift Testing package (`tools/logic-tests`) — 8 tests over models, storage migration, active-drive
  journal recovery, GPX export and insights math, executed on Windows in ~0.03 s.
- `xcodebuild test` on `macos-26` with an iPhone simulator, then XCUITest screen capture of every
  surface — the only lane that proves the SwiftUI code compiles and the material renders.

## 5. Open items

- `ContentUnavailableView` is still hand-built in three places (empty history, no matches, empty
  route); it is the native empty-state component and would remove ~40 lines.
- Settings still uses custom section cards rather than `Form`. A `Form` is the most native shape,
  but it would flatten the branded dark palette; the cards are now content surfaces, which is the
  part that mattered for glass correctness.
- Live Activity keeps its own palette mirror (`VeluraLiveActivity`) — unchanged, it already lets
  system glass through with `containerBackground { Color.clear }`.
