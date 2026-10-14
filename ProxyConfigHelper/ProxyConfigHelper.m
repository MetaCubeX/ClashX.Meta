//
//  ProxyConfigHelper.m
//  com.west2online.ClashX.ProxyConfigHelper
//
//  Created by yichengchen on 2019/8/17.
//  Copyright © 2019 west2online. All rights reserved.
//

#import "ProxyConfigHelper.h"
#import <AppKit/AppKit.h>
#import "ProxyConfigRemoteProcessProtocol.h"
#import "ProxySettingTool.h"

@interface ProxyConfigHelper()
<
NSXPCListenerDelegate,
ProxyConfigRemoteProcessProtocol
>

@property (nonatomic, strong) NSXPCListener *listener;
@property (nonatomic, strong) NSMutableSet<NSXPCConnection *> *connections;
@property (nonatomic, strong) NSTimer *checkTimer;
@property (nonatomic, assign) BOOL shouldQuit;

@end

@implementation ProxyConfigHelper

static NSString * const kMihomoLabel = @"com.west2online.ClashX.ProxyConfigHelper.mihomo";
static NSString * const kMihomoPlistPath = @"/Library/LaunchDaemons/com.west2online.ClashX.ProxyConfigHelper.mihomo.plist";

- (NSString *)runLaunchctlArguments:(NSArray<NSString *> *)arguments {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/launchctl";
    task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe];
    task.standardError = pipe;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return exception.reason ?: @"launchctl failed";
    }
    if (task.terminationStatus == 0) { return nil; }
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"launchctl failed";
}
- (instancetype)init {
    
    if (self = [super init]) {
        self.connections = [NSMutableSet new];
        self.shouldQuit = NO;
        self.listener = [[NSXPCListener alloc] initWithMachServiceName:@"com.west2online.ClashX.ProxyConfigHelper"];
        self.listener.delegate = self;
    }
    return self;
}

- (void)run {
    [self.listener resume];
    self.checkTimer =
    [NSTimer timerWithTimeInterval:5.f target:self selector:@selector(connectionCheckOnLaunch) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:self.checkTimer forMode:NSDefaultRunLoopMode];
    while (!self.shouldQuit) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
    }
}

- (void)connectionCheckOnLaunch {
    if (self.connections.count == 0) {
        [self stopMihomoIfOrphaned];
        self.shouldQuit = YES;
    }
}

- (void)stopMihomoIfOrphaned {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kMihomoPlistPath]) {
        NSString *error = [self runLaunchctlArguments:@[@"unload", kMihomoPlistPath]];
        if (error.length > 0) {
            NSLog(@"Failed to stop orphaned Mihomo: %@", error);
        }
        [[NSFileManager defaultManager] removeItemAtPath:kMihomoPlistPath error:nil];
    }
}

- (BOOL)connectionIsVaild: (NSXPCConnection *)connection {
    NSRunningApplication *remoteApp =
    [NSRunningApplication runningApplicationWithProcessIdentifier:connection.processIdentifier];
    return [remoteApp.bundleIdentifier isEqualToString:@"com.west2online.ClashX"];
}

// MARK: - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    if (![self connectionIsVaild:newConnection]) {
        return NO;
    }
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ProxyConfigRemoteProcessProtocol)];
    newConnection.exportedObject = self;
    __weak NSXPCConnection *weakConnection = newConnection;
    __weak ProxyConfigHelper *weakSelf = self;
    newConnection.invalidationHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.connections removeObject:weakConnection];
            if (weakSelf.connections.count == 0) {
                [weakSelf stopMihomoIfOrphaned];
                weakSelf.shouldQuit = YES;
            }
        });
    };
    [self.connections addObject:newConnection];
    [newConnection resume];
    return YES;
}

// MARK: - ProxyConfigRemoteProcessProtocol
- (void)getVersion:(stringReplyBlock)reply {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (version == nil) {
        version = @"unknown";
    }
    reply(version);
}

- (void)enableProxyWithPort:(int)port
          socksPort:(int)socksPort
            pac:(NSString *)pac
            filterInterface:(BOOL)filterInterface
            error:(stringReplyBlock)reply {
    dispatch_async(dispatch_get_main_queue(), ^{
        ProxySettingTool *tool = [ProxySettingTool new];
        [tool enableProxyWithport:port socksPort:socksPort pacUrl:pac filterInterface:filterInterface];
        reply(nil);
    });
}

- (void)disableProxyWithFilterInterface:(BOOL)filterInterface reply:(stringReplyBlock)reply {
    dispatch_async(dispatch_get_main_queue(), ^{
        ProxySettingTool *tool = [ProxySettingTool new];
        [tool disableProxyWithfilterInterface:filterInterface];
        reply(nil);
    });
}


- (void)restoreProxyWithCurrentPort:(int)port
                          socksPort:(int)socksPort
                               info:(NSDictionary *)dict
                    filterInterface:(BOOL)filterInterface
                              error:(stringReplyBlock)reply {
    dispatch_async(dispatch_get_main_queue(), ^{
        ProxySettingTool *tool = [ProxySettingTool new];
        [tool restoreProxySettint:dict currentPort:port currentSocksPort:socksPort filterInterface:filterInterface];
        reply(nil);
    });
}

- (void)getCurrentProxySetting:(dictReplyBlock)reply {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *info = [ProxySettingTool currentProxySettings];
        reply(info);
    });
}

- (void)startMihomoAtPath:(NSString *)path
               configPath:(NSString *)configPath
               controller:(NSString *)controller
                   secret:(NSString *)secret
                   uiPath:(NSString *)uiPath
                    reply:(stringReplyBlock)reply {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self runLaunchctlArguments:@[@"unload", kMihomoPlistPath]];
        [[NSFileManager defaultManager] removeItemAtPath:kMihomoPlistPath error:nil];

        BOOL executable = [[NSFileManager defaultManager] isExecutableFileAtPath:path];
        BOOL bundledCore = [path hasSuffix:@".app/Contents/Resources/mihomo"];
        if (!executable || !bundledCore || ![[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
            reply(@"Mihomo executable or config is missing");
            return;
        }

        NSString *configDirectory = [configPath stringByDeletingLastPathComponent];
        NSString *stdoutPath = [configDirectory stringByAppendingPathComponent:@"mihomo.log"];
        NSString *stderrPath = [configDirectory stringByAppendingPathComponent:@"mihomo-error.log"];
        NSMutableArray<NSString *> *arguments = [@[path, @"-d", configDirectory, @"-f", configPath,
                                                   @"-ext-ctl", controller, @"-secret", secret] mutableCopy];
        if (uiPath.length > 0) {
            [arguments addObjectsFromArray:@[@"-ext-ui", uiPath]];
        }
        NSDictionary *plist = @{
            @"Label": kMihomoLabel,
            @"ProgramArguments": arguments,
            @"WorkingDirectory": configDirectory,
            @"EnvironmentVariables": @{@"SAFE_PATHS": configDirectory},
            @"StandardOutPath": stdoutPath,
            @"StandardErrorPath": stderrPath,
            @"RunAtLoad": @YES,
            @"KeepAlive": @NO
        };
        NSError *error = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:&error];
        if (data == nil || ![data writeToFile:kMihomoPlistPath options:NSDataWritingAtomic error:&error]) {
            reply(error.localizedDescription ?: @"Unable to write Mihomo launchd plist");
            return;
        }
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644}
                                         ofItemAtPath:kMihomoPlistPath error:nil];
        reply([self runLaunchctlArguments:@[@"load", kMihomoPlistPath]]);
    });
}

- (void)stopMihomo:(stringReplyBlock)reply {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self runLaunchctlArguments:@[@"unload", kMihomoPlistPath]];
        [[NSFileManager defaultManager] removeItemAtPath:kMihomoPlistPath error:nil];
        reply(nil);
    });
}


@end
