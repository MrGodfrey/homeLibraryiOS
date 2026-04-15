//
//  homeLibraryUITestsLaunchTests.swift
//  homeLibraryUITests
//
//  Created by 王宇 on 2026/4/14.
//

import XCTest

final class homeLibraryUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HOME_LIBRARY_STORAGE_NAMESPACE"] = "launch-tests-\(UUID().uuidString)"
        app.launchEnvironment["HOME_LIBRARY_REMOTE_DRIVER"] = "memory"
        app.launch()

        let createRepositoryButton = app.buttons["createOwnedRepositoryButton"].firstMatch
        if createRepositoryButton.waitForExistence(timeout: 2) {
            XCTAssertTrue(createRepositoryButton.isHittable)
        } else {
            XCTAssertTrue(app.buttons["addBookButton"].waitForExistence(timeout: 5))
        }
    }
}
