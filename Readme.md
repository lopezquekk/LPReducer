# ``LPReducer``

A Swift-way Reducer to control the view state safely


## Overview

Some time ago, I've been entertaining the idea of changing certain concepts that we've taken for granted in Swift development. The architectures we used or use with UIKit don't seem to apply or be equally effective in SwiftUI. Shifting paradigms also entails changing tools and adjusting our perspective.

This marks the initial step towards transitioning from a closure/event-focused architecture to a state-driven architecture.

In state-driven architectures, MVVM/VIPER... models face several issues that we believe can be resolved by maintaining strict control over the state.

Issue No. 1: State disunity. In many UIKit projects, this problem recurs, but it wasn't considered significant because each variable's independence from the others meant that defining them one after another sufficed.

Issue No. 2: Multiple sources of truth.

Issue No. 3: Variable modifications across different threads.

Issue No. 4: Unclear flow between business logic and presentation layer.

Swift has now shifted its paradigm, but rather than solving problems, for many teams, this has turned into an even greater challenge. This isn't due to a lack of knowledge but rather because of the deeply ingrained familiarity with the old paradigm.

```swift

struct TodoReducer: Reducer {
    //Include here all your dependencies
    var api: ANYAPIYOUUSE

    struct State: Equatable {
/// changes on this struct/var will affect the UI and the view will refresh
/// you can access to this state without using the keyword ´refreshState´
        var refreshState: RefreshState = RefreshState()
/// changes on this struct/var won't affect the UI and the view won't refresh
        var staticState: StaticState = StaticState()

/// changes on this struct/var won't affect the UI and the view won't refresh
        struct StaticState: Equatable {
            var numberOfRows = 0
        }
        
        struct RefreshState: Equatable {
            var list: [Todo] = []
            var selectedTodo: Todo?
        }
    }

    enum Action {
        case onAppear
        case onTodosLoaded(Swift.Result<[Todos]>)
        case onDisappear
        case selectTodo(Todo)
    }

    func reduce(into state: inout State, _ action: Action) -> Operation<Action> {
        switch action {
            case .onAppear:
                return .task {
                    let todos = await api.callTodos()
                    return .onTodosLoaded(todos)
                }
            case let .onTodosLoaded(.success(todos)):
                state.list = todos
            case let .onTodosLoaded(.failure(error)):
                // control your errors
                print(error)
            case .onDisappear:
                // clean everything or cancel subscriptions
            case let .selectTodo(todo):
            state.selectedTodo = todo
        }
    }
}
```
