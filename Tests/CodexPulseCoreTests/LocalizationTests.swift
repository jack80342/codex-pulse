@testable import CodexPulseCore
import Foundation
import Testing

struct LocalizationTests {
    @Test
    func preferredLanguageUsesTheFirstSupportedLanguageAndDefaultsToEnglish() {
        #expect(PulseLocalization.preferredLanguage(in: ["en-US", "zh-Hans-CN"]) == .english)
        #expect(PulseLocalization.preferredLanguage(in: ["zh-Hans-CN", "en-US"]) == .chinese)
        #expect(PulseLocalization.preferredLanguage(in: ["ja-JP", "en-GB", "zh-CN"]) == .english)
        #expect(PulseLocalization.preferredLanguage(in: ["fr-FR", "zh-CN", "en"]) == .chinese)
        #expect(PulseLocalization.preferredLanguage(in: ["ja-JP"]) == .english)
        #expect(PulseLocalization.preferredLanguage(in: []) == .english)
        #expect(PulseLocalization.preferredLanguage(in: ["zhuang", "english"]) == .english)
    }

    @Test
    func chineseAndEnglishRegionAndScriptVariantsAreRecognized() {
        for preference in ["zh", "zh-CN", "zh-Hans-SG", "zh-Hant-TW", "ZH_hant_HK"] {
            #expect(PulseLocalization.preferredLanguage(in: [preference]) == .chinese)
        }
        for preference in ["en", "en-GB", "en-CN", "EN_us"] {
            #expect(PulseLocalization.preferredLanguage(in: [preference]) == .english)
        }
    }

    @Test
    func translationsHaveIdenticalKeysAndFormatArgumentsAndEnglishContainsNoChinese() throws {
        var tables: [PulseLanguage: [String: String]] = [:]
        for language in PulseLanguage.allCases {
            let directory = try #require(PulseLocalization.resourceBundle.url(forResource: language.rawValue, withExtension: "lproj"))
            let data = try Data(contentsOf: directory.appendingPathComponent("Localizable.strings"))
            tables[language] = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let english = try #require(tables[.english])
        let chinese = try #require(tables[.chinese])
        #expect(!english.isEmpty)
        #expect(Set(english.keys) == Set(chinese.keys))
        let placeholders = try NSRegularExpression(pattern: "%(@|ld|%)")
        for (key, value) in english {
            let translation = try #require(chinese[key])
            #expect(!value.isEmpty && !translation.isEmpty)
            #expect(!value.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) })
            func tokens(_ string: String) -> [String] {
                placeholders.matches(in: string, range: NSRange(string.startIndex..., in: string))
                    .compactMap { Range($0.range, in: string).map { String(string[$0]) } }
            }
            #expect(tokens(value) == tokens(translation))
            #expect(PulseLocalization.text(key, language: .english) == value)
            #expect(PulseLocalization.text(key, language: .chinese) == translation)
        }
    }

    @Test
    func formattedTranslationsPreserveNamesCountsErrorCodesAndPercentSigns() {
        #expect(PulseLocalization.text("ui.accounts.one", language: .english, 1) == "1 account")
        #expect(PulseLocalization.text("ui.accounts.many", language: .english, 6) == "6 accounts")
        #expect(PulseLocalization.text("ui.accounts.many", language: .chinese, 6) == "6 个账号")
        #expect(PulseLocalization.text("quota.remaining", language: .english, "51.5") == "51.5% remaining")
        #expect(PulseLocalization.text("quota.remaining", language: .chinese, "51.5") == "剩余 51.5%")
        #expect(PulseLocalization.text("status.duplicatePair", language: .english, "alice", "bob") == "alice and bob")
        #expect(PulseLocalization.text("error.profile.http", language: .english, 401) == "Account profile query failed (HTTP 401).")
        #expect(PulseLocalization.text("loginItem.error", language: .chinese, 42) == "无法更改登录启动设置（错误代码 42）。")
    }

    @Test
    func datesUseTheSelectedInterfaceLanguage() {
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        let english = PulseLocalization.formatDate(date, dateStyle: .abbreviated, timeStyle: .omitted, language: .english)
        let chinese = PulseLocalization.formatDate(date, dateStyle: .abbreviated, timeStyle: .omitted, language: .chinese)
        #expect(english != chinese)
        #expect(!english.contains("年"))
        #expect(chinese.contains("年"))
    }
}
