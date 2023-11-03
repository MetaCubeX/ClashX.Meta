//
//  Logger.swift
//  ClashX
//
//  Created by CYC on 2018/8/7.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import CocoaLumberjack
import Foundation
class Logger {
    static let shared = Logger()
    var fileLogger: DDFileLogger = .init()

    private init() {
        #if DEBUG
            DDLog.add(DDOSLogger.sharedInstance)
        #endif
        // default time zone is "UTC"
        let dataFormatter = DateFormatter()
        dataFormatter.setLocalizedDateFormatFromTemplate("YYYY/MM/dd HH:mm:ss:SSS")
        fileLogger.logFormatter = DDLogFileFormatterDefault(dateFormatter: dataFormatter)
        fileLogger.rollingFrequency = TimeInterval(60 * 60 * 24) // 24 hours
        fileLogger.logFileManager.maximumNumberOfLogFiles = 3
        DDLog.add(fileLogger)
        dynamicLogLevel = ConfigManager.selectLoggingApiLevel.toDDLogLevel()
    }

    private func logToFile(msg: String, level: ClashLogLevel) {
        switch level {
        case .debug, .silent:
            DDLogDebug(DDLogMessageFormat(stringLiteral: msg))
        case .error:
            DDLogError(DDLogMessageFormat(stringLiteral: msg))
        case .info:
            DDLogInfo(DDLogMessageFormat(stringLiteral: msg))
        case .warning:
            DDLogWarn(DDLogMessageFormat(stringLiteral: msg))
        case .unknow:
            DDLogWarn(DDLogMessageFormat(stringLiteral: msg))
        }
    }

    static func log(_ msg: String, level: ClashLogLevel = .info, file: String = #file, function: String = #function) {
        shared.logToFile(msg: "[\(level.rawValue)] \(file) \(function) \(msg)", level: level)
    }

    func logFilePath() -> String {
        return fileLogger.logFileManager.sortedLogFilePaths.first ?? ""
    }

    func logFolder() -> String {
        return fileLogger.logFileManager.logsDirectory
    }
}
