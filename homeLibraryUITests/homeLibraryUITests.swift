//
//  homeLibraryUITests.swift
//  homeLibraryUITests
//
//  Created by 王宇 on 2026/4/14.
//

import XCTest

final class homeLibraryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOME_LIBRARY_STORAGE_NAMESPACE"] = "ui-tests-\(UUID().uuidString)"
        app.launchEnvironment["HOME_LIBRARY_DISABLE_BUNDLED_SEED"] = "1"
        app.launchEnvironment["HOME_LIBRARY_DISABLE_CLOUD_SYNC"] = "1"
        app.launch()
    }

    @MainActor
    func testAddSearchEditAndDeleteBookOnIOS() throws {
        XCTAssertTrue(app.otherElements["emptyState"].waitForExistence(timeout: 5))

        app.buttons["addBookButton"].tap()

        let titleField = app.textFields["titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("测试驱动开发")

        let authorField = app.textFields["authorField"]
        authorField.tap()
        authorField.typeText("Kent Beck")

        let publisherField = app.textFields["publisherField"]
        publisherField.tap()
        publisherField.typeText("Addison-Wesley")

        let yearField = app.textFields["yearField"]
        yearField.tap()
        yearField.typeText("2002")

        let isbnField = app.textFields["isbnField"]
        isbnField.tap()
        isbnField.typeText("9780321146533")

        app.buttons["saveBookButton"].tap()

        XCTAssertTrue(app.staticTexts["测试驱动开发"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Kent Beck"].exists)

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Kent")

        XCTAssertTrue(app.staticTexts["测试驱动开发"].waitForExistence(timeout: 5))

        clearSearchField(searchField)

        app.staticTexts["测试驱动开发"].tap()

        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        replaceText(in: titleField, with: "测试驱动开发实践")
        app.buttons["saveBookButton"].tap()

        XCTAssertTrue(app.staticTexts["测试驱动开发实践"].waitForExistence(timeout: 5))

        app.buttons["删除 测试驱动开发实践"].tap()
        app.buttons["删除"].tap()

        XCTAssertTrue(app.otherElements["emptyState"].waitForExistence(timeout: 5))
    }

    private func clearSearchField(_ element: XCUIElement) {
        guard let existingValue = element.value as? String, !existingValue.isEmpty else {
            return
        }

        element.tap()
        element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingValue.count))
    }

    private func replaceText(in element: XCUIElement, with value: String) {
        guard let existingValue = element.value as? String else {
            element.tap()
            element.typeText(value)
            return
        }

        element.tap()
        element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingValue.count))
        element.typeText(value)
    }
}
