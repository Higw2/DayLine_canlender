import Foundation
import Darwin
import DayLineCore

/// One process per data directory. A distributed notification forwards CLI intent
/// to the running copy, keeping test data directories independent from real data.
final class SingleInstance {
    private var fd: Int32 = -1; private let name: Notification.Name
    var isPrimary = false; var onCommand: ((String)->Void)?
    init(dataDirectory: URL) {
        let hash = dataDirectory.path.data(using:.utf8)!.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }
        name = Notification.Name("io.github.dayline.Calendar.macOS.\(hash)")
        let lock = dataDirectory.appendingPathComponent("dayline.lock").path; fd = open(lock, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        isPrimary = fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0
        if isPrimary { DistributedNotificationCenter.default().addObserver(forName:name,object:nil,queue:.main) { [weak self] note in self?.onCommand?(note.userInfo?["command"] as? String ?? "activate") } }
    }
    deinit { DistributedNotificationCenter.default().removeObserver(self); if fd >= 0 { close(fd) } }
    func send(_ command:String) { DistributedNotificationCenter.default().postNotificationName(name,object:nil,userInfo:["command":command],deliverImmediately:true) }
}
