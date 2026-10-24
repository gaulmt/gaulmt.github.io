#import "ZTechDiagnostics.h"
#import "ZTechVaultManager.h"
#import "ZTechDeviceDatabase.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

@implementation ZTechDiagnostics

static NSString *ZTechFormatFilePerms(NSString *path, NSFileManager *fm) {
    if (!path || path.length == 0 || ![fm fileExistsAtPath:path]) {
        return @"[Không tồn tại]";
    }
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if (!attrs) return @"[Tồn tại - không đọc được thuộc tính]";
    NSNumber *posix = attrs[NSFilePosixPermissions];
    NSNumber *owner = attrs[NSFileOwnerAccountID];
    NSNumber *group = attrs[NSFileGroupOwnerAccountID];
    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
    NSString *sizeStr = (size > 1048576) ? [NSString stringWithFormat:@"%.1f MB", (double)size / 1048576.0]
                      : (size > 1024)    ? [NSString stringWithFormat:@"%.1f KB", (double)size / 1024.0]
                      : [NSString stringWithFormat:@"%llu B", size];
    return [NSString stringWithFormat:@"Tồn tại (%@, 0%o, %d:%d)",
            sizeStr,
            posix ? [posix unsignedShortValue] : 0,
            owner ? [owner intValue] : -1,
            group ? [group intValue] : -1];
}

+ (NSString *)generateFullSystemDiagnosticReport {
    NSMutableString *outStr = [NSMutableString string];
    NSFileManager *fm = [NSFileManager defaultManager];

    [outStr appendString:@"========================================================\n"];
    [outStr appendString:@"   🔍 QUANG LAM MARKETING BÁO CÁO CHẨN ĐOÁN THIẾT BỊ TOÀN DIỆN\n"];
    [outStr appendString:@"========================================================\n\n"];

    // 1. THIẾT BỊ GỐC (KERNEL & HARDWARE)
    [outStr appendString:@"1. THÔNG SỐ THIẾT BỊ GỐC (KERNEL & SYSTEM):\n"];
    struct utsname uts;
    if (uname(&uts) == 0) {
        [outStr appendFormat:@"- uts.machine: %s\n", uts.machine];
        [outStr appendFormat:@"- uts.nodename: %s\n", uts.nodename];
        [outStr appendFormat:@"- uts.release: %s\n", uts.release];
        [outStr appendFormat:@"- uts.version: %s\n", uts.version];
    }

    char sysMachine[64] = {0};
    size_t sLen = sizeof(sysMachine);
    if (sysctlbyname("hw.machine", sysMachine, &sLen, NULL, 0) == 0) {
        [outStr appendFormat:@"- sysctlbyname(hw.machine): %s\n", sysMachine];
    }
    char sysModel[64] = {0};
    sLen = sizeof(sysModel);
    if (sysctlbyname("hw.model", sysModel, &sLen, NULL, 0) == 0) {
        [outStr appendFormat:@"- sysctlbyname(hw.model): %s\n", sysModel];
    }

    uint64_t memBytes = 0;
    size_t mLen = sizeof(memBytes);
    if (sysctlbyname("hw.memsize", &memBytes, &mLen, NULL, 0) == 0) {
        [outStr appendFormat:@"- RAM phát hiện: %.2f GB (%llu bytes)\n", (double)memBytes / (1024.0 * 1024.0 * 1024.0), memBytes];
    }

    int ncpu = 0;
    size_t cLen = sizeof(ncpu);
    if (sysctlbyname("hw.ncpu", &ncpu, &cLen, NULL, 0) == 0) {
        [outStr appendFormat:@"- Số Core CPU: %d cores\n", ncpu];
    }

    UIDevice *curDev = [UIDevice currentDevice];
    [outStr appendFormat:@"- UIDevice model: %@\n", curDev.model];
    [outStr appendFormat:@"- UIDevice name: %@\n", curDev.name];
    [outStr appendFormat:@"- UIDevice systemVersion: %@\n", curDev.systemVersion];
    [outStr appendFormat:@"- NSProcessInfo OS: %@\n\n", [[NSProcessInfo processInfo] operatingSystemVersionString]];

    // 2. MÔI TRƯỜNG JAILBREAK & TWEAK INJECTION
    [outStr appendString:@"2. MÔI TRƯỜNG JAILBREAK & BOOTSTRAP:\n"];
    BOOL hasVarJb = [fm fileExistsAtPath:@"/var/jb"];
    [outStr appendFormat:@"- Thư mục /var/jb: %@\n", hasVarJb ? @"CÓ (Rootless)" : @"KHÔNG (Rootful / Jailed)"];

    NSString *jbType = @"Không rõ / Jailed";
    if (hasVarJb) {
        if ([fm fileExistsAtPath:@"/var/jb/basebin"]) {
            jbType = @"Dopamine (Rootless)";
        } else if ([fm fileExistsAtPath:@"/var/jb/.palera1n"]) {
            jbType = @"palera1n (Rootless)";
        } else {
            jbType = @"Rootless Bootstrap";
        }
    } else {
        if ([fm fileExistsAtPath:@"/Applications/Cydia.app"] || [fm fileExistsAtPath:@"/bin/bash"]) {
            jbType = @"Rootful (palera1n/unc0ver/checkra1n)";
        } else if ([fm fileExistsAtPath:@"/var/mobile/Applications"]) {
            jbType = @"TrollStore Jailed Environment";
        }
    }
    [outStr appendFormat:@"- Phân loại Jailbreak: %@\n", jbType];

    // Hook Libraries
    NSArray<NSString *> *hookLibs = @[
        @"/var/jb/usr/lib/libellekit.dylib",
        @"/var/jb/usr/lib/libsubstrate.dylib",
        @"/usr/lib/libsubstrate.dylib",
        @"/usr/lib/libsubstitute.dylib"
    ];
    [outStr appendString:@"- Thư viện Hook động:\n"];
    for (NSString *hl in hookLibs) {
        BOOL ex = [fm fileExistsAtPath:hl];
        [outStr appendFormat:@"  * %@: %@\n", hl, ex ? @"[TỒN TẠI - OK]" : @"[Không có]"];
    }

    if (hasVarJb && ![fm fileExistsAtPath:@"/var/jb/usr/lib/libellekit.dylib"] && ![fm fileExistsAtPath:@"/var/jb/usr/lib/libsubstrate.dylib"]) {
        [outStr appendString:@"\n  ⚠️ CẢNH BÁO QUAN TRỌNG:\n"];
        [outStr appendString:@"  Máy đang Jailbreak Dopamine nhưng CHƯA CÀI ĐẶT THƯ VIỆN 'ElleKit'!\n"];
        [outStr appendString:@"  ➜ Nguyên nhân AIDA64 và Zalo chưa nhận fake là do máy thiếu ElleKit.\n"];
        [outStr appendString:@"  ➜ KHẮC PHỤC: Mở Sileo, tìm kiếm gói 'ElleKit' ➜ Cài đặt rồi Respring là 100% HOẠT ĐỘNG NGAY!\n\n"];
    }

    // Tweak dylib & plist
    NSArray<NSString *> *tweakPaths = @[
        @"/var/jb/usr/lib/TweakInject/ZTechHook.dylib",
        @"/var/jb/usr/lib/TweakInject/ZTechHook.plist",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/ZTechHook.dylib",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/ZTechHook.plist",
        @"/Library/MobileSubstrate/DynamicLibraries/ZTechHook.dylib",
        @"/Library/MobileSubstrate/DynamicLibraries/ZTechHook.plist"
    ];
    [outStr appendString:@"- Tệp Tweak quang lam marketing Hook:\n"];
    for (NSString *tp in tweakPaths) {
        [outStr appendFormat:@"  * %@: %@\n", tp, ZTechFormatFilePerms(tp, fm)];
    }

    // List all installed tweaks in TweakInject / DynamicLibraries to detect conflicts
    NSArray<NSString *> *injectDirs = @[
        @"/var/jb/usr/lib/TweakInject",
        @"/Library/MobileSubstrate/DynamicLibraries"
    ];
    for (NSString *idir in injectDirs) {
        if ([fm fileExistsAtPath:idir]) {
            NSArray<NSString *> *dfiles = [fm contentsOfDirectoryAtPath:idir error:nil];
            NSMutableArray<NSString *> *dylibs = [NSMutableArray array];
            for (NSString *df in dfiles) {
                if ([df hasSuffix:@".dylib"]) {
                    [dylibs addObject:df];
                }
            }
            [outStr appendFormat:@"- Danh sách Tweak trong %@ (%lu dylib): %@\n",
             idir, (unsigned long)dylibs.count, dylibs.count > 0 ? [dylibs componentsJoinedByString:@", "] : @"Trống"];
        }
    }

    // Binaries
    NSArray<NSString *> *bins = @[
        @"/var/jb/usr/bin/chown",
        @"/var/jb/bin/chown",
        @"/usr/sbin/chown",
        @"/usr/bin/chown",
        @"/var/jb/bin/chmod",
        @"/bin/chmod",
        @"/var/jb/usr/bin/killall",
        @"/usr/bin/killall"
    ];
    [outStr appendString:@"- Lệnh hệ thống (chown/chmod/killall):\n"];
    for (NSString *b in bins) {
        if ([fm isExecutableFileAtPath:b]) {
            [outStr appendFormat:@"  * %@: [KHẢ DỤNG - Thực thi được]\n", b];
        }
    }
    [outStr appendString:@"\n"];

    // 3. ỨNG DỤNG ZALO
    [outStr appendString:@"3. THÔNG TIN & CẤU TRÚC ỨNG DỤNG ZALO:\n"];
    NSString *zaloContainer = [ZTechVaultManager findZaloDataContainerPath];
    if (zaloContainer && zaloContainer.length > 0) {
        [outStr appendFormat:@"- Data Container: %@ (%@)\n", zaloContainer, ZTechFormatFilePerms(zaloContainer, fm)];
        NSString *zMeta = [zaloContainer stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        NSString *zDocs = [zaloContainer stringByAppendingPathComponent:@"Documents"];
        NSString *zPrefs = [zaloContainer stringByAppendingPathComponent:@"Library/Preferences"];
        NSString *zActiveProf = [zDocs stringByAppendingPathComponent:@"_zt_active_profile.plist"];
        NSString *zGpLink = [zPrefs stringByAppendingPathComponent:@".GlobalPreferences.plist"];
        [outStr appendFormat:@"  * metadata.plist: %@\n", ZTechFormatFilePerms(zMeta, fm)];
        [outStr appendFormat:@"  * Documents: %@\n", ZTechFormatFilePerms(zDocs, fm)];
        NSArray<NSString *> *docItems = [fm contentsOfDirectoryAtPath:zDocs error:nil];
        if (docItems.count > 0) {
            NSArray *previewDocs = (docItems.count > 10) ? [docItems subarrayWithRange:NSMakeRange(0, 10)] : docItems;
            [outStr appendFormat:@"    + Tệp trong Documents (%lu): %@\n", (unsigned long)docItems.count, [previewDocs componentsJoinedByString:@", "]];
        }
        [outStr appendFormat:@"  * Library/Preferences: %@\n", ZTechFormatFilePerms(zPrefs, fm)];
        NSArray<NSString *> *prefItems = [fm contentsOfDirectoryAtPath:zPrefs error:nil];
        if (prefItems.count > 0) {
            [outStr appendFormat:@"    + Tệp trong Preferences (%lu): %@\n", (unsigned long)prefItems.count, [prefItems componentsJoinedByString:@", "]];
        }
        [outStr appendFormat:@"  * Symlink .GlobalPreferences.plist: %@\n", ZTechFormatFilePerms(zGpLink, fm)];
        [outStr appendFormat:@"  * _zt_active_profile.plist: %@\n", ZTechFormatFilePerms(zActiveProf, fm)];
        NSString *boundUuidPath = [zDocs stringByAppendingPathComponent:@"_zt_bound_uuid.txt"];
        NSString *boundVal = [[NSString stringWithContentsOfFile:boundUuidPath encoding:NSUTF8StringEncoding error:nil]
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [outStr appendFormat:@"  * _zt_bound_uuid.txt (Keychain Sync): %@\n", boundVal.length > 0 ? boundVal : @"[Chưa đồng bộ / Đang chờ làm sạch]"];
    } else {
        [outStr appendString:@"- Data Container Zalo: ⚠️ [CHƯA TÌM THẤY] (Hãy mở Zalo ít nhất 1 lần)\n"];
    }

    NSDictionary<NSString *, NSString *> *zGroups = [ZTechVaultManager findZaloAppGroupContainers];
    [outStr appendFormat:@"- AppGroup Containers (%lu nhóm):\n", (unsigned long)zGroups.count];
    for (NSString *gid in zGroups) {
        NSString *gp = zGroups[gid];
        [outStr appendFormat:@"  * %@ ➜ %@\n", gid, ZTechFormatFilePerms(gp, fm)];
        NSArray<NSString *> *gItems = [fm contentsOfDirectoryAtPath:gp error:nil];
        if (gItems.count > 0) {
            [outStr appendFormat:@"    + Mục gốc (%lu): %@\n", (unsigned long)gItems.count, [gItems componentsJoinedByString:@", "]];
        }
    }
    [outStr appendString:@"\n"];

    // 4. ỨNG DỤNG AIDA64
    [outStr appendString:@"4. THÔNG TIN & CẤU TRÚC ỨNG DỤNG AIDA64:\n"];
    NSString *aidaContainer = [ZTechVaultManager findAIDA64DataContainerPath];
    if (aidaContainer && aidaContainer.length > 0) {
        [outStr appendFormat:@"- Data Container AIDA64: %@\n", aidaContainer];
        NSString *aDocs = [aidaContainer stringByAppendingPathComponent:@"Documents"];
        NSString *aProf = [aDocs stringByAppendingPathComponent:@"_zt_active_profile.plist"];
        [outStr appendFormat:@"  * Documents: %@\n", ZTechFormatFilePerms(aDocs, fm)];
        [outStr appendFormat:@"  * _zt_active_profile.plist: %@\n", ZTechFormatFilePerms(aProf, fm)];
    } else {
        [outStr appendString:@"- Data Container AIDA64: [CHƯA TÌM THẤY hoặc Chưa cài AIDA64]\n"];
    }
    [outStr appendString:@"\n"];

    // 5. CẤU HÌNH ĐANG LƯU TRỮ TRONG HỆ THỐNG
    [outStr appendString:@"5. CẤU HÌNH PROFILE ĐANG LƯU TRÊN MÁY:\n"];
    NSArray<NSString *> *sharedProfPaths = @[
        @"/var/jb/var/mobile/Library/Preferences/com.ztech.profile.plist",
        @"/var/mobile/Library/Preferences/com.ztech.profile.plist",
        @"/var/tmp/com.ztech.profile.plist"
    ];
    for (NSString *spp in sharedProfPaths) {
        if ([fm fileExistsAtPath:spp]) {
            NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:spp];
            [outStr appendFormat:@"- %@: TỒN TẠI\n", spp];
            if (d) {
                [outStr appendFormat:@"  * Model: %@ (%@)\n", d[@"modelName"], d[@"machineId"]];
                [outStr appendFormat:@"  * iOS: %@ | RAM: %@ GB | Pin: %@%%\n", d[@"iosVersion"], d[@"ramGB"], d[@"batteryPercent"]];
                [outStr appendFormat:@"  * Nhà mạng: %@ | Proxy: %@\n", d[@"carrier"], d[@"activeProxy"] ?: @"Trực tiếp"];
            }
            break;
        }
    }

    // 6. THÔNG TIN CRASH REPORTER & TRACE NHẬT KÝ ZALO
    [outStr appendString:@"\n6. BÁO CÁO NHẬT KÝ CRASH & HOOK TRACE CỦA ZALO:\n"];

    // 6.1 Check in-process Hook Trace (inside Zalo container first, then /var/tmp)
    NSMutableArray<NSString *> *traceCandidates = [NSMutableArray array];
    if (zaloContainer.length > 0) {
        [traceCandidates addObject:[zaloContainer stringByAppendingPathComponent:@"Documents/ztech_hook_trace.log"]];
        [traceCandidates addObject:[zaloContainer stringByAppendingPathComponent:@"Library/Caches/ztech_hook_trace.log"]];
    }
    if (aidaContainer.length > 0) {
        [traceCandidates addObject:[aidaContainer stringByAppendingPathComponent:@"Documents/ztech_hook_trace.log"]];
    }
    [traceCandidates addObject:@"/var/tmp/ztech_hook_trace.log"];

    BOOL foundTrace = NO;
    for (NSString *tPath in traceCandidates) {
        if ([fm fileExistsAtPath:tPath]) {
            NSString *traceContent = [NSString stringWithContentsOfFile:tPath encoding:NSUTF8StringEncoding error:nil];
            if (traceContent && traceContent.length > 0) {
                foundTrace = YES;
                NSArray<NSString *> *lines = [traceContent componentsSeparatedByString:@"\n"];
                NSInteger startIdx = (lines.count > 24) ? (lines.count - 24) : 0;
                [outStr appendFormat:@"- Hook Trace tại %@:\n", [tPath lastPathComponent]];
                for (NSInteger i = startIdx; i < lines.count; i++) {
                    if (lines[i].length > 0) {
                        [outStr appendFormat:@"  * %@\n", lines[i]];
                    }
                }
                break;
            }
        }
    }
    if (!foundTrace) {
        [outStr appendString:@"- Hook Trace: [Chưa có nhật ký hook trace — Hãy mở Zalo 1 lần sau khi cập nhật v5.7.4]\n"];
    }

    // 6.2 Check in-process Crash / AtExit Log (inside Zalo container first, then /var/tmp)
    NSMutableArray<NSString *> *crashLogCandidates = [NSMutableArray array];
    if (zaloContainer.length > 0) {
        [crashLogCandidates addObject:[zaloContainer stringByAppendingPathComponent:@"Documents/ztech_crash.log"]];
        [crashLogCandidates addObject:[zaloContainer stringByAppendingPathComponent:@"Library/Caches/ztech_crash.log"]];
    }
    [crashLogCandidates addObject:@"/var/tmp/ztech_crash.log"];

    for (NSString *cPath in crashLogCandidates) {
        if ([fm fileExistsAtPath:cPath]) {
            NSString *crashContent = [NSString stringWithContentsOfFile:cPath encoding:NSUTF8StringEncoding error:nil];
            if (crashContent && crashContent.length > 0) {
                [outStr appendFormat:@"\n- Nhật ký Crash / Exit nội bộ (%@):\n", [cPath lastPathComponent]];
                NSArray<NSString *> *cLines = [crashContent componentsSeparatedByString:@"\n"];
                NSInteger cStart = (cLines.count > 30) ? (cLines.count - 30) : 0;
                for (NSInteger i = cStart; i < cLines.count; i++) {
                    if (cLines[i].length > 0) {
                        [outStr appendFormat:@"  * %@\n", cLines[i]];
                    }
                }
                break;
            }
        }
    }

    // 6.3 Check Apple System CrashReporter (.ips / .plist) including Retired folder
    NSArray<NSString *> *crashDirs = @[
        @"/var/mobile/Library/Logs/CrashReporter",
        @"/var/mobile/Library/Logs/CrashReporter/Retired",
        @"/private/var/mobile/Library/Logs/CrashReporter",
        @"/private/var/mobile/Library/Logs/CrashReporter/Retired",
        @"/Library/Logs/CrashReporter",
        @"/var/jb/var/mobile/Library/Logs/CrashReporter"
    ];
    NSString *latestCrashFile = nil;
    NSDate *latestDate = [NSDate distantPast];
    NSMutableArray<NSDictionary *> *allRecentLogs = [NSMutableArray array];
    NSMutableSet<NSString *> *seenFiles = [NSMutableSet set];

    for (NSString *cd in crashDirs) {
        if (![fm fileExistsAtPath:cd]) continue;
        NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:cd error:nil];
        for (NSString *file in files) {
            if ([seenFiles containsObject:file]) continue;
            NSString *fullPath = [cd stringByAppendingPathComponent:file];
            NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
            if ([attrs[NSFileType] isEqualToString:NSFileTypeDirectory]) continue;
            [seenFiles addObject:file];
            NSDate *modDate = attrs[NSFileModificationDate] ?: [NSDate distantPast];
            if (file && fullPath) {
                [allRecentLogs addObject:@{@"name": file, @"date": (modDate ?: [NSDate distantPast]), @"path": fullPath}];
            }

            NSString *lower = [file lowercaseString];
            if ([lower containsString:@"zalo"] || [lower containsString:@"zingalo"]) {
                if ([modDate compare:latestDate] == NSOrderedDescending) {
                    latestDate = modDate;
                    latestCrashFile = fullPath;
                }
            }
        }
    }

    [allRecentLogs sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"date"] compare:a[@"date"]];
    }];
    if (allRecentLogs.count > 0) {
        [outStr appendString:@"\n- 5 tệp CrashReporter mới nhất trên hệ thống:\n"];
        NSInteger limit = MIN((NSInteger)allRecentLogs.count, 5);
        for (NSInteger i = 0; i < limit; i++) {
            NSDictionary *item = allRecentLogs[i];
            [outStr appendFormat:@"  * %@ (%@)\n", item[@"name"], item[@"date"]];
        }
    }

    if (latestCrashFile) {
        [outStr appendFormat:@"\n- Chi tiết tệp CrashReporter Zalo: %@\n", [latestCrashFile lastPathComponent]];
        [outStr appendFormat:@"  * Thời điểm ghi nhận: %@\n", latestDate];
        NSString *rawIps = [NSString stringWithContentsOfFile:latestCrashFile encoding:NSUTF8StringEncoding error:nil];
        if (rawIps && rawIps.length > 0) {
            // Try parsing iOS 15+ IPS v2 JSON payload (starts after the first newline)
            NSRange firstNl = [rawIps rangeOfString:@"\n"];
            NSDictionary *ipsJson = nil;
            if (firstNl.location != NSNotFound && firstNl.location + 1 < rawIps.length) {
                NSString *jsonBody = [rawIps substringFromIndex:firstNl.location + 1];
                NSData *jData = [jsonBody dataUsingEncoding:NSUTF8StringEncoding];
                if (jData) {
                    ipsJson = [NSJSONSerialization JSONObjectWithData:jData options:0 error:nil];
                }
            }

            if ([ipsJson isKindOfClass:[NSDictionary class]]) {
                if (ipsJson[@"exception"]) {
                    [outStr appendFormat:@"  * Exception: %@\n", ipsJson[@"exception"]];
                }
                if (ipsJson[@"termination"]) {
                    [outStr appendFormat:@"  * Termination: %@\n", ipsJson[@"termination"]];
                }
                if (ipsJson[@"asi"]) {
                    [outStr appendFormat:@"  * ASI (Nguyên nhân trực tiếp): %@\n", ipsJson[@"asi"]];
                }
                NSArray *usedImages = [ipsJson[@"usedImages"] isKindOfClass:[NSArray class]] ? ipsJson[@"usedImages"] : nil;
                NSArray *threads = [ipsJson[@"threads"] isKindOfClass:[NSArray class]] ? ipsJson[@"threads"] : nil;
                NSInteger faultIdx = [ipsJson[@"faultingThread"] integerValue];
                NSDictionary *targetThread = nil;
                for (NSDictionary *th in threads) {
                    if ([th isKindOfClass:[NSDictionary class]] && [th[@"triggered"] boolValue]) {
                        targetThread = th;
                        break;
                    }
                }
                if (!targetThread && faultIdx >= 0 && faultIdx < (NSInteger)threads.count) {
                    targetThread = threads[faultIdx];
                }
                if (targetThread && [targetThread[@"frames"] isKindOfClass:[NSArray class]]) {
                    NSArray *frames = targetThread[@"frames"];
                    NSInteger fLimit = MIN((NSInteger)frames.count, 15);
                    [outStr appendFormat:@"  * Backtrace Thread Fault (%ld frames):\n", (long)fLimit];
                    for (NSInteger f = 0; f < fLimit; f++) {
                        NSDictionary *fr = frames[f];
                        if (![fr isKindOfClass:[NSDictionary class]]) continue;
                        NSInteger imgIdx = [fr[@"imageIndex"] integerValue];
                        NSString *imgName = @"?";
                        if (usedImages && imgIdx >= 0 && imgIdx < (NSInteger)usedImages.count) {
                            NSDictionary *img = usedImages[imgIdx];
                            imgName = img[@"name"] ?: [img[@"path"] lastPathComponent] ?: @"?";
                        }
                        NSString *sym = fr[@"symbol"] ?: @"";
                        NSNumber *off = fr[@"imageOffset"] ?: @0;
                        [outStr appendFormat:@"    [%02ld] %@ + %@ %@\n", (long)f, imgName, off, sym];
                    }
                }
            } else {
                // Legacy iOS 12-14 plain-text .ips parsing
                NSArray<NSString *> *ipsLines = [rawIps componentsSeparatedByString:@"\n"];
                BOOL printBacktrace = NO;
                int btCount = 0;
                for (NSString *line in ipsLines) {
                    if ([line hasPrefix:@"Exception Type:"] ||
                        [line hasPrefix:@"Exception Subtype:"] ||
                        [line hasPrefix:@"Exception Codes:"] ||
                        [line hasPrefix:@"Termination Reason:"] ||
                        [line hasPrefix:@"Triggered by Thread:"] ||
                        [line containsString:@"\"exception\""] ||
                        [line containsString:@"\"termination\""] ||
                        [line containsString:@"\"asi\""]) {
                        [outStr appendFormat:@"  * %@\n", line];
                    }
                    if ([line containsString:@"Thread 0 Crashed:"] || [line containsString:@"Crashed:"]) {
                        printBacktrace = YES;
                        [outStr appendFormat:@"  * %@\n", line];
                        continue;
                    }
                    if (printBacktrace) {
                        if (btCount < 12 && line.length > 0) {
                            [outStr appendFormat:@"    %@\n", line];
                            btCount++;
                        } else if (line.length == 0 || [line hasPrefix:@"Thread "]) {
                            printBacktrace = NO;
                        }
                    }
                }
            }
        }
    } else {
        [outStr appendString:@"- CrashReporter hệ thống: Không phát hiện tệp crash log Zalo nào trong thư mục Logs.\n"];
    }

    [outStr appendString:@"\n========================================================"];

    return outStr;
}

@end
