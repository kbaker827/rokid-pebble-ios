import Foundation

class SettingsStore: ObservableObject {
    // Tempest
    @Published var tempestEnabled: Bool {
        didSet { UserDefaults.standard.set(tempestEnabled, forKey: "rp_tempestEnabled") }
    }

    // Snapmaker
    @Published var snapmakerEnabled: Bool {
        didSet { UserDefaults.standard.set(snapmakerEnabled, forKey: "rp_snapmakerEnabled") }
    }
    @Published var snapmakerHost: String {
        didSet { UserDefaults.standard.set(snapmakerHost, forKey: "rp_snapmakerHost") }
    }
    @Published var snapmakerToken: String {
        didSet { UserDefaults.standard.set(snapmakerToken, forKey: "rp_snapmakerToken") }
    }

    // Pebble
    @Published var pebbleNameFilter: String {
        didSet { UserDefaults.standard.set(pebbleNameFilter, forKey: "rp_pebbleNameFilter") }
    }

    // Display
    @Published var showSummaryOnGlasses: Bool {
        didSet { UserDefaults.standard.set(showSummaryOnGlasses, forKey: "rp_summaryOnGlasses") }
    }

    init() {
        let ud = UserDefaults.standard
        tempestEnabled      = ud.object(forKey: "rp_tempestEnabled")    as? Bool   ?? true
        snapmakerEnabled    = ud.object(forKey: "rp_snapmakerEnabled")  as? Bool   ?? false
        snapmakerHost       = ud.string(forKey: "rp_snapmakerHost")                ?? ""
        snapmakerToken      = ud.string(forKey: "rp_snapmakerToken")               ?? ""
        pebbleNameFilter    = ud.string(forKey: "rp_pebbleNameFilter")             ?? "Pebble"
        showSummaryOnGlasses = ud.object(forKey: "rp_summaryOnGlasses") as? Bool  ?? true
    }
}
