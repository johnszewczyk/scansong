import AppKit
import ScanSongKit
import SwiftUI

struct ScannerOptionsView: View {
    @ObservedObject var model: ScannerAppModel
    @State private var selection: OptionsSection = .fileTypes

    private enum OptionsSection: String, Identifiable {
        case fileTypes = "File Types"

        var id: Self { self }
    }

    private let windowBackground = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    private let panelBackground = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("File Types") {
                    Label("Ignored Types", systemImage: "gearshape")
                        .tag(OptionsSection.fileTypes)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Options")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                        Text("Ignored Types")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        fileTypesPage
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(windowBackground)
        .background(OptionsWindowConfigurator())
    }

    private var fileTypesPage: some View {
        sectionCard(title: "Ignored Types") {
            Text("Checked types are skipped before scanner inspection because ScanSong has no usable decoder route for them. Uncheck a type only when you want its failures reported while developing support. Supported formats are never ignored because a member is malformed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.fileTypePolicies) { policy in
                    Toggle(isOn: Binding(
                        get: { model.isFileTypeIgnored(policy) },
                        set: { model.setFileTypeIgnored(policy.id, ignored: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(policy.displayName) (.\(policy.id))")
                                .foregroundStyle(.white)
                            Text(policy.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(model.isBusy)
                    .padding(.vertical, 10)

                    if policy.id != model.fileTypePolicies.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Divider()
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(panelBackground))
    }

    private struct OptionsWindowConfigurator: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { NSView() }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard let window = nsView.window else { return }
            window.minSize = NSSize(width: 620, height: 420)
            window.setFrameAutosaveName("ScanSong.Options")
        }
    }
}
