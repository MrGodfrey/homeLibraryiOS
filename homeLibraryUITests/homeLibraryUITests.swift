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

    @MainActor
    func testCreateBookDraftRestoresAfterSwipeDismiss() throws {
        createOwnedRepositoryIfNeeded()

        app.buttons["addBookButton"].tap()

        let titleField = app.textFields["titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        enterText("会被缓存的书", into: titleField)
        enterText("作者甲", into: app.textFields["authorField"])
        enterText("译者乙", into: app.textFields["translatorField"])
        enterText("9787111123456", into: app.textFields["isbnField"])

        dismissBookEditorBySwipe()
        XCTAssertTrue(waitForNonExistence(of: titleField, timeout: 5))

        app.buttons["addBookButton"].tap()

        let reopenedTitleField = app.textFields["titleField"]
        XCTAssertTrue(reopenedTitleField.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedTitleField.value as? String, "会被缓存的书")
        XCTAssertEqual(app.textFields["authorField"].value as? String, "作者甲")
        XCTAssertEqual(app.textFields["translatorField"].value as? String, "译者乙")
        XCTAssertEqual(app.textFields["isbnField"].value as? String, "9787111123456")

        app.buttons["cancelBookButton"].tap()
    }

    @MainActor
    func testRepositorySettingsShowsBookSortAndManagementOptions() throws {
        createOwnedRepositoryIfNeeded()
        openRepositorySettings()

        XCTAssertTrue(app.buttons["bookSortPicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addLocationButton"].waitForExistence(timeout: 5))
        app.swipeUp()
        let compressButton = app.buttons["compressRepositoryCoversButton"]
        XCTAssertTrue(compressButton.waitForExistence(timeout: 5))
        compressButton.tap()

        let compressionAlert = app.alerts["确认整理当前仓库封面？"].firstMatch
        XCTAssertTrue(compressionAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(compressionAlert.staticTexts["此操作会替换所有的封面。"].exists)
        compressionAlert.buttons["取消"].tap()

        XCTAssertTrue(compressButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["exportRepositoryButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["clearRepositoryButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTapBookCardOpensEditorAndDeleteRequiresConfirmation() throws {
        createOwnedRepositoryIfNeeded()

        addBook(title: "重构", author: "Martin Fowler", publisher: "Addison-Wesley", year: "1999")

        let firstBookCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'bookCard-'")).firstMatch
        XCTAssertTrue(firstBookCard.waitForExistence(timeout: 5))

        firstBookCard.tap()

        let titleField = app.textFields["titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(titleField.value as? String, "重构")

        let deleteButton = app.buttons["deleteBookButton"]
        scrollToElement(deleteButton)
        deleteButton.tap()

        let deleteAlert = app.alerts["确认删除这本书？"].firstMatch
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 5))
        deleteAlert.buttons["暂不删除"].tap()

        XCTAssertTrue(app.buttons["deleteBookButton"].waitForExistence(timeout: 5))
        app.buttons["cancelBookButton"].tap()
        XCTAssertTrue(firstBookCard.waitForExistence(timeout: 5))

        firstBookCard.tap()
        scrollToElement(deleteButton)
        deleteButton.tap()

        let confirmDeleteAlert = app.alerts["确认删除这本书？"].firstMatch
        XCTAssertTrue(confirmDeleteAlert.waitForExistence(timeout: 5))
        confirmDeleteAlert.buttons["确认删除"].tap()

        XCTAssertTrue(waitForNonExistence(of: firstBookCard, timeout: 5))
    }

    private func addBook(
        title: String,
        author: String,
        translator: String = "",
        publisher: String,
        year: String,
        isbn: String = ""
    ) {
        app.buttons["addBookButton"].tap()

        let titleField = app.textFields["titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        enterText(title, into: titleField)

        enterText(author, into: app.textFields["authorField"])
        if !translator.isEmpty {
            enterText(translator, into: app.textFields["translatorField"])
        }
        enterText(publisher, into: app.textFields["publisherField"])
        enterText(year, into: app.textFields["yearField"])
        if !isbn.isEmpty {
            enterText(isbn, into: app.textFields["isbnField"])
        }

        app.buttons["saveBookButton"].tap()
    }

    private func createOwnedRepositoryIfNeeded() {
        let createButton = app.buttons["createOwnedRepositoryButton"].firstMatch
        if createButton.waitForExistence(timeout: 2) {
            createButton.tap()
        }

        XCTAssertTrue(app.buttons["addBookButton"].waitForExistence(timeout: 5))
    }

    private func openRepositorySettings() {
        let settingsButton = app.buttons["repositoryManagementButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(app.buttons["repositorySettingsCloseButton"].waitForExistence(timeout: 5))
    }

    private func dismissBookEditorBySwipe() {
        let navigationBar = app.navigationBars["添加新书"].firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        navigationBar.swipeDown()
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

    private func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 6) {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return
            }

            app.swipeUp()
        }

        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }

    private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if !element.exists {
                return true
            }

            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while Date() < deadline

        return !element.exists
    }
}
