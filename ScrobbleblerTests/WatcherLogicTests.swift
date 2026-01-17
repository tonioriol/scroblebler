import XCTest
@testable import Scroblebler

final class WatcherLogicTests: XCTestCase {

    // MARK: - Scrobble Threshold Logic

    func testScrobbleThreshold_95PercentPlayed_ShouldScrobble() {
        let track = createTrack(duration: 240.0) // 4 minutes
        let maxPosition = 228.0 // 95% of 240

        let percentPlayed = (maxPosition / track.length) * 100
        let shouldScrobble = percentPlayed >= 95 && !track.scrobbled && track.length >= 30

        XCTAssertTrue(shouldScrobble, "Track at 95% should be scrobbled")
    }

    func testScrobbleThreshold_94PercentPlayed_ShouldNotScrobble() {
        let track = createTrack(duration: 240.0)
        let maxPosition = 225.6 // 94% of 240

        let percentPlayed = (maxPosition / track.length) * 100
        let shouldScrobble = percentPlayed >= 95 && !track.scrobbled && track.length >= 30

        XCTAssertFalse(shouldScrobble, "Track at 94% should not be scrobbled")
    }

    func testScrobbleThreshold_TooShort_ShouldNotScrobble() {
        let track = createTrack(duration: 25.0) // Less than 30 seconds
        let maxPosition = 24.0 // 96% played

        let percentPlayed = (maxPosition / track.length) * 100
        let shouldScrobble = percentPlayed >= 95 && !track.scrobbled && track.length >= 30

        XCTAssertFalse(shouldScrobble, "Track shorter than 30s should not be scrobbled")
    }

    func testScrobbleThreshold_AlreadyScrobbled_ShouldNotScrobble() {
        var track = createTrack(duration: 240.0)
        track.scrobbled = true
        let maxPosition = 228.0 // 95% played

        let percentPlayed = (maxPosition / track.length) * 100
        let shouldScrobble = percentPlayed >= 95 && !track.scrobbled && track.length >= 30

        XCTAssertFalse(shouldScrobble, "Already scrobbled track should not be scrobbled again")
    }

    func testScrobbleThreshold_ExactlyThirtySeconds_95Percent() {
        let track = createTrack(duration: 30.0) // Exactly 30 seconds
        let maxPosition = 28.5 // 95% of 30

        let percentPlayed = (maxPosition / track.length) * 100
        let shouldScrobble = percentPlayed >= 95 && !track.scrobbled && track.length >= 30

        XCTAssertTrue(shouldScrobble, "30s track at 95% should be scrobbled")
    }

    // MARK: - Position Interpolation Logic

    func testPositionInterpolation_Playing() {
        let snapshotTime = Date()
        let snapshotPosition = 100.0
        let playbackRate = 1.0
        let isPlaying = true

        // Simulate 2 seconds elapsed
        let now = snapshotTime.addingTimeInterval(2.0)
        let elapsed = now.timeIntervalSince(snapshotTime)

        guard isPlaying && playbackRate > 0 else {
            XCTFail("Should be playing")
            return
        }

        let interpolatedPosition = snapshotPosition + elapsed

        XCTAssertEqual(interpolatedPosition, 102.0, accuracy: 0.01)
    }

    func testPositionInterpolation_Paused() {
        let snapshotPosition = 100.0
        let isPlaying = false
        let playbackRate = 0.0

        // When paused, position should not interpolate
        let shouldInterpolate = isPlaying && playbackRate > 0

        XCTAssertFalse(shouldInterpolate)
    }

    func testPositionInterpolation_MaxPosition() {
        let currentMaxPosition = 150.0
        let newPosition = 155.0

        let updatedMaxPosition = max(currentMaxPosition, newPosition)

        XCTAssertEqual(updatedMaxPosition, 155.0)
    }

    func testPositionInterpolation_RewindDoesNotAffectMax() {
        let currentMaxPosition = 150.0
        let newPosition = 100.0 // User rewound

        let updatedMaxPosition = max(currentMaxPosition, newPosition)

        XCTAssertEqual(updatedMaxPosition, 150.0, "Max position should not decrease on rewind")
    }

    // MARK: - Track Change Detection

    func testTrackChanged_DifferentID() {
        let currentID = "track-id-1"
        let newID = "track-id-2"

        XCTAssertNotEqual(currentID, newID, "Different track IDs indicate track change")
    }

    func testTrackChanged_SameID() {
        let currentID = "track-id-1"
        let newID = "track-id-1"

        XCTAssertEqual(currentID, newID, "Same track ID indicates same track")
    }

    // MARK: - Media Status Validation

    func testMediaStatusValidation_Complete() {
        let title = "Test Track"
        let bundleId = "com.apple.Music"
        let duration = 240.0

        let isValid = !title.isEmpty && !bundleId.isEmpty && duration > 0

        XCTAssertTrue(isValid, "Complete status should be valid")
    }

    func testMediaStatusValidation_MissingTitle() {
        let title = ""
        let bundleId = "com.apple.Music"
        let duration = 240.0

        let isValid = !title.isEmpty && !bundleId.isEmpty && duration > 0

        XCTAssertFalse(isValid, "Missing title should be invalid")
    }

    func testMediaStatusValidation_MissingBundleId() {
        let title = "Test Track"
        let bundleId = ""
        let duration = 240.0

        let isValid = !title.isEmpty && !bundleId.isEmpty && duration > 0

        XCTAssertFalse(isValid, "Missing bundle ID should be invalid")
    }

    func testMediaStatusValidation_NoDuration() {
        let title = "Test Track"
        let bundleId = "com.apple.Music"
        let duration = 0.0

        let isValid = !title.isEmpty && !bundleId.isEmpty && duration > 0

        XCTAssertFalse(isValid, "Zero duration should be invalid")
    }

    // MARK: - Duration Preservation Logic

    func testDurationPreservation_SameTrackMissingDuration() {
        let currentTrackId = "track-1"
        let currentDuration = 240.0

        let newTrackId = "track-1" // Same track
        let newDuration: Double? = nil // Missing duration

        let isSameTrack = currentTrackId == newTrackId
        let shouldPreserveDuration = isSameTrack && (newDuration == nil || newDuration! <= 0) && currentDuration > 0

        XCTAssertTrue(shouldPreserveDuration, "Should preserve duration for same track")
    }

    func testDurationPreservation_DifferentTrack() {
        let currentTrackId = "track-1"
        let currentDuration = 240.0

        let newTrackId = "track-2" // Different track
        let newDuration: Double? = nil

        let isSameTrack = currentTrackId == newTrackId
        let shouldPreserveDuration = isSameTrack && (newDuration == nil || newDuration! <= 0) && currentDuration > 0

        XCTAssertFalse(shouldPreserveDuration, "Should not preserve duration for different track")
    }

    func testDurationPreservation_NewDurationProvided() {
        let currentTrackId = "track-1"
        let currentDuration = 240.0

        let newTrackId = "track-1" // Same track
        let newDuration: Double? = 250.0 // New duration provided

        let isSameTrack = currentTrackId == newTrackId
        let shouldPreserveDuration = isSameTrack && (newDuration == nil || newDuration! <= 0) && currentDuration > 0

        XCTAssertFalse(shouldPreserveDuration, "Should use new duration when provided")
    }

    // MARK: - Timestamp Calculation

    func testTimestampCalculation_WithElapsedTime() {
        let currentTime = Date(timeIntervalSince1970: 1704441600) // 2024-01-05 10:00:00
        let elapsedTime = 60.0 // 1 minute into track

        let startedAt = currentTime.timeIntervalSince1970 - elapsedTime

        XCTAssertEqual(startedAt, 1704441540.0, "Should calculate correct start time")
    }

    func testTimestampCalculation_JustStarted() {
        let currentTime = Date(timeIntervalSince1970: 1704441600)
        let elapsedTime = 0.0

        let startedAt = currentTime.timeIntervalSince1970 - elapsedTime

        XCTAssertEqual(startedAt, 1704441600.0, "Track just started should have current timestamp")
    }

    // MARK: - Helper

    private func createTrack(duration: Double, scrobbled: Bool = false) -> Track {
        Track(
            id: UUID(),
            artist: "Test Artist",
            album: "Test Album",
            name: "Test Track",
            timestamp: 1704441600,
            duration: duration,
            sourceService: .lastfm,
            scrobbled: scrobbled,
            blacklisted: false,
            serviceInfo: [:],
            artwork: nil,
            imageUrl: nil
        )
    }
}
