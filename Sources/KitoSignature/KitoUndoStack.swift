//
//  KitoUndoStack.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// A snapshot undo/redo history. `push` records a new state and forgets anything that was
/// undone; `undo` and `redo` step through the states.
///
/// ```swift
/// var history = KitoUndoStack([KitoSignatureStroke]())
/// history.push(strokes)          // after each stroke, clear or erase
/// strokes = history.undo() ?? strokes
/// ```
public struct KitoUndoStack<State: Equatable>: Equatable {
    private var past: [State]
    private var future: [State]
    public private(set) var current: State
    /// How many past states are kept; the oldest are dropped.
    public var limit: Int

    public init(_ initial: State, limit: Int = 100) {
        self.current = initial
        self.past = []
        self.future = []
        self.limit = max(limit, 1)
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var undoCount: Int { past.count }
    public var redoCount: Int { future.count }

    /// Records `state`. Does nothing if it equals the current state.
    public mutating func push(_ state: State) {
        guard state != current else { return }
        past.append(current)
        if past.count > limit { past.removeFirst(past.count - limit) }
        current = state
        future.removeAll()
    }

    /// Steps back, returning the restored state, or `nil` when there is nothing to undo.
    @discardableResult
    public mutating func undo() -> State? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        current = previous
        return previous
    }

    /// Steps forward again, returning the restored state, or `nil` when there is nothing to redo.
    @discardableResult
    public mutating func redo() -> State? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        current = next
        return next
    }

    /// Replaces the history with a single state.
    public mutating func reset(to state: State) {
        past.removeAll()
        future.removeAll()
        current = state
    }
}
