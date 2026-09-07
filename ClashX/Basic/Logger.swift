//
//  Logger.swift
//  ClashX
//
//  Created by CYC on 2018/8/7.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

private class AppLogFileManager: DDLogFileManagerDefault {
    override var newLogFileName: String {
        "clashx.log"
    }

    override func isLogFile(withName fileName: String) -> Bool {
        fileName.range(of: #"^clashx\.log(\.\d+)?$"#, options: .regularExpression) != nil
    }
}

private class CoreLogFileManager: DDLogFileManagerDefault {
    override var newLogFileName: String {
        let df = DateFormatter()
        df.dateFormat = "dd_HH-mm-ss"
        return "clashx_core_\(df.string(from: Date())).log"
    }

    override func isLogFile(withName fileName: String) -> Bool {
        fileName.range(of: #"^clashx_core_\d{2}_\d{2}-\d{2}-\d{2}\.log(\.\d+)?$"#, options: .regularExpression) != nil
    }
}

class Logger {
    static let shared = Logger()
    var fileLogger: DDFileLogger = .init()
    var coreFileLogger: DDFileLogger = .init()
    private(set) var sessionId = ""
    
    private let coreLog = DDLog()

    var coreLogFolder: String {
        (try? CoreLogMaintenance.sessionDirectory(sessionID: sessionId)) ?? CoreLogMaintenance.rootDirectory
    }

    var coreLogPath: String {
        "\(coreLogFolder)/\(kCoreLogName)"
    }

    var coreCrashLogPath: String {
        "\(coreLogFolder)/\(kCoreCrashLogName)"
    }

    private init() {
        #if DEBUG
            DDLog.add(DDOSLogger.sharedInstance)
        #endif
        dynamicLogLevel = .debug
    }

    func configure(logDirectory: String, sessionId: String) {
        self.sessionId = sessionId
        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("YYYY/MM/dd HH:mm:ss:SSS")

        let fm = AppLogFileManager(logsDirectory: logDirectory)
        let newLogger = DDFileLogger(logFileManager: fm)
        newLogger.logFormatter = DDLogFileFormatterDefault(dateFormatter: dateFormatter)
        DDLog.remove(fileLogger)
        fileLogger = newLogger
        DDLog.add(newLogger)

        let coreFm = CoreLogFileManager(logsDirectory: logDirectory)
        let newCoreLogger = DDFileLogger(logFileManager: coreFm)
        newCoreLogger.logFormatter = DDLogFileFormatterDefault(dateFormatter: dateFormatter)
        newCoreLogger.rollingFrequency = TimeInterval(60 * 60 * 24) // 24 hours
        newCoreLogger.maximumFileSize = 5 * 1024 * 1024 // 5MB
        newCoreLogger.logFileManager.maximumNumberOfLogFiles = 3
        coreLog.removeAllLoggers()
        coreLog.add(newCoreLogger)
        coreFileLogger = newCoreLogger
    }

    private func logToLog(_ ddlog: DDLog, msg: String, level: ClashLogLevel) {
        switch level {
        case .debug, .silent:
            DDLogDebug(DDLogMessageFormat(stringLiteral: msg), ddlog: ddlog)
        case .error:
            DDLogError(DDLogMessageFormat(stringLiteral: msg), ddlog: ddlog)
        case .info:
            DDLogInfo(DDLogMessageFormat(stringLiteral: msg), ddlog: ddlog)
        case .warning:
            DDLogWarn(DDLogMessageFormat(stringLiteral: msg), ddlog: ddlog)
        case .unknow:
            DDLogWarn(DDLogMessageFormat(stringLiteral: msg), ddlog: ddlog)
        }
    }

    static func log(_ msg: String, level: ClashLogLevel = .info, file: String = #file, function: String = #function) {
		let fileName = URL(fileURLWithPath: file).lastPathComponent
        shared.logToLog(.sharedInstance, msg: "[\(level.rawValue)] \(fileName) \(function) \(msg)", level: level)
    }

    static func logCore(_ msg: String, level: ClashLogLevel) {
        shared.logToLog(shared.coreLog, msg: "[\(level.rawValue)] \(msg)", level: level)
    }

    func logFilePath() -> String {
        return fileLogger.logFileManager.sortedLogFilePaths.first ?? ""
    }

    func logFolder() -> String {
        return fileLogger.logFileManager.logsDirectory
    }

    func setupLogSession() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let sessionId = dateFormatter.string(from: Date())

        let logsDir = "\(kConfigFolderPath)logs/\(sessionId)"
        try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)

        configure(logDirectory: logsDir, sessionId: sessionId)

        cleanupLogDirectories()
    }
    

    private func cleanupLogDirectories() {
        let logsRoot = "\(kConfigFolderPath)logs/"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: logsRoot) else { return }

        let maxCount = 20
        let sorted = contents
            .filter { $0.contains("-") }
            .sorted(by: >)

        guard sorted.count > maxCount else { return }

        for name in sorted[maxCount...] {
            try? FileManager.default.removeItem(atPath: "\(logsRoot)\(name)")
        }
    }
}
