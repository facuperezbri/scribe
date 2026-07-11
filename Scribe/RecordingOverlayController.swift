import AppKit
import Combine
import SwiftUI

/// Dueño de la burbuja flotante: un `NSPanel` sin foco propio y no activable que
/// solo refleja `viewModel.overlayPhase` — no decide nada por su cuenta, así que no duplica el
/// flujo centralizado de `DictationViewModel`. Vive en AppKit, fuera del árbol de `Scene` de
/// `ScribeApp`, porque un panel `.nonactivatingPanel` con `orderFrontRegardless()` no tiene
/// equivalente directo en SwiftUI: cualquier `Window`/`WindowGroup` puede terminar activando la
/// app y robándole el foco a la app en la que esté el usuario, justo lo que evita el atajo global
/// (ver `docs/DECISIONS.md`).
@MainActor
final class RecordingOverlayController {
    private let panel: NSPanel
    private let hostingView: NSHostingView<RecordingOverlayView>
    private var cancellable: AnyCancellable?
    private var hideTask: Task<Void, Never>?
    private var lastPhase: RecordingOverlayPhase = .hidden
    private var isPanelVisible = false

    /// Cuánto se muestra "Listo" antes de desaparecer sola.
    private static let doneDisplayDuration: Duration = .milliseconds(1200)
    private static let topMargin: CGFloat = 46
    private static let fadeDuration: TimeInterval = 0.15

    init(viewModel: DictationViewModel) {
        let hostingView = NSHostingView(rootView: RecordingOverlayView(phase: .hidden, elapsed: 0, inputLevel: 0))
        self.hostingView = hostingView

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        self.panel = panel

        cancellable = viewModel.$state
            .combineLatest(viewModel.$lastTranscriptionOutcome, viewModel.$recordingElapsed, viewModel.$inputLevel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak viewModel] _, _, elapsed, level in
                guard let self, let viewModel else { return }
                self.apply(phase: viewModel.overlayPhase, elapsed: elapsed, level: level)
            }
    }

    private func apply(phase: RecordingOverlayPhase, elapsed: TimeInterval, level: Float) {
        hostingView.rootView = RecordingOverlayView(phase: phase, elapsed: elapsed, inputLevel: level)

        switch phase {
        case .hidden:
            hideTask?.cancel()
            hideTask = nil
            lastPhase = .hidden
            fadeOut()
        case .recording, .transcribing:
            hideTask?.cancel()
            hideTask = nil
            lastPhase = phase
            layoutPanel()
            if !isPanelVisible {
                fadeIn()
            }
        case .done:
            layoutPanel()
            guard lastPhase != .done else { return }
            lastPhase = .done
            if !isPanelVisible {
                fadeIn()
            }
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: Self.doneDisplayDuration)
                guard !Task.isCancelled else { return }
                self?.dismissDone()
            }
        }
    }

    private func dismissDone() {
        guard lastPhase == .done else { return }
        lastPhase = .hidden
        fadeOut()
    }

    /// Aparece/desaparece con un fundido corto en vez de un corte seco: sigue sin robar foco (el
    /// fundido no cambia `ignoresMouseEvents`/`nonactivatingPanel`), solo se siente menos abrupto.
    private func fadeIn() {
        isPanelVisible = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 1
        }
    }

    private func fadeOut() {
        guard isPanelVisible else { return }
        isPanelVisible = false
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                guard let self, !self.isPanelVisible else { return }
                self.panel.orderOut(nil)
            }
        )
    }

    /// Centra la burbuja horizontalmente, cerca del borde superior de la pantalla principal.
    /// Recalcula tamaño y posición en cada actualización visible porque el ancho del texto varía
    /// (por ejemplo, "Grabando 0:09" es más angosto que "Grabando 1:30").
    private func layoutPanel() {
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0, let screen = NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.midX - fittingSize.width / 2,
            y: visibleFrame.maxY - Self.topMargin - fittingSize.height
        )
        panel.setFrame(NSRect(origin: origin, size: fittingSize), display: true)
    }
}
