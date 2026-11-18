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
            VStack(alignment: .leading, spacing: 22) {
                Text("发送到电脑").font(.title2.bold())
                if model.devices.isEmpty {
                    Text("请先打开 CommandC，扫描 Windows CtrlV 上的二维码完成配对，再返回分享。").foregroundColor(.secondary)
                } else {
                    Picker("接收电脑", selection: Binding(get: { model.selectedId }, set: { model.select($0) })) { ForEach(model.devices) { Text($0.name).tag($0.id) } }.pickerStyle(.menu).disabled(model.busy || sent)
                }
                HStack { Image(systemName: "photo.on.rectangle"); Text("\(model.items.count) 份待发素材") }.font(.headline)
                if model.busy { ProgressView("正在处理…") }
                Text(model.message).foregroundColor(model.failure ? .orange : .secondary)
                Spacer()
                if sent { Button("完成") { finish() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity) }
                else { Button("确认发送") { Task { sent = await model.send() } }.buttonStyle(.borderedProminent).disabled(model.busy || model.target == nil || model.items.isEmpty).frame(maxWidth: .infinity) }
            }.padding(24).navigationTitle("CommandC").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { finish() }.disabled(model.busy) } }
        }.navigationViewStyle(.stack)
            .task { model.startDiscovery(); await model.importProviders(providers) }
            .onDisappear { model.cleanup() }
    }
}
