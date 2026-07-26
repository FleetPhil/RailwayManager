//import Foundation
//
//public typealias PointID = Int
//public typealias SignalID = Int
//public typealias SensorID = Int
//public typealias TrainID = Int
//public typealias LightID = Int
//
//protocol RailwayHardware: Sendable {
//    func setup() async throws
//    func resetTrack() async throws
//    func requestSession(forAddress address: Int) async throws
//    func releaseSession(_ session: Int) async throws
//    func sendKeepAlive(session: Int) async throws
//
//    func setPoint(id: PointID, direction: PointDirection) async throws
//    func resetPoint(id: PointID, to direction: PointDirection) async throws
//    func setSignal(id: SignalID, state: SignalState) async throws
//    func setLight(id: LightID, on: Bool) async
//    func setClocks(_ on: Bool) async
//
//    func powerTrain(train: Train, session: Int, direction: Direction, speed: TrainSpeed, delay: TimeInterval) async throws
//    func stopAllTrains() async
//
//    func events() throws -> AsyncStream<LayoutHardwareEvent>
//}
