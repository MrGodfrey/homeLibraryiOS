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
        app.launchEnvironment["HOME_LIBRARY_REMOTE_DRIVER"] = "memory"
        XCUIDevice.shared.orientation = .portrait
        app.launch()
    }

    @MainActor
    func testAddAndEditBookOnIOS() throws {
        createOwnedRepositoryIfNeeded()

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
        createOwnedRepositoryIfNeeded()

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
        enterText(title, into: titleField)

        let authorField = app.textFields["authorField"]
        enterText(author, into: authorField)

        let publisherField = app.textFields["publisherField"]
        enterText(publisher, into: publisherField)

        let yearField = app.textFields["yearField"]
        enterText(year, into: yearField)

        app.buttons["saveBookButton"].tap()
    }

    private func createOwnedRepositoryIfNeeded() {
        let labeledCreateButton = app.buttons["创建我的仓库"].firstMatch
        let identifiedCreateButton = app.buttons["createOwnedRepositoryButton"].firstMatch

        if labeledCreateButton.waitForExistence(timeout: 2) {
            tapElement(labeledCreateButton)
        } else if identifiedCreateButton.waitForExistence(timeout: 3) {
            tapElement(identifiedCreateButton)
        }

        XCTAssertTrue(app.buttons["addBookButton"].waitForExistence(timeout: 5))
    }

    private func replaceText(in element: XCUIElement, with value: String) {
        focusTextInput(element)

        guard let existingValue = element.value as? String else {
            element.typeText(value)
            return
        }

        element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingValue.count))
        element.typeText(value)
    }

    private func enterText(_ value: String, into element: XCUIElement) {
        focusTextInput(element)
        element.typeText(value)
    }

    private func focusTextInput(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))

        for attempt in 0..<3 {
            if attempt == 0, element.isHittable {
                element.tap()
            } else {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }

            if waitForKeyboardFocus(on: element, timeout: 1) {
                return
            }
        }

        XCTFail("Failed to focus text input \(element)")
    }

    private func waitForKeyboardFocus(on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if element.debugDescription.contains("Keyboard Focused") {
                return true
            }

            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline

        return false
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
