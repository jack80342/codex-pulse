import Foundation

/// 只关闭当前登录创建的服务；唤醒同步等待，释放账号租约。
public final class LoginCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var client: AppServerClient?
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func bind(_ client: AppServerClient) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        self.client = client
    }

    func unbind() {
        lock.lock()
        client = nil
        lock.unlock()
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        let active = client
        lock.unlock()
        // close 可能等待子进程退出，不能阻塞界面线程。
        DispatchQueue.global(qos: .userInitiated).async { active?.close() }
    }
}
