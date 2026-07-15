import Foundation

struct WhiteLabelConfig {
    let key: String
    let appName: String
    let siteURL: URL
    let allowedHost: String
}

enum WhiteLabelResolver {
    private static let fallbackKey = "quarkgps"

    private static let configs: [String: WhiteLabelConfig] = [
        "quarkgps": WhiteLabelConfig(
            key: "quarkgps",
            appName: "QuarkGPS",
            siteURL: URL(string: "https://rastrear.quarkgps.com")!,
            allowedHost: "rastrear.quarkgps.com"
        ),
        "auramonitoramento": WhiteLabelConfig(
            key: "auramonitoramento",
            appName: "Aura Monitoramento",
            siteURL: URL(string: "https://auramonitoramento.com.br")!,
            allowedHost: "auramonitoramento.com.br"
        ),
        "rmrastreadores": WhiteLabelConfig(
            key: "rmrastreadores",
            appName: "RM Rastreadores",
            siteURL: URL(string: "https://rastrear.rmrastreadores.com/")!,
            allowedHost: "rastrear.rmrastreadores.com"
        ),
        "atualizasom": WhiteLabelConfig(
            key: "atualizasom",
            appName: "Atualizasom Rastreamento",
            siteURL: URL(string: "https://rastreamento.atualizasom.com.br/")!,
            allowedHost: "rastreamento.atualizasom.com.br"
        ),
        "trackergpsrastreamento": WhiteLabelConfig(
            key: "trackergpsrastreamento",
            appName: "Tracker GPS Rastreamento",
            siteURL: URL(string: "https://rastreamento.trackergpsrastreamento.com/")!,
            allowedHost: "rastreamento.trackergpsrastreamento.com"
        )
    ]

    static func current(bundle: Bundle = .main) -> WhiteLabelConfig {
        if let loadedConfig = loadFromBundledProperties(bundle: bundle) {
            return loadedConfig
        }

        let configuredKey = (bundle.object(forInfoDictionaryKey: "WhiteLabelKey") as? String)?.lowercased()
        let selectedKey = configuredKey ?? fallbackKey
        return configs[selectedKey] ?? configs[fallbackKey]!
    }

    private static func loadFromBundledProperties(bundle: Bundle) -> WhiteLabelConfig? {
        guard let url = bundle.url(forResource: "Branding", withExtension: "properties") else {
            return nil
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let values = parseProperties(contents)
        guard
            let key = values["key"]?.lowercased(),
            let appName = values["appName"],
            let siteURLString = values["siteURL"],
            let siteURL = URL(string: siteURLString),
            let allowedHost = values["allowedHost"]
        else {
            return nil
        }

        return WhiteLabelConfig(
            key: key,
            appName: appName,
            siteURL: siteURL,
            allowedHost: allowedHost
        )
    }

    private static func parseProperties(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]

        contents.enumerateLines { line, _ in
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                return
            }

            let parts = trimmedLine.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                return
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            values[key] = value
        }

        return values
    }
}
