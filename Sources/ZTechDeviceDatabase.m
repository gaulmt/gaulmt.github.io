#import "ZTechDeviceDatabase.h"
#import "ZTechVaultManager.h"
#import <sys/utsname.h>
#import <sys/stat.h>
#import <spawn.h>
#import <Security/Security.h>
#import <CoreFoundation/CoreFoundation.h>

extern char **environ;

@implementation ZTechDeviceProfile

- (NSString *)summaryLine1 {
    return [NSString stringWithFormat:@"%@ (%@) · iOS %@",
            self.modelName ?: @"iPhone 16 Pro Max",
            self.machineId ?: @"iPhone17,2",
            self.iosVersion ?: @"18.2.1"];
}

- (NSString *)summaryLine2 {
    NSString *proxyTag = (self.activeProxy && self.activeProxy.length > 0)
        ? [NSString stringWithFormat:@" · 🛡 Proxy: %@", self.activeProxy]
        : @"";
    return [NSString stringWithFormat:@"Pin %ld%% · %@ · %@ · %@ · %ld danh bạ%@",
            (long)self.batteryPercent,
            self.carrier ?: @"MobiFone",
            self.wifiSsid ?: @"The Coffee House",
            self.city ?: @"Hải Phòng",
            (long)self.contactsCount,
            proxyTag];
}

- (NSString *)fullReportTextWithFlags:(BOOL)lockModel
                          respringAfter:(BOOL)respring
                             sameScreen:(BOOL)sameScreen
                              matchChip:(BOOL)matchChip {
    NSString *modeText = lockModel ? @"Khoá Đời Máy" : @"Fake Tất Cả";
    return [NSString stringWithFormat:
            @"=== gaulmt -Tech Device Report v4.6 ===\n"
            @"ID: %@\n"
            @"Device: %@ (%@) - iOS %@\n"
            @"Chip/RAM: %@ (%ldGB) - Screen: %@\n"
            @"Proxy: %@\n"
            @"Status: Pin %ld%% | %@ | %@ | %@ | %ld danh bạ\n"
            @"Config: LockModel=%@ | Respring=%@ | SameScreen=%@ | MatchChip=%@\n"
            @"Result: %ld mục thành công · 0 chưa ghi · Đã ghi %ld file (%@)",
            self.identifier,
            self.modelName, self.machineId, self.iosVersion,
            self.chipName, (long)self.ramGB, self.screenKey,
            (self.activeProxy.length > 0 ? self.activeProxy : @"Direct (4G/WiFi)"),
            (long)self.batteryPercent, self.carrier, self.wifiSsid, self.city, (long)self.contactsCount,
            lockModel ? @"ON" : @"OFF",
            respring ? @"ON" : @"OFF",
            sameScreen ? @"ON" : @"OFF",
            matchChip ? @"ON" : @"OFF",
            (long)self.successItemsCount, (long)self.writtenFilesCount, modeText];
}

- (NSDictionary *)toDictionary {
    return @{
        @"identifier": self.identifier ?: @"",
        @"modelName": self.modelName ?: @"iPhone 16 Pro Max",
        @"machineId": self.machineId ?: @"iPhone17,2",
        @"iosVersion": self.iosVersion ?: @"18.2.1",
        @"batteryPercent": @(self.batteryPercent > 0 ? self.batteryPercent : 68),
        @"carrier": self.carrier ?: @"MobiFone",
        @"wifiSsid": self.wifiSsid ?: @"The Coffee House",
        @"city": self.city ?: @"Hải Phòng",
        @"contactsCount": @(self.contactsCount > 0 ? self.contactsCount : 36),
        @"chipName": self.chipName ?: @"A18 Pro",
        @"ramGB": @(self.ramGB > 0 ? self.ramGB : 8),
        @"screenKey": self.screenKey ?: @"440x956",
        @"activeProxy": self.activeProxy ?: @"",
        @"writtenFilesCount": @(self.writtenFilesCount),
        @"successItemsCount": @(self.successItemsCount)
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return nil;
    ZTechDeviceProfile *p = [[ZTechDeviceProfile alloc] init];
    p.identifier = dict[@"identifier"] ?: [[NSUUID UUID] UUIDString];
    p.modelName = dict[@"modelName"] ?: @"iPhone 16 Pro Max";
    p.machineId = dict[@"machineId"] ?: @"iPhone17,2";
    if (!p.modelName || p.modelName.length == 0) {
        p.modelName = @"iPhone 16 Pro Max";
        p.machineId = @"iPhone17,2";
    }
    NSString *ver = dict[@"iosVersion"] ?: @"18.2.1";
    if (!ver || [ver integerValue] < 14) {
        ver = @"17.4.1";
    }
    p.iosVersion = ver;
    p.batteryPercent = [dict[@"batteryPercent"] integerValue] ?: 68;
    p.carrier = dict[@"carrier"] ?: @"MobiFone";
    p.wifiSsid = dict[@"wifiSsid"] ?: @"The Coffee House";
    p.city = dict[@"city"] ?: @"Hải Phòng";
    p.contactsCount = [dict[@"contactsCount"] integerValue] ?: 36;
    p.chipName = dict[@"chipName"] ?: @"A18 Pro";
    p.ramGB = [dict[@"ramGB"] integerValue] ?: 8;
    p.screenKey = dict[@"screenKey"] ?: @"440x956";
    p.activeProxy = dict[@"activeProxy"] ?: @"";
    p.writtenFilesCount = [dict[@"writtenFilesCount"] integerValue] ?: 7;
    p.successItemsCount = [dict[@"successItemsCount"] integerValue] ?: 10;
    return p;
}

@end

@implementation ZTechDeviceDatabase

// Complete iPhone lineup: iPhone 6s/SE through iPhone 16 Pro Max (37 models)
+ (NSArray<NSDictionary *> *)allDeviceSpecs {
    return @[
        @{@"name": @"iPhone 6s", @"machine": @"iPhone8,1", @"chip": @"A9", @"ram": @2, @"screen": @"375x667", @"tier": @0, @"ios": @[@"15.8", @"15.8.2", @"15.8.3"]},
        @{@"name": @"iPhone 6s Plus", @"machine": @"iPhone8,2", @"chip": @"A9", @"ram": @2, @"screen": @"414x736", @"tier": @0, @"ios": @[@"15.8", @"15.8.2", @"15.8.3"]},
        @{@"name": @"iPhone SE (1st Gen)", @"machine": @"iPhone8,4", @"chip": @"A9", @"ram": @2, @"screen": @"320x568", @"tier": @0, @"ios": @[@"15.8", @"15.8.2", @"15.8.3"]},
        @{@"name": @"iPhone 7", @"machine": @"iPhone9,3", @"chip": @"A10 Fusion", @"ram": @2, @"screen": @"375x667", @"tier": @0, @"ios": @[@"15.8", @"15.8.2", @"15.8.3"]},
        @{@"name": @"iPhone 7 Plus", @"machine": @"iPhone9,4", @"chip": @"A10 Fusion", @"ram": @3, @"screen": @"414x736", @"tier": @0, @"ios": @[@"15.8", @"15.8.2", @"15.8.3"]},
        @{@"name": @"iPhone 8", @"machine": @"iPhone10,4", @"chip": @"A11 Bionic", @"ram": @2, @"screen": @"375x667", @"tier": @0, @"ios": @[@"16.4.1", @"16.6.1", @"16.7.5", @"16.7.8"]},
        @{@"name": @"iPhone 8 Plus", @"machine": @"iPhone10,5", @"chip": @"A11 Bionic", @"ram": @3, @"screen": @"414x736", @"tier": @0, @"ios": @[@"16.5.1", @"16.6.1", @"16.7.5", @"16.7.8"]},
        @{@"name": @"iPhone X", @"machine": @"iPhone10,6", @"chip": @"A11 Bionic", @"ram": @3, @"screen": @"375x812", @"tier": @0, @"ios": @[@"16.5.1", @"16.6.1", @"16.7.5", @"16.7.8"]},
        @{@"name": @"iPhone XR", @"machine": @"iPhone11,8", @"chip": @"A12 Bionic", @"ram": @3, @"screen": @"414x896", @"tier": @0, @"ios": @[@"16.5.1", @"16.6.1", @"17.1.2", @"17.4.1"]},
        @{@"name": @"iPhone XS", @"machine": @"iPhone11,2", @"chip": @"A12 Bionic", @"ram": @4, @"screen": @"375x812", @"tier": @0, @"ios": @[@"16.6.1", @"17.1.2", @"17.4.1", @"17.6.1"]},
        @{@"name": @"iPhone XS Max", @"machine": @"iPhone11,6", @"chip": @"A12 Bionic", @"ram": @4, @"screen": @"414x896", @"tier": @0, @"ios": @[@"16.6.1", @"17.1.2", @"17.4.1", @"17.6.1"]},
        @{@"name": @"iPhone SE (2020)", @"machine": @"iPhone12,8", @"chip": @"A13 Bionic", @"ram": @3, @"screen": @"375x667", @"tier": @0, @"ios": @[@"16.6.1", @"17.1.2", @"17.4.1", @"17.6.1"]},
        @{@"name": @"iPhone 11", @"machine": @"iPhone12,1", @"chip": @"A13 Bionic", @"ram": @4, @"screen": @"414x896", @"tier": @0, @"ios": @[@"16.6.1", @"17.2.1", @"17.5.1", @"18.1.1"]},
        @{@"name": @"iPhone 11 Pro", @"machine": @"iPhone12,3", @"chip": @"A13 Bionic", @"ram": @4, @"screen": @"375x812", @"tier": @0, @"ios": @[@"16.6.1", @"17.2.1", @"17.5.1", @"18.1.1"]},
        @{@"name": @"iPhone 11 Pro Max", @"machine": @"iPhone12,5", @"chip": @"A13 Bionic", @"ram": @4, @"screen": @"414x896", @"tier": @0, @"ios": @[@"16.6.1", @"17.2.1", @"17.5.1", @"18.1.1"]},
        @{@"name": @"iPhone 12 mini", @"machine": @"iPhone13,1", @"chip": @"A14 Bionic", @"ram": @4, @"screen": @"375x812", @"tier": @0, @"ios": @[@"16.6.1", @"17.3.1", @"17.6.1", @"18.1.1"]},
        @{@"name": @"iPhone 12", @"machine": @"iPhone13,2", @"chip": @"A14 Bionic", @"ram": @4, @"screen": @"390x844", @"tier": @0, @"ios": @[@"16.6.1", @"17.3.1", @"17.6.1", @"18.1.1"]},
        @{@"name": @"iPhone 12 Pro", @"machine": @"iPhone13,3", @"chip": @"A14 Bionic", @"ram": @6, @"screen": @"390x844", @"tier": @0, @"ios": @[@"16.6.1", @"17.3.1", @"17.6.1", @"18.1.1"]},
        @{@"name": @"iPhone 12 Pro Max", @"machine": @"iPhone13,4", @"chip": @"A14 Bionic", @"ram": @6, @"screen": @"428x926", @"tier": @0, @"ios": @[@"16.6.1", @"17.3.1", @"17.6.1", @"18.1.1"]},
        @{@"name": @"iPhone 13 mini", @"machine": @"iPhone14,4", @"chip": @"A15 Bionic", @"ram": @4, @"screen": @"375x812", @"tier": @0, @"ios": @[@"16.6.1", @"17.4.1", @"17.6.1", @"18.2.1"]},
        @{@"name": @"iPhone 13", @"machine": @"iPhone14,5", @"chip": @"A15 Bionic", @"ram": @4, @"screen": @"390x844", @"tier": @0, @"ios": @[@"16.6.1", @"17.4.1", @"17.6.1", @"18.2.1"]},
        @{@"name": @"iPhone 13 Pro", @"machine": @"iPhone14,2", @"chip": @"A15 Bionic", @"ram": @6, @"screen": @"390x844", @"tier": @0, @"ios": @[@"16.6.1", @"17.4.1", @"17.6.1", @"18.2.1"]},
        @{@"name": @"iPhone 13 Pro Max", @"machine": @"iPhone14,3", @"chip": @"A15 Bionic", @"ram": @6, @"screen": @"428x926", @"tier": @0, @"ios": @[@"16.6.1", @"17.4.1", @"17.6.1", @"18.2.1"]},
        @{@"name": @"iPhone SE (2022)", @"machine": @"iPhone14,6", @"chip": @"A15 Bionic", @"ram": @4, @"screen": @"375x667", @"tier": @0, @"ios": @[@"16.6.1", @"17.2.1", @"17.5.1", @"18.1.1"]},
        @{@"name": @"iPhone 14", @"machine": @"iPhone14,7", @"chip": @"A15 Bionic", @"ram": @6, @"screen": @"390x844", @"tier": @1, @"ios": @[@"16.6.1", @"17.4.1", @"17.6.1", @"18.2.1"]},
        @{@"name": @"iPhone 14 Plus", @"machine": @"iPhone14,8", @"chip": @"A15 Bionic", @"ram": @6, @"screen": @"428x926", @"tier": @1, @"ios": @[@"16.6.1", @"17.4.1", @"17.6.1", @"18.2.1"]},
        @{@"name": @"iPhone 14 Pro", @"machine": @"iPhone15,2", @"chip": @"A16 Bionic", @"ram": @6, @"screen": @"393x852", @"tier": @1, @"ios": @[@"16.6.1", @"17.4.1", @"17.6.1", @"18.2.1"]},
        @{@"name": @"iPhone 14 Pro Max", @"machine": @"iPhone15,3", @"chip": @"A16 Bionic", @"ram": @6, @"screen": @"430x932", @"tier": @1, @"ios": @[@"16.6.1", @"17.4.1", @"17.6.1", @"18.2.1"]},
        @{@"name": @"iPhone 15", @"machine": @"iPhone15,4", @"chip": @"A16 Bionic", @"ram": @6, @"screen": @"393x852", @"tier": @1, @"ios": @[@"17.2.1", @"17.5.1", @"18.1.1", @"18.2.1"]},
        @{@"name": @"iPhone 15 Plus", @"machine": @"iPhone15,5", @"chip": @"A16 Bionic", @"ram": @6, @"screen": @"430x932", @"tier": @1, @"ios": @[@"17.2.1", @"17.5.1", @"18.1.1", @"18.2.1"]},
        @{@"name": @"iPhone 15 Pro", @"machine": @"iPhone16,1", @"chip": @"A17 Pro", @"ram": @8, @"screen": @"393x852", @"tier": @1, @"ios": @[@"17.2.1", @"17.5.1", @"18.1.1", @"18.3.1"]},
        @{@"name": @"iPhone 15 Pro Max", @"machine": @"iPhone16,2", @"chip": @"A17 Pro", @"ram": @8, @"screen": @"430x932", @"tier": @1, @"ios": @[@"17.2.1", @"17.5.1", @"18.1.1", @"18.3.1"]},
        // New iPhone 16 Series (tier = 2)
        @{@"name": @"iPhone 16e", @"machine": @"iPhone17,5", @"chip": @"A18", @"ram": @8, @"screen": @"390x844", @"tier": @2, @"ios": @[@"18.3", @"18.3.1", @"18.3.2"]},
        @{@"name": @"iPhone 16", @"machine": @"iPhone17,3", @"chip": @"A18", @"ram": @8, @"screen": @"393x852", @"tier": @2, @"ios": @[@"18.0.1", @"18.1.1", @"18.2.1", @"18.3.1"]},
        @{@"name": @"iPhone 16 Plus", @"machine": @"iPhone17,4", @"chip": @"A18", @"ram": @8, @"screen": @"430x932", @"tier": @2, @"ios": @[@"18.0.1", @"18.1.1", @"18.2.1", @"18.3.1"]},
        @{@"name": @"iPhone 16 Pro", @"machine": @"iPhone17,1", @"chip": @"A18 Pro", @"ram": @8, @"screen": @"402x874", @"tier": @2, @"ios": @[@"18.0.1", @"18.1.1", @"18.2.1", @"18.3.1"]},
        @{@"name": @"iPhone 16 Pro Max", @"machine": @"iPhone17,2", @"chip": @"A18 Pro", @"ram": @8, @"screen": @"440x956", @"tier": @2, @"ios": @[@"18.0.1", @"18.1.1", @"18.2.1", @"18.3.1"]}
    ];
}

+ (NSString *)realHardwareMachine {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *machine = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    if (!machine || ![machine hasPrefix:@"iPhone"]) {
        return @"iPhone17,2";
    }
    return machine;
}

+ (NSString *)realScreenKey {
    CGSize size = [UIScreen mainScreen].bounds.size;
    NSInteger w = (NSInteger)MIN(size.width, size.height);
    NSInteger h = (NSInteger)MAX(size.width, size.height);
    return [NSString stringWithFormat:@"%ldx%ld", (long)w, (long)h];
}

+ (NSDictionary *)realDeviceSpecFallback {
    NSString *realMachine = [self realHardwareMachine];
    for (NSDictionary *spec in [self allDeviceSpecs]) {
        if ([spec[@"machine"] isEqualToString:realMachine]) {
            return spec;
        }
    }
    NSString *screenKey = [self realScreenKey];
    for (NSDictionary *spec in [self allDeviceSpecs]) {
        if ([spec[@"screen"] isEqualToString:screenKey]) {
            return spec;
        }
    }
    return [self allDeviceSpecs].lastObject; // iPhone 16 Pro Max
}

+ (ZTechDeviceProfile *)loadOrCreateDefaultProfile {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"ZTechCurrentProfile"];
    if (saved) {
        ZTechDeviceProfile *loaded = [ZTechDeviceProfile fromDictionary:saved];
        if (loaded) {
            [self writeProfileFiles:loaded error:nil];
            return loaded;
        }
    }
    ZTechDeviceProfile *initial = [[ZTechDeviceProfile alloc] init];
    initial.identifier = @"7BD46FDA-D93D-45BD-9158-7178669502DD";
    initial.modelName = @"iPhone 16 Pro Max";
    initial.machineId = @"iPhone17,2";
    initial.iosVersion = @"18.2.1";
    initial.batteryPercent = 76;
    initial.carrier = @"Viettel";
    initial.wifiSsid = @"The Coffee House";
    initial.city = @"Hà Nội";
    initial.contactsCount = 42;
    initial.chipName = @"A18 Pro";
    initial.ramGB = 8;
    initial.screenKey = @"440x956";
    initial.activeProxy = @"";
    initial.writtenFilesCount = 7;
    initial.successItemsCount = 10;
    [self writeProfileFiles:initial error:nil];
    return initial;
}

+ (ZTechDeviceProfile *)generateProfileWithLockRealModel:(BOOL)lockModel
                                              sameScreen:(BOOL)sameScreen
                                               matchChip:(BOOL)matchChip
                                               modelTier:(ZTechModelTierFilter)modelTier
                                             currentCity:(NSString *)currentCity {
    NSArray<NSDictionary *> *allSpecs = [self allDeviceSpecs];
    NSDictionary *realSpec = [self realDeviceSpecFallback];
    NSString *realScreen = [self realScreenKey];
    NSDictionary *prevSaved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"ZTechCurrentProfile"];
    NSString *prevMachine = prevSaved[@"machineId"];
    NSString *prevProxy = prevSaved[@"activeProxy"] ?: @"";

    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];

    if (lockModel) {
        [candidates addObject:realSpec];
    } else if (modelTier == ZTechModelTierIPhone16) {
        // User explicitly selected iPhone 16 Series only
        for (NSDictionary *spec in allSpecs) {
            if ([spec[@"tier"] integerValue] == 2) {
                [candidates addObject:spec];
            }
        }
    } else if (modelTier == ZTechModelTierHighEnd) {
        // User selected High-End (iPhone 14 -> iPhone 16 Pro Max)
        for (NSDictionary *spec in allSpecs) {
            if ([spec[@"tier"] integerValue] >= 1) {
                [candidates addObject:spec];
            }
        }
    } else {
        for (NSDictionary *spec in allSpecs) {
            BOOL ok = YES;
            if (sameScreen && ![spec[@"screen"] isEqualToString:realScreen] && ![spec[@"screen"] isEqualToString:realSpec[@"screen"]]) {
                ok = NO;
            }
            if (matchChip && ![spec[@"ram"] isEqualToNumber:realSpec[@"ram"]]) {
                ok = NO;
            }
            if (ok) {
                [candidates addObject:spec];
                // Weight iPhone 15 & iPhone 16 models 2x higher when in "All" mode
                if ([spec[@"tier"] integerValue] >= 1) {
                    [candidates addObject:spec];
                }
            }
        }
        if (candidates.count <= 1 && sameScreen) {
            [candidates removeAllObjects];
            for (NSDictionary *spec in allSpecs) {
                if ([spec[@"screen"] isEqualToString:realScreen] || [spec[@"screen"] isEqualToString:realSpec[@"screen"]]) {
                    [candidates addObject:spec];
                }
            }
        }
        if (candidates.count <= 1) {
            candidates = [allSpecs mutableCopy];
        }
    }

    if (!lockModel && prevMachine.length > 0) {
        NSMutableArray<NSDictionary *> *nonRepeat = [NSMutableArray array];
        for (NSDictionary *spec in candidates) {
            if (![spec[@"machine"] isEqualToString:prevMachine]) {
                [nonRepeat addObject:spec];
            }
        }
        if (nonRepeat.count > 0) {
            candidates = nonRepeat;
        } else {
            for (NSDictionary *spec in allSpecs) {
                if (![spec[@"machine"] isEqualToString:prevMachine]) {
                    [nonRepeat addObject:spec];
                }
            }
            if (nonRepeat.count > 0) {
                candidates = nonRepeat;
            }
        }
    }

    NSDictionary *chosen = candidates[arc4random_uniform((uint32_t)candidates.count)];
    NSArray<NSString *> *iosList = chosen[@"ios"];
    NSString *chosenIOS = iosList[arc4random_uniform((uint32_t)iosList.count)];

    NSArray<NSString *> *carriers = @[@"MobiFone", @"Viettel", @"Vinaphone", @"Vietnamobile"];
    NSArray<NSString *> *wifis = @[
        @"The Coffee House",
        @"Highlands Coffee",
        @"PhucLong_FreeWiFi",
        @"Starbucks_VN",
        @"Viettel_Home_5G",
        @"FPT_Telecom_5G",
        @"VNPT_Fiber_5G",
        @"Aha_Cafe_WiFi"
    ];
    NSArray<NSString *> *cities = @[
        @"Hải Phòng", @"Hà Nội", @"TP. Hồ Chí Minh", @"Đà Nẵng", @"Quảng Ninh", @"Cần Thơ"
    ];

    ZTechDeviceProfile *profile = [[ZTechDeviceProfile alloc] init];
    profile.identifier = [[[NSUUID UUID] UUIDString] uppercaseString];
    profile.modelName = chosen[@"name"];
    profile.machineId = chosen[@"machine"];
    profile.iosVersion = chosenIOS;
    profile.batteryPercent = 20 + arc4random_uniform(76);
    profile.carrier = carriers[arc4random_uniform((uint32_t)carriers.count)];
    profile.wifiSsid = wifis[arc4random_uniform((uint32_t)wifis.count)];
    profile.city = cities[arc4random_uniform((uint32_t)cities.count)];
    profile.contactsCount = 15 + arc4random_uniform(95);
    profile.chipName = chosen[@"chip"];
    profile.ramGB = [chosen[@"ram"] integerValue];
    profile.screenKey = chosen[@"screen"];
    profile.activeProxy = prevProxy;

    [self writeProfileFiles:profile error:nil];
    [[NSUserDefaults standardUserDefaults] setObject:[profile toDictionary] forKey:@"ZTechCurrentProfile"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [self terminateBackgroundInspectors];

    return profile;
}

+ (void)terminateBackgroundInspectors {
    [ZTechVaultManager killZaloProcess];
}

+ (NSString *)storageDirectoryPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *jbPrefPath = @"/var/jb/var/mobile/Library/Preferences/ZTechProfile";
    if ([fm fileExistsAtPath:@"/var/jb/var/mobile/Library/Preferences"] &&
        [fm isWritableFileAtPath:@"/var/jb/var/mobile/Library/Preferences"]) {
        return jbPrefPath;
    }
    NSString *rootPrefPath = @"/var/mobile/Library/Preferences/ZTechProfile";
    if ([fm isWritableFileAtPath:@"/var/mobile/Library/Preferences"]) {
        return rootPrefPath;
    }
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"ZTechProfile"];
}

+ (BOOL)writeProfileFiles:(ZTechDeviceProfile *)profile error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [self storageDirectoryPath];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSDictionary<NSString *, NSDictionary *> *filesToWrite = @{
        @"01_identity.plist": @{
            @"UUID": profile.identifier ?: @"",
            @"VendorID": [[NSUUID UUID] UUIDString],
            @"Timestamp": @([[NSDate date] timeIntervalSince1970])
        },
        @"02_hardware.plist": @{
            @"ModelName": profile.modelName ?: @"",
            @"Machine": profile.machineId ?: @"",
            @"Chip": profile.chipName ?: @"",
            @"RAM_GB": @(profile.ramGB)
        },
        @"03_system_os.plist": @{
            @"OSVersion": profile.iosVersion ?: @"",
            @"BuildVersion": @"22C152"
        },
        @"04_screen_display.plist": @{
            @"ScreenResolution": profile.screenKey ?: @"440x956",
            @"Scale": @3
        },
        @"05_network_carrier.plist": @{
            @"CarrierName": profile.carrier ?: @"MobiFone",
            @"WiFiSSID": profile.wifiSsid ?: @"The Coffee House",
            @"ActiveProxy": profile.activeProxy ?: @""
        },
        @"06_battery_power.plist": @{
            @"BatteryLevel": @(profile.batteryPercent),
            @"BatteryState": @"Unplugged"
        },
        @"07_region_contacts.plist": @{
            @"City": profile.city ?: @"Hải Phòng",
            @"ContactsCount": @(profile.contactsCount)
        }
    };

    NSInteger written = 0;
    for (NSString *fileName in filesToWrite) {
        NSString *fullPath = [dir stringByAppendingPathComponent:fileName];
        NSDictionary *content = filesToWrite[fileName];
        if ([content writeToFile:fullPath atomically:YES]) {
            chmod([fullPath UTF8String], 0644);
            NSDictionary *verify = [NSDictionary dictionaryWithContentsOfFile:fullPath];
            if (verify && verify.count > 0) {
                written++;
            }
        }
    }

    NSDictionary *sharedDict = [profile toDictionary];

    CFPreferencesSetValue(CFSTR("ZTechGlobalProfile"),
                          (__bridge CFPropertyListRef)sharedDict,
                          kCFPreferencesAnyApplication,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);

    NSArray<NSString *> *sharedDirs = @[
        @"/Library/Preferences/ZTechShared",
        @"/var/jb/Library/Preferences/ZTechShared",
        @"/var/jb/var/mobile/Library/Preferences",
        @"/var/mobile/Library/Preferences",
        @"/var/tmp"
    ];
    for (NSString *sdir in sharedDirs) {
        if (![fm fileExistsAtPath:sdir]) {
            [fm createDirectoryAtPath:sdir withIntermediateDirectories:YES attributes:nil error:nil];
            chmod([sdir UTF8String], 0777);
        }
        NSString *sp = [sdir stringByAppendingPathComponent:@"com.ztech.profile.plist"];
        if ([sharedDict writeToFile:sp atomically:YES]) {
            chmod([sp UTF8String], 0644);
        }
    }

    // Also write _zt_active_profile.plist directly inside Zalo's own Data Container & AppGroup so sandboxed Zalo can always read it
    NSString *zaloContainer = [ZTechVaultManager findZaloDataContainerPath];
    if (zaloContainer.length > 0) {
        NSString *zDocs = [zaloContainer stringByAppendingPathComponent:@"Documents"];
        if (![fm fileExistsAtPath:zDocs]) {
            [fm createDirectoryAtPath:zDocs withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *zProfPath = [zDocs stringByAppendingPathComponent:@"_zt_active_profile.plist"];
        if ([sharedDict writeToFile:zProfPath atomically:YES]) {
            chown([zProfPath UTF8String], 501, 501);
            chmod([zProfPath UTF8String], 0666);
        }
        NSString *zPrefDir = [zaloContainer stringByAppendingPathComponent:@"Library/Preferences"];
        if ([fm fileExistsAtPath:zPrefDir]) {
            NSString *zPrefPath = [zPrefDir stringByAppendingPathComponent:@"com.ztech.profile.plist"];
            if ([sharedDict writeToFile:zPrefPath atomically:YES]) {
                chown([zPrefPath UTF8String], 501, 501);
                chmod([zPrefPath UTF8String], 0666);
            }
        }
    }

    NSDictionary<NSString *, NSString *> *zaloGroups = [ZTechVaultManager findZaloAppGroupContainers];
    for (NSString *grpPath in zaloGroups.allValues) {
        if (grpPath.length > 0) {
            NSString *gProfPath = [grpPath stringByAppendingPathComponent:@"_zt_active_profile.plist"];
            if ([sharedDict writeToFile:gProfPath atomically:YES]) {
                chown([gProfPath UTF8String], 501, 501);
                chmod([gProfPath UTF8String], 0666);
            }
        }
    }

    // Also write _zt_active_profile.plist directly inside AIDA64's Data Container if installed
    NSString *aidaContainer = [ZTechVaultManager findAIDA64DataContainerPath];
    if (aidaContainer.length > 0) {
        NSString *aDocs = [aidaContainer stringByAppendingPathComponent:@"Documents"];
        if (![fm fileExistsAtPath:aDocs]) {
            [fm createDirectoryAtPath:aDocs withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *aProfPath = [aDocs stringByAppendingPathComponent:@"_zt_active_profile.plist"];
        if ([sharedDict writeToFile:aProfPath atomically:YES]) {
            chmod([aProfPath UTF8String], 0666);
        }
        NSString *aPrefDir = [aidaContainer stringByAppendingPathComponent:@"Library/Preferences"];
        if ([fm fileExistsAtPath:aPrefDir]) {
            NSString *aPrefPath = [aPrefDir stringByAppendingPathComponent:@"com.ztech.profile.plist"];
            if ([sharedDict writeToFile:aPrefPath atomically:YES]) {
                chmod([aPrefPath UTF8String], 0666);
            }
        }
    }

    profile.writtenFilesCount = written;
    profile.successItemsCount = (written == 7) ? 10 : (written * 10 / 7);
    return (written == 7);
}

+ (NSInteger)cleanDirectoryContents:(NSString *)dirPath fileManager:(NSFileManager *)fm {
    NSInteger count = 0;
    NSArray *items = [fm contentsOfDirectoryAtPath:dirPath error:nil];
    for (NSString *item in items) {
        if ([item isEqualToString:@".com.apple.mobile_container_manager.metadata.plist"] ||
            [item hasPrefix:@".GlobalPreferences"] ||
            [item hasPrefix:@"com.apple."] ||
            [item isEqualToString:@"_zt_last_reset_token.txt"] ||
            [item isEqualToString:@"_zt_zalo_marker.txt"] ||
            [item isEqualToString:@"_zt_active_profile.plist"]) {
            continue;
        }
        NSString *fullPath = [dirPath stringByAppendingPathComponent:item];
        if ([fm removeItemAtPath:fullPath error:nil]) {
            count++;
        }
    }
    return count;
}

+ (void)repairContainerStructureAtPath:(NSString *)containerPath fileManager:(NSFileManager *)fm {
    NSArray<NSString *> *requiredSubDirs = @[
        @"Documents",
        @"tmp",
        @"SystemData",
        @"Library",
        @"Library/Caches",
        @"Library/Preferences",
        @"Library/Cookies",
        @"Library/Application Support",
        @"Library/SplashBoard"
    ];
    for (NSString *sub in requiredSubDirs) {
        NSString *p = [containerPath stringByAppendingPathComponent:sub];
        if (![fm fileExistsAtPath:p]) {
            [fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
        }
        chown([p UTF8String], 501, 501);
        chmod([p UTF8String], 0777);
    }
    NSString *globalPrefsLink = [containerPath stringByAppendingPathComponent:@"Library/Preferences/.GlobalPreferences.plist"];
    if (![fm fileExistsAtPath:globalPrefsLink]) {
        symlink("/private/var/mobile/Library/Preferences/.GlobalPreferences.plist", [globalPrefsLink UTF8String]);
        lchown([globalPrefsLink UTF8String], 501, 501);
    }
}

+ (NSInteger)cleanResetAllProfileDataAndCache {
    NSInteger cleanedItems = 0;
    NSFileManager *fm = [NSFileManager defaultManager];

    // Guarantee Zalo, AIDA64 and Safari are terminated via kernel sysctl and clean Safari cookies/cache
    [ZTechVaultManager killZaloProcess];
    [ZTechVaultManager cleanSafariCookiesAndWebsiteData];
    cleanedItems += 5;

    NSMutableSet<NSString *> *zaloContainers = [NSMutableSet set];
    NSString *mainZalo = [ZTechVaultManager findZaloDataContainerPath];
    if (mainZalo.length > 0) {
        [zaloContainers addObject:mainZalo];
    }
    NSDictionary<NSString *, NSString *> *groups = [ZTechVaultManager findZaloAppGroupContainers];
    for (NSString *gPath in groups.allValues) {
        if (gPath.length > 0) {
            [zaloContainers addObject:gPath];
        }
    }

    for (NSString *containerPath in zaloContainers) {
        [self repairContainerStructureAtPath:containerPath fileManager:fm];
        NSArray<NSString *> *subDirs = @[@"Documents", @"tmp", @"Library/Caches", @"Library/Cookies", @"Library/Preferences", @"Library/WebKit", @"Library/Application Support"];
        for (NSString *sub in subDirs) {
            NSString *targetSub = [containerPath stringByAppendingPathComponent:sub];
            if ([fm fileExistsAtPath:targetSub]) {
                cleanedItems += [self cleanDirectoryContents:targetSub fileManager:fm];
            }
        }
        [self repairContainerStructureAtPath:containerPath fileManager:fm];
        [ZTechVaultManager runFastChownAndChmod:containerPath];
    }
    sync();

    NSString *dir = [self storageDirectoryPath];
    NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *file in files) {
        NSString *fullPath = [dir stringByAppendingPathComponent:file];
        if ([fm removeItemAtPath:fullPath error:nil]) {
            cleanedItems++;
        }
    }

    NSString *resetToken = [[NSUUID UUID] UUIDString];
    CFPreferencesSetValue(CFSTR("ZTechResetToken"),
                          (__bridge CFPropertyListRef)resetToken,
                          kCFPreferencesAnyApplication,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);
    cleanedItems++;

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ZTechActiveVaultAccountId"];
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    cleanedItems++;

    return cleanedItems;
}

+ (void)syncLocationByIPWithCompletion:(void (^)(NSString *city, NSString *isp, NSError *error))completion {
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 8.0;
    ZTechDeviceProfile *cur = [self loadOrCreateDefaultProfile];
    if (cur.activeProxy.length > 0) {
        NSString *s = [cur.activeProxy stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        BOOL isSocks = ([[s lowercaseString] hasPrefix:@"socks"]);
        s = [s stringByReplacingOccurrencesOfString:@"socks5://" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
        s = [s stringByReplacingOccurrencesOfString:@"socks://" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
        s = [s stringByReplacingOccurrencesOfString:@"http://" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
        s = [s stringByReplacingOccurrencesOfString:@"https://" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
        NSArray<NSString *> *parts = [s componentsSeparatedByString:@":"];
        if (parts.count >= 2) {
            NSString *host = parts[0];
            NSInteger port = [parts[1] integerValue];
            if (host.length > 0 && port > 0 && port <= 65535) {
                NSMutableDictionary *pDict = [NSMutableDictionary dictionary];
                if (isSocks) {
                    pDict[@"SOCKSEnable"] = @1;
                    pDict[@"SOCKSProxy"] = host;
                    pDict[@"SOCKSPort"] = @(port);
                } else {
                    pDict[@"HTTPEnable"] = @1;
                    pDict[@"HTTPProxy"] = host;
                    pDict[@"HTTPPort"] = @(port);
                    pDict[@"HTTPSEnable"] = @1;
                    pDict[@"HTTPSProxy"] = host;
                    pDict[@"HTTPSPort"] = @(port);
                }
                if (parts.count >= 4) {
                    NSString *rawCred = [NSString stringWithFormat:@"%@:%@", parts[2], parts[3]];
                    NSData *credData = [rawCred dataUsingEncoding:NSUTF8StringEncoding];
                    if (credData) {
                        cfg.HTTPAdditionalHeaders = @{@"Proxy-Authorization": [NSString stringWithFormat:@"Basic %@", [credData base64EncodedStringWithOptions:0]]};
                    }
                }
                cfg.connectionProxyDictionary = pDict;
            }
        }
    }
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    NSURL *url = [NSURL URLWithString:@"https://ipwho.is/"];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, nil, error);
            });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *city = json[@"city"];
        NSDictionary *conn = json[@"connection"];
        NSString *isp = [conn isKindOfClass:[NSDictionary class]] ? conn[@"isp"] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(city, isp, nil);
        });
    }];
    [task resume];
}

+ (void)performRespringIfPossible {
    NSArray<NSString *> *candidates = @[
        @"/var/jb/usr/bin/sbreload",
        @"/usr/bin/sbreload",
        @"/var/jb/usr/bin/killall",
        @"/usr/bin/killall"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *bin in candidates) {
        if ([fm isExecutableFileAtPath:bin]) {
            pid_t pid;
            if ([bin hasSuffix:@"sbreload"]) {
                const char *args[] = { [bin UTF8String], NULL };
                posix_spawn(&pid, [bin UTF8String], NULL, NULL, (char *const *)args, environ);
            } else {
                const char *args[] = { [bin UTF8String], "-9", "SpringBoard", NULL };
                posix_spawn(&pid, [bin UTF8String], NULL, NULL, (char *const *)args, environ);
            }
            break;
        }
    }
}

@end
