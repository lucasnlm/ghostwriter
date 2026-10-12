//
//  ghostwriterUITests.swift
//  ghostwriterUITests
//

import XCTest

final class ghostwriterUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAsAgent() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5) || app.wait(for: .runningForeground, timeout: 5))
    }
}
