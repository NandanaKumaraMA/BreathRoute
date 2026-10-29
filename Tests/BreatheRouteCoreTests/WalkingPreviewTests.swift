import Foundation
import Testing
@testable import BreatheRouteCore

private let previewPath = [GeoCoordinate(latitude: 6.915, longitude: 79.864), GeoCoordinate(latitude: 6.916, longitude: 79.864), GeoCoordinate(latitude: 6.916, longitude: 79.865)]

@Test func previewMovesAlongThePathAndEndsExactlyAtDestination() throws {
    var player = try WalkingPreviewPlayback(coordinates: previewPath, speed: 1.5)
    #expect(player.coordinate == previewPath[0] && player.state == .paused)
    player.play(); player.advance(seconds: 10)
    #expect(abs(player.metres - 15) < 0.0001 && player.coordinate.latitude > previewPath[0].latitude)
    #expect(player.coordinate.longitude == previewPath[0].longitude)
    player.advance(seconds: 10_000)
    #expect(player.state == .completed && player.coordinate == previewPath.last)
    #expect(abs(player.movingSeconds - player.totalMetres / 1.5) < 0.0001)
}
@Test func previewPauseAndResumePreservePositionAndExampleMetrics() throws {
    var player = try WalkingPreviewPlayback(coordinates: previewPath, speed: 1.5)
    player.play(); player.advance(seconds: 12); player.pause()
    let position = player.coordinate, metrics = player.exampleMetrics
    player.advance(seconds: 40)
    #expect(player.coordinate == position && player.exampleMetrics == metrics && player.movingSeconds == 12)
    player.play(); player.advance(seconds: 2)
    #expect(player.metres == 21 && player.exampleMetrics.steps == 28)
}
@Test func previewRestoresRecordedProgressWithoutStartingAutomatically() throws {
    let player = try WalkingPreviewPlayback(coordinates: previewPath, speed: 1.5, startingMetres: 30, movingSeconds: 20)
    #expect(player.state == .paused && player.metres == 30 && player.exampleMetrics.steps == 40)
}
@Test func previewRejectsInvalidPathsSpeedsAndProgress() throws {
    for path in [[], [previewPath[0]], [previewPath[0], previewPath[0]], [.init(latitude: .nan, longitude: 0), previewPath[0]]] {
        #expect(throws: WalkPreviewError.invalidPath) { try WalkingPreviewPlayback(coordinates: path, speed: 1.5) }
    }
    for speed in [0.0, -1, .nan, .infinity, 4] {
        #expect(throws: WalkPreviewError.invalidPath) { try WalkingPreviewPlayback(coordinates: previewPath, speed: speed) }
    }
    #expect(throws: WalkPreviewError.invalidPath) { try WalkingPreviewPlayback(coordinates: previewPath, speed: 1.5, startingMetres: .nan) }
}
@Test func previewIgnoresInvalidTimeAndHandlesRepeatedVertices() throws {
    var player = try WalkingPreviewPlayback(coordinates: [previewPath[0], previewPath[0], previewPath[1]], speed: 1.5)
    player.play()
    for seconds in [0.0, -1, .nan, .infinity] { player.advance(seconds: seconds) }
    #expect(player.metres == 0 && player.coordinate == previewPath[0])
    player.advance(seconds: 1)
    #expect(player.coordinate.isValid && player.metres == 1.5)
}
@Test func previewInterpolatesAcrossTheDateLineWithoutCrossingTheWorld() throws {
    var player = try WalkingPreviewPlayback(coordinates: [.init(latitude: 0, longitude: 179.999), .init(latitude: 0, longitude: -179.999)], speed: 1.5)
    player.play(); player.advance(seconds: player.totalMetres / 3)
    #expect(abs(player.coordinate.longitude) > 179.99)
}
@Test func gpsPaceFallbackUsesMovementAndRejectsJumpsNoiseAndStalePairs() {
    #expect(GPSWalkingSpeed.estimate(metres: 6, seconds: 4, previousAccuracy: 4, accuracy: 4) == 1.5)
    for values in [(0.0, 4.0, 4.0), (100.0, 2.0, 4.0), (6.0, 30.0, 4.0), (6.0, 0.0, 4.0), (6.0, 4.0, 101.0), (1.0, 2.0, 50.0)] {
        #expect(GPSWalkingSpeed.estimate(metres: values.0, seconds: values.1, previousAccuracy: values.2, accuracy: values.2) == nil)
    }
}
