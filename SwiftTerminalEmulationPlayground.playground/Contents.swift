import Foundation
import Darwin

class Shell {
    var process: Process?
    var slaveFile: FileHandle?
    var masterFile: FileHandle?
    var running = false
    
    init() {
        self.process = Process()
        var masterFD: Int32 = 0
        masterFD = posix_openpt(O_RDWR)
        grantpt(masterFD)
        unlockpt(masterFD)
        self.masterFile = FileHandle.init(fileDescriptor: masterFD)
        let slavePath = String.init(cString: ptsname(masterFD))
        self.slaveFile = FileHandle.init(forUpdatingAtPath: slavePath)
        self.process!.executableURL = URL(fileURLWithPath: "/bin/bash")
        self.process!.arguments = []
        self.process!.standardOutput = slaveFile
        self.process!.standardInput = slaveFile
        self.process!.standardError = slaveFile
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(printOutput(_:)),
                                               name: FileHandle.readCompletionNotification,
                                               object: self.masterFile!)
    }
    
    func run() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                return
            }
            do {
                try self.process!.run()
            } catch {
                print("Something went wrong.\n")
            }
        }
        self.running = true
    }
    
    func read() -> String? {
        if self.running {
            let data = self.masterFile!.availableData
            let string = String(data: data, encoding: String.Encoding.utf8)
            return string!
        }
        return nil
    }
    
    func write(_ string: String) {
        if self.running {
            let modifiedString = string+"\u{0D}"
            let length: Int = {
                let cstring = modifiedString.cString(using: String.Encoding.utf8)
                return cstring!.count
            }()
            let data = modifiedString.data(using: String.Encoding.utf8)
            self.masterFile!.write(data!)
            _ = self.masterFile!.readData(ofLength: length) // throw away echo.
            self.masterFile!.readInBackgroundAndNotify()
        }
    }
    
    @objc func printOutput(_ notification: Notification) {
        let data = notification.userInfo![NSFileHandleNotificationDataItem] as! Data
        let outputString = String(data: data, encoding: String.Encoding.utf8)
        print(outputString!)
    }
    
    deinit {
        self.process!.terminate()
        let slave = self.process!.standardInput as! FileHandle
        slave.closeFile()
    }
}

let shell = Shell()
shell.run()
print(shell.read()!)
shell.write("uptime")

