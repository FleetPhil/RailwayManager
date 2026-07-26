//
//  Array.swift
//  ModelRailway
//
//  Created by Phil Diggens on 25/03/2025.
//

import Foundation


extension Array {
    func item(at index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element: Hashable {
    var isUnique: Bool {
        var seen = Set<Element>()
        return allSatisfy { seen.insert($0).inserted }
    }
}

struct ArrayQueue<T> {
    private var array: [T] = []
    private let capacity: Int?
    
    public init() {
        self.capacity = nil
    }
    
    public init(capacity: Int) {
        precondition(capacity > 0, "Capacity must be greater than zero.")
        self.capacity = capacity
    }

    // MARK: - Queue
    
    public mutating func enqueue(_ element: T, atStart: Bool = false) throws {
        if let maxCapacity = capacity, array.count >= maxCapacity {
            throw TrainError.queueError("Capacity exceeded")
        }
        if atStart {
            array.insert(element, at: 0)
        } else {
            array.append(element)
        }
    }
    
    public mutating func dequeue() -> T? {
        isEmpty ? nil : array.removeFirst()
    }
    
    public mutating func replace(at: Int, with: T) {
        array[at] = with
    }
    
    public mutating func clear() {
        array.removeAll()
    }
    
    public var isEmpty: Bool {
        array.isEmpty
    }
    
    public var count: Int {
        array.count
    }
    
    public func item(_ at: Int) -> T? {
        if at < array.count {
            array[at]
        } else {
            nil
        }
    }
    
    public var peek: T? {
        array.first
    }
}
