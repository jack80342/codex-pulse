import CodexPulseCore
import CodexPulseUI
import Foundation
import ServiceManagement
import Testing

@MainActor
private final class LoginItemFixture {
    var status: SMAppService.Status = .notRegistered
    var registrations = 0
    var removals = 0
    var approvalRequired = false
    var fails = false
    var defaultApplied = false

    func model(installed: Bool = true) -> LoginItemModel {
        LoginItemModel(isInstalled: installed, readStatus: { self.status }, register: {
            self.registrations += 1
            if self.fails { throw NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "private details"]) }
            self.status = self.approvalRequired ? .requiresApproval : .enabled
        }, unregister: {
            self.removals += 1
            if self.fails { throw NSError(domain: "test", code: 43) }
            self.status = .notRegistered
        }, readDefaultApplied: { self.defaultApplied }, saveDefaultApplied: { self.defaultApplied = true })
    }
}

@MainActor
struct LoginItemModelTests {
    @Test
    func firstInstalledLaunchEnablesOnceAndRestartKeepsManualOff() async {
        let fixture = LoginItemFixture()
        let model = fixture.model()
        await model.applyDefaultIfNeeded()
        #expect(model.status == .enabled)
        #expect(fixture.defaultApplied)
        await model.applyDefaultIfNeeded()
        #expect(fixture.registrations == 1)
        await model.setEnabled(false)
        let restarted = fixture.model()
        await restarted.applyDefaultIfNeeded()
        #expect(!restarted.isEnabled)
        #expect(fixture.registrations == 1)
    }

    @Test
    func systemDisabledLoginItemIsNotReenabledOnLaterLaunch() async {
        let fixture = LoginItemFixture()
        await fixture.model().applyDefaultIfNeeded()
        fixture.status = .notRegistered
        await fixture.model().applyDefaultIfNeeded()
        #expect(fixture.status == .notRegistered)
        #expect(fixture.registrations == 1)
    }

    @Test
    func firstLaunchDefaultCanWaitForApprovalWithoutRegisteringTwice() async {
        let fixture = LoginItemFixture()
        fixture.approvalRequired = true
        await fixture.model().applyDefaultIfNeeded()
        #expect(fixture.status == .requiresApproval)
        await fixture.model().applyDefaultIfNeeded()
        #expect(fixture.registrations == 1)
    }

    @Test
    func existingEnabledLoginItemIsNotRegisteredAgain() async {
        let fixture = LoginItemFixture()
        fixture.status = .enabled
        await fixture.model().applyDefaultIfNeeded()
        #expect(fixture.registrations == 0)
        #expect(fixture.defaultApplied)
    }

    @Test
    func developmentLaunchDoesNotConsumeDefaultInitialization() async {
        let fixture = LoginItemFixture()
        await fixture.model(installed: false).applyDefaultIfNeeded()
        #expect(!fixture.defaultApplied)
        #expect(fixture.registrations == 0)
        await fixture.model().applyDefaultIfNeeded()
        #expect(fixture.registrations == 1)
    }

    @Test
    func initialFailureIsReportedAndManualRetryRemainsAvailable() async {
        let fixture = LoginItemFixture()
        fixture.fails = true
        let model = fixture.model()
        await model.applyDefaultIfNeeded()
        #expect(!model.isEnabled && model.error != nil)
        await model.applyDefaultIfNeeded()
        #expect(fixture.registrations == 1)
        fixture.fails = false
        await model.setEnabled(true)
        #expect(model.isEnabled && model.error == nil)
    }

    @Test
    func systemStatusControlsSwitchAndExternalChangesAreReflected() async {
        let fixture = LoginItemFixture()
        let model = fixture.model()
        #expect(!model.isEnabled)
        await model.setEnabled(true)
        #expect(model.isEnabled && model.status == .enabled)
        #expect(fixture.registrations == 1)
        await model.setEnabled(true)
        #expect(fixture.registrations == 1)
        fixture.status = .requiresApproval
        model.refresh()
        #expect(model.isEnabled && model.status == .requiresApproval)
        await model.setEnabled(false)
        #expect(!model.isEnabled && model.status == .notRegistered)
        #expect(fixture.removals == 1)
    }

    @Test
    func pendingApprovalNeverClaimsEnabledStatus() async {
        let fixture = LoginItemFixture()
        fixture.approvalRequired = true
        let model = fixture.model()
        await model.setEnabled(true)
        #expect(model.status == .requiresApproval)
        #expect(model.error == nil)
        await model.setEnabled(false)
        #expect(model.status == .notRegistered)
    }

    @Test
    func failedChangeRetainsActualStatusAndSanitizesError() async {
        let fixture = LoginItemFixture()
        fixture.fails = true
        let model = fixture.model()
        await model.setEnabled(true)
        #expect(!model.isEnabled)
        #expect(model.error?.contains("42") == true)
        #expect(model.error?.contains("private") == false)
        #expect(!model.isChanging)
        fixture.fails = false
        await model.setEnabled(true)
        fixture.fails = true
        await model.setEnabled(false)
        #expect(model.isEnabled)
        #expect(model.error?.contains("43") == true)
    }

    @Test
    func developmentCopyDoesNotRegisterLoginItem() async {
        let fixture = LoginItemFixture()
        let model = fixture.model(installed: false)
        await model.setEnabled(true)
        #expect(!model.isEnabled)
        #expect(fixture.registrations == 0)
        #expect(model.error == PulseLocalization.text("loginItem.installRequired"))
    }

    @Test
    func unsuccessfulSystemTransitionDoesNotPretendItSucceeded() async {
        let model = LoginItemModel(isInstalled: true, readStatus: { .notRegistered }, register: {}, unregister: {},
                                   readDefaultApplied: { false }, saveDefaultApplied: {})
        await model.setEnabled(true)
        #expect(!model.isEnabled)
        #expect(model.error != nil)
    }
}
