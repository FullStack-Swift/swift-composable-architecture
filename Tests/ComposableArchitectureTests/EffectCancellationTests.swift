import Combine
import XCTest

@testable import ComposableArchitecture

final class EffectCancellationTests: XCTestCase {
  struct CancelToken: Hashable {}
  var cancellables: Set<AnyCancellable> = []

  override func tearDown() {
    super.tearDown()
    self.cancellables.removeAll()
  }

  func testCancellation() {
    var values: [Int] = []

    let subject = PassthroughSubject<Int, Never>()
    let effect = Effect(subject)
      .cancellable(id: CancelToken())

    effect
      .sink { values.append($0) }
      .store(in: &self.cancellables)

    XCTAssertNoDifference(values, [])
    subject.send(1)
    XCTAssertNoDifference(values, [1])
    subject.send(2)
    XCTAssertNoDifference(values, [1, 2])

    Effect<Never, Never>.cancel(id: CancelToken())
      .sink { _ in }
      .store(in: &self.cancellables)

    subject.send(3)
    XCTAssertNoDifference(values, [1, 2])
  }

  func testCancelInFlight() {
    var values: [Int] = []

    let subject = PassthroughSubject<Int, Never>()
    Effect(subject)
      .cancellable(id: CancelToken(), cancelInFlight: true)
      .sink { values.append($0) }
      .store(in: &self.cancellables)

    XCTAssertNoDifference(values, [])
    subject.send(1)
    XCTAssertNoDifference(values, [1])
    subject.send(2)
    XCTAssertNoDifference(values, [1, 2])

    Effect(subject)
      .cancellable(id: CancelToken(), cancelInFlight: true)
      .sink { values.append($0) }
      .store(in: &self.cancellables)

    subject.send(3)
    XCTAssertNoDifference(values, [1, 2, 3])
    subject.send(4)
    XCTAssertNoDifference(values, [1, 2, 3, 4])
  }

  func testCancellationAfterDelay() {
    var value: Int?

    Just(1)
      .delay(for: 0.15, scheduler: DispatchQueue.main)
      .eraseToEffect()
      .cancellable(id: CancelToken())
      .sink { value = $0 }
      .store(in: &self.cancellables)

    XCTAssertNoDifference(value, nil)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      Effect<Never, Never>.cancel(id: CancelToken())
        .sink { _ in }
        .store(in: &self.cancellables)
    }

    _ = XCTWaiter.wait(for: [self.expectation(description: "")], timeout: 0.3)

    XCTAssertNoDifference(value, nil)
  }

  func testCancellationAfterDelay_WithTestScheduler() {
    let scheduler = DispatchQueue.test
    var value: Int?

    Just(1)
      .delay(for: 2, scheduler: scheduler)
      .eraseToEffect()
      .cancellable(id: CancelToken())
      .sink { value = $0 }
      .store(in: &self.cancellables)

    XCTAssertNoDifference(value, nil)

    scheduler.advance(by: 1)
    Effect<Never, Never>.cancel(id: CancelToken())
      .sink { _ in }
      .store(in: &self.cancellables)

    scheduler.run()

    XCTAssertNoDifference(value, nil)
  }

  func testCancellablesCleanUp_OnComplete() {
    Just(1)
      .eraseToEffect()
      .cancellable(id: 1)
      .sink(receiveValue: { _ in })
      .store(in: &self.cancellables)

    XCTAssertNoDifference([:], cancellationCancellables)
  }

  func testCancellablesCleanUp_OnCancel() {
    let scheduler = DispatchQueue.test
    Just(1)
      .delay(for: 1, scheduler: scheduler)
      .eraseToEffect()
      .cancellable(id: 1)
      .sink(receiveValue: { _ in })
      .store(in: &self.cancellables)

    Effect<Int, Never>.cancel(id: 1)
      .sink(receiveValue: { _ in })
      .store(in: &self.cancellables)

    XCTAssertNoDifference([:], cancellationCancellables)
  }

  func testDoubleCancellation() {
    var values: [Int] = []

    let subject = PassthroughSubject<Int, Never>()
    let effect = Effect(subject)
      .cancellable(id: CancelToken())
      .cancellable(id: CancelToken())

    effect
      .sink { values.append($0) }
      .store(in: &self.cancellables)

    XCTAssertNoDifference(values, [])
    subject.send(1)
    XCTAssertNoDifference(values, [1])

    Effect<Never, Never>.cancel(id: CancelToken())
      .sink { _ in }
      .store(in: &self.cancellables)

    subject.send(2)
    XCTAssertNoDifference(values, [1])
  }

  func testCompleteBeforeCancellation() {
    var values: [Int] = []

    let subject = PassthroughSubject<Int, Never>()
    let effect = Effect(subject)
      .cancellable(id: CancelToken())

    effect
      .sink { values.append($0) }
      .store(in: &self.cancellables)

    subject.send(1)
    XCTAssertNoDifference(values, [1])

    subject.send(completion: .finished)
    XCTAssertNoDifference(values, [1])

    Effect<Never, Never>.cancel(id: CancelToken())
      .sink { _ in }
      .store(in: &self.cancellables)

    XCTAssertNoDifference(values, [1])
  }

  func testConcurrentCancels() {
    let queues = [
      DispatchQueue.main,
      DispatchQueue.global(qos: .background),
      DispatchQueue.global(qos: .default),
      DispatchQueue.global(qos: .unspecified),
      DispatchQueue.global(qos: .userInitiated),
      DispatchQueue.global(qos: .userInteractive),
      DispatchQueue.global(qos: .utility),
    ]

    let effect = Effect.merge(
      (1...1_000).map { idx -> Effect<Int, Never> in
        let id = idx % 10

        return Effect.merge(
          Just(idx)
            .delay(
              for: .milliseconds(Int.random(in: 1...100)), scheduler: queues.randomElement()!
            )
            .eraseToEffect()
            .cancellable(id: id),

          Just(())
            .delay(
              for: .milliseconds(Int.random(in: 1...100)), scheduler: queues.randomElement()!
            )
            .flatMap { Effect.cancel(id: id) }
            .eraseToEffect()
        )
      }
    )

    let expectation = self.expectation(description: "wait")
    effect
      .sink(receiveCompletion: { _ in expectation.fulfill() }, receiveValue: { _ in })
      .store(in: &self.cancellables)
    self.wait(for: [expectation], timeout: 999)

    XCTAssertTrue(cancellationCancellables.isEmpty)
  }

  func testNestedCancels() {
    var effect = Empty<Void, Never>(completeImmediately: false)
      .eraseToEffect()
      .cancellable(id: 1)

    for _ in 1 ... .random(in: 1...1_000) {
      effect = effect.cancellable(id: 1)
    }

    effect
      .sink(receiveValue: { _ in })
      .store(in: &cancellables)

    cancellables.removeAll()

    XCTAssertNoDifference([:], cancellationCancellables)
  }

  func testSharedId() {
    let scheduler = DispatchQueue.test

    let effect1 = Just(1)
      .delay(for: 1, scheduler: scheduler)
      .eraseToEffect()
      .cancellable(id: "id")

    let effect2 = Just(2)
      .delay(for: 2, scheduler: scheduler)
      .eraseToEffect()
      .cancellable(id: "id")

    var expectedOutput: [Int] = []
    effect1
      .sink { expectedOutput.append($0) }
      .store(in: &cancellables)
    effect2
      .sink { expectedOutput.append($0) }
      .store(in: &cancellables)

    XCTAssertNoDifference(expectedOutput, [])
    scheduler.advance(by: 1)
    XCTAssertNoDifference(expectedOutput, [1])
    scheduler.advance(by: 1)
    XCTAssertNoDifference(expectedOutput, [1, 2])
  }

  func testImmediateCancellation() {
    let scheduler = DispatchQueue.test

    var expectedOutput: [Int] = []
    // Don't hold onto cancellable so that it is deallocated immediately.
    _ = Deferred { Just(1) }
      .delay(for: 1, scheduler: scheduler)
      .eraseToEffect()
      .cancellable(id: "id")
      .sink { expectedOutput.append($0) }

    XCTAssertNoDifference(expectedOutput, [])
    scheduler.advance(by: 1)
    XCTAssertNoDifference(expectedOutput, [])
  }

  func testNestedMergeCancellation() {
    let effect = Effect<Int, Never>.merge(
      (1...2).publisher
        .eraseToEffect()
        .cancellable(id: 1)
    )
    .cancellable(id: 2)

    var output: [Int] = []
    effect
      .sink { output.append($0) }
      .store(in: &cancellables)

    XCTAssertEqual(output, [1, 2])
  }
}
