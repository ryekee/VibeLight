import XCTest
@testable import VibeBrokerCore

final class PlaceholderTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertNotNil(VibeBrokerCore.self)
    }
}
