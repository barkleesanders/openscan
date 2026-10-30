import SwiftUI

struct ScanView: View {
    @Environment(ScanSession.self) private var session
    @Environment(ScanStore.self) private var store
    @Environment(MeasureState.self) private var measure

    @State private var pendingMesh: ScanMesh?
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if ScanSession.isSupported {
                LiveARView(session: session, measure: measure)
                    .ignoresSafeArea()
                    .overlay(alignment: .top) { hud }
                    .overlay(alignment: .bottom) { controls }
            } else {
                ContentUnavailableView("LiDAR required", systemImage: "camera.metering.unknown")
            }
        }
        .onDisappear { if session.state == .scanning { session.pause() } }
        .alert("Save scan", isPresented: Binding(get: { pendingMesh != nil },
                                                 set: { if !$0 { pendingMesh = nil } })) {
            TextField("Name", text: $name)
            Button("Save") { save() }
            Button("Discard", role: .destructive) { pendingMesh = nil; session.reset(); measure.clear() }
            Button("Keep scanning", role: .cancel) { pendingMesh = nil }
        }
        .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var hud: some View {
        VStack(spacing: 6) {
            Text("\(session.triangleCount.formatted()) triangles")
                .font(.headline.monospacedDigit())
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            if let readout = measure.summary {
                Text(readout)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Measurement \(readout)")
            }
            if let message = session.trackingMessage, session.state == .scanning {
                Text(message)
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button { measure.toggle() } label: {
                Image(systemName: measure.isActive ? "ruler.fill" : "ruler").frame(width: 44, height: 44)
            }
            .foregroundStyle(measure.isActive ? Color.yellow : Color.white)
            .disabled(session.state != .scanning && !measure.isActive)
            .accessibilityLabel(measure.isActive ? "Stop measuring" : "Measure")

            if measure.isActive {
                Button { measure.undo() } label: {
                    Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
                }
                .disabled(measure.points.isEmpty)
                .accessibilityLabel("Undo point")
            }

            Button { session.reset(); measure.clear() } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
            }
            .disabled(session.state == .idle)
            .accessibilityLabel("Reset")

            Button(action: toggle) {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                    if session.state == .scanning {
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
                    } else {
                        Circle().fill(.red).frame(width: 60, height: 60)
                    }
                }
            }
            .accessibilityLabel(session.state == .scanning ? "Pause" : "Start")

            Button(action: finish) {
                if isSaving {
                    ProgressView().frame(width: 44, height: 44)
                } else {
                    Image(systemName: "checkmark.circle.fill").frame(width: 44, height: 44)
                }
            }
            .disabled(session.state == .idle || session.triangleCount == 0 || isSaving)
            .accessibilityLabel("Finish")
        }
        .font(.title2)
        .foregroundStyle(.white)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 24)
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if session.state == .scanning { session.pause() } else { session.start() }
    }

    private func finish() {
        session.pause()
        let mesh = session.snapshot()
        guard !mesh.isEmpty else { return }
        name = Date.now.formatted(date: .abbreviated, time: .shortened)
        pendingMesh = mesh
    }

    private func save() {
        guard let mesh = pendingMesh else { return }
        pendingMesh = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await store.save(mesh, name: name.isEmpty ? "Scan" : name)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                session.reset(); measure.clear()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
