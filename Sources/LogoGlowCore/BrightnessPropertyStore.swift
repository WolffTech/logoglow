// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import Foundation

/// Key-value access to corebrightnessd. Abstracted so tests can substitute a fake.
public protocol BrightnessPropertyStore {
    func value(forKey key: String) -> Any?
    func setValue(_ value: Any, forKey key: String) -> Bool
    func setValueOnKeyboards(_ value: Any, forKey key: String)
}

/// Talks to corebrightnessd through the private `BrightnessSystemClient` class in
/// CoreBrightness.framework. No root or entitlement is needed for the logo keys.
public struct CoreBrightnessStore: BrightnessPropertyStore {
    private typealias CopyProperty = @convention(c) (NSObject, Selector, NSString) -> Unmanaged<AnyObject>?
    private typealias SetProperty = @convention(c) (NSObject, Selector, AnyObject, NSString) -> Bool
    private typealias SetKeyboardProperty = @convention(c) (NSObject, Selector, AnyObject, NSString, UInt64) -> Bool

    private static let copySelector = NSSelectorFromString("copyPropertyForKey:")
    private static let setSelector = NSSelectorFromString("setProperty:forKey:")
    private static let setKeyboardSelector = NSSelectorFromString("setProperty:withKey:keyboardID:")
    private static let keyboardIDsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")

    private let clientClass: NSObject.Type

    /// Returns nil when CoreBrightness or its client class is missing, such as after an
    /// incompatible macOS update.
    public init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("BrightnessSystemClient") as? NSObject.Type,
              cls.instancesRespond(to: Self.copySelector),
              cls.instancesRespond(to: Self.setSelector)
        else { return nil }
        clientClass = cls
    }

    // A fresh client per call keeps the store valid across corebrightnessd restarts, which
    // the full-range unlock causes. A call costs about 0.15 ms, which is negligible even for effects.
    private func makeClient() -> NSObject {
        clientClass.init()
    }

    public func value(forKey key: String) -> Any? {
        let client = makeClient()
        let imp = client.method(for: Self.copySelector)
        let copy = unsafeBitCast(imp, to: CopyProperty.self)
        // The copy-prefixed selector returns a +1 reference.
        return copy(client, Self.copySelector, key as NSString)?.takeRetainedValue()
    }

    public func setValue(_ value: Any, forKey key: String) -> Bool {
        let client = makeClient()
        let imp = client.method(for: Self.setSelector)
        let set = unsafeBitCast(imp, to: SetProperty.self)
        return set(client, Self.setSelector, value as AnyObject, key as NSString)
    }

    public func setValueOnKeyboards(_ value: Any, forKey key: String) {
        guard clientClass.instancesRespond(to: Self.setKeyboardSelector),
              let keyboardClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type,
              keyboardClass.instancesRespond(to: Self.keyboardIDsSelector),
              let ids = keyboardClass.init().perform(Self.keyboardIDsSelector)?.takeRetainedValue() as? [NSNumber]
        else { return }
        let client = makeClient()
        let imp = client.method(for: Self.setKeyboardSelector)
        let set = unsafeBitCast(imp, to: SetKeyboardProperty.self)
        for id in ids {
            _ = set(client, Self.setKeyboardSelector, value as AnyObject, key as NSString, id.uint64Value)
        }
    }
}
