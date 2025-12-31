//  Copyright © 2024 PRND. All rights reserved.
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif


public extension HTMLStyleContainer {
    var link: AttributeScopes.FoundationAttributes.LinkAttribute.Value? {
        get { container.link }
        set { container.link = newValue }
    }
    
    var foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.Value? {
        get { container.foregroundColor }
        set { container.foregroundColor = newValue }
    }
    
    var backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.Value? {
        get { container.backgroundColor }
        set { container.backgroundColor = newValue }
    }
    
    var inlinePresentationIntent: AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.Value? {
        get { container.inlinePresentationIntent }
        set { container.inlinePresentationIntent = newValue }
    }
    
#if os(macOS)
    var uiFont: AttributeScopes.AppKitAttributes.FontAttribute.Value? {
        get { container.appKit.font }
        set {
            container.swiftUI.font = nil
            container.appKit.font = newValue
        }
    }
#else
    var uiFont: AttributeScopes.UIKitAttributes.FontAttribute.Value? {
        get { container.uiKit.font }
        set {
            container.swiftUI.font = nil
            container.uiKit.font = newValue
        }
    }
#endif
    
    var font: AttributeScopes.SwiftUIAttributes.FontAttribute.Value? {
        get { container.swiftUI.font }
        set {
#if os(macOS)
            container.appKit.font = nil
#else
            container.uiKit.font = nil
#endif
            container.swiftUI.font = newValue
        }
    }
    
#if os(macOS)
    var underlineStyle: AttributeScopes.AppKitAttributes.UnderlineStyleAttribute.Value? {
        get { container.underlineStyle }
        set { container.underlineStyle = newValue }
    }

    var underlineColor: AttributeScopes.AppKitAttributes.UnderlineColorAttribute.Value? {
        get { container.underlineColor }
        set { container.underlineColor = newValue}
    }

    var kern: AttributeScopes.AppKitAttributes.KernAttribute.Value? {
        get { container.kern }
        set { container.kern = newValue }
    }

    var tracking: AttributeScopes.AppKitAttributes.TrackingAttribute.Value? {
        get { container.tracking }
        set { container.tracking = newValue }
    }
#else
    var underlineStyle: AttributeScopes.UIKitAttributes.UnderlineStyleAttribute.Value? {
        get { container.underlineStyle }
        set { container.underlineStyle = newValue }
    }

    var underlineColor: AttributeScopes.UIKitAttributes.UnderlineColorAttribute.Value? {
        get { container.underlineColor }
        set { container.underlineColor = newValue}
    }

    var kern: AttributeScopes.UIKitAttributes.KernAttribute.Value? {
        get { container.kern }
        set { container.kern = newValue }
    }

    var tracking: AttributeScopes.UIKitAttributes.TrackingAttribute.Value? {
        get { container.tracking }
        set { container.tracking = newValue }
    }
#endif
    
    func merging(_ other: HTMLStyleContainer, mergePolicy: AttributedString.AttributeMergePolicy = .keepNew) -> HTMLStyleContainer {
        var copy = self
        copy.container = container.merging(other.container, mergePolicy: mergePolicy)
        copy.textLine = other.textLine ?? textLine
        return copy
    }
}
