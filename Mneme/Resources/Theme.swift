//
//  Theme.swift
//  Mneme
//
//  Created by Emre Tekneci on 3.11.2025.
//

import SwiftUI

extension Color {
    // MARK: - Background Colors
    
    static func appBackground(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x1E1E1E) : Color(hex: 0xFFFFFF)
    }
    
    // MARK: - Accent Colors
    
    static let accent = Color(hex: 0xDF9105)
    
    // MARK: - Hex Initializer
    
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex & 0xFF0000) >> 16) / 255.0
        let g = Double((hex & 0x00FF00) >> 8) / 255.0
        let b = Double(hex & 0x0000FF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

