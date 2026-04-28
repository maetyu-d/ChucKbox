import AppKit
import SwiftUI

@main
struct ChuckDAWApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup("ChuckDAW") {
            ContentView()
                .environmentObject(model)
                .background(
                    WindowBootstrapper {
                        model.toggleMixerVisibility()
                    }
                )
        }
        .defaultSize(width: 1720, height: 980)
        .commands {
            CommandMenu("Transport") {
                Button("Panic Stop Audio") {
                    model.panicKillAllAudio()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }

            CommandGroup(after: .sidebar) {
                Divider()
                Toggle(
                    "Mixer",
                    isOn: Binding(
                        get: { model.isMixerVisible },
                        set: { model.setMixerVisibility($0) }
                    )
                )
                .keyboardShortcut(.tab, modifiers: [])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Form {
            Section("Engine") {
                TextField("ChucK Path", text: model.chuckPathBinding())
                    .onSubmit {
                        model.refreshEngineStatus()
                    }

                HStack(spacing: 10) {
                    Button("Auto Detect") {
                        model.autoDetectBinary()
                    }

                    Button("Test Audio") {
                        model.testEngine()
                    }

                    Text(model.engineStatus)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 620)
    }
}

private struct WindowBootstrapper: NSViewRepresentable {
    let onTab: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTab: onTab)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.configureWindowIfNeeded(from: view)
        }
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onTab = onTab
        DispatchQueue.main.async {
            context.coordinator.configureWindowIfNeeded(from: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        private var hasConfiguredWindow = false
        var onTab: () -> Void
        private var monitor: Any?

        init(onTab: @escaping () -> Void) {
            self.onTab = onTab
        }

        @MainActor
        func configureWindowIfNeeded(from view: NSView) {
            guard !hasConfiguredWindow, let window = view.window else { return }
            hasConfiguredWindow = true

            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
            window.setFrame(visibleFrame, display: true)
            window.minSize = NSSize(width: 1400, height: 820)
        }

        func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.keyCode == 48 && flags.isEmpty {
                    self.onTab()
                    return nil
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
