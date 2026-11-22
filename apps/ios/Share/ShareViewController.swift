import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let inputs = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = inputs.flatMap { $0.attachments ?? [] }.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) }
        let host = UIHostingController(rootView: ShareView(providers: providers, finish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
    }
}

private struct ShareView: View {
    let providers: [NSItemProvider]
    let finish: () -> Void
    @StateObject private var model = TransferModel()
    @State private var sent = false
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Send to Computer").font(.title2.bold())
                        if model.devices.isEmpty {
                            Text("Open CommandC and scan the QR code in CtrlV for Windows or CommandV for Mac. Then return to this share sheet.")
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Computer", selection: Binding(get: { model.selectedId }, set: { model.select($0) })) {
                                ForEach(model.devices) { Text($0.name).tag($0.id) }
                            }.pickerStyle(.menu).disabled(model.busy || sent)
                        }
                        Label("Items ready: \(model.items.count)", systemImage: "photo.on.rectangle").font(.headline)
                        if model.busy { ProgressView("Working…") }
                        if !model.message.isEmpty {
                            Text(model.message).foregroundColor(model.failure ? .orange : .secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if sent {
                    Button(action: finish) { Text("Done").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button { Task { sent = await model.send() } } label: {
                        Text("Confirm Send").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).disabled(model.busy || model.target == nil || model.items.isEmpty)
                }
            }.padding(24).navigationTitle("CommandC").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { finish() }.disabled(model.busy) } }
        }.navigationViewStyle(.stack)
            .task { model.startDiscovery(); await model.importProviders(providers) }
            .onDisappear { model.cleanup() }
    }
}
