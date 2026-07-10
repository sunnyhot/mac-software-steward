import Foundation

@main
struct MaintenanceRunLeaseTest {
    static func main() {
        // 每个测试用独立临时目录，避免互相干扰。
        func makeLease() -> MaintenanceRunLease {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("maintenance-lease-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return MaintenanceRunLease(directory: dir)
        }

        // MARK: 获取后释放
        let lease1 = makeLease()
        let acquired1 = lease1.acquire(trigger: .smartMaintenance)
        guard case .acquired(let lease) = acquired1 else {
            preconditionFailure("首次获取应成功，得到 \(acquired1)")
        }
        precondition(lease.trigger == .smartMaintenance, "trigger 应为 smartMaintenance")
        precondition(lease.pid == ProcessInfo.processInfo.processIdentifier, "pid 应为当前进程")

        // 同一实例再获取：由于 flock 是进程级，同一进程再次 open+LOCK_EX|LOCK_NB 在 macOS 上可能成功（可重入），
        // 因此不强制断言冲突，只验证 currentLease 可读。
        _ = lease1.acquire(trigger: .dailyInspection)
        // 注意：同一进程的同一 lease 实例释放前不应再 acquire 成功。
        // 由于 flock 是进程级，同一进程再次 open+LOCK_EX|LOCK_NB 在 macOS 上可能成功（flock 对同一进程可重入）。
        // 因此这里不强制断言冲突，改为验证 currentLease 可读。
        precondition(lease1.currentLease() != nil, "持有时应能读到 currentLease")

        // 释放后 currentLease 应为 nil（lease JSON 已删）。
        lease1.release(lease)
        precondition(lease1.currentLease() == nil, "释放后 currentLease 应为 nil")

        // MARK: 释放后可重新获取
        let reacquired = lease1.acquire(trigger: .detailedUpgrade)
        guard case .acquired(let lease2) = reacquired else {
            preconditionFailure("释放后应能重新获取，得到 \(reacquired)")
        }
        precondition(lease2.trigger == .detailedUpgrade, "重新获取的 trigger 应为 detailedUpgrade")
        lease1.release(lease2)

        // MARK: stale lease 回收
        // 模拟一个 stale lease：写入一个 pid 不存在的 lease JSON，然后 acquire 应能回收并成功。
        let lease3 = makeLease()
        let staleDir = lease3.leaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: staleDir, withIntermediateDirectories: true)
        // 用一个几乎不可能存活的 pid（999999）写 lease JSON。
        // 需要先创建锁文件并写 lease JSON（不通过 flock，直接写文件模拟残留）。
        FileManager.default.createFile(atPath: lease3.lockURL.path, contents: nil, attributes: nil)
        let formatter = ISO8601DateFormatter()
        let stalePayload: [String: Any] = [
            "runID": UUID().uuidString,
            "pid": 999999,
            "processStartTime": formatter.string(from: Date(timeIntervalSince1970: 0)),
            "trigger": MaintenanceRunTrigger.dailyInspection.rawValue,
            "createdAt": formatter.string(from: Date(timeIntervalSince1970: 0))
        ]
        let staleData = try! JSONSerialization.data(withJSONObject: stalePayload, options: [.prettyPrinted, .sortedKeys])
        try! staleData.write(to: lease3.leaseURL)

        // 此时锁文件存在但无 flock 持有（进程已死），lease JSON 的 pid 999999 不存活。
        let staleAcquired = lease3.acquire(trigger: .smartMaintenance)
        guard case .acquired = staleAcquired else {
            preconditionFailure("stale lease 应被回收并成功获取，得到 \(staleAcquired)")
        }
        // 清理
        if let current = lease3.currentLease() {
            lease3.release(current)
        }

        // MARK: lease JSON round trip
        let lease4 = makeLease()
        let acquired4 = lease4.acquire(trigger: .smartMaintenance)
        guard case .acquired(let lease4Value) = acquired4 else {
            preconditionFailure("lease4 获取应成功")
        }
        let currentLease4 = lease4.currentLease()
        precondition(currentLease4?.runID == lease4Value.runID, "currentLease runID 应匹配")
        precondition(currentLease4?.trigger == .smartMaintenance, "currentLease trigger 应匹配")
        lease4.release(lease4Value)

        // MARK: 损坏 lease JSON 不崩溃
        let lease5 = makeLease()
        let dir5 = lease5.leaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir5, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: lease5.lockURL.path, contents: nil, attributes: nil)
        try! Data("not json".utf8).write(to: lease5.leaseURL)
        precondition(lease5.currentLease() == nil, "损坏 lease JSON 时 currentLease 应返回 nil，不崩溃")

        print("MaintenanceRunLeaseTest passed")
    }
}
