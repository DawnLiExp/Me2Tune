//
//  Array+Extensions.swift
//  Me2Tune
//
//  数组安全访问扩展
//

import Foundation

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
