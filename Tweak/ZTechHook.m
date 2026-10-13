#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CFNetwork/CFNetwork.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>
#import <netinet/in.h>
#import <unistd.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <string.h>
#import <notify.h>
#import <execinfo.h>
#import <signal.h>
#import <time.h>
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif

#pragma mark - Lock-Free Pre-Cached Profile, Pure C Buffers & Pre-Parsed Proxy State

extern int __sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

static NSDictionary *gCachedProfile = nil;
static char gMachineCStr[64] = "iPhone17,2";
static char gBoardIdCStr[32] = "D94AP";
static char gModelNameCStr[64] = "iPhone 16 Pro Max";
static char gRealMachineCStr[64] = "iPhone9,3";
static struct utsname gRealUts;
static int gHasRealUts = 0;
static int gIsAidaProcess = 0;
static uint64_t gRamBytes = 8ULL * 1024ULL * 1024ULL * 1024ULL;
static NSString *gModelNameObj = @"iPhone 16 Pro Max";
static NSString *gMachineIdObj = @"iPhone17,2";
static NSString *gIosVersionObj = @"18.2.1";
static NSString *gUuidObj = @"7BD46FDA-D93D-45BD-9158-7178669502DD";
static NSUUID *gCachedVendorUUID = nil;
static NSString *gRealIosVersionObj = @"15.5";
static NSString *gCarrierNameObj = @"Viettel";
static NSString *gActiveProxyObj = @"";
static float gBatteryFloat = 0.76f;

static NSUncaughtExceptionHandler *gPrevUncaughtHandler = NULL;
static time_t gProcessStartTime = 0;

static void ZTechWriteLogToContainerAndTmp(const char *fileName, const char *content) {
    if (!fileName || !content) return;
    const char *home = getenv("HOME");
    if (home && home[0] != '\0') {
        char p1[1024] = {0};
        snprintf(p1, sizeof(p1), "%s/Documents/%s", home, fileName);
        FILE *f1 = fopen(p1, "a");
        if (f1) {
            fputs(content, f1);
            fflush(f1);
            fclose(f1);
        }
        char p2[1024] = {0};
        snprintf(p2, sizeof(p2), "%s/Library/Caches/%s", home, fileName);
        FILE *f2 = fopen(p2, "a");
        if (f2) {
            fputs(content, f2);
            fflush(f2);
            fclose(f2);
        }
    }
    char p3[256] = {0};
    snprintf(p3, sizeof(p3), "/var/tmp/%s", fileName);
    FILE *f3 = fopen(p3, "a");
    if (f3) {
        fputs(content, f3);
        fflush(f3);
        fclose(f3);
    }
}

static void ZTechHookTrace(const char *msg) {
    if (!msg) return;
    time_t now = time(NULL);
    char tbuf[32] = {0};
    struct tm tm_info;
    localtime_r(&now, &tm_info);
    strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", &tm_info);
    char line[1024] = {0};
    snprintf(line, sizeof(line), "[%s][pid:%d] %s\n", tbuf, getpid(), msg);
    ZTechWriteLogToContainerAndTmp("ztech_hook_trace.log", line);
}

static void ZTechAtExitHandler(void) {
    time_t now = time(NULL);
    char tbuf[32] = {0};
    struct tm tm_info;
    localtime_r(&now, &tm_info);
    strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", &tm_info);

    NSMutableString *buf = [NSMutableString stringWithFormat:@"\n=== [PROCESS EXIT CAUGHT BY ZTECH ATEXIT] ===\nTime: %s | PID: %d | Uptime: %lds\n",
                            tbuf, getpid(), (long)(now - gProcessStartTime)];
    void *callstack[48];
    int frames = backtrace(callstack, 48);
    char **strs = backtrace_symbols(callstack, frames);
    if (strs) {
        [buf appendFormat:@"Exit Callstack (%d frames):\n", frames];
        for (int i = 0; i < frames; ++i) {
            [buf appendFormat:@"  [%02d] %s\n", i, strs[i]];
        }
        free(strs);
    }
    [buf appendString:@"=============================================\n\n"];
    ZTechWriteLogToContainerAndTmp("ztech_crash.log", [buf UTF8String]);
    ZTechHookTrace("Process invoked exit() -> logged callstack to ztech_crash.log");
}

static void ZTechUncaughtExceptionHandler(NSException *exception) {
    if (exception) {
        time_t now = time(NULL);
        char tbuf[32] = {0};
        struct tm tm_info;
        localtime_r(&now, &tm_info);
        strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", &tm_info);
        NSMutableString *buf = [NSMutableString stringWithFormat:@"\n=== [UNCAUGHT EXCEPTION CAUGHT BY ZTECH HOOK] ===\nTime: %s | PID: %d\nName: %@\nReason: %@\n",
                                tbuf, getpid(), exception.name ?: @"Unknown", exception.reason ?: @"Unknown"];
        NSArray *syms = [exception callStackSymbols];
        if (syms) {
            [buf appendString:@"CallStack:\n"];
            for (NSString *sym in syms) {
                [buf appendFormat:@"  %@\n", sym];
            }
        }
        [buf appendString:@"=================================================\n\n"];
        ZTechWriteLogToContainerAndTmp("ztech_crash.log", [buf UTF8String]);
        ZTechHookTrace([[NSString stringWithFormat:@"[EXCEPTION] %@: %@", exception.name, exception.reason] UTF8String]);
    }
        if (gPrevUncaughtHandler && gPrevUncaughtHandler != &ZTechUncaughtExceptionHandler) {
        gPrevUncaughtHandler(exception);
    }
}

static void ZTechSignalHandler(int sig, siginfo_t *info, void *uap) {
    const char *sigName = "UNKNOWN";
    switch (sig) {
        case SIGABRT: sigName = "SIGABRT"; break;
        case SIGTRAP: sigName = "SIGTRAP"; break;
        case SIGILL:  sigName = "SIGILL";  break;
        case SIGSEGV: sigName = "SIGSEGV"; break;
        case SIGBUS:  sigName = "SIGBUS";  break;
    }
    time_t now = time(NULL);
    char header[256] = {0};
    snprintf(header, sizeof(header),
             "\n=== [SIGNAL %s (%d) CAUGHT BY ZTECH HOOK] ===\nPID: %d | Uptime: %lds | FaultAddr: %p\n",
             sigName, sig, getpid(), (long)(now - gProcessStartTime), info ? info->si_addr : NULL);
    ZTechWriteLogToContainerAndTmp("ztech_crash.log", header);
    ZTechHookTrace(header);

    void *callstack[48];
    int frames = backtrace(callstack, 48);
    char **strs = backtrace_symbols(callstack, frames);
    if (strs) {
        for (int i = 0; i < frames; ++i) {
            char fline[512] = {0};
            snprintf(fline, sizeof(fline), "  [%02d] %s\n", i, strs[i]);
            ZTechWriteLogToContainerAndTmp("ztech_crash.log", fline);
        }
        free(strs);
    }
    ZTechWriteLogToContainerAndTmp("ztech_crash.log", "=================================================\n\n");

    struct sigaction dfl = {0};
    dfl.sa_handler = SIG_DFL;
    sigemptyset(&dfl.sa_mask);
    sigaction(sig, &dfl, NULL);
    raise(sig);
}

static void ZTechInstallSignalHandlers(void) {
    int sigs[] = { SIGABRT, SIGTRAP, SIGILL, SIGSEGV, SIGBUS };
    for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); ++i) {
        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_sigaction = &ZTechSignalHandler;
        sa.sa_flags = SA_SIGINFO | SA_NODEFER;
        sigemptyset(&sa.sa_mask);
        sigaction(sigs[i], &sa, NULL);
    }
}




// Pre-cached Proxy Structures for Zero-Latency / Zero-Leak Networking Enforcement
static volatile int gProxyEnabled = 0;
static volatile int gProxyIsSocks = 0;
static uint32_t gMaskedLocalIPv4 = 0x6C01A8C0; // 192.168.1.108 in network byte order
static NSDictionary *gCachedProxyDict = nil;
static NSArray *gCachedCFProxyArray = nil;
static NSString *gCachedProxyAuthHeader = nil;

static void ZTechRebuildCachedProxyState(NSString *rawProxy) {
    if (!rawProxy || rawProxy.length == 0) {
        gProxyEnabled = 0;
        gProxyIsSocks = 0;
        gCachedProxyDict = nil;
        gCachedCFProxyArray = nil;
        gCachedProxyAuthHeader = nil;
        return;
    }

    NSString *s = [rawProxy stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) {
        gProxyEnabled = 0;
        gProxyIsSocks = 0;
        gCachedProxyDict = nil;
        gCachedCFProxyArray = nil;
        gCachedProxyAuthHeader = nil;
        return;
    }

    BOOL isSocks = NO;
    NSString *lower = [s lowercaseString];
    if ([lower hasPrefix:@"socks5://"]) {
        isSocks = YES;
        s = [s substringFromIndex:9];
    } else if ([lower hasPrefix:@"socks5h://"]) {
        isSocks = YES;
        s = [s substringFromIndex:10];
    } else if ([lower hasPrefix:@"socks://"]) {
        isSocks = YES;
        s = [s substringFromIndex:8];
    } else if ([lower hasPrefix:@"http://"]) {
        s = [s substringFromIndex:7];
    } else if ([lower hasPrefix:@"https://"]) {
        s = [s substringFromIndex:8];
    }

    NSRange slashRange = [s rangeOfString:@"/"];
    if (slashRange.location != NSNotFound) {
        s = [s substringToIndex:slashRange.location];
    }

    NSString *host = nil;
    NSInteger port = 0;
    NSString *user = nil;
    NSString *pass = nil;

    if ([s containsString:@"@"]) {
        NSArray<NSString *> *atParts = [s componentsSeparatedByString:@"@"];
        if (atParts.count == 2) {
            NSArray<NSString *> *p0 = [atParts[0] componentsSeparatedByString:@":"];
            NSArray<NSString *> *p1 = [atParts[1] componentsSeparatedByString:@":"];
            if (p1.count == 2 && [p1[1] integerValue] > 0 && [p1[1] integerValue] <= 65535 && [p1[0] containsString:@"."]) {
                user = p0.count >= 1 ? p0[0] : nil;
                pass = p0.count >= 2 ? [[p0 subarrayWithRange:NSMakeRange(1, p0.count - 1)] componentsJoinedByString:@":"] : nil;
                host = p1[0];
                port = [p1[1] integerValue];
            } else if (p0.count == 2 && [p0[1] integerValue] > 0 && [p0[1] integerValue] <= 65535) {
                host = p0[0];
                port = [p0[1] integerValue];
                user = p1.count >= 1 ? p1[0] : nil;
                pass = p1.count >= 2 ? [[p1 subarrayWithRange:NSMakeRange(1, p1.count - 1)] componentsJoinedByString:@":"] : nil;
            }
        }
    } else {
        NSArray<NSString *> *parts = [s componentsSeparatedByString:@":"];
        if (parts.count >= 2) {
            host = parts[0];
            port = [parts[1] integerValue];
            if (parts.count >= 4) {
                user = parts[2];
                pass = [[parts subarrayWithRange:NSMakeRange(3, parts.count - 3)] componentsJoinedByString:@":"];
            }
        }
    }

    host = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!host || host.length == 0 || port <= 0 || port > 65535) {
        gProxyEnabled = 0;
        gProxyIsSocks = 0;
        gCachedProxyDict = nil;
        gCachedCFProxyArray = nil;
        gCachedProxyAuthHeader = nil;
        return;
    }

    NSString *authHeader = nil;
    if (user.length > 0 && pass != nil) {
        NSString *rawCred = [NSString stringWithFormat:@"%@:%@", user, pass];
        NSData *credData = [rawCred dataUsingEncoding:NSUTF8StringEncoding];
        if (credData) {
            authHeader = [NSString stringWithFormat:@"Basic %@", [credData base64EncodedStringWithOptions:0]];
        }
    }

    NSMutableDictionary *proxyDict = [NSMutableDictionary dictionary];
    proxyDict[@"ProxyAutoConfigEnable"] = @0;
    proxyDict[@"ProxyAutoDiscoveryEnable"] = @0;
    proxyDict[@"ExcludeSimpleHostnames"] = @0;

    NSMutableDictionary *cfProxyItem = [NSMutableDictionary dictionary];
    cfProxyItem[(__bridge NSString *)kCFProxyHostNameKey] = host;
    cfProxyItem[(__bridge NSString *)kCFProxyPortNumberKey] = @(port);
    if (user.length > 0 && pass != nil) {
        cfProxyItem[(__bridge NSString *)kCFProxyUsernameKey] = user;
        cfProxyItem[(__bridge NSString *)kCFProxyPasswordKey] = pass;
    }

    if (isSocks) {
        proxyDict[@"SOCKSEnable"] = @1;
        proxyDict[@"SOCKSProxy"] = host;
        proxyDict[@"SOCKSPort"] = @(port);
        proxyDict[(__bridge NSString *)kCFStreamPropertySOCKSProxyHost] = host;
        proxyDict[(__bridge NSString *)kCFStreamPropertySOCKSProxyPort] = @(port);
        proxyDict[(__bridge NSString *)kCFStreamPropertySOCKSVersion] = (__bridge NSString *)kCFStreamSocketSOCKSVersion5;
        if (user.length > 0 && pass != nil) {
            proxyDict[(__bridge NSString *)kCFStreamPropertySOCKSUser] = user;
            proxyDict[(__bridge NSString *)kCFStreamPropertySOCKSPassword] = pass;
            proxyDict[(__bridge NSString *)kCFProxyUsernameKey] = user;
            proxyDict[(__bridge NSString *)kCFProxyPasswordKey] = pass;
        }
        cfProxyItem[(__bridge NSString *)kCFProxyTypeKey] = (__bridge NSString *)kCFProxyTypeSOCKS;
    } else {
        proxyDict[@"HTTPEnable"] = @1;
        proxyDict[@"HTTPProxy"] = host;
        proxyDict[@"HTTPPort"] = @(port);
        proxyDict[@"HTTPSEnable"] = @1;
        proxyDict[@"HTTPSProxy"] = host;
        proxyDict[@"HTTPSPort"] = @(port);
        proxyDict[(__bridge NSString *)kCFStreamPropertyHTTPProxyHost] = host;
        proxyDict[(__bridge NSString *)kCFStreamPropertyHTTPProxyPort] = @(port);
        proxyDict[(__bridge NSString *)kCFStreamPropertyHTTPSProxyHost] = host;
        proxyDict[(__bridge NSString *)kCFStreamPropertyHTTPSProxyPort] = @(port);
        if (user.length > 0 && pass != nil) {
            proxyDict[(__bridge NSString *)kCFProxyUsernameKey] = user;
            proxyDict[(__bridge NSString *)kCFProxyPasswordKey] = pass;
            proxyDict[@"HTTPUser"] = user;
            proxyDict[@"HTTPPassword"] = pass;
            proxyDict[@"HTTPSUser"] = user;
            proxyDict[@"HTTPSPassword"] = pass;
        }
        cfProxyItem[(__bridge NSString *)kCFProxyTypeKey] = (__bridge NSString *)kCFProxyTypeHTTPS;
    }

    NSMutableDictionary *cfProxyHttpItem = [cfProxyItem mutableCopy];
    if (!isSocks) {
        cfProxyHttpItem[(__bridge NSString *)kCFProxyTypeKey] = (__bridge NSString *)kCFProxyTypeHTTP;
    }

    uint32_t hash = (uint32_t)([host hash] ^ (NSUInteger)port);
    uint8_t lastOctet = (uint8_t)((hash % 230) + 15);
    gMaskedLocalIPv4 = htonl((192U << 24) | (168U << 16) | (1U << 8) | (uint32_t)lastOctet);

    gCachedProxyDict = [proxyDict copy];
    gCachedCFProxyArray = isSocks ? @[[cfProxyItem copy]] : @[[cfProxyItem copy], [cfProxyHttpItem copy]];
    gCachedProxyAuthHeader = [authHeader copy];
    gProxyIsSocks = isSocks ? 1 : 0;
    gProxyEnabled = 1;
}

static NSDictionary *ZTechNormalizeProfile(NSDictionary *raw) {
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:raw ?: @{}];
    NSString *machine = m[@"machineId"];
    NSString *model = m[@"modelName"];
    if (!machine || machine.length == 0 || !model || model.length == 0) {
        m[@"machineId"] = @"iPhone17,2";
        m[@"modelName"] = @"iPhone 16 Pro Max";
    }
    NSString *ios = m[@"iosVersion"];
    if (!ios || [ios integerValue] < 14) {
        m[@"iosVersion"] = @"18.2.1";
    }
    if (!m[@"ramGB"] || [m[@"ramGB"] integerValue] < 2) {
        m[@"ramGB"] = @8;
    }
    if (!m[@"batteryPercent"] || [m[@"batteryPercent"] integerValue] <= 0) {
        m[@"batteryPercent"] = @76;
    }
    if (!m[@"identifier"] || [m[@"identifier"] length] == 0) {
        m[@"identifier"] = @"7BD46FDA-D93D-45BD-9158-7178669502DD";
    }
    if (!m[@"carrier"] || [m[@"carrier"] length] == 0) {
        m[@"carrier"] = @"Viettel";
    }
    if (!m[@"activeProxy"]) {
        m[@"activeProxy"] = @"";
    }
    return m;
}

static NSString *ZTechBoardIdForMachine(NSString *m) {
    if (!m) return @"D94AP";
    if ([m isEqualToString:@"iPhone17,2"]) return @"D94AP"; // 16 Pro Max
    if ([m isEqualToString:@"iPhone17,1"]) return @"D93AP"; // 16 Pro
    if ([m isEqualToString:@"iPhone17,3"]) return @"D47AP"; // 16
    if ([m isEqualToString:@"iPhone17,4"]) return @"D48AP"; // 16 Plus
    if ([m isEqualToString:@"iPhone17,5"]) return @"D49AP"; // 16e
    if ([m isEqualToString:@"iPhone16,2"]) return @"D84AP"; // 15 Pro Max
    if ([m isEqualToString:@"iPhone16,1"]) return @"D83AP"; // 15 Pro
    if ([m isEqualToString:@"iPhone15,3"]) return @"D74AP"; // 14 Pro Max
    if ([m isEqualToString:@"iPhone15,2"]) return @"D73AP"; // 14 Pro
    if ([m isEqualToString:@"iPhone15,5"]) return @"D28AP"; // 14 Plus
    if ([m isEqualToString:@"iPhone15,4"]) return @"D27AP"; // 14
    if ([m isEqualToString:@"iPhone14,3"]) return @"D28AP"; // 13 Pro Max
    if ([m isEqualToString:@"iPhone14,2"]) return @"D27AP"; // 13 Pro
    if ([m isEqualToString:@"iPhone14,5"]) return @"D17AP"; // 13
    if ([m isEqualToString:@"iPhone14,4"]) return @"D16AP"; // 13 mini
    if ([m isEqualToString:@"iPhone14,6"]) return @"D49AP"; // SE 2022
    if ([m isEqualToString:@"iPhone13,4"]) return @"D54pAP"; // 12 Pro Max
    if ([m isEqualToString:@"iPhone13,3"]) return @"D53pAP"; // 12 Pro
    if ([m isEqualToString:@"iPhone13,2"]) return @"D53gAP"; // 12
    if ([m isEqualToString:@"iPhone13,1"]) return @"D52gAP"; // 12 mini
    if ([m isEqualToString:@"iPhone12,8"]) return @"D79AP"; // SE 2020
    if ([m isEqualToString:@"iPhone12,5"]) return @"D431AP"; // 11 Pro Max
    if ([m isEqualToString:@"iPhone12,3"]) return @"D421AP"; // 11 Pro
    if ([m isEqualToString:@"iPhone12,1"]) return @"N104AP"; // 11
    if ([m isEqualToString:@"iPhone11,8"]) return @"N841AP"; // XR
    if ([m isEqualToString:@"iPhone11,6"]) return @"D331pAP"; // XS Max
    if ([m isEqualToString:@"iPhone11,2"]) return @"D321AP"; // XS
    if ([m isEqualToString:@"iPhone10,6"] || [m isEqualToString:@"iPhone10,3"]) return @"D22AP"; // X
    if ([m isEqualToString:@"iPhone10,5"] || [m isEqualToString:@"iPhone10,2"]) return @"D21AP"; // 8 Plus
    if ([m isEqualToString:@"iPhone10,4"] || [m isEqualToString:@"iPhone10,1"]) return @"D20AP"; // 8
    if ([m isEqualToString:@"iPhone9,4"] || [m isEqualToString:@"iPhone9,2"]) return @"D11AP"; // 7 Plus
    if ([m isEqualToString:@"iPhone9,3"] || [m isEqualToString:@"iPhone9,1"]) return @"D10AP"; // 7
    if ([m isEqualToString:@"iPhone8,4"]) return @"N69uAP"; // SE 1st Gen
    if ([m isEqualToString:@"iPhone8,2"]) return @"N66AP"; // 6s Plus
    if ([m isEqualToString:@"iPhone8,1"]) return @"N71AP"; // 6s
    return @"D94AP";
}

static void ZTechApplyCachedProfileValues(NSDictionary *prof) {
    if (!prof) return;
    gCachedProfile = prof;
    gModelNameObj = [prof[@"modelName"] ?: @"iPhone 16 Pro Max" copy];
    gMachineIdObj = [prof[@"machineId"] ?: @"iPhone17,2" copy];
    gIosVersionObj = [prof[@"iosVersion"] ?: @"18.2.1" copy];
    gUuidObj = [prof[@"identifier"] ?: @"7BD46FDA-D93D-45BD-9158-7178669502DD" copy];
    if (gUuidObj.length > 0) {
        gCachedVendorUUID = [[NSUUID alloc] initWithUUIDString:gUuidObj];
    }
    if (!gCachedVendorUUID) {
        gCachedVendorUUID = [NSUUID UUID];
    }
    gCarrierNameObj = [prof[@"carrier"] ?: @"Viettel" copy];
    gActiveProxyObj = [prof[@"activeProxy"] ?: @"" copy];

    const char *mc = [gMachineIdObj UTF8String];
    if (mc) {
        strncpy(gMachineCStr, mc, sizeof(gMachineCStr) - 1);
        gMachineCStr[sizeof(gMachineCStr) - 1] = '\0';
    }
    const char *mnc = [gModelNameObj UTF8String];
    if (mnc) {
        strncpy(gModelNameCStr, mnc, sizeof(gModelNameCStr) - 1);
        gModelNameCStr[sizeof(gModelNameCStr) - 1] = '\0';
    }
    NSString *boardObj = ZTechBoardIdForMachine(gMachineIdObj);
    const char *bc = [boardObj UTF8String];
    if (bc) {
        strncpy(gBoardIdCStr, bc, sizeof(gBoardIdCStr) - 1);
        gBoardIdCStr[sizeof(gBoardIdCStr) - 1] = '\0';
    }

    NSInteger ramGB = [prof[@"ramGB"] integerValue];
    if (ramGB < 2) ramGB = 8;
    gRamBytes = (uint64_t)ramGB * 1024ULL * 1024ULL * 1024ULL;

    NSInteger pct = [prof[@"batteryPercent"] integerValue];
    gBatteryFloat = (pct > 0 && pct <= 100) ? ((float)pct / 100.0f) : 0.76f;

    ZTechRebuildCachedProxyState(gActiveProxyObj);
}

static NSDictionary *ZTechLoadProfileOnce(void) {
    if (gCachedProfile) {
        return gCachedProfile;
    }

    // 1. Check inside app's own sandbox container FIRST via getenv("HOME") (100% sandbox-safe, zero XPC, zero /var/jb access)
    const char *homeC = getenv("HOME");
    if (homeC && homeC[0] != '\0') {
        NSString *home = [NSString stringWithUTF8String:homeC];
        if (home.length > 0) {
            NSArray<NSString *> *localPaths = @[
                [home stringByAppendingPathComponent:@"Documents/_zt_active_profile.plist"],
                [home stringByAppendingPathComponent:@"Library/Preferences/com.ztech.profile.plist"]
            ];
            for (NSString *lp in localPaths) {
                NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:lp];
                if (d && [d isKindOfClass:[NSDictionary class]] && d.count > 0) {
                    NSDictionary *norm = ZTechNormalizeProfile(d);
                    ZTechApplyCachedProfileValues(norm);
                    return gCachedProfile;
                }
            }
        }
    }

    // 2. Fallback to shared global paths
    NSArray<NSString *> *globalPaths = @[
        @"/var/jb/var/mobile/Library/Preferences/com.ztech.profile.plist",
        @"/var/mobile/Library/Preferences/com.ztech.profile.plist",
        @"/var/jb/Library/Preferences/ZTechShared/com.ztech.profile.plist",
        @"/Library/Preferences/ZTechShared/com.ztech.profile.plist",
        @"/var/tmp/com.ztech.profile.plist"
    ];
    for (NSString *path in globalPaths) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if (dict && [dict isKindOfClass:[NSDictionary class]] && dict.count > 0) {
            NSDictionary *norm = ZTechNormalizeProfile(dict);
            ZTechApplyCachedProfileValues(norm);
            return gCachedProfile;
        }
    }

    NSDictionary *norm = ZTechNormalizeProfile(nil);
    ZTechApplyCachedProfileValues(norm);
    return gCachedProfile;
}

#pragma mark - Metal Driver Protection & Lock-Free Pure C Function Hooks

static inline BOOL ZTechIsMetalCaller(const void *retAddr) {
    if (!retAddr) return NO;
    Dl_info info;
    if (dladdr(retAddr, &info) != 0 && info.dli_fname) {
        const char *fn = info.dli_fname;
        if (strstr(fn, "Metal") != NULL ||
            strstr(fn, "AGX") != NULL ||
            strstr(fn, "IOAccelerator") != NULL) {
            return YES;
        }
    }
    return NO;
}

static int (*orig_uname)(struct utsname *buf) = NULL;
static int hooked_uname(struct utsname *buf) {
    if (buf == NULL) return -1;
    if (gHasRealUts) {
        memcpy(buf, &gRealUts, sizeof(struct utsname));
    } else {
        memset(buf, 0, sizeof(struct utsname));
        strncpy(buf->sysname, "Darwin", sizeof(buf->sysname) - 1);
        strncpy(buf->nodename, "iPhone", sizeof(buf->nodename) - 1);
        strncpy(buf->release, "21.5.0", sizeof(buf->release) - 1);
        strncpy(buf->version, "Darwin Kernel Version 21.5.0", sizeof(buf->version) - 1);
        strncpy(buf->machine, gRealMachineCStr, sizeof(buf->machine) - 1);
    }
    if (gMachineCStr[0] != '\0') {
        strncpy(buf->machine, gMachineCStr, sizeof(buf->machine) - 1);
        buf->machine[sizeof(buf->machine) - 1] = '\0';
    }
    if (gModelNameCStr[0] != '\0') {
        strncpy(buf->nodename, gModelNameCStr, sizeof(buf->nodename) - 1);
        buf->nodename[sizeof(buf->nodename) - 1] = '\0';
    }
    return 0;
}

static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int hooked_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name != NULL && namelen >= 2 && name[0] == CTL_HW) {
        if (name[1] == HW_MACHINE) {
            size_t len = strlen(gMachineCStr) + 1;
            if (oldp != NULL && oldlenp != NULL) {
                size_t copyLen = (*oldlenp < len) ? *oldlenp : len;
                memcpy(oldp, gMachineCStr, copyLen);
            }
            if (oldlenp != NULL) {
                *oldlenp = len;
            }
            return 0;
        } else if (name[1] == HW_MODEL) {
            if (!ZTechIsMetalCaller(__builtin_return_address(0))) {
                size_t len = strlen(gBoardIdCStr) + 1;
                if (oldp != NULL && oldlenp != NULL) {
                    size_t copyLen = (*oldlenp < len) ? *oldlenp : len;
                    memcpy(oldp, gBoardIdCStr, copyLen);
                }
                if (oldlenp != NULL) {
                    *oldlenp = len;
                }
                return 0;
            }
        } else if (gIsAidaProcess && name[1] == HW_MEMSIZE) {
            if (oldlenp != NULL) {
                if (oldp != NULL) {
                    size_t copyLen = (*oldlenp < sizeof(uint64_t)) ? *oldlenp : sizeof(uint64_t);
                    memcpy(oldp, &gRamBytes, copyLen);
                }
                *oldlenp = sizeof(uint64_t);
                return 0;
            }
        } else if (gIsAidaProcess && name[1] == HW_PHYSMEM) {
            if (oldlenp != NULL) {
                if (oldp != NULL) {
                    if (*oldlenp >= sizeof(uint64_t)) {
                        memcpy(oldp, &gRamBytes, sizeof(uint64_t));
                        *oldlenp = sizeof(uint64_t);
                    } else {
                        uint32_t ram32 = (gRamBytes > 0xFFFFFFFFULL) ? 0xFFFFFFFFU : (uint32_t)gRamBytes;
                        size_t copyLen = (*oldlenp < sizeof(uint32_t)) ? *oldlenp : sizeof(uint32_t);
                        memcpy(oldp, &ram32, copyLen);
                        *oldlenp = sizeof(uint32_t);
                    }
                } else {
                    *oldlenp = sizeof(uint64_t);
                }
                return 0;
            }
        } else if (gIsAidaProcess && (name[1] == HW_NCPU || name[1] == HW_AVAILCPU)) {
            if (oldlenp != NULL) {
                if (oldp != NULL) {
                    int cores = 6;
                    size_t copyLen = (*oldlenp < sizeof(int)) ? *oldlenp : sizeof(int);
                    memcpy(oldp, &cores, copyLen);
                }
                *oldlenp = sizeof(int);
                return 0;
            }
        }
    }
    return __sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int hooked_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name != NULL) {
        if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.product") == 0) {
            size_t len = strlen(gMachineCStr) + 1;
            if (oldp != NULL && oldlenp != NULL) {
                size_t copyLen = (*oldlenp < len) ? *oldlenp : len;
                memcpy(oldp, gMachineCStr, copyLen);
            }
            if (oldlenp != NULL) {
                *oldlenp = len;
            }
            return 0;
        } else if (strcmp(name, "hw.model") == 0 || strcmp(name, "hw.targettype") == 0) {
            if (!ZTechIsMetalCaller(__builtin_return_address(0))) {
                size_t len = strlen(gBoardIdCStr) + 1;
                if (oldp != NULL && oldlenp != NULL) {
                    size_t copyLen = (*oldlenp < len) ? *oldlenp : len;
                    memcpy(oldp, gBoardIdCStr, copyLen);
                }
                if (oldlenp != NULL) {
                    *oldlenp = len;
                }
                return 0;
            }
        } else if (gIsAidaProcess && strcmp(name, "hw.memsize") == 0) {
            if (oldlenp != NULL) {
                if (oldp != NULL) {
                    size_t copyLen = (*oldlenp < sizeof(uint64_t)) ? *oldlenp : sizeof(uint64_t);
                    memcpy(oldp, &gRamBytes, copyLen);
                }
                *oldlenp = sizeof(uint64_t);
                return 0;
            }
        } else if (gIsAidaProcess && strcmp(name, "hw.physmem") == 0) {
            if (oldlenp != NULL) {
                if (oldp != NULL) {
                    if (*oldlenp >= sizeof(uint64_t)) {
                        memcpy(oldp, &gRamBytes, sizeof(uint64_t));
                        *oldlenp = sizeof(uint64_t);
                    } else {
                        uint32_t ram32 = (gRamBytes > 0xFFFFFFFFULL) ? 0xFFFFFFFFU : (uint32_t)gRamBytes;
                        size_t copyLen = (*oldlenp < sizeof(uint32_t)) ? *oldlenp : sizeof(uint32_t);
                        memcpy(oldp, &ram32, copyLen);
                        *oldlenp = sizeof(uint32_t);
                    }
                } else {
                    *oldlenp = sizeof(uint64_t);
                }
                return 0;
            }
        } else if (gIsAidaProcess && (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.physicalcpu") == 0 || strcmp(name, "hw.logicalcpu") == 0)) {
            if (oldlenp != NULL) {
                if (oldp != NULL) {
                    int cores = 6;
                    size_t copyLen = (*oldlenp < sizeof(int)) ? *oldlenp : sizeof(int);
                    memcpy(oldp, &cores, copyLen);
                }
                *oldlenp = sizeof(int);
                return 0;
            }
        } else if (gIsAidaProcess && strcmp(name, "machdep.cpu.brand_string") == 0) {
            const char *soc = "Apple A18 Pro";
            size_t len = strlen(soc) + 1;
            if (oldp != NULL && oldlenp != NULL) {
                size_t copyLen = (*oldlenp < len) ? *oldlenp : len;
                memcpy(oldp, soc, copyLen);
            }
            if (oldlenp != NULL) {
                *oldlenp = len;
            }
            return 0;
        }

        int name2oid_oid[2] = { 0, 3 };
        int real_oid[CTL_MAXNAME + 2];
        size_t oidlen = sizeof(real_oid);
        int err = __sysctl(name2oid_oid, 2, real_oid, &oidlen, (void *)name, strlen(name));
        if (err < 0) return err;
        return __sysctl(real_oid, (u_int)(oidlen / sizeof(int)), oldp, oldlenp, newp, newlen);
    }
    return -1;
}

typedef CFTypeRef (*zt_MGCopyAnswerWithError_t)(CFStringRef prop, int *error);
static zt_MGCopyAnswerWithError_t orig_MGCopyAnswerWithError = NULL;
typedef CFTypeRef (*zt_MGCopyAnswer_t)(CFStringRef prop);
static zt_MGCopyAnswer_t orig_MGCopyAnswer = NULL;

static CFTypeRef hooked_MGCopyAnswerWithError(CFStringRef prop, int *error) {
    if (prop != NULL && CFGetTypeID(prop) == CFStringGetTypeID()) {
        if (CFEqual(prop, CFSTR("ProductType")) || CFEqual(prop, CFSTR("hw-machine")) || CFEqual(prop, CFSTR("device-name"))) {
            if (error) *error = 0;
            return (__bridge_retained CFTypeRef)[gMachineIdObj copy];
        }
        if (CFEqual(prop, CFSTR("HWModelStr")) || CFEqual(prop, CFSTR("HardwareModel"))) {
            if (error) *error = 0;
            return (__bridge_retained CFTypeRef)[[NSString stringWithUTF8String:gBoardIdCStr] copy];
        }
        if (CFEqual(prop, CFSTR("MarketingNameString")) || CFEqual(prop, CFSTR("marketing-name")) ||
            CFEqual(prop, CFSTR("DeviceName")) || CFEqual(prop, CFSTR("UserAssignedDeviceName"))) {
            if (error) *error = 0;
            return (__bridge_retained CFTypeRef)[gModelNameObj copy];
        }
        if (CFEqual(prop, CFSTR("ProductVersion"))) {
            if (error) *error = 0;
            return (__bridge_retained CFTypeRef)[gIosVersionObj copy];
        }
        if (CFEqual(prop, CFSTR("BuildVersion"))) {
            if (error) *error = 0;
            return (__bridge_retained CFTypeRef)[@"22B83" copy];
        }
    }
    if (orig_MGCopyAnswerWithError) {
        return orig_MGCopyAnswerWithError(prop, error);
    }
    if (orig_MGCopyAnswer) {
        return orig_MGCopyAnswer(prop);
    }
    return NULL;
}

static CFTypeRef hooked_MGCopyAnswer(CFStringRef prop) {
    return hooked_MGCopyAnswerWithError(prop, NULL);
}

typedef struct {
    uintptr_t start;
    uintptr_t end;
} ZTechAddrRange;

static ZTechAddrRange gAppImageRanges[128];
static volatile int gAppImageRangeCount = 0;

static void ZTechRebindImageAndRecordRange(const struct mach_header *header, intptr_t slide) {
    if (!header || header->magic != MH_MAGIC_64) return;
    Dl_info info;
    if (dladdr(header, &info) == 0 || !info.dli_fname) return;

    const char *fname = info.dli_fname;
    BOOL isAppImg = (strstr(fname, ".app/") != NULL);
    BOOL isSelfTweak = (strstr(fname, "ZTechHook") != NULL);
    if (!isAppImg && !isSelfTweak) return;

    const struct mach_header_64 *mh64 = (const struct mach_header_64 *)header;
    const struct segment_command_64 *linkedit_seg = NULL;
    const struct symtab_command *symtab_cmd = NULL;
    const struct dysymtab_command *dysymtab_cmd = NULL;

    uintptr_t cur = (uintptr_t)mh64 + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < mh64->ncmds; ++i) {
        const struct load_command *lc = (const struct load_command *)cur;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strcmp(seg->segname, "__TEXT") == 0) {
                int idx = gAppImageRangeCount;
                if (idx < 128) {
                    uintptr_t start = (uintptr_t)slide + seg->vmaddr;
                    uintptr_t end = start + seg->vmsize;
                    BOOL exists = NO;
                    for (int k = 0; k < idx; ++k) {
                        if (gAppImageRanges[k].start == start) { exists = YES; break; }
                    }
                    if (!exists) {
                        gAppImageRanges[idx].start = start;
                        gAppImageRanges[idx].end = end;
                        gAppImageRangeCount = idx + 1;
                    }
                }
            } else if (strcmp(seg->segname, "__LINKEDIT") == 0) {
                linkedit_seg = seg;
            }
        } else if (lc->cmd == LC_SYMTAB) {
            symtab_cmd = (const struct symtab_command *)lc;
        } else if (lc->cmd == LC_DYSYMTAB) {
            dysymtab_cmd = (const struct dysymtab_command *)lc;
        }
        cur += lc->cmdsize;
    }

    // Only rebind GOT / lazy symbol pointers on pure arm64 app images (skip on arm64e PAC pointers)
#if !__has_feature(ptrauth_calls)
    if (!isAppImg || !linkedit_seg || !symtab_cmd || !dysymtab_cmd) return;
    uintptr_t linkedit_base = (uintptr_t)slide + linkedit_seg->vmaddr - linkedit_seg->fileoff;
    const struct nlist_64 *symtab = (const struct nlist_64 *)(linkedit_base + symtab_cmd->symoff);
    const char *strtab = (const char *)(linkedit_base + symtab_cmd->stroff);
    const uint32_t *indirect_symtab = (const uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

    cur = (uintptr_t)mh64 + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < mh64->ncmds; ++i) {
        const struct load_command *lc = (const struct load_command *)cur;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strcmp(seg->segname, "__DATA") == 0 || strcmp(seg->segname, "__DATA_CONST") == 0) {
                const struct section_64 *sec = (const struct section_64 *)((uintptr_t)seg + sizeof(struct segment_command_64));
                for (uint32_t j = 0; j < seg->nsects; ++j) {
                    uint8_t type = sec[j].flags & SECTION_TYPE;
                    if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS) {
                        uint32_t *indices = (uint32_t *)(indirect_symtab + sec[j].reserved1);
                        void **bindings = (void **)((uintptr_t)slide + sec[j].addr);
                        size_t count = sec[j].size / sizeof(void *);
                        vm_protect(mach_task_self(), (vm_address_t)bindings, (vm_size_t)sec[j].size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
                        for (size_t k = 0; k < count; ++k) {
                            uint32_t sym_idx = indices[k];
                            if (sym_idx == INDIRECT_SYMBOL_ABS || sym_idx == INDIRECT_SYMBOL_LOCAL ||
                                sym_idx == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS) || sym_idx >= symtab_cmd->nsyms) {
                                continue;
                            }
                            const char *sym_name = strtab + symtab[sym_idx].n_un.n_strx;
                            if (strcmp(sym_name, "_uname") == 0) {
                                bindings[k] = (void *)hooked_uname;
                            } else if (strcmp(sym_name, "_sysctlbyname") == 0) {
                                bindings[k] = (void *)hooked_sysctlbyname;
                            } else if (strcmp(sym_name, "_sysctl") == 0) {
                                bindings[k] = (void *)hooked_sysctl;
                            } else if (strcmp(sym_name, "_MGCopyAnswer") == 0) {
                                bindings[k] = (void *)hooked_MGCopyAnswer;
                            }
                        }
                    }
                }
            }
        }
        cur += lc->cmdsize;
    }
#endif
}







static NSString *ZTechGPUNameForMachine(NSString *machine) {
    if (!machine || machine.length == 0) return @"Apple A18 Pro GPU";
    if ([machine hasPrefix:@"iPhone17,1"] || [machine hasPrefix:@"iPhone17,2"]) return @"Apple A18 Pro GPU";
    if ([machine hasPrefix:@"iPhone17,"]) return @"Apple A18 GPU";
    if ([machine hasPrefix:@"iPhone16,"]) return @"Apple A17 Pro GPU";
    if ([machine hasPrefix:@"iPhone15,2"] || [machine hasPrefix:@"iPhone15,3"]) return @"Apple A16 Bionic GPU";
    if ([machine hasPrefix:@"iPhone15,"]) return @"Apple A15 Bionic GPU";
    if ([machine hasPrefix:@"iPhone14,"]) return @"Apple A15 Bionic GPU";
    if ([machine hasPrefix:@"iPhone13,"]) return @"Apple A14 Bionic GPU";
    if ([machine hasPrefix:@"iPhone12,"]) return @"Apple A13 Bionic GPU";
    if ([machine hasPrefix:@"iPhone11,"]) return @"Apple A12 Bionic GPU";
    if ([machine hasPrefix:@"iPhone10,"]) return @"Apple A11 Bionic GPU";
    if ([machine hasPrefix:@"iPhone9,"]) return @"Apple A10 Fusion GPU";
    if ([machine hasPrefix:@"iPhone8,"]) return @"Apple A9 GPU";
    return @"Apple A18 Pro GPU";
}

static NSString *(*orig_MTLDevice_name)(id, SEL) = NULL;
static NSString *swizzled_MTLDevice_name(id self, SEL _cmd) {
    return ZTechGPUNameForMachine(gMachineIdObj);
}

static NSString *(*orig_carrierName)(id, SEL) = NULL;
static NSString *swizzled_carrierName(id self, SEL _cmd) {
    return gCarrierNameObj ?: @"Viettel";
}

static NSString *(*orig_isoCountryCode)(id, SEL) = NULL;
static NSString *swizzled_isoCountryCode(id self, SEL _cmd) {
    return @"vn";
}

static NSString *(*orig_mobileCountryCode)(id, SEL) = NULL;
static NSString *swizzled_mobileCountryCode(id self, SEL _cmd) {
    return @"452";
}

static NSString *(*orig_mobileNetworkCode)(id, SEL) = NULL;
static NSString *swizzled_mobileNetworkCode(id self, SEL _cmd) {
    if ([gCarrierNameObj isEqualToString:@"MobiFone"]) return @"01";
    if ([gCarrierNameObj isEqualToString:@"Vinaphone"]) return @"02";
    if ([gCarrierNameObj isEqualToString:@"Vietnamobile"]) return @"05";
    return @"04";
}

static NSString *(*orig_systemVersion)(id, SEL) = NULL;
static NSString *swizzled_systemVersion(id self, SEL _cmd) {
    return gIosVersionObj ?: @"18.2.1";
}

static NSString *(*orig_deviceName)(id, SEL) = NULL;
static NSString *swizzled_deviceName(id self, SEL _cmd) {
    return gModelNameObj ?: @"iPhone 16 Pro Max";
}

static float (*orig_batteryLevel)(id, SEL) = NULL;
static float swizzled_batteryLevel(id self, SEL _cmd) {
    return gBatteryFloat;
}

static NSUUID *(*orig_identifierForVendor)(id, SEL) = NULL;
static NSUUID *swizzled_identifierForVendor(id self, SEL _cmd) {
    if (gCachedVendorUUID) {
        return gCachedVendorUUID;
    }
    return [NSUUID UUID];
}

static NSOperatingSystemVersion (*orig_osVersion)(id, SEL) = NULL;
static NSOperatingSystemVersion swizzled_osVersion(id self, SEL _cmd) {
    NSArray<NSString *> *parts = [gIosVersionObj componentsSeparatedByString:@"."];
    NSOperatingSystemVersion v = {18, 2, 1};
    if (parts.count > 0 && [parts[0] integerValue] >= 16) v.majorVersion = [parts[0] integerValue];
    if (parts.count > 1) v.minorVersion = [parts[1] integerValue];
    if (parts.count > 2) v.patchVersion = [parts[2] integerValue];
    return v;
}

static NSString *(*orig_osVersionString)(id, SEL) = NULL;
static NSString *swizzled_osVersionString(id self, SEL _cmd) {
    return [NSString stringWithFormat:@"Version %@ (Build 22C152)", gIosVersionObj ?: @"18.2.1"];
}

static unsigned long long (*orig_physicalMemory)(id, SEL) = NULL;
static unsigned long long swizzled_physicalMemory(id self, SEL _cmd) {
    return (unsigned long long)gRamBytes;
}

static SEL gZTechOrigDevInfoSel = NULL;
static id swizzled_deviceInfoForKey(id self, SEL _cmd, NSString *key) {
    if (key && [key isKindOfClass:[NSString class]]) {
        if ([key isEqualToString:@"ProductType"] || [key isEqualToString:@"hw-machine"] || [key isEqualToString:@"device-name"]) {
            return gMachineIdObj ?: @"iPhone17,2";
        }
        if ([key isEqualToString:@"HWModelStr"] || [key isEqualToString:@"HardwareModel"]) {
            return [NSString stringWithUTF8String:gBoardIdCStr];
        }
        if ([key isEqualToString:@"DeviceName"] || [key isEqualToString:@"UserAssignedDeviceName"] ||
            [key isEqualToString:@"MarketingNameString"] || [key isEqualToString:@"marketing-name"]) {
            return gModelNameObj ?: @"iPhone 16 Pro Max";
        }
        if ([key isEqualToString:@"ProductVersion"]) {
            return gIosVersionObj ?: @"18.1.1";
        }
        if ([key isEqualToString:@"BuildVersion"]) {
            return @"22B83";
        }
    }
    if (gZTechOrigDevInfoSel && [self respondsToSelector:gZTechOrigDevInfoSel]) {
        return ((id (*)(id, SEL, id))objc_msgSend)(self, gZTechOrigDevInfoSel, key);
    }
    return nil;
}

static NSString *swizzled_model(id self, SEL _cmd) {
    return @"iPhone";
}

static SEL gZTechOrigDefCfgSel = NULL;
static SEL gZTechOrigEphCfgSel = NULL;

static NSURLSessionConfiguration *swizzled_defaultSessionConfig(id self, SEL _cmd) {
    NSURLSessionConfiguration *cfg = nil;
    if (gZTechOrigDefCfgSel && [self respondsToSelector:gZTechOrigDefCfgSel]) {
        cfg = ((NSURLSessionConfiguration *(*)(id, SEL))objc_msgSend)(self, gZTechOrigDefCfgSel);
    }
    if (cfg && gProxyEnabled && gCachedProxyDict) {
        @try {
            cfg.connectionProxyDictionary = gCachedProxyDict;
            if (gCachedProxyAuthHeader.length > 0) {
                NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:cfg.HTTPAdditionalHeaders ?: @{}];
                headers[@"Proxy-Authorization"] = gCachedProxyAuthHeader;
                cfg.HTTPAdditionalHeaders = headers;
            }
        } @catch (NSException *e) {}
    }
    return cfg;
}

static NSURLSessionConfiguration *swizzled_ephemeralSessionConfig(id self, SEL _cmd) {
    NSURLSessionConfiguration *cfg = nil;
    if (gZTechOrigEphCfgSel && [self respondsToSelector:gZTechOrigEphCfgSel]) {
        cfg = ((NSURLSessionConfiguration *(*)(id, SEL))objc_msgSend)(self, gZTechOrigEphCfgSel);
    }
    if (cfg && gProxyEnabled && gCachedProxyDict) {
        @try {
            cfg.connectionProxyDictionary = gCachedProxyDict;
            if (gCachedProxyAuthHeader.length > 0) {
                NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:cfg.HTTPAdditionalHeaders ?: @{}];
                headers[@"Proxy-Authorization"] = gCachedProxyAuthHeader;
                cfg.HTTPAdditionalHeaders = headers;
            }
        } @catch (NSException *e) {}
    }
    return cfg;
}

#pragma mark - In-Memory NSUbiquitousKeyValueStore Stub (Prevents SyncedDefaults EXC_GUARD & iCloud KVS Leaks)

@interface ZTechUbiquitousStoreStub : NSObject {
    NSMutableDictionary<NSString *, id> *_store;
    NSLock *_lock;
}
+ (instancetype)sharedStore;
- (void)resetStore;
@end

@implementation ZTechUbiquitousStoreStub

+ (instancetype)sharedStore {
    static ZTechUbiquitousStoreStub *sStub = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sStub = [[ZTechUbiquitousStoreStub alloc] init];
    });
    return sStub;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _store = [[NSMutableDictionary alloc] init];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)resetStore {
    [_lock lock];
    [_store removeAllObjects];
    [_lock unlock];
}

- (BOOL)isKindOfClass:(Class)aClass {
    Class kvsCls = objc_getClass("NSUbiquitousKeyValueStore");
    if (kvsCls && (aClass == kvsCls || [kvsCls isSubclassOfClass:aClass])) {
        return YES;
    }
    return [super isKindOfClass:aClass];
}

- (id)objectForKey:(NSString *)aKey {
    if (!aKey) return nil;
    [_lock lock];
    id val = _store[aKey];
    [_lock unlock];
    return val;
}

- (void)setObject:(id)anObject forKey:(NSString *)aKey {
    if (!aKey) return;
    [_lock lock];
    if (anObject) {
        _store[aKey] = anObject;
    } else {
        [_store removeObjectForKey:aKey];
    }
    [_lock unlock];
}

- (void)removeObjectForKey:(NSString *)aKey {
    if (!aKey) return;
    [_lock lock];
    [_store removeObjectForKey:aKey];
    [_lock unlock];
}

- (NSString *)stringForKey:(NSString *)aKey {
    id v = [self objectForKey:aKey];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

- (NSArray *)arrayForKey:(NSString *)aKey {
    id v = [self objectForKey:aKey];
    return [v isKindOfClass:[NSArray class]] ? v : nil;
}

- (NSDictionary<NSString *, id> *)dictionaryForKey:(NSString *)aKey {
    id v = [self objectForKey:aKey];
    return [v isKindOfClass:[NSDictionary class]] ? v : nil;
}

- (NSData *)dataForKey:(NSString *)aKey {
    id v = [self objectForKey:aKey];
    return [v isKindOfClass:[NSData class]] ? v : nil;
}

- (long long)longLongForKey:(NSString *)aKey {
    id v = [self objectForKey:aKey];
    if ([v respondsToSelector:@selector(longLongValue)]) return [v longLongValue];
    return 0;
}

- (double)doubleForKey:(NSString *)aKey {
    id v = [self objectForKey:aKey];
    if ([v respondsToSelector:@selector(doubleValue)]) return [v doubleValue];
    return 0.0;
}

- (BOOL)boolForKey:(NSString *)aKey {
    id v = [self objectForKey:aKey];
    if ([v respondsToSelector:@selector(boolValue)]) return [v boolValue];
    return NO;
}

- (void)setString:(NSString *)aString forKey:(NSString *)aKey {
    [self setObject:aString forKey:aKey];
}

- (void)setData:(NSData *)aData forKey:(NSString *)aKey {
    [self setObject:aData forKey:aKey];
}

- (void)setArray:(NSArray *)anArray forKey:(NSString *)aKey {
    [self setObject:anArray forKey:aKey];
}

- (void)setDictionary:(NSDictionary<NSString *, id> *)aDictionary forKey:(NSString *)aKey {
    [self setObject:aDictionary forKey:aKey];
}

- (void)setLongLong:(long long)value forKey:(NSString *)aKey {
    [self setObject:@(value) forKey:aKey];
}

- (void)setDouble:(double)value forKey:(NSString *)aKey {
    [self setObject:@(value) forKey:aKey];
}

- (void)setBool:(BOOL)value forKey:(NSString *)aKey {
    [self setObject:@(value) forKey:aKey];
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    [_lock lock];
    NSDictionary *copy = [_store copy] ?: @{};
    [_lock unlock];
    return copy;
}

- (BOOL)synchronize {
    return YES;
}

- (id)valueForKey:(NSString *)key {
    return [self objectForKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key {
    [self setObject:value forKey:key];
}

- (id)objectForKeyedSubscript:(NSString *)key {
    return [self objectForKey:key];
}

- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key {
    [self setObject:obj forKey:key];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
    if (!sig) {
        sig = [NSMethodSignature signatureWithObjCTypes:"@@:"];
    }
    return sig;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    id nilVal = nil;
    if (anInvocation.methodSignature.methodReturnLength == sizeof(id)) {
        [anInvocation setReturnValue:&nilVal];
    }
}

@end

static id swizzled_ubiquitousDefaultStore(id self, SEL _cmd) {
    return [ZTechUbiquitousStoreStub sharedStore];
}

#pragma mark - In-Process Zalo Keychain, Container & AppGroup Synchronization

static void ZTechWipeDirectoryContentsAtPath(NSString *dirPath, NSFileManager *fm) {
    if (!dirPath || dirPath.length == 0) return;
    chmod([dirPath UTF8String], 0755);
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:dirPath error:nil];
    for (NSString *item in items) {
        if ([item isEqualToString:@".com.apple.mobile_container_manager.metadata.plist"] ||
            [item isEqualToString:@"SystemData"] ||
            [item isEqualToString:@"_zt_active_profile.plist"] ||
            [item isEqualToString:@"com.ztech.profile.plist"] ||
            [item isEqualToString:@"_zt_zalo_marker.txt"] ||
            [item isEqualToString:@"_zt_bound_uuid.txt"] ||
            [item isEqualToString:@"_zt_restore_trigger.txt"] ||
            [item isEqualToString:@"_zt_keychain_snapshot.plist"] ||
            [item isEqualToString:@"_zt_prefs_snapshot.plist"] ||
            [item isEqualToString:@"ztech_hook_trace.log"] ||
            [item isEqualToString:@"ztech_crash.log"] ||
            [item isEqualToString:@"Library"] ||
            [item isEqualToString:@"Documents"] ||
            [item isEqualToString:@"tmp"] ||
            [item isEqualToString:@"Caches"] ||
            [item isEqualToString:@"Preferences"] ||
            [item isEqualToString:@"Cookies"] ||
            [item isEqualToString:@"Application Support"] ||
            [item isEqualToString:@"SplashBoard"]) {
            continue;
        }
        NSString *fullPath = [dirPath stringByAppendingPathComponent:item];
        struct stat st;
        if (lstat([fullPath UTF8String], &st) == 0 && S_ISLNK(st.st_mode)) {
            unlink([fullPath UTF8String]);
            continue;
        }
        chflags([fullPath UTF8String], 0);
        chmod([fullPath UTF8String], 0755);
        if (![fm removeItemAtPath:fullPath error:nil]) {
            NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:fullPath];
            NSString *rel = nil;
            while ((rel = [enumerator nextObject])) {
                NSString *subP = [fullPath stringByAppendingPathComponent:rel];
                chflags([subP UTF8String], 0);
                chmod([subP UTF8String], 0755);
            }
            [fm removeItemAtPath:fullPath error:nil];
        }
    }
}

static void ZTechSnapshotZaloKeychainAndPrefs(NSString *bundleId) {
    @try {
        const char *homeC = getenv("HOME");
        if (!homeC || homeC[0] == '\0') return;
        NSString *home = [NSString stringWithUTF8String:homeC];
        NSString *docsDir = [home stringByAppendingPathComponent:@"Documents"];

        if (bundleId.length > 0) {
            NSDictionary *dom = [[NSUserDefaults standardUserDefaults] persistentDomainForName:bundleId];
            if (dom && dom.count > 0) {
                NSString *prefsSnapPath = [docsDir stringByAppendingPathComponent:@"_zt_prefs_snapshot.plist"];
                [dom writeToFile:prefsSnapPath atomically:YES];
            }
        }

        NSMutableArray *savedItems = [NSMutableArray array];
        NSArray *classes = @[
            (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecClassInternetPassword
        ];
        for (id secClass in classes) {
            NSDictionary *query = @{
                (__bridge id)kSecClass: secClass,
                (__bridge id)kSecReturnAttributes: @YES,
                (__bridge id)kSecReturnData: @YES,
                (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll
            };
            CFTypeRef result = NULL;
            OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
            if (status == errSecSuccess && result) {
                NSArray *items = (__bridge_transfer NSArray *)result;
                for (NSDictionary *item in items) {
                    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                    entry[@"secClass"] = [secClass isEqual:(__bridge id)kSecClassGenericPassword] ? @"genp" : @"inet";
                    if ([item[(__bridge id)kSecAttrAccount] isKindOfClass:[NSString class]] ||
                        [item[(__bridge id)kSecAttrAccount] isKindOfClass:[NSData class]]) {
                        entry[@"acct"] = item[(__bridge id)kSecAttrAccount];
                    }
                    if ([item[(__bridge id)kSecAttrService] isKindOfClass:[NSString class]] ||
                        [item[(__bridge id)kSecAttrService] isKindOfClass:[NSData class]]) {
                        entry[@"svce"] = item[(__bridge id)kSecAttrService];
                    }
                    if ([item[(__bridge id)kSecAttrGeneric] isKindOfClass:[NSData class]] ||
                        [item[(__bridge id)kSecAttrGeneric] isKindOfClass:[NSString class]]) {
                        entry[@"gena"] = item[(__bridge id)kSecAttrGeneric];
                    }
                    if ([item[(__bridge id)kSecValueData] isKindOfClass:[NSData class]]) {
                        entry[@"v_Data"] = item[(__bridge id)kSecValueData];
                    }
                    if (entry[@"v_Data"]) {
                        [savedItems addObject:entry];
                    }
                }
            }
        }
        if (savedItems.count > 0) {
            NSString *kcSnapPath = [docsDir stringByAppendingPathComponent:@"_zt_keychain_snapshot.plist"];
            [savedItems writeToFile:kcSnapPath atomically:YES];
        }
    } @catch (NSException *e) {}
}

static void ZTechSyncZaloSessionAndKeychain(NSString *bundleId) {
    @try {
        const char *homeC = getenv("HOME");
        if (!homeC || homeC[0] == '\0') return;
        NSString *home = [NSString stringWithUTF8String:homeC];
        if (home.length == 0) return;

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *docsDir = [home stringByAppendingPathComponent:@"Documents"];
        if (![fm fileExistsAtPath:docsDir]) {
            [fm createDirectoryAtPath:docsDir withIntermediateDirectories:YES attributes:nil error:nil];
            chmod([docsDir UTF8String], 0755);
        }

        NSString *restoreTrigger = [docsDir stringByAppendingPathComponent:@"_zt_restore_trigger.txt"];
        NSString *wipeFlag = [docsDir stringByAppendingPathComponent:@"_zt_wipe_keychain.flag"];
        NSString *boundUuidFile = [docsDir stringByAppendingPathComponent:@"_zt_bound_uuid.txt"];

        // Case 1: Vault Restore Triggered (Write plist directly to disk without initializing CFPreferences during dyld constructor)
        if ([fm fileExistsAtPath:restoreTrigger]) {
            [fm removeItemAtPath:restoreTrigger error:nil];
            [fm removeItemAtPath:wipeFlag error:nil];

            NSString *prefsSnapPath = [docsDir stringByAppendingPathComponent:@"_zt_prefs_snapshot.plist"];
            NSDictionary *savedPrefs = [NSDictionary dictionaryWithContentsOfFile:prefsSnapPath];
            if (savedPrefs && [savedPrefs isKindOfClass:[NSDictionary class]] && bundleId.length > 0) {
                NSString *prefsDir = [home stringByAppendingPathComponent:@"Library/Preferences"];
                [fm createDirectoryAtPath:prefsDir withIntermediateDirectories:YES attributes:nil error:nil];
                chmod([prefsDir UTF8String], 0755);
                NSString *destPlist = [prefsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", bundleId]];
                [savedPrefs writeToFile:destPlist atomically:YES];
                chmod([destPlist UTF8String], 0644);
            }

            NSString *kcSnapPath = [docsDir stringByAppendingPathComponent:@"_zt_keychain_snapshot.plist"];
            NSArray *savedKc = [NSArray arrayWithContentsOfFile:kcSnapPath];
            if (savedKc && [savedKc isKindOfClass:[NSArray class]]) {
                NSArray *secClasses = @[
                    (__bridge id)kSecClassGenericPassword,
                    (__bridge id)kSecClassInternetPassword
                ];
                for (id secClass in secClasses) {
                    SecItemDelete((__bridge CFDictionaryRef)@{(__bridge id)kSecClass: secClass});
                }
                for (NSDictionary *entry in savedKc) {
                    if (![entry isKindOfClass:[NSDictionary class]] || !entry[@"v_Data"]) continue;
                    NSMutableDictionary *addItem = [NSMutableDictionary dictionary];
                    NSString *clsType = entry[@"secClass"];
                    addItem[(__bridge id)kSecClass] = [clsType isEqualToString:@"inet"]
                        ? (__bridge id)kSecClassInternetPassword
                        : (__bridge id)kSecClassGenericPassword;
                    addItem[(__bridge id)kSecValueData] = entry[@"v_Data"];
                    addItem[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
                    if (entry[@"acct"]) addItem[(__bridge id)kSecAttrAccount] = entry[@"acct"];
                    if (entry[@"svce"]) addItem[(__bridge id)kSecAttrService] = entry[@"svce"];
                    if (entry[@"gena"]) addItem[(__bridge id)kSecAttrGeneric] = entry[@"gena"];
                    SecItemAdd((__bridge CFDictionaryRef)addItem, NULL);
                }
            }

            NSString *currentSig = [NSString stringWithFormat:@"%@:%@", gUuidObj ?: @"", gMachineIdObj ?: @""];
            if (currentSig.length > 1) {
                [currentSig writeToFile:boundUuidFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
                chmod([boundUuidFile UTF8String], 0666);
            }
            ZTechHookTrace([[NSString stringWithFormat:@"[2.5/6] Vault session restored (Keychain + Prefs) for sig=%@", currentSig] UTF8String]);
            return;
        }

        // Case 2: Check if Clean Reset or New Device UUID/Model requires purging stale Keychain & Container
        NSString *currentSig = [NSString stringWithFormat:@"%@:%@", gUuidObj ?: @"", gMachineIdObj ?: @""];
        NSString *boundSig = [[NSString stringWithContentsOfFile:boundUuidFile encoding:NSUTF8StringEncoding error:nil]
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        BOOL hasWipeFlag = [fm fileExistsAtPath:wipeFlag];
        BOOL sigChanged = (!boundSig || boundSig.length == 0 || ![boundSig isEqualToString:currentSig]);

        if (hasWipeFlag || sigChanged) {
            ZTechHookTrace([[NSString stringWithFormat:@"[2.1/6] In-process deep clean triggered (wipeFlag=%d, boundSig=%@ -> newSig=%@)",
                             hasWipeFlag ? 1 : 0, boundSig ?: @"(none)", currentSig] UTF8String]);

            [fm removeItemAtPath:wipeFlag error:nil];
            [fm removeItemAtPath:[docsDir stringByAppendingPathComponent:@"_zt_keychain_snapshot.plist"] error:nil];
            [fm removeItemAtPath:[docsDir stringByAppendingPathComponent:@"_zt_prefs_snapshot.plist"] error:nil];
            [[ZTechUbiquitousStoreStub sharedStore] resetStore];

            // 1. Purge all Zalo Keychain items (prevents stale account e.g. 466042823 from auto-restoring & crashing on new UUID)
            NSArray *secClasses = @[
                (__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecClassInternetPassword,
                (__bridge id)kSecClassCertificate,
                (__bridge id)kSecClassKey,
                (__bridge id)kSecClassIdentity
            ];
            int matchedClasses = 0;
            for (id secClass in secClasses) {
                OSStatus st1 = SecItemDelete((__bridge CFDictionaryRef)@{(__bridge id)kSecClass: secClass});
                OSStatus st2 = SecItemDelete((__bridge CFDictionaryRef)@{
                    (__bridge id)kSecClass: secClass,
                    (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny
                });
                if (st1 == errSecSuccess || st2 == errSecSuccess) {
                    matchedClasses++;
                }
            }
            ZTechHookTrace([[NSString stringWithFormat:@"[2.2/6] Zalo Keychain purged across 5 classes (matched=%d)", matchedClasses] UTF8String]);

            // 2. Wipe Zalo container subdirectories from inside Zalo's own process (uid 501)
            // Note: Do NOT call [NSUserDefaults standardUserDefaults] during __attribute__((constructor))
            // because initializing CFPreferences while dyld holds the loader lock causes SyncedDefaults/CFPrefs EXC_GUARD faults.
            NSArray<NSString *> *subDirs = @[
                @"Documents",
                @"tmp",
                @"Library/Preferences",
                @"Library/Caches",
                @"Library/Cookies",
                @"Library/WebKit",
                @"Library/Application Support",
                @"Library/HTTPStorages",
                @"Library/Saved Application State"
            ];
            for (NSString *sub in subDirs) {
                NSString *target = [home stringByAppendingPathComponent:sub];
                if ([fm fileExistsAtPath:target]) {
                    ZTechWipeDirectoryContentsAtPath(target, fm);
                }
            }

            // 3. Wipe all 6 Zalo AppGroup containers (using pre-resolved appGroupPaths from _zt_active_profile.plist)
            NSArray<NSString *> *groupPaths = [gCachedProfile[@"appGroupPaths"] isKindOfClass:[NSArray class]]
                ? gCachedProfile[@"appGroupPaths"]
                : nil;
            for (NSString *grpPath in groupPaths) {
                if ([grpPath isKindOfClass:[NSString class]] && grpPath.length > 0 && [fm fileExistsAtPath:grpPath]) {
                    ZTechWipeDirectoryContentsAtPath(grpPath, fm);
                    NSArray<NSString *> *grpSubs = @[@"Documents", @"Library/Preferences", @"Library/Caches", @"Library/Application Support"];
                    for (NSString *gs in grpSubs) {
                        NSString *gTarget = [grpPath stringByAppendingPathComponent:gs];
                        if ([fm fileExistsAtPath:gTarget]) {
                            ZTechWipeDirectoryContentsAtPath(gTarget, fm);
                        }
                    }
                }
            }

            // 4. Bind the new UUID:machineId so subsequent launches of the same session preserve login data
            if (currentSig.length > 1) {
                [currentSig writeToFile:boundUuidFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
                chmod([boundUuidFile UTF8String], 0666);
            }
            ZTechHookTrace([[NSString stringWithFormat:@"[2.3/6] In-process deep clean completed 100%% for sig=%@", currentSig] UTF8String]);
        }
    } @catch (NSException *e) {
        ZTechHookTrace([[NSString stringWithFormat:@"[2.3/6 ERROR] Sync exception: %@", e] UTF8String]);
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void ZTechHookInit(void) {
    @autoreleasepool {
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        NSString *bundlePath = [[NSBundle mainBundle] bundlePath];

        if ([bundleId isEqualToString:@"com.apple.springboard"]) {
            static int tokenOn = 0;
            notify_register_dispatch("com.ztech.airplaneModeOn", &tokenOn, dispatch_get_main_queue(), ^(int token) {
                @try {
                    Class sbClass = objc_getClass("SBAirplaneModeController");
                    if (sbClass) {
                        SEL sharedSel = sel_registerName("sharedInstance");
                        SEL setAirSel = sel_registerName("setInAirplaneMode:");
                        if ([sbClass respondsToSelector:sharedSel]) {
                            id ctrl = ((id (*)(id, SEL))objc_msgSend)(sbClass, sharedSel);
                            if (ctrl && [ctrl respondsToSelector:setAirSel]) {
                                ((void (*)(id, SEL, BOOL))objc_msgSend)(ctrl, setAirSel, YES);
                            }
                        }
                    }
                    Class rpClass = objc_getClass("RadiosPreferences");
                    if (rpClass) {
                        id rp = [[rpClass alloc] init];
                        SEL setAirSel = sel_registerName("setAirplaneMode:");
                        if ([rp respondsToSelector:setAirSel]) {
                            ((void (*)(id, SEL, BOOL))objc_msgSend)(rp, setAirSel, YES);
                        }
                        SEL syncSel = sel_registerName("synchronize");
                        if ([rp respondsToSelector:syncSel]) {
                            ((void (*)(id, SEL))objc_msgSend)(rp, syncSel);
                        }
                    }
                } @catch (NSException *e) {}
            });

            static int tokenOff = 0;
            notify_register_dispatch("com.ztech.airplaneModeOff", &tokenOff, dispatch_get_main_queue(), ^(int token) {
                @try {
                    Class sbClass = objc_getClass("SBAirplaneModeController");
                    if (sbClass) {
                        SEL sharedSel = sel_registerName("sharedInstance");
                        SEL setAirSel = sel_registerName("setInAirplaneMode:");
                        if ([sbClass respondsToSelector:sharedSel]) {
                            id ctrl = ((id (*)(id, SEL))objc_msgSend)(sbClass, sharedSel);
                            if (ctrl && [ctrl respondsToSelector:setAirSel]) {
                                ((void (*)(id, SEL, BOOL))objc_msgSend)(ctrl, setAirSel, NO);
                            }
                        }
                    }
                    Class rpClass = objc_getClass("RadiosPreferences");
                    if (rpClass) {
                        id rp = [[rpClass alloc] init];
                        SEL setAirSel = sel_registerName("setAirplaneMode:");
                        if ([rp respondsToSelector:setAirSel]) {
                            ((void (*)(id, SEL, BOOL))objc_msgSend)(rp, setAirSel, NO);
                        }
                        SEL syncSel = sel_registerName("synchronize");
                        if ([rp respondsToSelector:syncSel]) {
                            ((void (*)(id, SEL))objc_msgSend)(rp, syncSel);
                        }
                    }
                } @catch (NSException *e) {}
            });
            return;
        }

        NSString *procName = [[NSProcessInfo processInfo] processName];
        BOOL isAida = (bundleId && [bundleId localizedCaseInsensitiveContainsString:@"aida64"]) ||
                      (procName && [procName localizedCaseInsensitiveContainsString:@"aida64"]);
        BOOL isZalo = (bundleId && [bundleId localizedCaseInsensitiveContainsString:@"zalo"]) ||
                      (procName && [procName localizedCaseInsensitiveContainsString:@"zalo"]) ||
                      (bundleId && [bundleId localizedCaseInsensitiveContainsString:@"zingalo"]) ||
                      (procName && [procName localizedCaseInsensitiveContainsString:@"zingalo"]);

        if (!isAida && !isZalo) {
            return;
        }

        gIsAidaProcess = isAida ? 1 : 0;
        gProcessStartTime = time(NULL);

        // Immediately clean up any broken .GlobalPreferences.plist symlink inside the app's container before CFPreferences initializes
        const char *homeEnv = getenv("HOME");
        if (homeEnv && homeEnv[0] != '\0') {
            char gpLink[1024] = {0};
            snprintf(gpLink, sizeof(gpLink), "%s/Library/Preferences/.GlobalPreferences.plist", homeEnv);
            struct stat st;
            if (lstat(gpLink, &st) == 0 && S_ISLNK(st.st_mode)) {
                unlink(gpLink);
            }
        }

        gPrevUncaughtHandler = NSGetUncaughtExceptionHandler();
        NSSetUncaughtExceptionHandler(&ZTechUncaughtExceptionHandler);
        ZTechInstallSignalHandlers();
        atexit(ZTechAtExitHandler);

        ZTechHookTrace([[NSString stringWithFormat:@"[1/6] ZTechHookInit v5.6.0 started in pid:%d (%@ / %@)",
                         getpid(), bundleId ?: @"(nil)", procName ?: @"(nil)"] UTF8String]);

        if (uname(&gRealUts) == 0 && gRealUts.machine[0] != '\0') {
            gHasRealUts = 1;
            strncpy(gRealMachineCStr, gRealUts.machine, sizeof(gRealMachineCStr) - 1);
            gRealMachineCStr[sizeof(gRealMachineCStr) - 1] = '\0';
        }

        // Fast instant cached profile read (reads local container first)
        ZTechLoadProfileOnce();

        ZTechHookTrace([[NSString stringWithFormat:@"[2/6] Profile loaded: model=%@, id=%@, ios=%@, uuid=%@",
                         gModelNameObj, gMachineIdObj, gIosVersionObj, gUuidObj] UTF8String]);

        // Synchronize Zalo Keychain, Container & AppGroup state before Zalo's main() runs
        if (isZalo) {
            ZTechSyncZaloSessionAndKeychain(bundleId);

            // Swizzle +[NSUbiquitousKeyValueStore defaultStore] to return in-memory stub
            // Eliminates SyncedDefaults (SYDRemotePreferencesSource) EXC_GUARD fault & blocks iCloud KVS tracking
            @try {
                Class kvsCls = objc_getClass("NSUbiquitousKeyValueStore");
                if (kvsCls) {
                    Method mDefStore = class_getClassMethod(kvsCls, @selector(defaultStore));
                    if (mDefStore) {
                        method_setImplementation(mDefStore, (IMP)swizzled_ubiquitousDefaultStore);
                    }
                }
            } @catch (NSException *e) {}

            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification * _Nonnull note) {
                ZTechSnapshotZaloKeychainAndPrefs(bundleId);
            }];
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification * _Nonnull note) {
                ZTechSnapshotZaloKeychainAndPrefs(bundleId);
            }];
        }

        // 1. Safe Objective-C Swizzling for UIDevice & NSURLSessionConfiguration using objc_getClass
        @try {
            Class uiDeviceCls = objc_getClass("UIDevice");
            if (uiDeviceCls) {
                Method mSysVer = class_getInstanceMethod(uiDeviceCls, @selector(systemVersion));
                if (mSysVer) {
                    orig_systemVersion = (void *)method_getImplementation(mSysVer);
                    method_setImplementation(mSysVer, (IMP)swizzled_systemVersion);
                }

                Method mDevName = class_getInstanceMethod(uiDeviceCls, @selector(name));
                if (mDevName) {
                    orig_deviceName = (void *)method_getImplementation(mDevName);
                    method_setImplementation(mDevName, (IMP)swizzled_deviceName);
                }

                Method mModel = class_getInstanceMethod(uiDeviceCls, @selector(model));
                if (mModel) {
                    method_setImplementation(mModel, (IMP)swizzled_model);
                }

                Method mLocModel = class_getInstanceMethod(uiDeviceCls, @selector(localizedModel));
                if (mLocModel) {
                    method_setImplementation(mLocModel, (IMP)swizzled_model);
                }

                SEL rawNameSel = sel_registerName("_rawDeviceName");
                Method mRawName = class_getInstanceMethod(uiDeviceCls, rawNameSel);
                if (mRawName) {
                    method_setImplementation(mRawName, (IMP)swizzled_deviceName);
                }

                Method mBat = class_getInstanceMethod(uiDeviceCls, @selector(batteryLevel));
                if (mBat) {
                    orig_batteryLevel = (void *)method_getImplementation(mBat);
                    method_setImplementation(mBat, (IMP)swizzled_batteryLevel);
                }

                Method mIdfv = class_getInstanceMethod(uiDeviceCls, @selector(identifierForVendor));
                if (mIdfv) {
                    orig_identifierForVendor = (void *)method_getImplementation(mIdfv);
                    method_setImplementation(mIdfv, (IMP)swizzled_identifierForVendor);
                }

                SEL devInfoSel = sel_registerName("_deviceInfoForKey:");
                Method mDevInfo = class_getInstanceMethod(uiDeviceCls, devInfoSel);
                if (mDevInfo) {
                    gZTechOrigDevInfoSel = sel_registerName("_ztech_orig_deviceInfoForKey:");
                    if (class_addMethod(uiDeviceCls, gZTechOrigDevInfoSel, (IMP)swizzled_deviceInfoForKey, method_getTypeEncoding(mDevInfo))) {
                        Method mSwizDevInfo = class_getInstanceMethod(uiDeviceCls, gZTechOrigDevInfoSel);
                        if (mSwizDevInfo) method_exchangeImplementations(mDevInfo, mSwizDevInfo);
                    }
                }
            }

            // Only swizzle NSURLSessionConfiguration when proxy is enabled, using arm64e PAC-safe method_exchangeImplementations
            if (gProxyEnabled && gCachedProxyDict) {
                Class urlCfgCls = objc_getClass("NSURLSessionConfiguration");
                Class urlCfgMeta = urlCfgCls ? object_getClass(urlCfgCls) : nil;
                if (urlCfgCls && urlCfgMeta) {
                    gZTechOrigDefCfgSel = sel_registerName("_ztech_orig_defaultSessionConfiguration");
                    Method mDefCfg = class_getClassMethod(urlCfgCls, @selector(defaultSessionConfiguration));
                    if (mDefCfg && class_addMethod(urlCfgMeta, gZTechOrigDefCfgSel, (IMP)swizzled_defaultSessionConfig, method_getTypeEncoding(mDefCfg))) {
                        Method mSwizDef = class_getClassMethod(urlCfgCls, gZTechOrigDefCfgSel);
                        if (mSwizDef) method_exchangeImplementations(mDefCfg, mSwizDef);
                    }

                    gZTechOrigEphCfgSel = sel_registerName("_ztech_orig_ephemeralSessionConfiguration");
                    Method mEphCfg = class_getClassMethod(urlCfgCls, @selector(ephemeralSessionConfiguration));
                    if (mEphCfg && class_addMethod(urlCfgMeta, gZTechOrigEphCfgSel, (IMP)swizzled_ephemeralSessionConfig, method_getTypeEncoding(mEphCfg))) {
                        Method mSwizEph = class_getClassMethod(urlCfgCls, gZTechOrigEphCfgSel);
                        if (mSwizEph) method_exchangeImplementations(mEphCfg, mSwizEph);
                    }
                }
            }
            ZTechHookTrace("[3/6] UIDevice & NSUbiquitousKeyValueStore swizzled (arm64e PAC-safe)");
        } @catch (NSException *e) {
            ZTechHookTrace([[NSString stringWithFormat:@"[3/6 ERROR] UIDevice swizzle exception: %@", e] UTF8String]);
        }

        // 2. Safe Objective-C Swizzling for CTCarrier using objc_getClass
        @try {
            Class ctCarrierCls = objc_getClass("CTCarrier");
            if (ctCarrierCls) {
                Method mCarrier = class_getInstanceMethod(ctCarrierCls, @selector(carrierName));
                if (mCarrier) {
                    orig_carrierName = (void *)method_getImplementation(mCarrier);
                    method_setImplementation(mCarrier, (IMP)swizzled_carrierName);
                }
                Method mIso = class_getInstanceMethod(ctCarrierCls, @selector(isoCountryCode));
                if (mIso) {
                    orig_isoCountryCode = (void *)method_getImplementation(mIso);
                    method_setImplementation(mIso, (IMP)swizzled_isoCountryCode);
                }
                Method mMcc = class_getInstanceMethod(ctCarrierCls, @selector(mobileCountryCode));
                if (mMcc) {
                    orig_mobileCountryCode = (void *)method_getImplementation(mMcc);
                    method_setImplementation(mMcc, (IMP)swizzled_mobileCountryCode);
                }
                Method mMnc = class_getInstanceMethod(ctCarrierCls, @selector(mobileNetworkCode));
                if (mMnc) {
                    orig_mobileNetworkCode = (void *)method_getImplementation(mMnc);
                    method_setImplementation(mMnc, (IMP)swizzled_mobileNetworkCode);
                }
                ZTechHookTrace("[4/6] CTCarrier swizzled successfully");
            } else {
                ZTechHookTrace("[4/6] CTCarrier not loaded (skipped)");
            }
        } @catch (NSException *e) {
            ZTechHookTrace([[NSString stringWithFormat:@"[4/6 ERROR] CTCarrier swizzle exception: %@", e] UTF8String]);
        }

        // 3. Hardware Model & MobileGestalt Spoofing (ElleKit MSHookFunction + Mach-O GOT Rebinding)
        _dyld_register_func_for_add_image(&ZTechRebindImageAndRecordRange);

        typedef void (*zt_MSHookFunction_t)(void *symbol, void *replace, void **result);
        zt_MSHookFunction_t pMSHook = (zt_MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
        if (!pMSHook) {
            void *hElle = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_LAZY | RTLD_GLOBAL);
            if (!hElle) hElle = dlopen("/var/jb/usr/lib/libsubstrate.dylib", RTLD_LAZY | RTLD_GLOBAL);
            if (!hElle) hElle = dlopen("/usr/lib/libsubstrate.dylib", RTLD_LAZY | RTLD_GLOBAL);
            if (!hElle) hElle = dlopen("/usr/lib/libellekit.dylib", RTLD_LAZY | RTLD_GLOBAL);
            if (!hElle) hElle = dlopen("/usr/lib/libsubstitute.dylib", RTLD_LAZY | RTLD_GLOBAL);
            if (!hElle) hElle = dlopen("/var/jb/usr/lib/libsubstitute.dylib", RTLD_LAZY | RTLD_GLOBAL);
            if (hElle) {
                pMSHook = (zt_MSHookFunction_t)dlsym(hElle, "MSHookFunction");
            }
        }
        if (pMSHook) {
            void *raw_uname = dlsym(RTLD_DEFAULT, "uname");
            if (raw_uname) pMSHook(raw_uname, (void *)hooked_uname, (void **)&orig_uname);

            void *raw_sysctlbyname = dlsym(RTLD_DEFAULT, "sysctlbyname");
            void *raw_sysctl = dlsym(RTLD_DEFAULT, "sysctl");
            if (raw_sysctlbyname) pMSHook(raw_sysctlbyname, (void *)hooked_sysctlbyname, (void **)&orig_sysctlbyname);
            if (raw_sysctl) pMSHook(raw_sysctl, (void *)hooked_sysctl, (void **)&orig_sysctl);

            void *raw_MGWithError = dlsym(RTLD_DEFAULT, "MGCopyAnswerWithError");
            if (!raw_MGWithError) {
                void *hMG = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_GLOBAL | RTLD_LAZY);
                if (hMG) raw_MGWithError = dlsym(hMG, "MGCopyAnswerWithError");
            }
            if (raw_MGWithError) {
                pMSHook(raw_MGWithError, (void *)hooked_MGCopyAnswerWithError, (void **)&orig_MGCopyAnswerWithError);
            }
        }

        struct utsname verifyUts;
        memset(&verifyUts, 0, sizeof(verifyUts));
        uname(&verifyUts);
        char verifyMach[64] = {0};
        size_t verifyLen = sizeof(verifyMach);
        sysctlbyname("hw.machine", verifyMach, &verifyLen, NULL, 0);
        ZTechHookTrace([[NSString stringWithFormat:@"[4.5/6] Universal hardware spoofing active: uname.machine=%s, sysctl(hw.machine)=%s, board=%s",
                         verifyUts.machine, verifyMach, gBoardIdCStr] UTF8String]);

        // 4. OS Version & Diagnostic Spoofing (NSProcessInfo for all apps, Metal GPU for AIDA)
        @try {
            Class procCls = objc_getClass("NSProcessInfo");
            if (procCls) {
                Method mOsVer = class_getInstanceMethod(procCls, @selector(operatingSystemVersion));
                if (mOsVer) {
                    orig_osVersion = (void *)method_getImplementation(mOsVer);
                    method_setImplementation(mOsVer, (IMP)swizzled_osVersion);
                }

                Method mOsVerStr = class_getInstanceMethod(procCls, @selector(operatingSystemVersionString));
                if (mOsVerStr) {
                    orig_osVersionString = (void *)method_getImplementation(mOsVerStr);
                    method_setImplementation(mOsVerStr, (IMP)swizzled_osVersionString);
                }

                if (isAida) {
                    Method mPhysMem = class_getInstanceMethod(procCls, @selector(physicalMemory));
                    if (mPhysMem) {
                        orig_physicalMemory = (void *)method_getImplementation(mPhysMem);
                        method_setImplementation(mPhysMem, (IMP)swizzled_physicalMemory);
                    }
                }
            }

            if (isAida) {
                Class mtlDevCls = objc_getClass("_MTLDevice");
                if (!mtlDevCls) mtlDevCls = objc_getClass("MTLDevice");
                if (mtlDevCls) {
                    Method mGpu = class_getInstanceMethod(mtlDevCls, @selector(name));
                    if (mGpu) {
                        orig_MTLDevice_name = (void *)method_getImplementation(mGpu);
                        method_setImplementation(mGpu, (IMP)swizzled_MTLDevice_name);
                    }
                }
            }
        } @catch (NSException *e) {}

        // Observe UIApplicationDidFinishLaunchingNotification to confirm app reached UI loop & re-assert signal handlers
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            ZTechInstallSignalHandlers();
            ZTechHookTrace("[6/6] UIApplicationDidFinishLaunchingNotification reached OK!");
        }];

        ZTechHookTrace("[5/6] ZTechHookInit completed 100% OK");
    }
}

