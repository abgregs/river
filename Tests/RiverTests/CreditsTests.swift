import Foundation
import Testing
@testable import River

@Suite("Credits")
struct CreditsTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    // MIT and Apache-2.0 require the notice to travel with every copy. A package added to
    // Package.swift without a credit would ship uncredited, so every resolved package must be
    // credited or named as one River never links.
    @Test("every resolved package is credited or known not to ship")
    func everyPackageIsAccountedFor() throws {
        let data = try Data(contentsOf: Self.repo.appendingPathComponent("Package.resolved"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pins = try #require(json["pins"] as? [[String: Any]])
        let credited = Set(Credits.software.map(\.identity))
        for identity in pins.compactMap({ $0["identity"] as? String }) {
            #expect(credited.contains(identity) || Credits.notShipped.contains(identity), "\(identity) has no credit")
        }
    }

    @Test("the notices file names every credited package and model family")
    func noticesNameEverything() throws {
        let notices = try String(contentsOf: Self.repo.appendingPathComponent("Sources/River/Resources/\(Credits.noticesFileName)"),
                                 encoding: .utf8)
        for package in Credits.software { #expect(notices.contains(package.name), "\(package.name) missing") }
        for model in Constants.curatedModels { #expect(notices.contains(model.label), "\(model.label) missing") }
    }

    // The About window lists models first, then software (maintainer, 2026-11-10).
    @Test("the About credits list every model, then every package")
    func aboutTextOrder() throws {
        let text = Credits.aboutText(models: Constants.curatedModels)
        let software = try #require(text.range(of: "Software"))
        for model in Constants.curatedModels {
            let range = try #require(text.range(of: model.label))
            #expect(range.lowerBound < software.lowerBound)
        }
        for package in Credits.software { #expect(text[software.upperBound...].contains(package.name)) }
    }
}
