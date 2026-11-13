import Foundation
#if canImport(Network)
import Network
#endif

#if canImport(Network)
/// Apple 平台网络路径守卫：共享 NWPathMonitor，路径失效时让进行中的请求快速失败。
nonisolated enum NetworkPathGuard {
    private static let state = PathState()

    /// 全局共享监视器，首次使用时启动。
    static let monitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            state.update(path.status)
        }
        monitor.start(queue: DispatchQueue(label: "SwiftOpenAI.NetworkPathGuard", qos: .utility))
        return monitor
    }()

    /// 路径是否已确认失效。
    /// 注意：NWPathMonitor 首次更新到达前 currentPath 恒为 unsatisfied（已实测），
    /// 必须等首次更新后才可判定，否则会误杀启动窗口内的首个请求。
    static var isPathUnsatisfied: Bool {
        _ = monitor // 确保监视器已启动
        return state.isUnsatisfied
    }

    private final class PathState: @unchecked Sendable {
        private let lock = NSLock()
        private var hasReceivedUpdate = false
        private var unsatisfied = false

        var isUnsatisfied: Bool {
            lock.withLock { hasReceivedUpdate && unsatisfied }
        }

        func update(_ status: NWPath.Status) {
            lock.withLock {
                hasReceivedUpdate = true
                unsatisfied = status == .unsatisfied
            }
        }
    }
}

private enum NetworkPathGuardOutcome<T: Sendable>: Sendable {
    case value(T)
    case failure(Error)
    case pathLost
    case cancelled
}
#endif

/// 包裹整个流式操作的网络路径守卫。
///
/// - 发起前路径已失效：立即抛 ``OpenAIError/networkConnectionLost``。
/// - 进行中路径失效（如 Wi-Fi 断开）：取消操作并抛 ``OpenAIError/networkConnectionLost``。
/// - 用户主动取消仍按 `CancellationError` 传播。
/// - 非 Apple 平台为透传，无额外开销。
nonisolated func withNetworkPathGuard<T: Sendable>(
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    #if canImport(Network)
    if NetworkPathGuard.isPathUnsatisfied {
        throw OpenAIError.networkConnectionLost
    }

    return try await withThrowingTaskGroup(of: NetworkPathGuardOutcome<T>.self) { group in
        // 监视任务：轻量轮询监视器缓存的最新路径，失效立即返回。
        group.addTask {
            while !Task.isCancelled {
                if NetworkPathGuard.isPathUnsatisfied {
                    return .pathLost
                }
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    return .cancelled
                }
            }
            return .cancelled
        }
        // 操作任务：所有错误装入结果，避免组内抛出干扰首个结果的判定。
        group.addTask {
            do {
                return .value(try await operation())
            } catch {
                return .failure(error)
            }
        }

        guard let first = try await group.next() else {
            throw CancellationError()
        }
        group.cancelAll()
        switch first {
        case .value(let value):
            return value
        case .failure(let error):
            throw error
        case .pathLost:
            throw OpenAIError.networkConnectionLost
        case .cancelled:
            throw CancellationError()
        }
    }
    #else
    return try await operation()
    #endif
}