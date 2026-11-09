// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import Foundation

/// Key-value access to corebrightnessd. Abstracted so tests can substitute a fake.
public protocol BrightnessPropertyStore {
    func value(forKey key: String) -> Any?
    func setValue(_ value: Any, forKey key: String) -> Bool
}

/// Talks to corebrightnessd through the private `BrightnessSystemClient` class in
/// CoreBrightness.framework. No root or entitlement is needed for the logo keys.
public struct CoreBrightnessStore: BrightnessPropertyStore {
    private typealias CopyProperty = @convention(c) (NSObject, Selector, NSString) -> Unmanaged<AnyObject>?
    private typealias SetProperty = @convention(c) (NSObject, Selector, AnyObject, NSString) -> Bool

    private static let copySelector = NSSelectorFromString("copyPropertyForKey:")
    private static let setSelector = NSSelectorFromString("setProperty:forKey:")

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
    // the full-range unlock causes. Calls are rare (menu actions), so the cost is negligible.
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
}
