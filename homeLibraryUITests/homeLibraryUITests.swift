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
    func testAddAndSearchBookOnIOS() throws {
        createOwnedRepositoryIfNeeded()

        addBook(title: "测试驱动开发", author: "Kent Beck", publisher: "Addison-Wesley", year: "2002")
        let firstBookCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'bookCard-'")).firstMatch
        XCTAssertTrue(firstBookCard.waitForExistence(timeout: 5))

        let searchField = app.textFields["floatingSearchField"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Kent")
        XCTAssertTrue(firstBookCard.waitForExistence(timeout: 5))
    }

    private func addBook(title: String, author: String, publisher: String, year: String) {
        app.buttons["addBookButton"].tap()

        let titleField = app.textFields["titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        enterText(title, into: titleField)

        enterText(author, into: app.textFields["authorField"])
        enterText(publisher, into: app.textFields["publisherField"])
        enterText(year, into: app.textFields["yearField"])

        app.buttons["saveBookButton"].tap()
    }

    private func createOwnedRepositoryIfNeeded() {
        let createButton = app.buttons["createOwnedRepositoryButton"].firstMatch
        if createButton.waitForExistence(timeout: 2) {
            createButton.tap()
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
}
