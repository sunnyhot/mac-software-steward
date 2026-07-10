import Foundation

// MARK: - Cross-process maintenance run lease
//
// Foundation-only 跨进程租约，GUI 应用与后台 Agent 共用。
// 通过独占锁文件确保同一时刻只有一个维护运行。
// PID 复用防护：校验 pid 存活且进程启动时间与记录一致。
// 设计依据：docs/superpowers/specs/2026-07-10-unified-maintenance-engine-dashboard-design.md

/// Foundation-only 的跨进程维护租约实现。
///
/// 锁机制：用 `open(O_CREAT|O_EXLOCK)` 对锁文件做独占 flock。
/// 竞争方获取时若拿不到锁（已有活跃 lease），读取锁文件旁的 lease JSON 判断是否 stale。
/// stale lease（pid 不存活或启动时间不匹配）会被回收并标记关联 run 为 interrupted。
final class MaintenanceRunLease: MaintenanceRunLeasing {
    let lockURL: URL
    let leaseURL: URL
    /// 持有的文件描述符；释放时关闭以让出 flock。nil 表示未持有。
    private var heldFileDescriptor: Int32?

    init(directory: URL) {
        let dir = directory.appendingPathComponent("MacSoftwareSteward", isDirectory: true)
        self.lockURL = dir.appendingPathComponent("maintenance.lock")
        self.leaseURL = dir.appendingPathComponent("maintenance-lease.json")
    }

    /// 默认目录：~/Library/Application Support/
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
    }

    // MARK: - MaintenanceRunLeasing

    func acquire(trigger: MaintenanceRunTrigger) -> MaintenanceLeaseAcquisition {
        let lease = MaintenanceLease(
            runID: UUID(),
            pid: ProcessInfo.processInfo.processIdentifier,
            processStartTime: currentProcessStartTime(),
            trigger: trigger,
            createdAt: Date()
        )

        // 确保锁文件所在目录存在（Finder/Dock 启动环境与测试临时目录都可能缺）。
        let lockDir = lockURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: lockDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: lockURL.path, contents: nil, attributes: nil)
        // O_EXLOCK: 打开时尝试获取独占锁，拿不到则阻塞。用非阻塞 + 重试避免死锁。
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            // 无法打开锁文件：保守视为冲突（读取已存在 lease 供展示）。
            if let existing = readLease(), !isStale(existing) {
                return .conflict(existingLease: existing)
            }
            // 锁文件打不开但 lease 已 stale/缺失：强制回收后重试。
            reclaimStaleIfNeeded()
            return acquireFallback(lease: lease)
        }

        // 尝试非阻塞独占锁。
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            // 拿到锁。写 lease 并持有 fd。
            heldFileDescriptor = fd
            writeLease(lease)
            return .acquired(lease)
        }

        // 没拿到锁：有竞争方。读取 lease 判断是否 stale。
        close(fd)
        if let existing = readLease(), !isStale(existing) {
            return .conflict(existingLease: existing)
        }
        // stale：回收后重试。
        reclaimStaleIfNeeded()
        return acquireFallback(lease: lease)
    }

    func release(_ lease: MaintenanceLease) {
        // 删除 lease JSON，关闭 fd 释放 flock。
        try? FileManager.default.removeItem(at: leaseURL)
        if let fd = heldFileDescriptor {
            flock(fd, LOCK_UN)
            close(fd)
            heldFileDescriptor = nil
        }
    }

    func currentLease() -> MaintenanceLease? {
        guard let lease = readLease(), !isStale(lease) else { return nil }
        return lease
    }

    // MARK: - Stale detection

    /// lease 是否已失效：pid 不存活，或启动时间不匹配（PID 复用）。
    private func isStale(_ lease: MaintenanceLease) -> Bool {
        if lease.pid == ProcessInfo.processInfo.processIdentifier {
            // 自己持有：不 stale。
            return false
        }
        guard isProcessAlive(lease.pid) else { return true }
        // pid 存活，但启动时间不一致 → PID 被复用。
        let startTime = processStartTime(for: lease.pid)
        guard let startTime else {
            // 无法获取启动时间：保守视为存活（不 stale），避免误回收活跃 lease。
            return false
        }
        return startTime != lease.processStartTime
    }

    private func reclaimStaleIfNeeded() {
        guard let stale = readLease(), isStale(stale) else { return }
        // stale lease 关联的非终态 run 应被标记为 interrupted（由 RunStore 在后续处理）。
        // 这里只清理 lease 文件，让锁可被重新获取。
        try? FileManager.default.removeItem(at: leaseURL)
    }

    /// stale 回收后的兜底获取：再次尝试拿锁。
    private func acquireFallback(lease: MaintenanceLease) -> MaintenanceLeaseAcquisition {
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return .conflict(existingLease: lease) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            heldFileDescriptor = fd
            writeLease(lease)
            return .acquired(lease)
        }
        close(fd)
        // 仍拿不到：返回原 lease 作为冲突信息。
        return .conflict(existingLease: lease)
    }

    // MARK: - Lease JSON persistence

    private func writeLease(_ lease: MaintenanceLease) {
        let dir = leaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "runID": lease.runID.uuidString,
            "pid": Int(lease.pid),
            "processStartTime": ISO8601DateFormatter().string(from: lease.processStartTime),
            "trigger": lease.trigger.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: lease.createdAt)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: leaseURL, options: .atomic)
    }

    private func readLease() -> MaintenanceLease? {
        guard let data = try? Data(contentsOf: leaseURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runIDString = dict["runID"] as? String,
              let runID = UUID(uuidString: runIDString),
              let pidValue = dict["pid"] as? Int,
              let triggerRaw = dict["trigger"] as? String,
              let trigger = MaintenanceRunTrigger(rawValue: triggerRaw)
        else { return nil }

        let formatter = ISO8601DateFormatter()
        let processStartTime = (dict["processStartTime"] as? String).flatMap { formatter.date(from: $0) } ?? Date(timeIntervalSince1970: 0)
        let createdAt = (dict["createdAt"] as? String).flatMap { formatter.date(from: $0) } ?? Date()

        return MaintenanceLease(
            runID: runID,
            pid: pid_t(pidValue),
            processStartTime: processStartTime,
            trigger: trigger,
            createdAt: createdAt
        )
    }

    // MARK: - Process inspection

    private func currentProcessStartTime() -> Date {
        processStartTime(for: ProcessInfo.processInfo.processIdentifier) ?? Date()
    }

    /// 检查 pid 是否存活（发信号 0）。
    private func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    /// 通过 sysctl KERN_PROC_PID 获取进程启动时间。
    private func processStartTime(for pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let mibCount = u_int(mib.count)
        let result = mib.withUnsafeMutableBufferPointer { mibPtr -> Int32 in
            sysctl(mibPtr.baseAddress, mibCount, &info, &size, nil, 0)
        }
        guard result == 0, size == MemoryLayout<kinfo_proc>.size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.kp_proc.p_starttime.tv_sec))
    }
}
