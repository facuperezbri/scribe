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
    private static let bottomMargin: CGFloat = 46
    private static let fadeDuration: TimeInterval = ScribeMotion.fast

    init(viewModel: DictationViewModel) {
        let hostingView = NSHostingView(
            rootView: RecordingOverlayView(phase: .hidden, elapsed: 0, inputLevel: 0, autoPasteResult: nil)
        )
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

        // `combineLatest` de a 4 publishers como máximo por llamada: se anida una segunda vez
        // para sumar `$lastAutoPasteResult` sin tocar la tupla ya existente. Ese resultado puede
        // llegar después de que la fase ya esté en `.done` (el paste es async) — ver comentario en
        // el caso `.done` de `apply(...)` sobre por qué el guard existente ya cubre ese caso común.
        cancellable = viewModel.$state
            .combineLatest(viewModel.$lastTranscriptionOutcome, viewModel.$recordingElapsed, viewModel.$inputLevel)
            .combineLatest(viewModel.$lastAutoPasteResult)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak viewModel] combined, autoPasteResult in
                guard let self, let viewModel else { return }
                let (_, _, elapsed, level) = combined
                self.apply(phase: viewModel.overlayPhase, elapsed: elapsed, level: level, autoPasteResult: autoPasteResult)
            }
    }

    private func apply(phase: RecordingOverlayPhase, elapsed: TimeInterval, level: Float, autoPasteResult: AutoPasteResult?) {
        hostingView.rootView = RecordingOverlayView(
            phase: phase,
            elapsed: elapsed,
            inputLevel: level,
            autoPasteResult: autoPasteResult
        )

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

    /// Centra la burbuja horizontalmente, cerca del borde inferior de la pantalla principal.
    /// Recalcula tamaño y posición en cada actualización visible porque el ancho del texto varía
    /// (por ejemplo, "Grabando 0:09" es más angosto que "Grabando 1:30").
    private func layoutPanel() {
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0, let screen = NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.midX - fittingSize.width / 2,
            y: visibleFrame.minY + Self.bottomMargin
        )
        panel.setFrame(NSRect(origin: origin, size: fittingSize), display: true)
    }
}
