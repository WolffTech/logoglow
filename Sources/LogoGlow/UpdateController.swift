// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
import Observation
import Sparkle

@MainActor
@Observable
final class UpdateController {
    private(set) var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false {
        didSet {
            if oldValue != automaticallyChecksForUpdates {
                updater?.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
        }
    }
    var automaticallyDownloadsUpdates = false {
        didSet {
            if oldValue != automaticallyDownloadsUpdates {
                updater?.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
            }
        }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private var updater: SPUUpdater? { controller?.updater }

    var isAvailable: Bool { controller != nil }

    init(bundle: Bundle = .main) {
        let isInstalledAppBundle = bundle.bundleURL.pathExtension == "app"
        guard isInstalledAppBundle else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        refresh()
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func refresh() {
        automaticallyChecksForUpdates = updater?.automaticallyChecksForUpdates ?? false
        automaticallyDownloadsUpdates = updater?.automaticallyDownloadsUpdates ?? false
    }
}
