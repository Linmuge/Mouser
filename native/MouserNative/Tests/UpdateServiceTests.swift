import Foundation
import Testing
@testable import MouserNative

@Suite("Native update service")
struct UpdateServiceTests {
    @Test("decodes a stable release from the fork repository response")
    func decodesRelease() throws {
        let payload = Data(
            """
            {
              "tag_name": "v3.8.0",
              "html_url": "https://github.com/Linmuge/Mouser/releases/tag/v3.8.0",
              "name": "Mouser 3.8.0",
              "body": "Native release",
              "draft": false,
              "prerelease": false,
              "assets": [
                {
                  "name": "Mouser-3.8.0.dmg",
                  "browser_download_url": "https://github.com/Linmuge/Mouser/releases/download/v3.8.0/Mouser-3.8.0.dmg",
                  "size": 123456,
                  "content_type": "application/x-apple-diskimage",
                  "digest": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                },
                {
                  "name": "Mouser-3.8.0-debug.dmg",
                  "browser_download_url": "https://example.test/debug.dmg",
                  "size": 654321,
                  "content_type": "application/x-apple-diskimage",
                  "digest": "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
                }
              ]
            }
            """.utf8
        )

        let release = try GitHubReleaseDecoder.decode(payload)

        #expect(release.version == "3.8.0")
        #expect(release.releaseURL.host() == "github.com")
        #expect(!release.isPrerelease)
        #expect(release.installAsset?.name == "Mouser-3.8.0.dmg")
        #expect(release.installAsset?.size == 123456)
        #expect(
            release.installAsset?.sha256 ==
                "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        )
    }

    @Test("release without a verified DMG remains notify-only")
    func rejectsUnverifiedAsset() throws {
        let payload = Data(
            """
            {
              "tag_name": "v3.8.0",
              "html_url": "https://github.com/Linmuge/Mouser/releases/tag/v3.8.0",
              "draft": false,
              "prerelease": false,
              "assets": [{
                "name": "Mouser-3.8.0.dmg",
                "browser_download_url": "https://example.test/Mouser.dmg",
                "size": 10,
                "content_type": "application/x-apple-diskimage",
                "digest": null
              }]
            }
            """.utf8
        )

        #expect(try GitHubReleaseDecoder.decode(payload).installAsset == nil)
    }

    @Test("download verification rejects size and digest mismatches")
    func verifiesDownloadedBytes() throws {
        let data = Data("Mouser update".utf8)
        let digest = UpdateAssetVerifier.sha256(data)

        #expect(throws: Never.self) {
            try UpdateAssetVerifier.verify(
                data,
                expectedSize: data.count,
                expectedSHA256: digest
            )
        }
        #expect(throws: UpdateInstallError.self) {
            try UpdateAssetVerifier.verify(
                data,
                expectedSize: data.count + 1,
                expectedSHA256: digest
            )
        }
        #expect(throws: UpdateInstallError.self) {
            try UpdateAssetVerifier.verify(
                data,
                expectedSize: data.count,
                expectedSHA256: String(repeating: "0", count: 64)
            )
        }
    }

    @Test("update helper only accepts sibling staging and backup paths")
    func validatesInstallPlanPaths() throws {
        let installURL = URL(filePath: "/Applications/Mouser.app", directoryHint: .isDirectory)
        let safePlan = NativeUpdateInstallPlan(
            parentProcessID: 123,
            stagedAppPath: "/Applications/.Mouser.app.update-123/Mouser.app",
            installAppPath: installURL.path,
            backupAppPath: "/Applications/.Mouser.backup-123.app",
            expectedBundleIdentifier: "io.github.tombadash.mouser",
            expectedVersion: "3.8.0"
        )

        #expect(throws: Never.self) {
            try safePlan.validatePaths()
        }

        var unsafePlan = safePlan
        unsafePlan.stagedAppPath = "/tmp/Mouser.app"
        #expect(throws: UpdateInstallError.self) {
            try unsafePlan.validatePaths()
        }
    }

    @Test("diskutil attachment parser retains the mounted volume and whole disk")
    func parsesDiskutilAttachment() throws {
        let payload = try PropertyListSerialization.data(
            fromPropertyList: [
                "system-entities": [
                    ["dev-entry": "disk8", "content-hint": "GUID_partition_scheme"],
                    ["dev-entry": "disk9s1", "mount-point": "/Volumes/Mouser 3.8.0"],
                ],
            ],
            format: .xml,
            options: 0
        )

        let attachment = try DiskImageAttachment(plistData: payload)

        #expect(attachment.mountURL.path == "/Volumes/Mouser 3.8.0")
        #expect(attachment.wholeDiskIdentifier == "disk8")
        #expect(
            DiskImageAttachment.attachArguments(for: URL(filePath: "/tmp/Mouser.dmg")) == [
                "image", "attach", "--readOnly", "--nobrowse", "--plist",
                "/tmp/Mouser.dmg",
            ]
        )
        #expect(attachment.ejectArguments == ["eject", "disk8"])
    }

    @Test("diskutil attachment parser rejects a plist without a mount or whole disk")
    func rejectsIncompleteDiskutilAttachment() throws {
        let noMount = try PropertyListSerialization.data(
            fromPropertyList: ["system-entities": [["dev-entry": "disk8"]]],
            format: .xml,
            options: 0
        )
        let noWholeDisk = try PropertyListSerialization.data(
            fromPropertyList: [
                "system-entities": [[
                    "dev-entry": "disk9s1",
                    "mount-point": "/Volumes/Mouser",
                ]],
            ],
            format: .xml,
            options: 0
        )

        #expect(throws: UpdateInstallError.self) {
            try DiskImageAttachment(plistData: noMount)
        }
        #expect(throws: UpdateInstallError.self) {
            try DiskImageAttachment(plistData: noWholeDisk)
        }
    }

    @Test(
        "semantic versions compare numerically",
        arguments: [
            ("3.7.10", "3.7.3", true),
            ("v3.7.3", "3.7.3", false),
            ("3.7.2", "3.7.3", false),
            ("4.0.0-beta.1", "3.9.9", true),
        ]
    )
    func comparesVersions(candidate: String, current: String, expected: Bool) {
        #expect(SemanticVersion.isNewer(candidate, than: current) == expected)
    }

    @Test("the production checker targets the user's fork")
    func targetsFork() {
        #expect(GitHubReleaseChecker.defaultRepository == "Linmuge/Mouser")
        #expect(
            GitHubReleaseChecker.latestReleaseEndpoint.absoluteString ==
                "https://api.github.com/repos/Linmuge/Mouser/releases/latest"
        )
    }
}
