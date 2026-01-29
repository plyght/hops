import XCTest

@testable import HopsCore

final class PolicyTests: XCTestCase {
  func testPolicyDefault() {
    let policy = Policy.default
    XCTAssertEqual(policy.name, "default")
  }
}
