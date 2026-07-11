import XCTest
@testable import Scribe

@MainActor
final class RecordingMeterTests: XCTestCase {
    func testStartTicksWithTheCurrentInputLevel() async {
        let audioRecorder = FakeAudioRecordingService()
        audioRecorder.level = 0.42
        let meter = RecordingMeter(audioRecorder: audioRecorder)

        var lastLevel: Float?
        var tickCount = 0
        meter.start { _, level in
            lastLevel = level
            tickCount += 1
        }

        try? await Task.sleep(for: .milliseconds(450))
        meter.stop()

        XCTAssertGreaterThanOrEqual(tickCount, 2, "debería haber sondeado más de una vez en 450ms con un intervalo de 200ms")
        XCTAssertEqual(lastLevel, 0.42)
    }

    func testStopPreventsFurtherTicks() async {
        let audioRecorder = FakeAudioRecordingService()
        let meter = RecordingMeter(audioRecorder: audioRecorder)

        var tickCount = 0
        meter.start { _, _ in tickCount += 1 }
        try? await Task.sleep(for: .milliseconds(250))
        meter.stop()
        let countAtStop = tickCount

        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(tickCount, countAtStop, "no debería seguir sondeando después de stop()")
    }
}
