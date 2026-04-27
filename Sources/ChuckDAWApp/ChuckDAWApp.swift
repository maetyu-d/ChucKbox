import AppKit
import SwiftUI

@main
struct ChuckDAWApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup("ChuckDAW") {
            ContentView()
                .environmentObject(model)
                .background(WindowBootstrapper())
        }
        .defaultSize(width: 1720, height: 980)

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
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.configureWindowIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.configureWindowIfNeeded(from: nsView)
        }
    }

    final class Coordinator {
        private var hasConfiguredWindow = false

        @MainActor
        func configureWindowIfNeeded(from view: NSView) {
            guard !hasConfiguredWindow, let window = view.window else { return }
            hasConfiguredWindow = true

            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
            window.setFrame(visibleFrame, display: true)
            window.minSize = NSSize(width: 1400, height: 820)
        }
    }
}
