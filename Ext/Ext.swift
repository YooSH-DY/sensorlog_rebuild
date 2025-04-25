//
//  Ext.swift
//  Ext
//
//  Created by Velab on 4/21/25.
//

import AppIntents

struct Ext: AppIntent {
    static var title: LocalizedStringResource { "Ext" }
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
