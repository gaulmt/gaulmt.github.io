#import "ZTechVaultManager.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <unistd.h>
#import <spawn.h>
#import <dlfcn.h>
#import <notify.h>
#import <dirent.h>

extern char **environ;

@implementation ZTechVaultAccount

- (NSDictionary *)toDictionary {
    return @{
        @"accountId": self.accountId ?: @"",
        @"title": self.title ?: @"Acc Zalo",
        @"proxyString": self.proxyString ?: @"",
        @"createdAt": self.createdAt ?: @"",
        @"deviceProfileDict": self.deviceProfileDict ?: @{}
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return nil;
    ZTechVaultAccount *acc = [[ZTechVaultAccount alloc] init];
    acc.accountId = dict[@"accountId"] ?: @"";
    if (acc.accountId.length == 0) return nil;
    acc.title = dict[@"title"] ?: @"Acc Zalo";
    acc.proxyString = dict[@"proxyString"] ?: @"";
    acc.createdAt = dict[@"createdAt"] ?: @"";
    acc.deviceProfileDict = [dict[@"deviceProfileDict"] isKindOfClass:[NSDictionary class]] ? dict[@"deviceProfileDict"] : @{};
    return acc;
}

- (NSString *)shortDeviceSummary {
    NSString *model = self.deviceProfileDict[@"modelName"] ?: @"iPhone 16 Pro Max";
    NSString *ios = self.deviceProfileDict[@"iosVersion"] ?: @"18.2";
    NSString *uuid = self.deviceProfileDict[@"identifier"] ?: @"";
    NSString *shortUuid = (uuid.length >= 8) ? [uuid substringToIndex:8] : uuid;
    return [NSString stringWithFormat:@"%@ · iOS %@ · ID:%@", model, ios, shortUuid];
}

- (NSString *)proxyDisplayText {
    if (!self.proxyString || self.proxyString.length == 0) {
        return @"🌐 Mạng trực tiếp (Không Proxy / 4G)";
    }
    return [NSString stringWithFormat:@"🛡 Proxy: %@", self.proxyString];
}

@end

@implementation ZTechVaultManager

+ (NSString *)vaultRootDirectory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *candidates = @[
        @"/var/jb/var/mobile/Library/Preferences/ZTechVault",
        @"/var/mobile/Library/Preferences/ZTechVault"
    ];
    for (NSString *path in candidates) {
        NSString *parent = [path stringByDeletingLastPathComponent];
        if ([fm fileExistsAtPath:parent] && [fm isWritableFileAtPath:parent]) {
            if (![fm fileExistsAtPath:path]) {
                [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
                chmod([path UTF8String], 0777);
            }
            return path;
        }
    }
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *fallback = [docs.firstObject stringByAppendingPathComponent:@"ZTechVault"];
    if (![fm fileExistsAtPath:fallback]) {
        [fm createDirectoryAtPath:fallback withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return fallback;
}

+ (NSString *)indexFilePath {
    return [[self vaultRootDirectory] stringByAppendingPathComponent:@"vault_index.plist"];
}

+ (NSString *)activeAccountId {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"ZTechActiveVaultAccountId"];
}

+ (NSArray<ZTechVaultAccount *> *)listSavedAccounts {
    NSArray *rawList = [NSArray arrayWithContentsOfFile:[self indexFilePath]];
    if (!rawList || ![rawList isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray<ZTechVaultAccount *> *result = [NSMutableArray array];
    for (NSDictionary *item in rawList) {
        ZTechVaultAccount *acc = [ZTechVaultAccount fromDictionary:item];
        if (acc) {
            [result addObject:acc];
        }
    }
    return result;
}

+ (void)saveAccountsList:(NSArray<ZTechVaultAccount *> *)accounts {
    NSMutableArray *raw = [NSMutableArray arrayWithCapacity:accounts.count];
    for (ZTechVaultAccount *acc in accounts) {
        [raw addObject:[acc toDictionary]];
    }
    NSString *indexPath = [self indexFilePath];
    [raw writeToFile:indexPath atomically:YES];
    chmod([indexPath UTF8String], 0666);
}

+ (void)killZaloProcess {
    NSMutableArray<NSNumber *> *killedPids = [NSMutableArray array];

    // 1. Direct Darwin kernel sysctl process scan (guaranteed on all jailbreaks & TrollStore)
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) == 0 && size > 0) {
        struct kinfo_proc *procs = malloc(size);
        if (procs && sysctl(mib, 4, procs, &size, NULL, 0) == 0) {
            int count = (int)(size / sizeof(struct kinfo_proc));
            for (int i = 0; i < count; i++) {
                const char *name = procs[i].kp_proc.p_comm;
                if (name && strcasecmp(name, "ZTech") != 0 &&
                    (strcasecmp(name, "Zalo") == 0 ||
                     strcasestr(name, "zalo") != NULL ||
                     strcasestr(name, "zingalo") != NULL ||
                     strcasestr(name, "aida64") != NULL ||
                     strcasestr(name, "NotificationService") != NULL ||
                     strcasestr(name, "NotificationContent") != NULL)) {
                    pid_t p = procs[i].kp_proc.p_pid;
                    kill(p, SIGKILL);
                    [killedPids addObject:@(p)];
                }
            }
        }
        if (procs) free(procs);
    }

    // 2. Fallback via posix_spawn killall
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *killBins = @[@"/var/jb/usr/bin/killall", @"/usr/bin/killall"];
    for (NSString *bin in killBins) {
        if ([fm isExecutableFileAtPath:bin]) {
            pid_t pid1, pid2, pid3, pid4;
            const char *args1[] = { [bin UTF8String], "-9", "Zalo", NULL };
            posix_spawn(&pid1, [bin UTF8String], NULL, NULL, (char *const *)args1, environ);
            const char *args2[] = { [bin UTF8String], "-9", "vn.com.vng.zalo", NULL };
            posix_spawn(&pid2, [bin UTF8String], NULL, NULL, (char *const *)args2, environ);
            const char *args3[] = { [bin UTF8String], "-9", "AIDA64", NULL };
            posix_spawn(&pid3, [bin UTF8String], NULL, NULL, (char *const *)args3, environ);
            const char *args4[] = { [bin UTF8String], "-9", "aida64", NULL };
            posix_spawn(&pid4, [bin UTF8String], NULL, NULL, (char *const *)args4, environ);
            break;
        }
    }

    // 3. Confirm target processes have fully exited from kernel tables so SQLite / MMKV locks are released
    for (NSNumber *pidNum in killedPids) {
        pid_t p = (pid_t)[pidNum intValue];
        for (int retries = 0; retries < 15; retries++) {
            if (kill(p, 0) == -1) break;
            usleep(10000); // 10ms
        }
    }
}

+ (void)cleanSafariCookiesAndWebsiteData {
    // 1. Terminate MobileSafari & SafariViewService processes via direct kernel kill
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) == 0 && size > 0) {
        struct kinfo_proc *procs = malloc(size);
        if (procs && sysctl(mib, 4, procs, &size, NULL, 0) == 0) {
            int count = (int)(size / sizeof(struct kinfo_proc));
            for (int i = 0; i < count; i++) {
                const char *name = procs[i].kp_proc.p_comm;
                if (name && (strcasecmp(name, "MobileSafari") == 0 ||
                             strcasecmp(name, "SafariViewService") == 0 ||
                             strcasecmp(name, "com.apple.WebKit.WebContent") == 0 ||
                             strcasecmp(name, "com.apple.WebKit.Networking") == 0)) {
                    kill(procs[i].kp_proc.p_pid, SIGKILL);
                }
            }
        }
        if (procs) free(procs);
    }

    // Fallback killall MobileSafari
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *killBins = @[@"/var/jb/usr/bin/killall", @"/usr/bin/killall"];
    for (NSString *bin in killBins) {
        if ([fm isExecutableFileAtPath:bin]) {
            pid_t pid;
            const char *args[] = { [bin UTF8String], "-9", "MobileSafari", NULL };
            posix_spawn(&pid, [bin UTF8String], NULL, NULL, (char *const *)args, environ);
            break;
        }
    }

    // 2. Clear in-memory HTTP Cookie storage
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage.cookies copy]) {
        [storage deleteCookie:cookie];
    }

    // 3. Delete Safari Cookies & Web caches from shared system paths
    NSArray<NSString *> *safariPaths = @[
        @"/var/mobile/Library/Cookies",
        @"/var/jb/var/mobile/Library/Cookies",
        @"/var/mobile/Library/Safari",
        @"/var/jb/var/mobile/Library/Safari",
        @"/var/mobile/Library/Caches/com.apple.mobilesafari",
        @"/var/jb/var/mobile/Library/Caches/com.apple.mobilesafari",
        @"/var/mobile/Library/WebKit/com.apple.mobilesafari",
        @"/var/jb/var/mobile/Library/WebKit/com.apple.mobilesafari",
        @"/var/mobile/Library/WebKit/WebsiteData",
        @"/var/jb/var/mobile/Library/WebKit/WebsiteData"
    ];

    for (NSString *sp in safariPaths) {
        if ([fm fileExistsAtPath:sp]) {
            NSArray *items = [fm contentsOfDirectoryAtPath:sp error:nil];
            for (NSString *sub in items) {
                if ([sub containsString:@"Cookies"] ||
                    [sub containsString:@"History"] ||
                    [sub containsString:@"Favicons"] ||
                    [sub containsString:@"TouchIcons"] ||
                    [sub containsString:@"Cache"] ||
                    [sub containsString:@"WebpageIcons"] ||
                    [sub containsString:@"LocalData"] ||
                    [sub containsString:@"IndexedDB"] ||
                    [sub containsString:@"LocalStorage"] ||
                    [sub hasSuffix:@".db"] ||
                    [sub hasSuffix:@".db-wal"] ||
                    [sub hasSuffix:@".db-shm"] ||
                    [sub hasSuffix:@".binarycookies"]) {
                    [fm removeItemAtPath:[sp stringByAppendingPathComponent:sub] error:nil];
                }
            }
        }
    }

    // 4. Scan MobileSafari Data Container under /var/mobile/Containers/Data/Application
    static NSString *sCachedSafariContainer = nil;
    if (sCachedSafariContainer && [fm fileExistsAtPath:sCachedSafariContainer]) {
        NSArray *targets = @[@"Library/Cookies", @"Library/Caches", @"Library/WebKit", @"tmp"];
        for (NSString *t in targets) {
            NSString *targetPath = [sCachedSafariContainer stringByAppendingPathComponent:t];
            NSArray *subs = [fm contentsOfDirectoryAtPath:targetPath error:nil];
            for (NSString *s in subs) {
                [fm removeItemAtPath:[targetPath stringByAppendingPathComponent:s] error:nil];
            }
        }
    } else {
        NSString *appDataRoot = @"/var/mobile/Containers/Data/Application";
        NSArray *guids = [fm contentsOfDirectoryAtPath:appDataRoot error:nil];
        for (NSString *guid in guids) {
            NSString *guidPath = [appDataRoot stringByAppendingPathComponent:guid];
            NSString *metaPath = [guidPath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
            if (meta && [[meta[@"MCMMetadataIdentifier"] lowercaseString] isEqualToString:@"com.apple.mobilesafari"]) {
                sCachedSafariContainer = guidPath;
                NSArray *targets = @[@"Library/Cookies", @"Library/Caches", @"Library/WebKit", @"tmp"];
                for (NSString *t in targets) {
                    NSString *targetPath = [guidPath stringByAppendingPathComponent:t];
                    NSArray *subs = [fm contentsOfDirectoryAtPath:targetPath error:nil];
                    for (NSString *s in subs) {
                        [fm removeItemAtPath:[targetPath stringByAppendingPathComponent:s] error:nil];
                    }
                }
                break;
            }
        }
    }
}

+ (BOOL)isContainerDirectoryForZalo:(NSString *)containerPath fileManager:(NSFileManager *)fm {
    if (!containerPath || containerPath.length == 0) return NO;

    // 1. Check ZTechHook marker file inside Documents
    NSString *markerPath = [containerPath stringByAppendingPathComponent:@"Documents/_zt_zalo_marker.txt"];
    if ([fm fileExistsAtPath:markerPath]) {
        return YES;
    }

    // 2. Check metadata plist if readable
    NSString *metaPath = [containerPath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
    if (meta) {
        NSString *bundleId = [meta[@"MCMMetadataIdentifier"] lowercaseString];
        if ([bundleId containsString:@"zalo"] || [bundleId containsString:@"vng"]) {
            return YES;
        }
    }

    // 3. Scan mobile-owned subdirectories (Preferences, Caches, Application Support, Documents)
    NSArray<NSString *> *subDirsToCheck = @[
        @"Library/Preferences",
        @"Library/Caches",
        @"Library/Application Support",
        @"Documents"
    ];
    for (NSString *sub in subDirsToCheck) {
        NSString *dir = [containerPath stringByAppendingPathComponent:sub];
        NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *item in items) {
            NSString *lower = [item lowercaseString];
            if ([lower containsString:@"vn.com.vng.zalo"] ||
                [lower containsString:@"com.vng.zalo"] ||
                [lower hasPrefix:@"zalo"] ||
                [lower containsString:@".zalo"] ||
                [lower containsString:@"zalo."]) {
                return YES;
            }
        }
    }
    return NO;
}

+ (nullable NSString *)findZaloDataContainerPath {
    static NSString *sCachedContainer = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (sCachedContainer && [fm fileExistsAtPath:sCachedContainer]) {
        return sCachedContainer;
    }

    // Layer 1: Direct LSApplicationProxy lookup by bundle ID (fast)
    @try {
        Class proxyCls = NSClassFromString(@"LSApplicationProxy");
        if (proxyCls) {
            SEL selProxy = sel_registerName("applicationProxyForIdentifier:");
            NSArray<NSString *> *candidateIds = @[@"vn.com.vng.zalo", @"com.vng.zalo", @"com.zing.zalo", @"com.vng.zingalo", @"vn.com.vng.zingalo", @"com.zing.zingalo"];
            for (NSString *bid in candidateIds) {
                if ([proxyCls respondsToSelector:selProxy]) {
                    id proxy = ((id (*)(id, SEL, NSString *))objc_msgSend)(proxyCls, selProxy, bid);
                    if (proxy && [proxy respondsToSelector:sel_registerName("dataContainerURL")]) {
                        NSURL *url = ((NSURL *(*)(id, SEL))objc_msgSend)(proxy, sel_registerName("dataContainerURL"));
                        if ([url isKindOfClass:[NSURL class]] && url.path.length > 0 && [fm fileExistsAtPath:url.path]) {
                            sCachedContainer = url.path;
                            return sCachedContainer;
                        }
                    }
                }
            }
        }
    } @catch (NSException *e) {}

    // Layer 2: Fast scan of Data/Application containers via marker, metadata.plist, and mobile-owned subdirectories
    NSArray<NSString *> *roots = @[
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application"
    ];
    for (NSString *root in roots) {
        NSArray<NSString *> *uuids = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *uuid in uuids) {
            NSString *container = [root stringByAppendingPathComponent:uuid];
            if ([self isContainerDirectoryForZalo:container fileManager:fm]) {
                sCachedContainer = container;
                return sCachedContainer;
            }
        }
    }

    // Layer 3: Fallback to LSApplicationWorkspace allInstalledApplications
    @try {
        Class wsCls = NSClassFromString(@"LSApplicationWorkspace");
        if (wsCls) {
            id ws = ((id (*)(id, SEL))objc_msgSend)(wsCls, sel_registerName("defaultWorkspace"));
            if (ws && [ws respondsToSelector:sel_registerName("allInstalledApplications")]) {
                NSArray *apps = ((NSArray *(*)(id, SEL))objc_msgSend)(ws, sel_registerName("allInstalledApplications"));
                for (id proxy in apps) {
                    NSString *appId = nil;
                    if ([proxy respondsToSelector:sel_registerName("applicationIdentifier")]) {
                        appId = [((NSString *(*)(id, SEL))objc_msgSend)(proxy, sel_registerName("applicationIdentifier")) lowercaseString];
                    }
                    if ([appId containsString:@"zalo"] || [appId containsString:@"vng"]) {
                        if ([proxy respondsToSelector:sel_registerName("dataContainerURL")]) {
                            NSURL *url = ((NSURL *(*)(id, SEL))objc_msgSend)(proxy, sel_registerName("dataContainerURL"));
                            if ([url isKindOfClass:[NSURL class]] && url.path.length > 0 && [fm fileExistsAtPath:url.path]) {
                                sCachedContainer = url.path;
                                return sCachedContainer;
                            }
                        }
                    }
                }
            }
        }
    } @catch (NSException *e) {}

    return nil;
}

+ (nullable NSString *)findAIDA64DataContainerPath {
    static NSString *sCachedAIDA64 = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (sCachedAIDA64 && [fm fileExistsAtPath:sCachedAIDA64]) {
        return sCachedAIDA64;
    }

    @try {
        Class proxyCls = NSClassFromString(@"LSApplicationProxy");
        if (proxyCls && [proxyCls respondsToSelector:sel_registerName("applicationProxyForIdentifier:")]) {
            SEL selProxy = sel_registerName("applicationProxyForIdentifier:");
            SEL selData = sel_registerName("dataContainerURL");
            NSArray<NSString *> *candidates = @[@"com.finalwire.aida64", @"com.finalwire.AIDA64", @"hu.finalwire.aida64"];
            for (NSString *cand in candidates) {
                id proxy = ((id (*)(id, SEL, NSString *))objc_msgSend)(proxyCls, selProxy, cand);
                if (proxy && [proxy respondsToSelector:selData]) {
                    NSURL *url = ((NSURL *(*)(id, SEL))objc_msgSend)(proxy, selData);
                    if ([url isKindOfClass:[NSURL class]] && url.path.length > 0 && [fm fileExistsAtPath:url.path]) {
                        sCachedAIDA64 = url.path;
                        return sCachedAIDA64;
                    }
                }
            }
        }
    } @catch (NSException *e) {}

    NSArray<NSString *> *roots = @[
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application"
    ];
    for (NSString *root in roots) {
        NSArray<NSString *> *uuids = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *uuid in uuids) {
            NSString *container = [root stringByAppendingPathComponent:uuid];
            NSString *metaPath = [container stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
            if (meta && [[meta[@"MCMMetadataIdentifier"] lowercaseString] containsString:@"aida64"]) {
                sCachedAIDA64 = container;
                return sCachedAIDA64;
            }
            NSArray<NSString *> *subDirsToCheck = @[@"Library/Preferences", @"Library/Caches", @"Documents"];
            for (NSString *sub in subDirsToCheck) {
                NSString *dir = [container stringByAppendingPathComponent:sub];
                NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:dir error:nil];
                for (NSString *item in items) {
                    if ([[item lowercaseString] containsString:@"aida64"] || [[item lowercaseString] containsString:@"finalwire"]) {
                        sCachedAIDA64 = container;
                        return sCachedAIDA64;
                    }
                }
            }
        }
    }

    return nil;
}

+ (NSDictionary<NSString *, NSString *> *)findZaloAppGroupContainers {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableDictionary<NSString *, NSString *> *groups = [NSMutableDictionary dictionary];

    // Layer 1: Query LaunchServices groupContainerURLs
    @try {
        Class proxyCls = NSClassFromString(@"LSApplicationProxy");
        if (proxyCls && [proxyCls respondsToSelector:sel_registerName("applicationProxyForIdentifier:")]) {
            NSArray<NSString *> *candBids = @[@"vn.com.vng.zalo", @"com.vng.zalo", @"com.zing.zalo", @"com.vng.zingalo", @"vn.com.vng.zingalo", @"com.zing.zingalo"];
            for (NSString *bid in candBids) {
                id proxy = ((id (*)(id, SEL, NSString *))objc_msgSend)(proxyCls, sel_registerName("applicationProxyForIdentifier:"), bid);
                if (proxy && [proxy respondsToSelector:sel_registerName("groupContainerURLs")]) {
                    NSDictionary *gUrls = ((NSDictionary *(*)(id, SEL))objc_msgSend)(proxy, sel_registerName("groupContainerURLs"));
                    if ([gUrls isKindOfClass:[NSDictionary class]] && gUrls.count > 0) {
                        for (NSString *gid in gUrls) {
                            NSURL *u = gUrls[gid];
                            if ([u isKindOfClass:[NSURL class]] && u.path.length > 0 && [fm fileExistsAtPath:u.path]) {
                                groups[[gid lowercaseString]] = u.path;
                            }
                        }
                        break;
                    }
                }
            }
        }
    } @catch (NSException *e) {}

    // Layer 2: Scan Shared/AppGroup directories
    NSArray<NSString *> *roots = @[
        @"/var/mobile/Containers/Shared/AppGroup",
        @"/private/var/mobile/Containers/Shared/AppGroup"
    ];
    for (NSString *root in roots) {
        NSArray<NSString *> *uuids = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *uuid in uuids) {
            NSString *container = [root stringByAppendingPathComponent:uuid];
            NSString *metaPath = [container stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
            NSString *groupId = [meta[@"MCMMetadataIdentifier"] lowercaseString];
            if ([groupId containsString:@"zalo"] || [groupId containsString:@"vng"]) {
                groups[groupId] = container;
            } else if ([self isContainerDirectoryForZalo:container fileManager:fm]) {
                NSString *fallbackKey = [NSString stringWithFormat:@"group.vn.com.vng.zalo.%@", uuid];
                groups[fallbackKey] = container;
            }
        }
    }
    return groups;
}

static void ZTechNativeRecursiveChownAndChmod(const char *cpath, uid_t uid, gid_t gid, mode_t dirMode, mode_t fileMode) {
    if (!cpath || cpath[0] == '\0') return;
    DIR *dir = opendir(cpath);
    if (!dir) return;

    struct dirent *entry;
    char subBuf[1024];
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        if (strcmp(entry->d_name, ".com.apple.mobile_container_manager.metadata.plist") == 0 ||
            strcmp(entry->d_name, "SystemData") == 0) {
            continue;
        }

        snprintf(subBuf, sizeof(subBuf), "%s/%s", cpath, entry->d_name);
        struct stat st;
        if (lstat(subBuf, &st) == 0) {
            if (S_ISLNK(st.st_mode)) {
                if (strstr(entry->d_name, ".GlobalPreferences") != NULL) {
                    unlink(subBuf);
                }
                continue;
            }
            chflags(subBuf, 0);
            if (S_ISDIR(st.st_mode)) {
                chown(subBuf, uid, gid);
                chmod(subBuf, dirMode);
                ZTechNativeRecursiveChownAndChmod(subBuf, uid, gid, dirMode, fileMode);
            } else {
                chown(subBuf, uid, gid);
                chmod(subBuf, fileMode);
            }
        }
    }
    closedir(dir);
}

+ (void)runFastChownAndChmod:(NSString *)path {
    if (!path || path.length == 0) return;
    const char *cpath = [path UTF8String];
    if (!cpath) return;

    NSFileManager *fm = [NSFileManager defaultManager];

    // Remove any illegal .GlobalPreferences.plist symlink inside the container's Library/Preferences
    NSString *gpLink = [path stringByAppendingPathComponent:@"Library/Preferences/.GlobalPreferences.plist"];
    struct stat gpSt;
    if (lstat([gpLink UTF8String], &gpSt) == 0) {
        unlink([gpLink UTF8String]);
    }
    NSString *gpLinkM = [path stringByAppendingPathComponent:@"Library/Preferences/.GlobalPreferences_m.plist"];
    if (lstat([gpLinkM UTF8String], &gpSt) == 0) {
        unlink([gpLinkM UTF8String]);
    }

    // Fast in-process native syscalls (0.001s instead of multi-second posix_spawn forks)
    ZTechNativeRecursiveChownAndChmod(cpath, 501, 501, 0755, 0666);

    // Ensure container root is 0755 and metadata.plist is 0644 (never 0777!)
    chown(cpath, 501, 501);
    chmod(cpath, 0755);
    NSString *metaPath = [path stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
    if ([fm fileExistsAtPath:metaPath]) {
        chmod([metaPath UTF8String], 0644);
    }
}


+ (void)removeStaleSqliteShmFilesAtPath:(NSString *)rootPath fileManager:(NSFileManager *)fm {
    if (!rootPath || ![fm fileExistsAtPath:rootPath]) return;
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:rootPath];
    NSString *sub = nil;
    while ((sub = [enumerator nextObject])) {
        NSString *last = [sub lastPathComponent];
        if ([last hasSuffix:@"-shm"] || [last hasSuffix:@".sqlite-shm"] || [last hasSuffix:@".db-shm"] ||
            [last hasPrefix:@"bak_sm_"] || [last hasSuffix:@".lock"] || [last isEqualToString:@"zalo.lock"] ||
            [last isEqualToString:@".lock"]) {
            NSString *full = [rootPath stringByAppendingPathComponent:sub];
            [fm removeItemAtPath:full error:nil];
        }
    }
}

+ (void)copyDirectoryContentsFrom:(NSString *)srcDir to:(NSString *)dstDir fileManager:(NSFileManager *)fm fixMobileOwner:(BOOL)fixOwner {
    if (![fm fileExistsAtPath:srcDir]) return;
    if (![fm fileExistsAtPath:dstDir]) {
        [fm createDirectoryAtPath:dstDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:srcDir error:nil];
    for (NSString *item in items) {
        if ([item isEqualToString:@".com.apple.mobile_container_manager.metadata.plist"] ||
            [item hasPrefix:@".GlobalPreferences"] ||
            [item isEqualToString:@"SystemData"] ||
            [item isEqualToString:@"SplashBoard"] ||
            [item isEqualToString:@"Caches"]) {
            continue;
        }
        NSString *srcPath = [srcDir stringByAppendingPathComponent:item];
        NSString *dstPath = [dstDir stringByAppendingPathComponent:item];

        NSDictionary *attrs = [fm attributesOfItemAtPath:srcPath error:nil];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
            continue;
        }

        [fm removeItemAtPath:dstPath error:nil];
        [fm copyItemAtPath:srcPath toPath:dstPath error:nil];
    }
    if (fixOwner) {
        [self runFastChownAndChmod:dstDir];
    }
}

+ (void)recursivelyFixMobileOwnershipAtPath:(NSString *)path fileManager:(NSFileManager *)fm {
    [self runFastChownAndChmod:path];
}

+ (nullable ZTechVaultAccount *)saveCurrentZaloSessionWithTitle:(nullable NSString *)title
                                                          proxy:(nullable NSString *)proxyString
                                                        profile:(ZTechDeviceProfile *)profile
                                                          error:(NSError **)error {
    // 1. Terminate Zalo cleanly and flush filesystem buffers to disk so SQLite databases are consistent and unlocked
    [self killZaloProcess];
    usleep(150000); // 150ms
    sync();

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *zaloContainer = [self findZaloDataContainerPath];
    if (!zaloContainer) {
        if (error) {
            *error = [NSError errorWithDomain:@"ZTechVault"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Không tìm thấy thư mục dữ liệu Zalo trên máy. Hãy cài đặt và mở Zalo ít nhất 1 lần."}];
        }
        return nil;
    }

    NSMutableArray<ZTechVaultAccount *> *accounts = [[self listSavedAccounts] mutableCopy];
    NSInteger nextIndex = accounts.count + 1;
    NSString *accId = [NSString stringWithFormat:@"ACC-%03ld-%04u", (long)nextIndex, arc4random_uniform(9000) + 1000];

    NSString *cleanTitle = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!cleanTitle || cleanTitle.length == 0) {
        cleanTitle = [NSString stringWithFormat:@"Acc Zalo #%ld (%@)", (long)nextIndex, profile.modelName ?: @"iPhone"];
    }

    NSString *cleanProxy = [proxyString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"dd/MM HH:mm";
    NSString *nowStr = [df stringFromDate:[NSDate date]];

    // Update profile proxy before saving
    profile.activeProxy = cleanProxy;
    [ZTechDeviceDatabase writeProfileFiles:profile error:nil];

    NSString *slotDir = [[self vaultRootDirectory] stringByAppendingPathComponent:accId];
    NSString *dataBackupDir = [slotDir stringByAppendingPathComponent:@"DataContainer"];
    NSString *groupBackupDir = [slotDir stringByAppendingPathComponent:@"AppGroups"];
    [fm createDirectoryAtPath:dataBackupDir withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:groupBackupDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Copy DataContainer (Documents + all Library subdirectories except Caches/SplashBoard/.GlobalPreferences)
    [self copyDirectoryContentsFrom:zaloContainer to:dataBackupDir fileManager:fm fixMobileOwner:NO];

    // Remove any cached/temporary subdirs inside backed-up Library
    NSArray<NSString *> *skipLibDirs = @[@"Library/Caches", @"Library/SplashBoard", @"Library/Saved Application State", @"Library/Preferences/.GlobalPreferences.plist", @"Library/Preferences/.GlobalPreferences_m.plist"];
    for (NSString *sk in skipLibDirs) {
        [fm removeItemAtPath:[dataBackupDir stringByAppendingPathComponent:sk] error:nil];
    }

    // Clean trigger flags and stale SQLite shared memory files from backup DataContainer
    [fm removeItemAtPath:[dataBackupDir stringByAppendingPathComponent:@"Documents/_zt_wipe_keychain.flag"] error:nil];
    [fm removeItemAtPath:[dataBackupDir stringByAppendingPathComponent:@"Documents/_zt_restore_trigger.txt"] error:nil];
    [self removeStaleSqliteShmFilesAtPath:dataBackupDir fileManager:fm];

    // Copy ALL Zalo AppGroup containers (including root-level MMKV/SQLite files in group.vn.com.vng.zingalo!)
    NSDictionary<NSString *, NSString *> *appGroups = [self findZaloAppGroupContainers];
    for (NSString *groupId in appGroups) {
        NSString *groupContainer = appGroups[groupId];
        NSString *dstGroup = [groupBackupDir stringByAppendingPathComponent:groupId];
        [fm createDirectoryAtPath:dstGroup withIntermediateDirectories:YES attributes:nil error:nil];
        [self copyDirectoryContentsFrom:groupContainer to:dstGroup fileManager:fm fixMobileOwner:NO];
        for (NSString *sk in skipLibDirs) {
            [fm removeItemAtPath:[dstGroup stringByAppendingPathComponent:sk] error:nil];
        }
        [self removeStaleSqliteShmFilesAtPath:dstGroup fileManager:fm];
    }

    ZTechVaultAccount *newAcc = [[ZTechVaultAccount alloc] init];
    newAcc.accountId = accId;
    newAcc.title = cleanTitle;
    newAcc.proxyString = cleanProxy;
    newAcc.createdAt = nowStr;
    newAcc.deviceProfileDict = [profile toDictionary];

    [accounts insertObject:newAcc atIndex:0];
    [self saveAccountsList:accounts];

    [[NSUserDefaults standardUserDefaults] setObject:accId forKey:@"ZTechActiveVaultAccountId"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    return newAcc;
}

+ (BOOL)restoreAndLaunchAccount:(ZTechVaultAccount *)account
                     outProfile:(ZTechDeviceProfile * _Nullable * _Nullable)outProfile
                          error:(NSError **)error {
    if (!account || account.accountId.length == 0) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *slotDir = [[self vaultRootDirectory] stringByAppendingPathComponent:account.accountId];
    NSString *dataBackupDir = [slotDir stringByAppendingPathComponent:@"DataContainer"];
    if (![fm fileExistsAtPath:dataBackupDir]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ZTechVault"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Không tìm thấy dữ liệu sao lưu của Acc này trong Kho."}];
        }
        return NO;
    }

    NSString *zaloContainer = [self findZaloDataContainerPath];
    if (!zaloContainer) {
        if (error) {
            *error = [NSError errorWithDomain:@"ZTechVault"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Không tìm thấy thư mục Zalo trên thiết bị."}];
        }
        return NO;
    }

    // 1. Kill Zalo first so SQLite databases are flushed and unlocked
    [self killZaloProcess];
    usleep(200000); // 200ms
    sync();

    // 2. Clean current active container safely WITHOUT writing _zt_wipe_keychain.flag
    [ZTechDeviceDatabase cleanResetContainerContentsForRestore];

    // 3. Restore Device Profile
    ZTechDeviceProfile *restoredProfile = [ZTechDeviceProfile fromDictionary:account.deviceProfileDict];
    if (!restoredProfile) {
        restoredProfile = [ZTechDeviceDatabase loadOrCreateDefaultProfile];
    }
    restoredProfile.activeProxy = account.proxyString ?: @"";

    if (outProfile) {
        *outProfile = restoredProfile;
    }

    // 4. Restore DataContainer contents
    [self copyDirectoryContentsFrom:dataBackupDir to:zaloContainer fileManager:fm fixMobileOwner:NO];

    // 5. Restore AppGroups (including root-level files in group.vn.com.vng.zingalo)
    NSString *groupBackupDir = [slotDir stringByAppendingPathComponent:@"AppGroups"];
    NSDictionary<NSString *, NSString *> *appGroups = [self findZaloAppGroupContainers];
    for (NSString *groupId in appGroups) {
        NSString *liveGroupPath = appGroups[groupId];
        NSString *savedGroupPath = [groupBackupDir stringByAppendingPathComponent:groupId];
        if ([fm fileExistsAtPath:savedGroupPath]) {
            [self copyDirectoryContentsFrom:savedGroupPath to:liveGroupPath fileManager:fm fixMobileOwner:YES];
        }
    }

    // 6. Remove stale SQLite shared memory (.shm) files to prevent memory-mapping lock corruption
    [self removeStaleSqliteShmFilesAtPath:zaloContainer fileManager:fm];
    for (NSString *groupId in appGroups) {
        NSString *liveGroupPath = appGroups[groupId];
        [self removeStaleSqliteShmFilesAtPath:liveGroupPath fileManager:fm];
    }

    // 7. Reconstruct standard directory skeleton (ensures Library/Caches, Library/SplashBoard, etc. exist)
    [ZTechDeviceDatabase repairContainerStructureAtPath:zaloContainer fileManager:fm];
    for (NSString *groupId in appGroups) {
        NSString *liveGroupPath = appGroups[groupId];
        [ZTechDeviceDatabase repairContainerStructureAtPath:liveGroupPath fileManager:fm];
    }

    // 8. Write active profile files & fix permissions safely
    [ZTechDeviceDatabase writeProfileFiles:restoredProfile error:nil];
    [[NSUserDefaults standardUserDefaults] setObject:[restoredProfile toDictionary] forKey:@"ZTechCurrentProfile"];
    [[NSUserDefaults standardUserDefaults] setObject:account.accountId forKey:@"ZTechActiveVaultAccountId"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSString *docsDir = [zaloContainer stringByAppendingPathComponent:@"Documents"];
    [fm createDirectoryAtPath:docsDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Explicitly guarantee no wipe flag exists
    [fm removeItemAtPath:[docsDir stringByAppendingPathComponent:@"_zt_wipe_keychain.flag"] error:nil];

    // Write restore trigger
    NSString *restoreTrigger = [docsDir stringByAppendingPathComponent:@"_zt_restore_trigger.txt"];
    [@"1" writeToFile:restoreTrigger atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod([restoreTrigger UTF8String], 0666);

    // Write full signature (UUID:MachineId) to bound UUID file so signature always matches perfectly
    NSString *fullSig = [NSString stringWithFormat:@"%@:%@", restoredProfile.identifier ?: @"", restoredProfile.machineId ?: @""];
    NSString *boundUuidFile = [docsDir stringByAppendingPathComponent:@"_zt_bound_uuid.txt"];
    [fullSig writeToFile:boundUuidFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod([boundUuidFile UTF8String], 0666);

    NSString *markerFile = [docsDir stringByAppendingPathComponent:@"_zt_zalo_marker.txt"];
    [@"vn.com.vng.zalo" writeToFile:markerFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod([markerFile UTF8String], 0666);

        [self runFastChownAndChmod:zaloContainer];
    for (NSString *groupId in appGroups) {
        NSString *liveGroupPath = appGroups[groupId];
        [self runFastChownAndChmod:liveGroupPath];
    }
    system("killall -9 cfprefsd 2>/dev/null");
    sync();

    // 9. Launch Zalo with slight delay so buffers are flushed to flash storage
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self launchZaloApp];
    });

    return YES;
}

+ (BOOL)updateAccount:(NSString *)accountId
                title:(nullable NSString *)title
          proxyString:(nullable NSString *)proxyString {
    NSMutableArray<ZTechVaultAccount *> *accounts = [[self listSavedAccounts] mutableCopy];
    BOOL found = NO;
    NSString *cleanProxy = [proxyString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";

    for (ZTechVaultAccount *acc in accounts) {
        if ([acc.accountId isEqualToString:accountId]) {
            if (title && title.length > 0) {
                acc.title = title;
            }
            acc.proxyString = cleanProxy;
            NSMutableDictionary *profMut = [acc.deviceProfileDict mutableCopy] ?: [NSMutableDictionary dictionary];
            profMut[@"activeProxy"] = cleanProxy;
            acc.deviceProfileDict = profMut;
            found = YES;

            // If this account is currently active, immediately apply the new proxy to active profile and restart Zalo sockets
            if ([[self activeAccountId] isEqualToString:accountId]) {
                ZTechDeviceProfile *cur = [ZTechDeviceDatabase loadOrCreateDefaultProfile];
                cur.activeProxy = cleanProxy;
                [ZTechDeviceDatabase writeProfileFiles:cur error:nil];
                [[NSUserDefaults standardUserDefaults] setObject:[cur toDictionary] forKey:@"ZTechCurrentProfile"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [self killZaloProcess];
            }
            break;
        }
    }
    if (found) {
        [self saveAccountsList:accounts];
    }
    return found;
}

+ (BOOL)deleteAccountWithId:(NSString *)accountId {
    if (!accountId || accountId.length == 0) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *slotDir = [[self vaultRootDirectory] stringByAppendingPathComponent:accountId];
    [fm removeItemAtPath:slotDir error:nil];

    NSMutableArray<ZTechVaultAccount *> *accounts = [[self listSavedAccounts] mutableCopy];
    NSIndexSet *toRemove = [accounts indexesOfObjectsPassingTest:^BOOL(ZTechVaultAccount * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [obj.accountId isEqualToString:accountId];
    }];
    if (toRemove.count > 0) {
        [accounts removeObjectsAtIndexes:toRemove];
        [self saveAccountsList:accounts];
        return YES;
    }
    return NO;
}

+ (void)launchZaloApp {
    @try {
        Class wsCls = NSClassFromString(@"LSApplicationWorkspace");
        if (wsCls) {
            id ws = ((id (*)(id, SEL))objc_msgSend)(wsCls, sel_registerName("defaultWorkspace"));
            if (ws) {
                SEL openSel = sel_registerName("openApplicationWithBundleID:");
                if ([ws respondsToSelector:openSel]) {
                    NSArray<NSString *> *bids = @[@"vn.com.vng.zalo", @"com.vng.zalo", @"com.zing.zalo", @"com.vng.zingalo", @"vn.com.vng.zingalo", @"com.zing.zingalo"];
                    for (NSString *bid in bids) {
                        BOOL opened = ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(ws, openSel, bid);
                        if (opened) return;
                    }
                }
            }
        }
        NSURL *zaloUrl = [NSURL URLWithString:@"zalo://"];
        if ([[UIApplication sharedApplication] canOpenURL:zaloUrl]) {
            [[UIApplication sharedApplication] openURL:zaloUrl options:@{} completionHandler:nil];
        }
    } @catch (NSException *e) {}
}

+ (void)setSystemAirplaneMode:(BOOL)enabled {
    @try {
        static void *appSupportHandle = NULL;
        if (!appSupportHandle) {
            appSupportHandle = dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        }
        if (!appSupportHandle) {
            appSupportHandle = dlopen("/System/Library/PrivateFrameworks/RadiosPreferences.framework/RadiosPreferences", RTLD_NOW);
        }

        Class rpClass = NSClassFromString(@"RadiosPreferences");
        if (rpClass) {
            id rp = [[rpClass alloc] init];
            SEL setAirSel = sel_registerName("setAirplaneMode:");
            if ([rp respondsToSelector:setAirSel]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(rp, setAirSel, enabled);
            }
            SEL syncSel = sel_registerName("synchronize");
            if ([rp respondsToSelector:syncSel]) {
                ((void (*)(id, SEL))objc_msgSend)(rp, syncSel);
            }
        }

        notify_post(enabled ? "com.ztech.airplaneModeOn" : "com.ztech.airplaneModeOff");
        notify_post("com.apple.radios.airplaneModeChanged");
    } @catch (NSException *e) {}
}

+ (BOOL)isSystemAirplaneModeEnabled {
    @try {
        Class rpClass = NSClassFromString(@"RadiosPreferences");
        if (rpClass) {
            id rp = [[rpClass alloc] init];
            SEL airSel = sel_registerName("airplaneMode");
            if ([rp respondsToSelector:airSel]) {
                return ((BOOL (*)(id, SEL))objc_msgSend)(rp, airSel);
            }
        }
    } @catch (NSException *e) {}
    return NO;
}

+ (BOOL)rescueAccountWithId:(NSString *)accountId
             resetCorruptDb:(BOOL)resetDb
                 outProfile:(ZTechDeviceProfile * _Nullable * _Nullable)outProfile
                      error:(NSError **)error {
    if (!accountId || accountId.length == 0) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *slotDir = [[self vaultRootDirectory] stringByAppendingPathComponent:accountId];
    NSString *dataBackupDir = [slotDir stringByAppendingPathComponent:@"DataContainer"];
    if (![fm fileExistsAtPath:dataBackupDir]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ZTechVault"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Không tìm thấy dữ liệu sao lưu của Acc này."}];
        }
        return NO;
    }

    // 1. If resetCorruptDb is requested, find user folders inside Documents/ and quarantine corrupted message.sqlite*
    if (resetDb) {
        NSString *docs = [dataBackupDir stringByAppendingPathComponent:@"Documents"];
        NSArray *items = [fm contentsOfDirectoryAtPath:docs error:nil];
        for (NSString *item in items) {
            NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            if ([item rangeOfCharacterFromSet:nonDigits].location == NSNotFound && item.length >= 5) {
                NSString *uDir = [docs stringByAppendingPathComponent:item];
                NSString *quarantine = [uDir stringByAppendingPathComponent:@"Corrupt_DB_Backup"];
                [fm createDirectoryAtPath:quarantine withIntermediateDirectories:YES attributes:nil error:nil];
                NSArray *uFiles = [fm contentsOfDirectoryAtPath:uDir error:nil];
                for (NSString *uf in uFiles) {
                    if ([uf containsString:@"message"] || [uf hasSuffix:@".sqlite"] || [uf hasSuffix:@".sqlite-wal"] || [uf hasSuffix:@".sqlite-shm"]) {
                        NSString *src = [uDir stringByAppendingPathComponent:uf];
                        NSString *dst = [quarantine stringByAppendingPathComponent:uf];
                        [fm removeItemAtPath:dst error:nil];
                        [fm moveItemAtPath:src toPath:dst error:nil];
                    }
                }
            }
        }
        NSString *platSqlite = [docs stringByAppendingPathComponent:@"platform.sqlite"];
        if ([fm fileExistsAtPath:platSqlite]) {
            [fm removeItemAtPath:[platSqlite stringByAppendingString:@"-wal"] error:nil];
            [fm removeItemAtPath:[platSqlite stringByAppendingString:@"-shm"] error:nil];
        }
    }

    // 2. Clean all lock files and memory-mapped files from backup
    [self removeStaleSqliteShmFilesAtPath:dataBackupDir fileManager:fm];
    NSString *groupBackupDir = [slotDir stringByAppendingPathComponent:@"AppGroups"];
    if ([fm fileExistsAtPath:groupBackupDir]) {
        [self removeStaleSqliteShmFilesAtPath:groupBackupDir fileManager:fm];
    }

    // 3. Find target account model
    NSMutableArray<ZTechVaultAccount *> *accounts = [[self listSavedAccounts] mutableCopy];
    ZTechVaultAccount *targetAcc = nil;
    for (ZTechVaultAccount *a in accounts) {
        if ([a.accountId isEqualToString:accountId]) {
            targetAcc = a;
            break;
        }
    }
    if (!targetAcc) {
        if (error) {
            *error = [NSError errorWithDomain:@"ZTechVault"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Không tìm thấy thông tin Acc."}];
        }
        return NO;
    }

    return [self restoreAndLaunchAccount:targetAcc outProfile:outProfile error:error];
}


@end
