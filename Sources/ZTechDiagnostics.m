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
    [outStr appendString:@"   🔍 GAULMT -TECH BÁO CÁO CHẨN ĐOÁN THIẾT BỊ TOÀN DIỆN\n"];
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
    [outStr appendString:@"- Tệp Tweak gaulmt -Tech Hook:\n"];
    for (NSString *tp in tweakPaths) {
        [outStr appendFormat:@"  * %@: %@\n", tp, ZTechFormatFilePerms(tp, fm)];
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
        [outStr appendFormat:@"- Data Container: %@\n", zaloContainer];
        NSString *zDocs = [zaloContainer stringByAppendingPathComponent:@"Documents"];
        NSString *zPrefs = [zaloContainer stringByAppendingPathComponent:@"Library/Preferences"];
        NSString *zActiveProf = [zDocs stringByAppendingPathComponent:@"_zt_active_profile.plist"];
        [outStr appendFormat:@"  * Documents: %@\n", ZTechFormatFilePerms(zDocs, fm)];
        [outStr appendFormat:@"  * Library/Preferences: %@\n", ZTechFormatFilePerms(zPrefs, fm)];
        [outStr appendFormat:@"  * _zt_active_profile.plist: %@\n", ZTechFormatFilePerms(zActiveProf, fm)];

        // Check SQLite
        NSArray<NSString *> *dbNames = @[@"app_data.db", @"message.db", @"contact.db"];
        for (NSString *dbn in dbNames) {
            NSString *dbp = [zDocs stringByAppendingPathComponent:dbn];
            if ([fm fileExistsAtPath:dbp]) {
                [outStr appendFormat:@"  * SQLite %@: %@\n", dbn, ZTechFormatFilePerms(dbp, fm)];
            }
        }
    } else {
        [outStr appendString:@"- Data Container Zalo: ⚠️ [CHƯA TÌM THẤY] (Hãy mở Zalo ít nhất 1 lần)\n"];
    }

    NSDictionary<NSString *, NSString *> *zGroups = [ZTechVaultManager findZaloAppGroupContainers];
    [outStr appendFormat:@"- AppGroup Containers (%lu nhóm):\n", (unsigned long)zGroups.count];
    for (NSString *gid in zGroups) {
        NSString *gp = zGroups[gid];
        [outStr appendFormat:@"  * %@ ➜ %@\n", gid, ZTechFormatFilePerms(gp, fm)];
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
    [outStr appendString:@"\n========================================================"];

    return outStr;
}

@end
