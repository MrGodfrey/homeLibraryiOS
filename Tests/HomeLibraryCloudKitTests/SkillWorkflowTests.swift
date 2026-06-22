import Foundation
import XCTest

final class SkillWorkflowTests: XCTestCase {
    func testHomeLibraryCuratorSkillDocumentsRequiredWorkflowAndSafetyRules() throws {
        let skill = try String(contentsOf: skillURL(), encoding: .utf8)

        for requiredCommand in [
            "doctor",
            "repos",
            "export-ai-workspace",
            "validate-patch",
            "review-patch",
            "apply-patch"
        ] {
            XCTAssertTrue(
                skill.contains(".build/debug/home-library-cloudkit \(requiredCommand)"),
                "Skill should document \(requiredCommand)"
            )
        }

        for requiredRule in [
            "Do not read, print, copy, or summarize `markdownNote/test`.",
            "Do not edit `cloudkit-cache`",
            "Do not call CloudKit APIs directly from the agent",
            "Do not bypass `validate-patch`.",
            "High-risk operations require `review-patch`",
            "Test-only auto approval is allowed only for `--remote memory` or `AIWorkflowTest-*`"
        ] {
            XCTAssertTrue(skill.contains(requiredRule), "Skill should include rule: \(requiredRule)")
        }
    }

    private func skillURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("skills/home-library-curator/SKILL.md")
    }
}
