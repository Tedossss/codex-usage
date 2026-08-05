import Foundation
import Testing

@testable import ClaudeUsage

/// Captured verbatim from a live `GET /api/oauth/usage`, trimmed of the fields the app
/// does not read. Regenerate from the app's last-response.json
/// if the endpoint ever changes shape.
private let liveResponse = Data(
    """
    {"five_hour":{"utilization":18.0,"resets_at":"2026-08-05T13:30:00.191297+00:00","limit_dollars":null},
     "seven_day":{"utilization":20.0,"resets_at":"2026-08-10T06:00:00.191326+00:00","limit_dollars":null},
     "seven_day_opus":null,"seven_day_sonnet":null,
     "extra_usage":{"is_enabled":false,"utilization":null},
     "limits":[{"kind":"session","group":"session","percent":18,"severity":"normal","resets_at":"2026-08-05T13:30:00.191297+00:00","is_active":false},
               {"kind":"weekly_all","group":"weekly","percent":20,"severity":"normal","resets_at":"2026-08-10T06:00:00.191326+00:00","is_active":true},
               {"kind":"weekly_scoped","group":"weekly","percent":0,"severity":"normal","resets_at":null,"scope":{"model":{"display_name":"Fable"}},"is_active":false}]}
    """.utf8
)

@Test func readsBothWindowsFromTheLiveShape() throws {
    let usage = try #require(UsageReader.parse(liveResponse))
    #expect(usage.fiveHour?.percent == 18)
    #expect(usage.sevenDay?.percent == 20)
    #expect(usage.sevenDayOpus == nil)
}

@Test func parsesMicrosecondTimestamps() throws {
    let usage = try #require(UsageReader.parse(liveResponse))
    let resets = try #require(usage.fiveHour?.resetsAt)
    #expect(abs(resets.timeIntervalSince1970 - 1785936600.191297) < 0.001)
}

@Test func headlineTracksTheFullestWindow() throws {
    let usage = try #require(UsageReader.parse(liveResponse))
    #expect(usage.headline?.percent == 20)
}

@Test func fallsBackToTheLimitsArrayWhenNamedObjectsAreMissing() throws {
    let onlyArray = Data(
        """
        {"five_hour":null,"seven_day":null,
         "limits":[{"kind":"session","percent":41,"resets_at":"2026-08-05T13:30:00+00:00"},
                   {"kind":"weekly_all","percent":7,"resets_at":null}]}
        """.utf8
    )
    let usage = try #require(UsageReader.parse(onlyArray))
    #expect(usage.fiveHour?.percent == 41)
    #expect(usage.sevenDay?.percent == 7)
    #expect(usage.sevenDay?.resetsAt == nil)
}

@Test func returnsNothingWhenNoWindowIsPresent() {
    #expect(UsageReader.parse(Data(#"{"limits":[],"spend":{}}"#.utf8)) == nil)
}

@Test func levelsStayGreyUntilSixty() {
    #expect(Level(percent: 0) == .calm)
    #expect(Level(percent: 59.9) == .calm)
    #expect(Level(percent: 60) == .warm)
    #expect(Level(percent: 80) == .high)
    #expect(Level(percent: 93) == .critical)
}

@Test func readsTheNestedKeychainCredentialShape() throws {
    let stored = Data(
        #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","expiresAt":1785936600000,"subscriptionType":"max"}}"#
            .utf8
    )
    let credentials = try Keychain.parse(stored)
    #expect(credentials.accessToken == "sk-ant-oat01-abc")
    #expect(credentials.subscription == "max")
    #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1785936600))
}
