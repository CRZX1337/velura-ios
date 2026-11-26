//
//  VeluraScreenShots.swift
//  VeluraUITests
//
//  Screenshot harness. Walks the app's primary surfaces and attaches a full-screen
//  capture for every stop, so a CI run produces visual evidence of the real,
//  system-rendered Liquid Glass chrome (local Windows toolchains cannot render SwiftUI).
//
//  Run:
//    xcodebuild test -project Velura.xcodeproj -scheme Velura \
//      -destination 'platform=iOS Simulator,id=<UDID>' \
//      -only-testing:VeluraUITests/VeluraScreenShots \
//      -resultBundlePath build/shots.xcresult CODE_SIGNING_ALLOWED=NO
//    xcrun xcresulttool export attachments --path build/shots.xcresult --output-path build/shots
//

import XCTest

final class VeluraScreenShots: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        // Volatile defaults so the harness always lands on the dashboards.
        app.launchArguments = [
            "-speedometer.firstLaunchSetup.completed", "YES",
            "-speedometer.keepScreenAwake", "NO",
            "-speedometer.appearance.mode", "palette",
            "-speedometer.appearance.theme", "midnight",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        // Let glass settle and the first location fix arrive.
        sleep(3)
    }

    func testCaptureAllScreens() throws {
        capture("01-speed")
        openDriveMode()
        capture("02-drive-mode")
        closeDriveMode()

        if tapTab("Test") { capture("03-acceleration") }
        if tapTab("Drives") { capture("04-drives") }
        if tapTab("Settings") {
            capture("05-settings-top")
            app.swipeUp()
            sleep(1)
            capture("06-settings-appearance")
            app.swipeUp()
            sleep(1)
            capture("07-settings-bottom")
        }
        if tapTab("Speed") { capture("08-speed-after-tour") }
    }

    func testCaptureActiveDrive() throws {
        let start = app.buttons["Start drive"].firstMatch
        if start.waitForExistence(timeout: 10) {
            start.tap()
            sleep(4)
        }
        capture("10-speed-active-drive")
        if tapTab("Drives") { capture("11-drives-with-record") }
    }

    // MARK: - Helpers

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapTab(_ label: String) -> Bool {
        let candidates = [
            app.tabBars.buttons[label],
            app.buttons[label],
        ]
        for candidate in candidates where candidate.waitForExistence(timeout: 4) {
            candidate.tap()
            sleep(2)
            return true
        }
        return false
    }

    private func openDriveMode() {
        let entry = app.buttons["Open Drive Mode cockpit and in-app navigation"].firstMatch
        let fallback = app.buttons["Drive Mode"].firstMatch
        if entry.waitForExistence(timeout: 6) {
            entry.tap()
        } else if fallback.waitForExistence(timeout: 4) {
            fallback.tap()
        }
        sleep(3)
    }

    private func closeDriveMode() {
        let close = app.buttons["Exit Drive Mode"].firstMatch
        if close.waitForExistence(timeout: 6) {
            close.tap()
            sleep(2)
        }
    }
}
