//
//  Item.swift
//  polymarket-iosapp
//
//  Created by Kengo Shibata on 2026/10/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
