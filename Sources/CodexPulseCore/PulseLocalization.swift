import Foundation

public enum PulseLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"

    public var locale: Locale { Locale(identifier: rawValue) }
}

/// 界面与服务层共用资源；按系统首选语言顺序选择，启动时确定语言。
public enum PulseLocalization {
    public static let currentLanguage = preferredLanguage(in: Locale.preferredLanguages)
    public static var locale: Locale { currentLanguage.locale }

    public static func preferredLanguage(in preferences: [String]) -> PulseLanguage {
        for preference in preferences {
            switch preference.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first {
            case "zh": return .chinese
            case "en": return .english
            default: continue
            }
        }
        return .english
    }

    static let resourceBundle: Bundle = {
        // 安装包优先从自身 Resources 加载，不依赖构建机器的绝对路径。
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(url: resources.appendingPathComponent("CodexPulse_CodexPulseCore.bundle")) {
            return bundle
        }
        return Bundle.module
    }()

    private static let languageBundles: [PulseLanguage: Bundle] = Dictionary(uniqueKeysWithValues:
        PulseLanguage.allCases.map { language in
            guard let url = resourceBundle.url(forResource: language.rawValue, withExtension: "lproj"),
                  let bundle = Bundle(url: url) else {
                preconditionFailure("Missing localization resources: \(language.rawValue)")
            }
            return (language, bundle)
        })

    public static func text(_ key: String, language: PulseLanguage = currentLanguage,
                            _ arguments: CVarArg...) -> String {
        guard let bundle = languageBundles[language] else {
            preconditionFailure("Missing localization bundle: \(language.rawValue)")
        }
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: language.locale, arguments: arguments)
    }

    public static func formatDate(_ date: Date, dateStyle: Date.FormatStyle.DateStyle,
                                  timeStyle: Date.FormatStyle.TimeStyle,
                                  language: PulseLanguage = currentLanguage) -> String {
        date.formatted(Date.FormatStyle(date: dateStyle, time: timeStyle).locale(language.locale))
    }
}
