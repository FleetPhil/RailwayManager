//
//  File.swift
//  
//
//  Created by Phil Diggens on 29/11/2024.
//

import Foundation

extension Sequence {
    func asyncMap<T: Sendable>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] where Element: Sendable {
        var values = [T]()

        for element in self {
            try await values.append(transform(element))
        }

        return values
    }

    func asyncCompactMap<T: Sendable>(
        _ transform: (Element) async throws -> T?
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            if let result = try await transform(element) {
                values.append(result)
            }
        }

        return values
    }
    
    func asyncFlatMap<T: Sequence>(
            _ transform: (Element) async throws -> T
        ) async rethrows -> [T.Element] {
            var values = [T.Element]()

            for element in self {
                try await values.append(contentsOf: transform(element))
            }

            return values
        }

    func asyncForEach(
            _ operation: (Element) async throws -> Void
        ) async rethrows {
            for element in self {
                try await operation(element)
            }
        }

}

