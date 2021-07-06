import XCTest
@testable import SwiftUICaseStudies
import ComposableArchitecture

class RefreshableTests: XCTestCase {

  func testTCA() {
    let store = TestStore(
      initialState: .init(),
      reducer: pullToRefreshReducer,
      environment: .init(
        fact: .init { .init(value: "\($0) is a good number.") },
        mainQueue: .immediate
      )
    )

    store.send(.incrementButtonTapped) {
      $0.count = 1
    }
    store.send(.refresh) {
      $0.isLoading = true
    }
    // Explain why it's ok to have this duplication of string
    store.receive(.factResponse(.success("1 is a good number."))) {
      $0.isLoading = false
      $0.fact = "1 is a good number."
    }
  }

  func testTCA_Cancellation() {
    let mainQueue = DispatchQueue.test

    let store = TestStore(
      initialState: .init(),
      reducer: pullToRefreshReducer,
      environment: .init(
        fact: .init { .init(value: "\($0) is a good number.") },
        mainQueue: mainQueue.eraseToAnyScheduler()
      )
    )

    store.send(.refresh) {
      $0.isLoading = true
    }
    store.send(.cancelButtonTapped) {
      $0.isLoading = false
    }
  }

  func testVanilla2() async {
    let viewModel = PullToRefreshViewModel(
      fetch: {
      await Task.sleep(1_000_000)
      return "\($0) is a good number."
    }
    )

    viewModel.incrementButtonTapped()
    XCTAssertEqual(viewModel.count, 1)

    let handle = async {
      await viewModel.getFact()
    }
    await Task.sleep(500_000)
    XCTAssertEqual(viewModel.isLoading, true)
    await handle.get()
    XCTAssertEqual(viewModel.isLoading, false)

    XCTAssertEqual(viewModel.fact, "1 is a good number.")
    XCTAssertEqual(viewModel.isLoading, false)
  }

  func testVanilla3() async {
    let viewModel = PullToRefreshViewModel(
      fetch: {
      await Task.sleep(1_000_000)
      return "\($0) is a good number."
    }
    )

    viewModel.incrementButtonTapped()
    XCTAssertEqual(viewModel.count, 1)

    let handle = async {
      await viewModel.getFact()
    }
    await Task.sleep(500_000)
    XCTAssertEqual(viewModel.isLoading, true)
    viewModel.cancelButtonTapped()
    XCTAssertEqual(viewModel.isLoading, false)
    await handle.get()

    XCTAssertEqual(viewModel.fact, "1 is a good number.")
    XCTAssertEqual(viewModel.isLoading, false)
  }

  func testVanilla1() async {
    let viewModel = PullToRefreshViewModel(
      fetch: { "\($0) is a good number."}
    )

    async let x: () = viewModel.getFact()
    await sleep(1_000)
//    await Task.sleep(1000000)

    XCTAssertEqual(viewModel.isLoading, true)
    viewModel.cancelButtonTapped()
    XCTAssertEqual(viewModel.isLoading, false)

    await x
    XCTAssertEqual(viewModel.fact, nil) 
  }
}

func sleep(_ duration: UInt64) async {
  _ = try! await URLSession.shared.data(
    from: URL(string: "https://laggard.herokuapp.com/delay/\(duration / 1_000_000)")!
  )
}
