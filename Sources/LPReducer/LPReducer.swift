import Foundation
import SwiftUI
import Combine

@dynamicMemberLookup
final class Store<R: Reducer>: ObservableObject {
    let reducer: R = R.init()
    private var cancellables: [AnyHashable: AnyCancellable] = [:]
    private var taskCancellables: [AnyHashable: Task<Void, Never>] = [:]
    private(set) lazy var objectWillChange = ObservableObjectPublisher()
    private var provisionalState: R.State
    private(set) var state: R.State {
        didSet {
            if state != oldValue {
                objectWillChange.send()
            }
        }
    }
    subscript<T>(dynamicMember keyPath: WritableKeyPath<R.State, T>) -> T {
        state[keyPath: keyPath]
    }

    init(initialState: R.State) {
        self.state = initialState
        self.provisionalState = state
    }
    
    deinit {
        #if DEBUG
            print("Leaving \(self)")
        #endif
    }
    
    @MainActor
    func binding<T>(_ keyPath: WritableKeyPath<R.State, T>) -> Binding<T> {
        Binding {
            self.provisionalState[keyPath: keyPath]
        } set: {
            self.provisionalState[keyPath: keyPath] = $0
            self.state = self.provisionalState
        }
    }
    
    @MainActor
    func binding<T>(_ keyPath: WritableKeyPath<R.State, T>, action: R.Action) -> Binding<T> {
        Binding {
            self.provisionalState[keyPath: keyPath]
        } set: {
            self.provisionalState[keyPath: keyPath] = $0
            self.state = self.provisionalState
            self.send(action)
        }
    }
    
    @MainActor
    func send(_ action: R.Action) {
        let operation = reducer.reduce(into: &provisionalState, action)
        state = provisionalState
        Task {
            await resolveOperation(operation)
        }
    }
    
    
    @MainActor
    private func resolveOperation(_ operation: Operation<R.Action>) async {
        switch operation {
        /// `.asyncSequence`
        /// A way for use asyncSequence based on a AsyncStream
        /// ```swift
        ///     return .asyncSequence(
        ///           stream: monitor.paths(),
        ///           cancellableId: "cancellableId") { result in
        ///               if let path = result as? NWPath {
        ///                  print(path.status)
        ///               }
        ///               await .printStatus(true)
        ///     }```
        ///  For using this case you'll need to create a asyncStream using
        ///  `AsyncStream<Sendable>`
        ///  ```swift
        ///     func paths() -> AsyncStream<Sendable> {
        ///         AsyncStream { continuation in
        ///             pathUpdateHandler = { path in
        ///             continuation.yield(path)
        ///         }
        ///         continuation.onTermination = { [weak self] _ in
        ///             self?.cancel()
        ///         }
        ///         start(queue: DispatchQueue(label: "NSPathMonitor.paths"))
        ///     }```
        ///  you can cancel it anytime by using `.cancel(cancellableId)`
        case let .asyncSequence(sequence, cancellableId, toExecute):
            let iterator = Task {
                for await res in sequence {
                    await send(toExecute(res))
                }
            }
            
            taskCancellables[cancellableId] = iterator
        /// This represent not additional action to perform
        case .none:
            break
        /// This case represent a background action that you want to perform in background like
        /// calling a service from the internet, this is suppose to be executed outside of the
        /// `MainActor` scope.
        /// Once this background process finishes it will trigger another action back on the `MainActor` context
        case let .task(nextAction):
            Task.detached(priority: .background) {
                await self.send(nextAction())
            }
        /// this work exactly the same way as `.task(nextAction)`
        /// but without trigger any other action
        case let .run(toExecute):
            Task.detached(priority: .background) {
                await toExecute()
            }
        /// This one wil trigger an new action in the `MainActor` context, recommended for synchronous processes
        case let .action(act):
            send(act)
        /// You can send two `Operations` for execute both one after the other
        case let .syncMerge(act1, act2):
            await resolveOperation(act1)
            await resolveOperation(act2)
        /// You can send two `Operations` concurrently
        case let .asyncMerge(act1, act2):
            await withTaskGroup(of: Void.self) { taskGroup in
                taskGroup.addTask {
                    await self.resolveOperation(act1)
                }
                
                taskGroup.addTask {
                    await self.resolveOperation(act2)
                }
            }
        /// This case will create a `Timer.publish`and you can execute a action for every iteration
        /// Cancel it any time by using: `.cancel()`
        ///
        /// ```swift
        ///     return .timer(
        ///         every: 1,
        ///         on: .main,
        ///         in: .default,
        ///         cancellableId: TimerID(),
        ///         action: .updateTime)```
        ///
        case let .timer(interval, runLoop, mode, cancellableId, action):
            let cancellable = Timer.publish(every: interval, on: runLoop, in: mode)
                .autoconnect()
                .sink { _ in
                    self.send(action)
                }
            cancellables[cancellableId] = cancellable
            
        case let .cancel(cancellableId):
            cancellables[cancellableId]?.cancel()
            taskCancellables[cancellableId]?.cancel()
        }
    }
}

protocol Reducer<State, Action> {
    associatedtype Action
    associatedtype State: Equatable
    
    init()
    
    @MainActor func reduce(into state: inout State, _ action: Action) -> Operation<Action>
}

indirect enum Operation<Action> {
    case asyncSequence(stream: AsyncStream<Sendable>,
                       cancellableId: AnyHashable,
                       @Sendable (Sendable) async -> Action)
    case syncMerge(Operation<Action>, Operation<Action>)
    case asyncMerge(Operation<Action>, Operation<Action>)
    case task(@Sendable () async -> Action)
    case run(() async -> Void)
    case action(Action)
    case timer(every: TimeInterval,
               on: RunLoop,
               in: RunLoop.Mode,
               cancellableId: AnyHashable,
               action: Action)
    case cancel(cancellable: AnyHashable)
    case none
}

