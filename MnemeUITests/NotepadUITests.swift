import XCTest

final class NotepadUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testUnsupportedBannerAppearsWhenLanguageModelUnavailable() {
        let app = XCUIApplication()
        app.launchArguments += ["MNEME_UI_TEST_MODE"]
        app.launchEnvironment["MNEME_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["MNEME_FORCE_NLP_UNAVAILABLE"] = "1"

        app.launch()

        XCTAssertTrue(app.otherElements["notepad.nlpUnsupportedBanner"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["notepad.doneButton"].isEnabled)
    }

    func testStubbedEventFlowProcessesSuccessfully() {
        let app = XCUIApplication()
        app.launchArguments += ["MNEME_UI_TEST_MODE"]
        app.launchEnvironment["MNEME_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["MNEME_USE_STUB_NLP"] = "1"
        app.launchEnvironment["MNEME_USE_MOCK_EVENTKIT"] = "1"
        app.launchEnvironment["MNEME_USE_IN_MEMORY_STORES"] = "1"

        app.launch()

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("Meeting with Sarah tomorrow at 3pm")

        let doneButton = app.buttons["notepad.doneButton"]
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: enabledPredicate, evaluatedWith: doneButton)
        waitForExpectations(timeout: 5)

        doneButton.tap()

        XCTAssertTrue(app.staticTexts["Processing Complete"].waitForExistence(timeout: 5))
    }

    func testRelaunchStartsWithEmptyNotepad() {
        let app = XCUIApplication()
        app.launchArguments += ["MNEME_UI_TEST_MODE"]
        app.launchEnvironment["MNEME_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["MNEME_USE_STUB_NLP"] = "1"

        app.launch()

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("Unsaved draft")
        app.terminate()

        app.launch()

        let relaunchedTextView = app.textViews.firstMatch
        XCTAssertTrue(relaunchedTextView.waitForExistence(timeout: 5))
        XCTAssertNotEqual(relaunchedTextView.value as? String, "Unsaved draft")
    }

    func testMoodPickerInsertsEmojiPrefix() {
        let app = XCUIApplication()
        app.launchArguments += ["MNEME_UI_TEST_MODE"]
        app.launchEnvironment["MNEME_SKIP_ONBOARDING"] = "1"

        app.launch()

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText(":")

        let moodButton = app.buttons["😊"]
        XCTAssertTrue(moodButton.waitForExistence(timeout: 5))
        moodButton.tap()

        XCTAssertTrue((textView.value as? String)?.contains("😊") == true)
    }
}
