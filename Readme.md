# ``LPReducer``

A Swift-way Reducer to control the view state safely


## Overview

Hace algun tiempo hemos venido cocechando la idea de cambiar algunos conceptos que damos por snetados en el desarrollo en swift, las arquitecturas que usabamos o usamos con UIKit no consideramos que apliquen o que en realidad sean igual de efectivas en SwiftUI, cambiar de paradigma también significa cambiar de herramientas y también empezar a cambiar nuestra forma de ver.

Este es un primer paso para pasar de una arquitecturea enfocada en `closure/eventos` a pasar a una arquitectura `orientada a estados`.

En las arquitecturas orientadas a estados los modelos de MVVM/VIPER... tienen varios problemas los cuales creemos se pueden solucionar teniendo un control estricto del estado.

Problema No 1: El estado no está unificado, en muchos proyectos UIKit este problema es recurrente pero realmente no era considerado un problema ya que como una variable maneja una independencia con relación a las otras solo bastaba con definirlas una después de la otra.

Problema No 2: Multiples fuentes de la verdad

Problema No 3: Modificacion de las variables en diferentes hilos

Problema No 4: Un flujo no muy claro en relación a la lógica de negocio vs capa de presentación

Ahora swift ha cambiado su paradigma pero lejos de solucionar los problemas para muchos equipos esto ha sido un problema aun mas grande, no por falta de conocimiento pero sí por venir acostumbrados a un antiguo paradigma.

```swift

struct TodoReducer: Reducer {
    //Include here all your dependencies
    var api: ANYAPIYOUUSE

    struct State: Equatable {
        var list: [Todo] = []
        var selectedTodo: Todo?
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
