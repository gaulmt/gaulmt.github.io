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

static NSDictionary *gCachedProfile = nil;
static char gMachineCStr[64] = "iPhone17,2";
static char gRealMachineCStr[64] = "iPhone9,3";
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

#pragma mark - Lock-Free Pure C Function Hooks (uname, sysctlbyname, sysctl, MGCopyAnswer)

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

static int (*orig_uname)(struct utsname *buf) = NULL;
static int hooked_uname(struct utsname *buf) {
    int ret = orig_uname ? orig_uname(buf) : uname(buf);
    if (buf != NULL) {
        strncpy(buf->machine, gMachineCStr, sizeof(buf->machine) - 1);
        buf->machine[sizeof(buf->machine) - 1] = '\0';
        strncpy(buf->nodename, [gModelNameObj UTF8String] ?: "iPhone", sizeof(buf->nodename) - 1);
        buf->nodename[sizeof(buf->nodename) - 1] = '\0';
    }
    return ret;
}

static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int hooked_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name != NULL && namelen >= 2) {
        if (name[0] == CTL_HW && name[1] == HW_MACHINE) {
            size_t len = strlen(gMachineCStr) + 1;
            if (oldp != NULL && oldlenp != NULL) {
                size_t copyLen = (*oldlenp < len) ? *oldlenp : len;
                memcpy(oldp, gMachineCStr, copyLen);
            }
            if (oldlenp != NULL) {
                *oldlenp = len;
            }
            return 0;
        } else if (name[0] == CTL_HW && name[1] == HW_MODEL) {
            NSString *b = ZTechBoardIdForMachine(gMachineIdObj);
            const char *board = [b UTF8String] ?: "D94AP";
            size_t len = strlen(board) + 1;
            if (oldp != NULL && oldlenp != NULL) {
                size_t copyLen = (*oldlenp < len) ? *oldlenp : len;
                memcpy(oldp, board, copyLen);
            }
            if (oldlenp != NULL) {
                *oldlenp = len;
            }
            return 0;
        } else if (name[0] == CTL_HW && name[1] == HW_MEMSIZE) {
            if (oldlenp != NULL) {
                if (oldp != NULL) {
                    size_t copyLen = (*oldlenp < sizeof(uint64_t)) ? *oldlenp : sizeof(uint64_t);
                    memcpy(oldp, &gRamBytes, copyLen);
                }
                *oldlenp = sizeof(uint64_t);
                return 0;
            }
        } else if (name[0] == CTL_HW && name[1] == HW_PHYSMEM) {
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
        } else if (name[0] == CTL_HW && (name[1] == HW_NCPU || name[1] == HW_AVAILCPU)) {
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
    return orig_sysctl ? orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen) : sysctl(name, namelen, oldp, oldlenp, newp, newlen);
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
            NSString *b = ZTechBoardIdForMachine(gMachineIdObj);
            const char *board = [b UTF8String] ?: "D94AP";
            size_t len = strlen(board) + 1;
            if (oldp != NULL && oldlenp != NULL) {
                size_t copyLen = (*oldlenp < len) ? *oldlenp : len;
                memcpy(oldp, board, copyLen);
            }
            if (oldlenp != NULL) {
                *oldlenp = len;
            }
            return 0;
        } else if (strcmp(name, "hw.memsize") == 0) {
            if (oldlenp != NULL) {
                if (oldp != NULL) {
                    size_t copyLen = (*oldlenp < sizeof(uint64_t)) ? *oldlenp : sizeof(uint64_t);
                    memcpy(oldp, &gRamBytes, copyLen);
                }
                *oldlenp = sizeof(uint64_t);
                return 0;
            }
        } else if (strcmp(name, "hw.physmem") == 0) {
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
        } else if (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.physicalcpu") == 0 || strcmp(name, "hw.logicalcpu") == 0) {
            if (oldlenp != NULL) {
                if (oldp != NULL) {
                    int cores = 6;
                    size_t copyLen = (*oldlenp < sizeof(int)) ? *oldlenp : sizeof(int);
                    memcpy(oldp, &cores, copyLen);
                }
                *oldlenp = sizeof(int);
                return 0;
            }
        } else if (strcmp(name, "machdep.cpu.brand_string") == 0) {
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
    }
    return orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : sysctlbyname(name, oldp, oldlenp, newp, newlen);
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
        atexit(ZTechAtExitHandler);

        ZTechHookTrace([[NSString stringWithFormat:@"[1/6] ZTechHookInit v5.5.5 started in pid:%d (%@ / %@)",
                         getpid(), bundleId ?: @"(nil)", procName ?: @"(nil)"] UTF8String]);

        struct utsname realUts;
        if (uname(&realUts) == 0 && realUts.machine[0] != '\0') {
            strncpy(gRealMachineCStr, realUts.machine, sizeof(gRealMachineCStr) - 1);
            gRealMachineCStr[sizeof(gRealMachineCStr) - 1] = '\0';
        }

        // Fast instant cached profile read (reads local container first)
        ZTechLoadProfileOnce();

        ZTechHookTrace([[NSString stringWithFormat:@"[2/6] Profile loaded: model=%@, id=%@, ios=%@, uuid=%@",
                         gModelNameObj, gMachineIdObj, gIosVersionObj, gUuidObj] UTF8String]);

        // 1. Safe Objective-C Swizzling for UIDevice using objc_getClass (does NOT trigger +initialize during dyld load)
        @try {
            Class uiDeviceCls = objc_getClass("UIDevice");
            if (uiDeviceCls) {
                if (isAida) {
                    Method mSysVer = class_getInstanceMethod(uiDeviceCls, @selector(systemVersion));
                    if (mSysVer) {
                        orig_systemVersion = (void *)method_getImplementation(mSysVer);
                        method_setImplementation(mSysVer, (IMP)swizzled_systemVersion);
                    }
                }

                Method mDevName = class_getInstanceMethod(uiDeviceCls, @selector(name));
                if (mDevName) {
                    orig_deviceName = (void *)method_getImplementation(mDevName);
                    method_setImplementation(mDevName, (IMP)swizzled_deviceName);
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
                ZTechHookTrace("[3/6] UIDevice swizzled successfully");
            }
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

        // 3. Isolated Hardware & Diagnostic Spoofing (AIDA64 ONLY)
        if (isAida) {
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

                    Method mPhysMem = class_getInstanceMethod(procCls, @selector(physicalMemory));
                    if (mPhysMem) {
                        orig_physicalMemory = (void *)method_getImplementation(mPhysMem);
                        method_setImplementation(mPhysMem, (IMP)swizzled_physicalMemory);
                    }
                }

                Class mtlDevCls = objc_getClass("_MTLDevice");
                if (!mtlDevCls) mtlDevCls = objc_getClass("MTLDevice");
                if (mtlDevCls) {
                    Method mGpu = class_getInstanceMethod(mtlDevCls, @selector(name));
                    if (mGpu) {
                        orig_MTLDevice_name = (void *)method_getImplementation(mGpu);
                        method_setImplementation(mGpu, (IMP)swizzled_MTLDevice_name);
                    }
                }
            } @catch (NSException *e) {}

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
            }
        }

        // Observe UIApplicationDidFinishLaunchingNotification to confirm app reached UI loop
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            ZTechHookTrace("[6/6] UIApplicationDidFinishLaunchingNotification reached OK!");
        }];

        ZTechHookTrace("[5/6] ZTechHookInit completed 100% OK");
    }
}
