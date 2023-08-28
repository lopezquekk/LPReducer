//
//  File.swift
//  
//
//  Created by juan.lopez on 27/08/23.
//

import Foundation

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
