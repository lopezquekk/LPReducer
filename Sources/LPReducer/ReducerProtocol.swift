//
//  ReducerProtocol.swift
//  
//
//  Created by juan.lopez on 27/08/23.
//

import Foundation

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
