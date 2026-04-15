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
        app.launchEnvironment["HOME_LIBRARY_REMOTE_DRIVER"] = "memory"
        app.launch()
    }

    @MainActor
    func testAddAndEditBookOnIOS() throws {
        XCTAssertTrue(app.staticTexts["当前没有匹配的书籍"].waitForExistence(timeout: 5))

        addBook(title: "测试驱动开发", author: "Kent Beck", publisher: "Addison-Wesley", year: "2002")

        XCTAssertTrue(app.staticTexts["测试驱动开发"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Kent Beck"].exists)

        tapElement(app.buttons["编辑 测试驱动开发"].firstMatch)

        let titleField = app.textFields["titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        replaceText(in: titleField, with: "测试驱动开发实践")
        app.buttons["saveBookButton"].tap()

        XCTAssertTrue(app.staticTexts["测试驱动开发实践"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSearchFiltersBooksOnIOS() throws {
        XCTAssertTrue(app.staticTexts["当前没有匹配的书籍"].waitForExistence(timeout: 5))

        addBook(title: "测试驱动开发", author: "Kent Beck", publisher: "Addison-Wesley", year: "2002")

        XCTAssertTrue(app.staticTexts["测试驱动开发"].waitForExistence(timeout: 5))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Kent")

        XCTAssertTrue(app.staticTexts["测试驱动开发"].waitForExistence(timeout: 5))
    }

    private func addBook(title: String, author: String, publisher: String, year: String) {
        app.buttons["addBookButton"].tap()

        let titleField = app.textFields["titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(title)

        let authorField = app.textFields["authorField"]
        authorField.tap()
        authorField.typeText(author)

        let publisherField = app.textFields["publisherField"]
        publisherField.tap()
        publisherField.typeText(publisher)

        let yearField = app.textFields["yearField"]
        yearField.tap()
        yearField.typeText(year)

        app.buttons["saveBookButton"].tap()
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

    private func tapElement(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))

        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}
