import Foundation
import SwiftUI
import Combine

@dynamicMemberLookup
final class TestableStore<R: Reducer>: ObservableObject {
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
    
    var changes: [(state: R.State, action: R.Action)] = []
    subscript<T>(dynamicMember keyPath: WritableKeyPath<R.State, T>) -> T {
        state[keyPath: keyPath]
    }

    init(initialState: R.State) {
        self.state = initialState
        self.provisionalState = state
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
            Task { await self.send(action) }
        }
    }
    
    @MainActor
    func send(_ action: R.Action) async {
        let operation = reducer.reduce(into: &provisionalState, action)
        state = provisionalState
        changes.append((state: state, action: action))
        await resolveOperation(operation)
    }
    
    @MainActor
    func cancellAll() {
        cancellables.forEach { _, item in
            item.cancel()
        }
    }
    
    @MainActor
    func getActionsPerformed() -> [R.Action] {
        changes.map { $0.action }
    }
    
    @MainActor
    func getLastState() -> R.State? {
        changes.last?.state
    }
    
    @MainActor
    private func resolveOperation(_ operation: Operation<R.Action>) async {
        switch operation {
        case let .asyncSequence(sequence, cancellableId, toExecute):
            let iterator = Task {
                for await res in sequence {
                    await send(toExecute(res))
                }
            }
            
            taskCancellables[cancellableId] = iterator
        case .none:
            break
        case let .task(nextAction):
            Task.detached(priority: .background) {
                await self.send(nextAction())
            }
        case let .run(toExecute):
            Task.detached(priority: .background) {
                await toExecute()
            }
        case let .action(act):
            await send(act)
        case let .syncMerge(act1, act2):
            await resolveOperation(act1)
            await resolveOperation(act2)
        case let .asyncMerge(act1, act2):
            await withTaskGroup(of: Void.self) { taskGroup in
                taskGroup.addTask {
                    await self.resolveOperation(act1)
                }
                
                taskGroup.addTask {
                    await self.resolveOperation(act2)
                }
            }
        case let .timer(interval, runLoop, mode, cancellableId, action):
            let cancellable = Timer.publish(every: interval, on: runLoop, in: mode)
                .autoconnect()
                .sink { _ in
                    Task {
                        await self.send(action)
                    }
                }
            cancellables[cancellableId] = cancellable
            
        case let .cancel(cancellableId):
            cancellables[cancellableId]?.cancel()
        }
    }
}
