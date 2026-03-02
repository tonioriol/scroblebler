//
//  AppDelegate.swift
//  Scroblebler
//
//  Created by Victor Gama on 25/11/2022.
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    var popover: NSPopover!
    var statusBarItem: NSStatusItem!
    var launchAtLoginItem: NSMenuItem!
    var contextMenu: NSMenu!
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        contextMenu = NSMenu()
        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(self.toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        contextMenu.addItem(launchAtLoginItem)

        if Defaults.shared.firstRun {
            Defaults.shared.firstRun = false
            LaunchAtStartup.launchAtStartup = true
        }
        updateLaunchAtLogin()

        contextMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Scroblebler", action: #selector(self.applicationQuit), keyEquivalent: "")
        quitItem.target = self
        contextMenu.addItem(quitItem)

        let contentView = ContentView()
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 700)
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.delegate = self
        self.popover = popover

        self.statusBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))

        if let button = self.statusBarItem.button {
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            popover.contentViewController?.view.window?.makeKey()
            Task {
                try? await Task.sleep(nanoseconds: 500_000)
                DispatchQueue.main.async {
                    self.popover.performClose(self)
                }
            }
        }

        if let button = self.statusBarItem.button {
            if let image = NSImage(named: "app-logo-opaque") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            }
        }

        // Initialize network reachability monitoring
        _ = Reachability.shared

        // Auto-authenticate Last.fm web client, then flush pending listens.
        // Sequential to avoid race where deletes run before web client is ready.
        Task { @MainActor in
            await ScrobbleManager.shared.autoAuthenticateLastFmWebClient()
            SyncEngine.shared.scheduleProcessPending(reason: "launch")
            SyncEngine.shared.startPeriodicSync()
        }

        // Backfill plays from Music.app (catches iPhone/HomePod/CarPlay plays synced via iCloud)
        if #available(macOS 14.0, *) {
            MusicLibraryBackfill.shared.start()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func updateLaunchAtLogin() {
        if LaunchAtStartup.launchAtStartup {
            launchAtLoginItem.state = .on
        } else {
            launchAtLoginItem.state = .off
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = self.statusBarItem.button {
            let event = NSApp.currentEvent!
            if event.type == NSEvent.EventType.rightMouseUp {
                if self.popover.isShown {
                    closePopover()
                }

                NSMenu.popUpContextMenu(contextMenu, with: event, for: self.statusBarItem.button!)
            } else {
                if self.popover.isShown {
                    closePopover()
                } else {
                    self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
                    if let popoverWindow = popover.contentViewController?.view.window {
                        popoverWindow.level = .floating
                        popoverWindow.collectionBehavior = .fullScreenAuxiliary
                        popoverWindow.makeKey()
                    }
                    NotificationCenter.default.post(name: NSNotification.Name("ScrobleblerDidShow"), object: nil)

                    // When the UI is shown, try flushing any pending backlog.
                    // Debounced to avoid doing work if user rapidly opens/closes.
                    Task { @MainActor in
                        SyncEngine.shared.scheduleProcessPending(reason: "popover_open")
                    }

                    startMonitoring()
                }
            }
        }
    }

    func closePopover() {
        self.popover.performClose(nil)
        stopMonitoring()
    }

    func startMonitoring() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let strongSelf = self, strongSelf.popover.isShown {
                strongSelf.closePopover()
            }
        }
    }

    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func popoverWillClose(_ notification: Notification) {
        stopMonitoring()
        NotificationCenter.default.post(name: NSNotification.Name("ScrobleblerWillHide"), object: nil)
    }

    @objc func applicationQuit() {
        NSApplication.shared.terminate(self)
    }

    @objc func toggleLaunchAtLogin() {
        if launchAtLoginItem.state == .on {
            launchAtLoginItem.state = .off
            LaunchAtStartup.launchAtStartup = false
        } else {
            launchAtLoginItem.state = .on
            LaunchAtStartup.launchAtStartup = true
        }
        updateLaunchAtLogin()
    }

}
