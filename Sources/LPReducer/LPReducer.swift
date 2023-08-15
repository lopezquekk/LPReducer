import Foundation
import SwiftUI
import Combine

@dynamicMemberLookup
/// Store, is a class which owns the `state`, the `reducer` and the `actions`
@MainActor
public final class Store<R: Reducer>: ObservableObject {
    let reducer: R = R.init()
    private var cancellables: [AnyHashable: AnyCancellable] = [:]
    private var taskCancellables: [AnyHashable: Task<Void, Never>] = [:]
    
    private var provisionalState: R.State
    
    /// The state will look for changes comparing the `newState` and `oldState`
    /// if so, `objectWillChange.send()` is triggered and the view will be refreshed
    /// since the `state` is private for setting you won't be able to modifying from another place different from the reducer function.
    private(set) var state: R.State {
        didSet {
            if state.refreshState != oldValue.refreshState {
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
    
    
    /// This function manages binding variables between reducer and the view
    /// - Parameter keyPath: The Path from the state, avoiding reusing the word `state`
    /// - Returns: a controled binding variable
    /// ``` swift
    ///     Text(store.binding(\.myStateText))
    /// ```
    public func binding<T>(_ keyPath: WritableKeyPath<R.State, T>) -> Binding<T> {
        Binding {
            self.provisionalState[keyPath: keyPath]
        } set: {
            self.provisionalState[keyPath: keyPath] = $0
            self.state = self.provisionalState
        }
    }
    
    
    /// This function manages binding variables between reducer and the view
    /// - Parameters:
    ///   - keyPath: The Path from the state, avoiding reusing the word `state`
    ///   - action: an Action for tracking the binding changes.
    /// - Returns: a controled binding variable
    /// ``` swift
    ///     Text(store.binding(\.myStateText), .myAction)
    ///
    ///     //.... The Store
    ///
    ///     case .myAction:
    ///         print(state.myStateText)
    /// ```
    public func binding<T>(_ keyPath: WritableKeyPath<R.State, T>, action: R.Action) -> Binding<T> {
        Binding {
            self.provisionalState[keyPath: keyPath]
        } set: {
            self.provisionalState[keyPath: keyPath] = $0
            self.state = self.provisionalState
            self.send(action)
        }
    }
    
    func send(_ action: R.Action) {
        let operation = reducer.reduce(into: &provisionalState, action)
        state = provisionalState
        Task {
            await resolveOperation(operation)
        }
    }
    
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
        case let .task(cancellableId, nextAction):
            let task = Task.detached(priority: .background) {
                guard Task.isCancelled else { return }
                await self.send(nextAction())
            }
            taskCancellables[cancellableId] = task
            /// this work exactly the same way as `.task(nextAction)`
            /// but without trigger any other action
        case let .run(cancellableId, toExecute):
            let task = Task.detached(priority: .background) {
                guard Task.isCancelled else { return }
                await toExecute()
            }
            taskCancellables[cancellableId] = task
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

/// Reducer Protocol
///
/// Use this protocol for conforming a presentation entity
/// this entity will contain the `State` and `Action` definition
/// in the `reduce` function you'll need to implement all the logic for every single action triggered
/// you can return an operation for use asyncronous resources such as endpoint callings, timers, asyncSequences and so, anyway if you don't want to perform any aditional task just return `Operation.none`
///
/// We strongly recommend you to use a struct for defining a reducer
///
/// ```swift
///
///struct TodoReducer: Reducer {
///     //Include here all your dependencies
///     var api: ANYAPIYOUUSE
///
///     struct State: Equatable {
///         var list: [Todo] = []
///         var selectedTodo: Todo?
///     }
///
///     enum Action {
///         case onAppear
///         case onTodosLoaded(Swift.Result<[Todos]>)
///         case onDisappear
///         case selectTodo(Todo)
///     }
///
///     func reduce(into state: inout State, _ action: Action) -> Operation<Action> {
///         switch action {
///             case .onAppear:
///                 return .task {
///                     let todos = await api.callTodos()
///                     return .onTodosLoaded(todos)
///                 }
///             case let .onTodosLoaded(.success(todos)):
///                 state.list = todos
///             case let .onTodosLoaded(.failure(error)):
///                 // control your errors
///                 print(error)
///             case .onDisappear:
///                 // clean everything or cancel subscriptions
///             case let .selectTodo(todo):
///             state.selectedTodo = todo
///         }
///     }
///}
/// ```
public protocol Reducer<State, Action> {
    associatedtype Action
    associatedtype State: Equatable, StateProtocol
    
    init()
    
    /// Everytime the view or any operation sends an action, this function is triggered
    @MainActor func reduce(into state: inout State, _ action: Action) -> Operation<Action>
}

@dynamicMemberLookup
public protocol StateProtocol {
    associatedtype StaticState
    associatedtype RefreshState: Equatable
    
    var refreshState: RefreshState { set get }
    var staticState: StaticState { set get }
}

extension StateProtocol {
    subscript<T>(dynamicMember keyPath: WritableKeyPath<RefreshState, T>) -> T {
        refreshState[keyPath: keyPath]
    }
}

public indirect enum Operation<Action> {
    case asyncSequence(stream: AsyncStream<Sendable>,
                       cancellableId: AnyHashable,
                       @Sendable (Sendable) async -> Action)
    case syncMerge(Operation<Action>, Operation<Action>)
    case asyncMerge(Operation<Action>, Operation<Action>)
    case task(cancellableId: AnyHashable, @Sendable () async -> Action)
    case run(cancellableId: AnyHashable, () async -> Void)
    case action(Action)
    case timer(every: TimeInterval,
               on: RunLoop,
               in: RunLoop.Mode,
               cancellableId: AnyHashable,
               action: Action)
    case cancel(cancellable: AnyHashable)
    case none
}

