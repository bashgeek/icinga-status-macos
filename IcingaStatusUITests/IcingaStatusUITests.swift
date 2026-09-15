import XCTest

@MainActor
final class IcingaStatusUITests: XCTestCase {
    func testDemoShowsProblemsAndConnectionFailure() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--preview", "--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["4 problems need attention"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 unavailable"].exists)
        XCTAssertTrue(app.staticTexts["db-01"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Status panel"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        XCTAssertFalse(app.textFields["checkSearch"].exists)
        app.buttons["toggleCheckFilters"].click()
        let search = app.textFields["checkSearch"]
        search.click()
        search.typeText("no-such-host")
        XCTAssertTrue(app.staticTexts["No matching checks"].exists)
        app.buttons["Clear search"].click()
        XCTAssertTrue(app.staticTexts["db-01"].exists)
    }

    func testHealthyOverviewHidesProblemListAndInventoryFiltersStartClosed() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--preview", "--ui-testing", "--scenario", "healthy"]
        app.launch()
        XCTAssertTrue(app.staticTexts["All systems operational"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["toggleCheckFilters"].exists)
        XCTAssertFalse(app.textFields["checkSearch"].exists)
        app.radioButtons["Hosts · 12"].click()
        XCTAssertTrue(app.buttons["toggleCheckFilters"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["checkSearch"].exists)
        app.buttons["toggleCheckFilters"].click()
        XCTAssertTrue(app.textFields["checkSearch"].exists)
    }

    func testFirstRunSettingsValidateBeforeSaving() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--ui-testing"]
        app.launch()
        let add = app.buttons["addFirstInstance"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.click()
        let settingsAdd = app.buttons["addInstance"]
        XCTAssertTrue(settingsAdd.waitForExistence(timeout: 5))
        settingsAdd.click()
        let save = app.buttons["saveInstance"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        XCTAssertTrue(app.staticTexts["Give this instance a name."].exists)
        let name = app.textFields["instanceName"]
        name.click()
        name.typeText("Test instance")
        app.radioButtons["General"].click()
        XCTAssertTrue(app.links["generalGitHubLink"].exists)
        app.radioButtons["Instances"].click()
        XCTAssertEqual(name.value as? String, "Test instance")
        let username = app.textFields["instanceUsername"]
        username.click()
        username.typeText("monitor")
        let url = app.textFields["instanceAPIURL"]
        url.click()
        url.typeText("http://example.com")
        save.click()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Enter an HTTPS API URL")).firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Instance settings"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
    }
}
