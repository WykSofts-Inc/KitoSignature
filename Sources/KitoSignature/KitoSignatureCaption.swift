//
//  KitoSignatureCaption.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// The small line under a signature: "Signed by Wycliff N · 24 Sep 2026".
public struct KitoSignatureCaption: Equatable, Sendable {
    public var signerName: String
    public var date: Date
    /// "Wycliff N" instead of "Wycliff Njenga".
    public var abbreviatesSurname: Bool
    public var locale: Locale

    public init(signerName: String, date: Date = Date(), abbreviatesSurname: Bool = true,
                locale: Locale = .current) {
        self.signerName = signerName
        self.date = date
        self.abbreviatesSurname = abbreviatesSurname
        self.locale = locale
    }

    /// The caption, e.g. "Signed by Wycliff N · 24 Sep 2026". Without a name: "Signed · 24 Sep 2026".
    public var text: String {
        let name = abbreviatesSurname ? Self.shortName(signerName) : Self.clean(signerName)
        let day = Self.dateText(date, locale: locale)
        return name.isEmpty ? "Signed · \(day)" : "Signed by \(name) · \(day)"
    }

    /// "Wycliff Njenga" → "Wycliff N", "Amina Wanjiru Odhiambo" → "Amina O", "Cher" → "Cher".
    public static func shortName(_ fullName: String) -> String {
        let words = clean(fullName).split(separator: " ")
        guard let first = words.first else { return "" }
        guard words.count > 1, let initial = words.last?.first else { return String(first) }
        return "\(first) \(String(initial).uppercased())"
    }

    /// "24 Sep 2026".
    public static func dateText(_ date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    static func clean(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
