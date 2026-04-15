//
//  LibraryTheme.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/15.
//

import SwiftUI
import UIKit

enum LibraryTheme {
    static let background = Color.libraryDynamic(light: 0xF7F5EF, dark: 0x11151A)
    static let surface = Color.libraryDynamic(light: 0xFFFFFF, dark: 0x1B2026)
    static let surfaceSecondary = Color.libraryDynamic(light: 0xF2F5F9, dark: 0x252C35)
    static let accent = Color.libraryDynamic(light: 0x038B5D, dark: 0x23B27C)
    static let title = Color.libraryDynamic(light: 0x121E34, dark: 0xF3F7FA)
    static let bodyText = Color.libraryDynamic(light: 0x4C596D, dark: 0xD7DEE8)
    static let secondaryText = Color.libraryDynamic(light: 0x98A3BC, dark: 0x9EA7B6)
    static let tertiaryText = Color.libraryDynamic(light: 0xA6ACBD, dark: 0x7E8796)
    static let icon = Color.libraryDynamic(light: 0x6E788F, dark: 0xB7C0CE)
    static let stroke = Color.libraryDynamic(light: 0xE0E3EB, dark: 0x313846)
    static let divider = Color.libraryDynamic(light: 0xE9EBF0, dark: 0x262D37)
    static let success = Color.libraryDynamic(light: 0x1D9A52, dark: 0x69D68A)
    static let info = Color.libraryDynamic(light: 0x2563EB, dark: 0x79A8FF)
    static let destructive = Color.libraryDynamic(light: 0xD64545, dark: 0xFF7B72)
}

struct LibraryFormChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(LibraryTheme.background)
    }
}

extension View {
    func libraryFormChrome() -> some View {
        modifier(LibraryFormChromeModifier())
    }
}

private extension Color {
    static func libraryDynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traitCollection in
            UIColor(rgbHex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgbHex: UInt32) {
        let red = CGFloat((rgbHex >> 16) & 0xFF) / 255
        let green = CGFloat((rgbHex >> 8) & 0xFF) / 255
        let blue = CGFloat(rgbHex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
