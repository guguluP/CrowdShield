//
//  Item.swift
//  CrowdShield
//
//  Created by Purushottam Patnaik on 8/4/26.
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
