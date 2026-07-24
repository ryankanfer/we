//
//  DesignSystem.swift
//  WE
//
//  Created by Ryan Kanfer on 7/24/26.
//

import SwiftUI

extension Font {
    static var weLargeTitle: Font {
        .system(size: 34, weight: .regular, design: .serif)
    }

    static var weTitle: Font {
        .system(size: 24, weight: .regular, design: .serif)
    }

    static var weHeadline: Font {
        .system(size: 17, weight: .semibold)
    }

    static var weBody: Font {
        .system(size: 16, weight: .regular)
    }

    static var weCaption: Font {
        .system(size: 12, weight: .medium)
    }
}
