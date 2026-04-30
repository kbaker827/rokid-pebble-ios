import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var vm: HubViewModel
    @State private var showSettings = false

    init() {
        let s = SettingsStore()
        _settings = StateObject(wrappedValue: s)
        _vm = StateObject(wrappedValue: HubViewModel(settings: s))
    }

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(vm: vm)
                    .navigationTitle("Rokid Hub")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar { toolbarItems }
                    .background(Color(.systemGroupedBackground))
            }
            .tabItem { Label("Hub", systemImage: "antenna.radiowaves.left.and.right") }

            NavigationStack {
                PebblePreviewView(vm: vm)
                    .navigationTitle("Pebble Preview")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbarItems }
                    .background(Color(.systemGroupedBackground))
            }
            .tabItem { Label("Watch", systemImage: "applewatch") }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings, vm: vm)
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack(spacing: 4) {
                Circle()
                    .fill(vm.pebble.connectionState == .connected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(vm.pebble.connectionState == .connected
                     ? (vm.pebble.watchName ?? "Watch")
                     : "No watch")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
    }
}
