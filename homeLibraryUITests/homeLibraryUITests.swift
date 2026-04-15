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
    func testAddSearchEditAndDeleteBookOnIOS() throws {
        createOwnedRepositoryIfNeeded()

        addBook(title: "测试驱动开发", author: "Kent Beck", publisher: "Addison-Wesley", year: "2002")
        XCTAssertTrue(app.staticTexts["测试驱动开发"].waitForExistence(timeout: 5))

        let searchButton = app.buttons["floatingSearchBar"].firstMatch
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.tap()

        let searchField = app.textFields["floatingSearchField"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Kent")
        XCTAssertTrue(app.staticTexts["测试驱动开发"].waitForExistence(timeout: 5))

        let bookCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'bookCard-'")).firstMatch
        if bookCard.waitForExistence(timeout: 5) {
            bookCard.tap()
        } else {
            app.staticTexts["测试驱动开发"].tap()
        }

        let editButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'editBook-'")).firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let titleField = app.textFields["titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        replaceText(in: titleField, with: "测试驱动开发实践")
        app.buttons["saveBookButton"].tap()
        XCTAssertTrue(app.staticTexts["测试驱动开发实践"].waitForExistence(timeout: 5))

        let updatedCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'bookCard-'")).firstMatch
        if updatedCard.waitForExistence(timeout: 5) {
            updatedCard.tap()
        } else {
            app.staticTexts["测试驱动开发实践"].tap()
        }
        let deleteButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deleteBook-'")).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
        let confirmDeleteButton = app.sheets.buttons["删除"].firstMatch
        XCTAssertTrue(confirmDeleteButton.waitForExistence(timeout: 5))
        confirmDeleteButton.tap()
        XCTAssertFalse(app.staticTexts["测试驱动开发实践"].waitForExistence(timeout: 2))
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
