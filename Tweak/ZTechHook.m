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

#pragma mark - Safe Embedded Fishhook (Supports Chained Fixups __got + Lazy/Non-Lazy Symbol Pointers)

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
typedef struct nlist_64 nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT_64
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
typedef struct nlist nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT
#endif

#ifndef SEG_DATA_CONST
#define SEG_DATA_CONST "__DATA_CONST"
#endif

#ifndef SEG_AUTH_CONST
#define SEG_AUTH_CONST "__AUTH_CONST"
#endif

struct zt_rebinding {
    const char *name;
    void *replacement;
    void *raw_target;
};

static struct zt_rebinding gRebindings[20];
static size_t gRebindingsCount = 0;

static inline uintptr_t zt_strip_ptr(const void *p) {
    return ((uintptr_t)p) & 0x0000000FFFFFFFFFULL;
}

static void perform_rebinding_with_section(section_t *section,
                                           intptr_t slide,
                                           nlist_t *symtab,
                                           char *strtab,
                                           uint32_t *indirect_symtab,
                                           uint32_t nindirectsyms,
                                           BOOL allowSymbolTableIndexMatch) {
    if (section->size < sizeof(void *)) return;
    void **indirect_symbol_bindings = (void **)((uintptr_t)slide + section->addr);

    vm_address_t page_start = (vm_address_t)indirect_symbol_bindings & ~(vm_address_t)(PAGE_SIZE - 1);
    vm_size_t page_len = (((vm_address_t)indirect_symbol_bindings + section->size) - page_start + PAGE_SIZE - 1) & ~(vm_size_t)(PAGE_SIZE - 1);
    kern_return_t kr = vm_protect(mach_task_self(), page_start, page_len, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        kr = vm_protect(mach_task_self(), page_start, page_len, FALSE, VM_PROT_READ | VM_PROT_WRITE);
        if (kr != KERN_SUCCESS) {
            return;
        }
    }

    uint32_t *indirect_symbol_indices = (allowSymbolTableIndexMatch && indirect_symtab && section->reserved1 < nindirectsyms)
        ? (indirect_symtab + section->reserved1)
        : NULL;

    uint count = (uint)(section->size / sizeof(void *));
    for (uint i = 0; i < count; i++) {
        void *cur_ptr = indirect_symbol_bindings[i];
        uintptr_t cur_stripped = zt_strip_ptr(cur_ptr);
        BOOL rebound = NO;

        // 1. Direct resolved pointer match (safe for S_REGULAR __got / __auth_got in LC_DYLD_CHAINED_FIXUPS)
        if (cur_stripped != 0) {
            for (size_t j = 0; j < gRebindingsCount; j++) {
                if (gRebindings[j].raw_target != NULL &&
                    cur_stripped == zt_strip_ptr(gRebindings[j].raw_target) &&
                    cur_stripped != zt_strip_ptr(gRebindings[j].replacement)) {
                    indirect_symbol_bindings[i] = gRebindings[j].replacement;
                    rebound = YES;
                    break;
                }
            }
        }
        if (rebound || !allowSymbolTableIndexMatch) continue;

        // 2. Classic indirect symbol table match (strictly only for S_LAZY_SYMBOL_POINTERS & S_NON_LAZY_SYMBOL_POINTERS)
        if (indirect_symbol_indices && symtab && strtab && (section->reserved1 + i) < nindirectsyms) {
            uint32_t symtab_index = indirect_symbol_indices[i];
            if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL ||
                symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
                continue;
            }
            uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
            char *symbol_name = strtab + strtab_offset;
            if (symbol_name[0] == '\0') continue;
            for (size_t j = 0; j < gRebindingsCount; j++) {
                if (strcmp(&symbol_name[1], gRebindings[j].name) == 0) {
                    indirect_symbol_bindings[i] = gRebindings[j].replacement;
                    break;
                }
            }
        }
    }
}

static void rebind_symbols_for_image(const struct mach_header *header, intptr_t slide) {
    Dl_info info;
    if (dladdr(header, &info) == 0 || !info.dli_fname) return;

    // Never rebind our own tweak or low-level libsystem/dyld/objc/CoreFoundation images
    if (strstr(info.dli_fname, "ZTechHook") != NULL ||
        strstr(info.dli_fname, "libsystem") != NULL ||
        strstr(info.dli_fname, "libdyld") != NULL ||
        strstr(info.dli_fname, "libobjc") != NULL ||
        strstr(info.dli_fname, "CoreFoundation") != NULL ||
        strstr(info.dli_fname, "libMobileGestalt") != NULL) {
        return;
    }

    // Rebind app binary, embedded frameworks, and high-level UIKit/WebKit/CFNetwork frameworks
    BOOL isAppImage = (strstr(info.dli_fname, "/Application/") != NULL ||
                       strstr(info.dli_fname, "Zalo") != NULL);
    BOOL isTargetSysFramework = (strstr(info.dli_fname, "/UIKit") != NULL ||
                                 strstr(info.dli_fname, "/WebKit") != NULL ||
                                 strstr(info.dli_fname, "/CFNetwork") != NULL);
    if (!isAppImage && !isTargetSysFramework) {
        return;
    }

    segment_command_t *cur_seg_cmd;
    segment_command_t *linkedit_segment = NULL;
    struct symtab_command *symtab_cmd = NULL;
    struct dysymtab_command *dysymtab_cmd = NULL;

    uintptr_t cur = (uintptr_t)header + sizeof(mach_header_t);
    for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (segment_command_t *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) {
                linkedit_segment = cur_seg_cmd;
            }
        } else if (cur_seg_cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command *)cur_seg_cmd;
        } else if (cur_seg_cmd->cmd == LC_DYSYMTAB) {
            dysymtab_cmd = (struct dysymtab_command *)cur_seg_cmd;
        }
    }

    nlist_t *symtab = NULL;
    char *strtab = NULL;
    uint32_t *indirect_symtab = NULL;
    uint32_t nindirectsyms = 0;

    if (symtab_cmd && dysymtab_cmd && linkedit_segment && dysymtab_cmd->nindirectsyms > 0) {
        uintptr_t linkedit_base = (uintptr_t)slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
        symtab = (nlist_t *)(linkedit_base + symtab_cmd->symoff);
        strtab = (char *)(linkedit_base + symtab_cmd->stroff);
        indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);
        nindirectsyms = dysymtab_cmd->nindirectsyms;
    }

    cur = (uintptr_t)header + sizeof(mach_header_t);
    for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (segment_command_t *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_DATA) != 0 &&
                strcmp(cur_seg_cmd->segname, SEG_DATA_CONST) != 0 &&
                strcmp(cur_seg_cmd->segname, SEG_AUTH_CONST) != 0) {
                continue;
            }
            for (uint j = 0; j < cur_seg_cmd->nsects; j++) {
                section_t *sect = (section_t *)(cur + sizeof(segment_command_t)) + j;
                uint32_t flags = sect->flags & SECTION_TYPE;
                BOOL isSymPtrSect = (flags == S_LAZY_SYMBOL_POINTERS || flags == S_NON_LAZY_SYMBOL_POINTERS);
                BOOL isChainedGotSect = (strncmp(sect->sectname, "__got", 5) == 0 ||
                                         strncmp(sect->sectname, "__auth_got", 10) == 0 ||
                                         strncmp(sect->sectname, "__la_symbol_ptr", 15) == 0 ||
                                         strncmp(sect->sectname, "__nl_symbol_ptr", 15) == 0);
                if (isSymPtrSect || isChainedGotSect) {
                    perform_rebinding_with_section(sect, slide, symtab, strtab, indirect_symtab, nindirectsyms, isSymPtrSect);
                }
            }
        }
    }
}

#pragma mark - Lock-Free Pre-Cached Profile, Pure C Buffers & Pre-Parsed Proxy State

static NSDictionary *gCachedProfile = nil;
static char gMachineCStr[64] = "iPhone17,2";
static char gRealMachineCStr[64] = "iPhone9,3";
static uint64_t gRamBytes = 8ULL * 1024ULL * 1024ULL * 1024ULL;
static NSString *gModelNameObj = @"iPhone 16 Pro Max";
static NSString *gMachineIdObj = @"iPhone17,2";
static NSString *gIosVersionObj = @"18.2.1";
static NSString *gUuidObj = @"7BD46FDA-D93D-45BD-9158-7178669502DD";
static NSString *gCarrierNameObj = @"Viettel";
static NSString *gActiveProxyObj = @"";
static float gBatteryFloat = 0.76f;

// Pre-created CFStringRefs for 100% Lock-Free MGCopyAnswer
static CFStringRef gCFMachineId = NULL;
static CFStringRef gCFModelName = NULL;
static CFStringRef gCFIosVersion = NULL;
static CFStringRef gCFUuid = NULL;

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

    if (gCFMachineId) CFRelease(gCFMachineId);
    if (gCFModelName) CFRelease(gCFModelName);
    if (gCFIosVersion) CFRelease(gCFIosVersion);
    if (gCFUuid) CFRelease(gCFUuid);

    gCFMachineId = CFStringCreateWithCString(kCFAllocatorDefault, [gMachineIdObj UTF8String], kCFStringEncodingUTF8);
    gCFModelName = CFStringCreateWithCString(kCFAllocatorDefault, [gModelNameObj UTF8String], kCFStringEncodingUTF8);
    gCFIosVersion = CFStringCreateWithCString(kCFAllocatorDefault, [gIosVersionObj UTF8String], kCFStringEncodingUTF8);
    gCFUuid = CFStringCreateWithCString(kCFAllocatorDefault, [gUuidObj UTF8String], kCFStringEncodingUTF8);

    ZTechRebuildCachedProxyState(gActiveProxyObj);
}

static NSDictionary *ZTechLoadProfileOnce(void) {
    if (gCachedProfile) {
        return gCachedProfile;
    }

    // 1. Check shared global paths FIRST (always updated by ZTech.app when user changes device)
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

    // 2. Check inside app's own sandbox container (written by ZTechDeviceDatabase & ZTechVaultManager)
    NSString *home = NSHomeDirectory();
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

    // 3. Check CFPreferences AnyApplication
    CFPropertyListRef cfVal = CFPreferencesCopyAppValue(CFSTR("ZTechGlobalProfile"), kCFPreferencesAnyApplication);
    if (cfVal) {
        if (CFGetTypeID(cfVal) == CFDictionaryGetTypeID()) {
            NSDictionary *d = (__bridge_transfer NSDictionary *)cfVal;
            NSDictionary *norm = ZTechNormalizeProfile(d);
            ZTechApplyCachedProfileValues(norm);
            return gCachedProfile;
        }
        CFRelease(cfVal);
    }

    NSDictionary *norm = ZTechNormalizeProfile(nil);
    ZTechApplyCachedProfileValues(norm);
    return gCachedProfile;
}

#pragma mark - Zero-Leak Proxy Enforcement (NSURLSession, CFNetwork, SocketStream & getifaddrs)

static void ZTechEnforceProxyOnConfiguration(NSURLSessionConfiguration *cfg) {
    if (!cfg || !gProxyEnabled || !gCachedProxyDict) return;
    @try {
        cfg.connectionProxyDictionary = gCachedProxyDict;
        if (@available(iOS 13.0, *)) {
            cfg.multipathServiceType = NSURLSessionMultipathServiceTypeNone;
        }
        NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:cfg.HTTPAdditionalHeaders ?: @{}];
        if (gCachedProxyAuthHeader.length > 0) {
            headers[@"Proxy-Authorization"] = gCachedProxyAuthHeader;
            headers[@"Authorization-Proxy"] = gCachedProxyAuthHeader;
        }
        [headers removeObjectForKey:@"X-Forwarded-For"];
        [headers removeObjectForKey:@"X-Real-IP"];
        [headers removeObjectForKey:@"Client-IP"];
        [headers removeObjectForKey:@"Forwarded"];
        cfg.HTTPAdditionalHeaders = headers;
    } @catch (NSException *e) {}
}

static NSURLRequest *ZTechSanitizeAndAuthorizeRequest(NSURLRequest *req) {
    if (!req || !gProxyEnabled) return req;
    @try {
        NSMutableURLRequest *mReq = [req isKindOfClass:[NSMutableURLRequest class]]
            ? (NSMutableURLRequest *)req
            : [req mutableCopy];
        if (gCachedProxyAuthHeader.length > 0 && ![mReq valueForHTTPHeaderField:@"Proxy-Authorization"]) {
            [mReq setValue:gCachedProxyAuthHeader forHTTPHeaderField:@"Proxy-Authorization"];
        }
        [mReq setValue:nil forHTTPHeaderField:@"X-Forwarded-For"];
        [mReq setValue:nil forHTTPHeaderField:@"X-Real-IP"];
        [mReq setValue:nil forHTTPHeaderField:@"Client-IP"];
        [mReq setValue:nil forHTTPHeaderField:@"Forwarded"];
        return mReq;
    } @catch (NSException *e) {
        return req;
    }
}

static NSURLSessionConfiguration *(*orig_defaultSessionConfig)(id, SEL) = NULL;
static NSURLSessionConfiguration *swizzled_defaultSessionConfig(id self, SEL _cmd) {
    NSURLSessionConfiguration *cfg = orig_defaultSessionConfig ? orig_defaultSessionConfig(self, _cmd) : nil;
    ZTechEnforceProxyOnConfiguration(cfg);
    return cfg;
}

static NSURLSessionConfiguration *(*orig_ephemeralSessionConfig)(id, SEL) = NULL;
static NSURLSessionConfiguration *swizzled_ephemeralSessionConfig(id self, SEL _cmd) {
    NSURLSessionConfiguration *cfg = orig_ephemeralSessionConfig ? orig_ephemeralSessionConfig(self, _cmd) : nil;
    ZTechEnforceProxyOnConfiguration(cfg);
    return cfg;
}

static NSURLSessionConfiguration *(*orig_backgroundSessionConfig)(id, SEL, NSString *) = NULL;
static NSURLSessionConfiguration *swizzled_backgroundSessionConfig(id self, SEL _cmd, NSString *identifier) {
    NSURLSessionConfiguration *cfg = orig_backgroundSessionConfig ? orig_backgroundSessionConfig(self, _cmd, identifier) : nil;
    ZTechEnforceProxyOnConfiguration(cfg);
    return cfg;
}

static NSURLSession *(*orig_sessionWithConfig)(id, SEL, NSURLSessionConfiguration *) = NULL;
static NSURLSession *swizzled_sessionWithConfig(id self, SEL _cmd, NSURLSessionConfiguration *configuration) {
    ZTechEnforceProxyOnConfiguration(configuration);
    return orig_sessionWithConfig ? orig_sessionWithConfig(self, _cmd, configuration) : nil;
}

static NSURLSession *(*orig_sessionWithConfigDelegateQueue)(id, SEL, NSURLSessionConfiguration *, id, NSOperationQueue *) = NULL;
static NSURLSession *swizzled_sessionWithConfigDelegateQueue(id self, SEL _cmd, NSURLSessionConfiguration *configuration, id delegate, NSOperationQueue *queue) {
    ZTechEnforceProxyOnConfiguration(configuration);
    return orig_sessionWithConfigDelegateQueue ? orig_sessionWithConfigDelegateQueue(self, _cmd, configuration, delegate, queue) : nil;
}

static NSURLSessionDataTask *(*orig_dataTaskWithRequest)(id, SEL, NSURLRequest *) = NULL;
static NSURLSessionDataTask *swizzled_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request) {
    NSURLRequest *cleanReq = ZTechSanitizeAndAuthorizeRequest(request);
    return orig_dataTaskWithRequest ? orig_dataTaskWithRequest(self, _cmd, cleanReq) : nil;
}

static NSURLSessionDataTask *(*orig_dataTaskWithRequestCompletion)(id, SEL, NSURLRequest *, id) = NULL;
static NSURLSessionDataTask *swizzled_dataTaskWithRequestCompletion(id self, SEL _cmd, NSURLRequest *request, id completionHandler) {
    NSURLRequest *cleanReq = ZTechSanitizeAndAuthorizeRequest(request);
    return orig_dataTaskWithRequestCompletion ? orig_dataTaskWithRequestCompletion(self, _cmd, cleanReq, completionHandler) : nil;
}

static CFDictionaryRef (*orig_CFNetworkCopySystemProxySettings)(void) = NULL;
static CFDictionaryRef hooked_CFNetworkCopySystemProxySettings(void) {
    if (gProxyEnabled && gCachedProxyDict != nil) {
        return (__bridge_retained CFDictionaryRef)[gCachedProxyDict copy];
    }
    return orig_CFNetworkCopySystemProxySettings ? orig_CFNetworkCopySystemProxySettings() : NULL;
}

static CFArrayRef (*orig_CFNetworkCopyProxiesForURL)(CFURLRef url, CFDictionaryRef proxySettings) = NULL;
static CFArrayRef hooked_CFNetworkCopyProxiesForURL(CFURLRef url, CFDictionaryRef proxySettings) {
    if (gProxyEnabled && gCachedCFProxyArray != nil) {
        return (__bridge_retained CFArrayRef)[gCachedCFProxyArray copy];
    }
    return orig_CFNetworkCopyProxiesForURL ? orig_CFNetworkCopyProxiesForURL(url, proxySettings) : NULL;
}

static void (*orig_CFStreamCreatePairWithSocketToHost)(CFAllocatorRef alloc, CFStringRef host, UInt32 port, CFReadStreamRef *readStream, CFWriteStreamRef *writeStream) = NULL;
static void hooked_CFStreamCreatePairWithSocketToHost(CFAllocatorRef alloc, CFStringRef host, UInt32 port, CFReadStreamRef *readStream, CFWriteStreamRef *writeStream) {
    if (orig_CFStreamCreatePairWithSocketToHost) {
        orig_CFStreamCreatePairWithSocketToHost(alloc, host, port, readStream, writeStream);
    }
    if (gProxyEnabled && gCachedProxyDict != nil) {
        CFStringRef propKey = gProxyIsSocks ? kCFStreamPropertySOCKSProxy : kCFStreamPropertyHTTPProxy;
        if (readStream && *readStream) {
            CFReadStreamSetProperty(*readStream, propKey, (__bridge CFTypeRef)gCachedProxyDict);
        }
        if (writeStream && *writeStream) {
            CFWriteStreamSetProperty(*writeStream, propKey, (__bridge CFTypeRef)gCachedProxyDict);
        }
    }
}

static int (*orig_getifaddrs)(struct ifaddrs **ifap) = NULL;
static int hooked_getifaddrs(struct ifaddrs **ifap) {
    int ret = orig_getifaddrs ? orig_getifaddrs(ifap) : -1;
    if (ret == 0 && ifap != NULL && *ifap != NULL && gProxyEnabled) {
        struct ifaddrs *cur = *ifap;
        while (cur != NULL) {
            if (cur->ifa_addr != NULL && cur->ifa_name != NULL && strncmp(cur->ifa_name, "lo", 2) != 0) {
                sa_family_t fam = cur->ifa_addr->sa_family;
                if (fam == AF_INET) {
                    struct sockaddr_in *sin = (struct sockaddr_in *)cur->ifa_addr;
                    sin->sin_addr.s_addr = gMaskedLocalIPv4;
                } else if (fam == AF_INET6) {
                    struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)cur->ifa_addr;
                    memset(&sin6->sin6_addr, 0, sizeof(struct in6_addr));
                    sin6->sin6_addr.s6_addr[0] = 0xfe;
                    sin6->sin6_addr.s6_addr[1] = 0x80;
                    sin6->sin6_addr.s6_addr[15] = 0x01;
                }
            }
            cur = cur->ifa_next;
        }
    }
    return ret;
}

#pragma mark - Lock-Free Pure C Function Hooks (uname, sysctlbyname, sysctl, MGCopyAnswer)

static int (*orig_uname)(struct utsname *buf) = NULL;
static int hooked_uname(struct utsname *buf) {
    int ret = orig_uname ? orig_uname(buf) : 0;
    if (buf != NULL) {
        strncpy(buf->machine, gMachineCStr, sizeof(buf->machine) - 1);
        buf->machine[sizeof(buf->machine) - 1] = '\0';
    }
    return ret;
}

static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int hooked_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name != NULL) {
        if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.product") == 0 || strcmp(name, "hw.model") == 0) {
            size_t len = strlen(gMachineCStr) + 1;
            if (oldp != NULL && oldlenp != NULL) {
                size_t copyLen = (*oldlenp < len) ? *oldlenp : len;
                memcpy(oldp, gMachineCStr, copyLen);
            }
            if (oldlenp != NULL) {
                *oldlenp = len;
            }
            return 0;
        } else if (strcmp(name, "hw.memsize") == 0 || strcmp(name, "hw.physmem") == 0) {
            if (oldp != NULL && oldlenp != NULL && *oldlenp >= sizeof(uint64_t)) {
                memcpy(oldp, &gRamBytes, sizeof(uint64_t));
                *oldlenp = sizeof(uint64_t);
                return 0;
            }
        }
    }
    return orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;
}

static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int hooked_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name != NULL && namelen == 2 && name[0] == CTL_HW) {
        if (name[1] == HW_MACHINE || name[1] == HW_MODEL) {
            size_t len = strlen(gMachineCStr) + 1;
            if (oldp != NULL && oldlenp != NULL) {
                size_t copyLen = (*oldlenp < len) ? *oldlenp : len;
                memcpy(oldp, gMachineCStr, copyLen);
            }
            if (oldlenp != NULL) {
                *oldlenp = len;
            }
            return 0;
        } else if (name[1] == HW_MEMSIZE || name[1] == HW_PHYSMEM) {
            if (oldp != NULL && oldlenp != NULL && *oldlenp >= sizeof(uint64_t)) {
                memcpy(oldp, &gRamBytes, sizeof(uint64_t));
                *oldlenp = sizeof(uint64_t);
                return 0;
            }
        }
    }
    return orig_sysctl ? orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen) : -1;
}

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef prop) = NULL;
static CFTypeRef hooked_MGCopyAnswer(CFStringRef prop) {
    if (prop != NULL) {
        if (CFStringCompare(prop, CFSTR("ProductType"), 0) == kCFCompareEqualTo ||
            CFStringCompare(prop, CFSTR("HWModelStr"), 0) == kCFCompareEqualTo) {
            if (gCFMachineId) return CFRetain(gCFMachineId);
        } else if (CFStringCompare(prop, CFSTR("MarketingName"), 0) == kCFCompareEqualTo ||
                   CFStringCompare(prop, CFSTR("DeviceName"), 0) == kCFCompareEqualTo ||
                   CFStringCompare(prop, CFSTR("UserAssignedDeviceName"), 0) == kCFCompareEqualTo) {
            if (gCFModelName) return CFRetain(gCFModelName);
        } else if (CFStringCompare(prop, CFSTR("ProductVersion"), 0) == kCFCompareEqualTo) {
            if (gCFIosVersion) return CFRetain(gCFIosVersion);
        } else if (CFStringCompare(prop, CFSTR("UniqueDeviceID"), 0) == kCFCompareEqualTo) {
            if (gCFUuid) return CFRetain(gCFUuid);
        }
    }
    return orig_MGCopyAnswer ? orig_MGCopyAnswer(prop) : NULL;
}

static CFTypeRef (*orig_IORegistryEntryCreateCFProperty)(uint32_t entry, CFStringRef key, CFAllocatorRef allocator, uint32_t options) = NULL;
static CFTypeRef hooked_IORegistryEntryCreateCFProperty(uint32_t entry, CFStringRef key, CFAllocatorRef allocator, uint32_t options) {
    CFTypeRef res = orig_IORegistryEntryCreateCFProperty ? orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options) : NULL;
    if (key != NULL) {
        if (CFStringCompare(key, CFSTR("IOPlatformSerialNumber"), 0) == kCFCompareEqualTo) {
            if (res) CFRelease(res);
            return gCFUuid ? CFRetain(gCFUuid) : NULL;
        } else if (CFStringCompare(key, CFSTR("serial-number"), 0) == kCFCompareEqualTo) {
            if (res && CFGetTypeID(res) == CFDataGetTypeID()) {
                CFRelease(res);
                const char *s = [gUuidObj UTF8String] ?: "F17X890ABCDE";
                return (CFTypeRef)CFDataCreate(kCFAllocatorDefault, (const UInt8 *)s, strlen(s) + 1);
            }
            if (res) CFRelease(res);
            return gCFUuid ? CFRetain(gCFUuid) : NULL;
        } else if (CFStringCompare(key, CFSTR("product-name"), 0) == kCFCompareEqualTo ||
                   CFStringCompare(key, CFSTR("model"), 0) == kCFCompareEqualTo ||
                   CFStringCompare(key, CFSTR("compatible"), 0) == kCFCompareEqualTo) {
            if (res && CFGetTypeID(res) == CFDataGetTypeID()) {
                CFRelease(res);
                const char *s = [gMachineIdObj UTF8String] ?: "iPhone17,2";
                return (CFTypeRef)CFDataCreate(kCFAllocatorDefault, (const UInt8 *)s, strlen(s) + 1);
            }
            if (res) CFRelease(res);
            return gCFMachineId ? CFRetain(gCFMachineId) : NULL;
        }
    }
    return res;
}

#pragma mark - Universal iPhone Lineup Spoofing Across NSDictionary, UILabel, NSAttributedString, JSON & WKWebView

static NSRegularExpression *gIPhoneModelRegex = nil;

static void ZTechInitRegexOnce(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *pattern = @"iPhone(?:\\d+,\\d+|\\s*(?:6s?|7|8|SE|X[SR]?|1[1-6]e?)(?:\\s*(?:Plus|Pro\\s*Max|Pro|Max|mini|\\(\\d+[a-z]*\\s*(?:generation|gen\\.?)\\)|\\(\\d{4}\\)))?)";
        gIPhoneModelRegex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                      options:NSRegularExpressionCaseInsensitive
                                                                        error:nil];
    });
}

static inline NSString *ZTechReplaceIPhoneStringIfNeeded(NSString *input) {
    if (![input isKindOfClass:[NSString class]] || input.length < 7) return input;
    if ([input rangeOfString:@"iPhone" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return input;
    }
    NSString *targetModel = gModelNameObj ?: @"iPhone 16 Pro Max";
    if ([input isEqualToString:targetModel]) {
        return input;
    }
    // Do not alter URLs, file paths, or bundle identifiers
    if ([input containsString:@"/"] || [input containsString:@"_"] || [input containsString:@"com."]) {
        return input;
    }
    // Exact match for raw machine IDs (e.g. "iPhone17,2", "iPhone12,8", "iPhone14,6", "iPhone9,3")
    if (gMachineIdObj.length > 0 && [input isEqualToString:gMachineIdObj]) {
        return targetModel;
    }
    ZTechInitRegexOnce();
    if (gIPhoneModelRegex != nil) {
        return [gIPhoneModelRegex stringByReplacingMatchesInString:input
                                                           options:0
                                                             range:NSMakeRange(0, input.length)
                                                        withTemplate:targetModel];
    }
    return input;
}

// Intercept NSDictionary lookups for machineId in Zalo's internal device mapping dictionary!
static id (*orig_NSDict_objectForKey)(id, SEL, id) = NULL;
static id swizzled_NSDict_objectForKey(id self, SEL _cmd, id aKey) {
    if ([aKey isKindOfClass:[NSString class]]) {
        NSString *k = (NSString *)aKey;
        if (gMachineIdObj.length > 0 && [k isEqualToString:gMachineIdObj]) {
            return gModelNameObj ?: @"iPhone 16 Pro Max";
        }
    }
    id val = orig_NSDict_objectForKey ? orig_NSDict_objectForKey(self, _cmd, aKey) : nil;
    if (val == nil && [aKey isKindOfClass:[NSString class]]) {
        NSString *k = (NSString *)aKey;
        if ([k hasPrefix:@"iPhone"]) {
            // Check if this dictionary is a hardware machineId -> Marketing Name map
            if (orig_NSDict_objectForKey(self, _cmd, @"iPhone10,1") != nil ||
                orig_NSDict_objectForKey(self, _cmd, @"iPhone11,2") != nil ||
                orig_NSDict_objectForKey(self, _cmd, @"iPhone9,1") != nil ||
                orig_NSDict_objectForKey(self, _cmd, @"iPhone8,1") != nil) {
                return gModelNameObj ?: @"iPhone 16 Pro Max";
            }
        }
    }
    return val;
}

static id (*orig_NSDict_objectForKeyedSubscript)(id, SEL, id) = NULL;
static id swizzled_NSDict_objectForKeyedSubscript(id self, SEL _cmd, id aKey) {
    if ([aKey isKindOfClass:[NSString class]]) {
        NSString *k = (NSString *)aKey;
        if (gMachineIdObj.length > 0 && [k isEqualToString:gMachineIdObj]) {
            return gModelNameObj ?: @"iPhone 16 Pro Max";
        }
    }
    id val = orig_NSDict_objectForKeyedSubscript ? orig_NSDict_objectForKeyedSubscript(self, _cmd, aKey) : nil;
    if (val == nil && [aKey isKindOfClass:[NSString class]]) {
        NSString *k = (NSString *)aKey;
        if ([k hasPrefix:@"iPhone"]) {
            if (orig_NSDict_objectForKeyedSubscript(self, _cmd, @"iPhone10,1") != nil ||
                orig_NSDict_objectForKeyedSubscript(self, _cmd, @"iPhone11,2") != nil ||
                orig_NSDict_objectForKeyedSubscript(self, _cmd, @"iPhone9,1") != nil ||
                orig_NSDict_objectForKeyedSubscript(self, _cmd, @"iPhone8,1") != nil) {
                return gModelNameObj ?: @"iPhone 16 Pro Max";
            }
        }
    }
    return val;
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
    if (gUuidObj.length > 0) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:gUuidObj];
        if (u) return u;
    }
    return orig_identifierForVendor ? orig_identifierForVendor(self, _cmd) : [NSUUID UUID];
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

static void (*orig_UILabel_setText)(id, SEL, NSString *) = NULL;
static void swizzled_UILabel_setText(id self, SEL _cmd, NSString *text) {
    text = ZTechReplaceIPhoneStringIfNeeded(text);
    if (orig_UILabel_setText) {
        orig_UILabel_setText(self, _cmd, text);
    }
}

static void (*orig_UILabel_setAttributedText)(id, SEL, NSAttributedString *) = NULL;
static void swizzled_UILabel_setAttributedText(id self, SEL _cmd, NSAttributedString *attrText) {
    if ([attrText isKindOfClass:[NSAttributedString class]] && attrText.length >= 7) {
        NSString *rawStr = attrText.string;
        if ([rawStr rangeOfString:@"iPhone" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NSString *replaced = ZTechReplaceIPhoneStringIfNeeded(rawStr);
            if (![replaced isEqualToString:rawStr]) {
                NSMutableAttributedString *mut = [attrText mutableCopy];
                [mut.mutableString setString:replaced];
                attrText = mut;
            }
        }
    }
    if (orig_UILabel_setAttributedText) {
        orig_UILabel_setAttributedText(self, _cmd, attrText);
    }
}

// Covers Texture / AsyncDisplayKit (ASTextNode), YYLabel, CATextLayer, and CoreText in Zalo!
static id (*orig_NSAttrStr_initWithString)(id, SEL, NSString *) = NULL;
static id swizzled_NSAttrStr_initWithString(id self, SEL _cmd, NSString *str) {
    str = ZTechReplaceIPhoneStringIfNeeded(str);
    return orig_NSAttrStr_initWithString ? orig_NSAttrStr_initWithString(self, _cmd, str) : nil;
}

static id (*orig_NSAttrStr_initWithStringAttrs)(id, SEL, NSString *, NSDictionary *) = NULL;
static id swizzled_NSAttrStr_initWithStringAttrs(id self, SEL _cmd, NSString *str, NSDictionary *attrs) {
    str = ZTechReplaceIPhoneStringIfNeeded(str);
    return orig_NSAttrStr_initWithStringAttrs ? orig_NSAttrStr_initWithStringAttrs(self, _cmd, str, attrs) : nil;
}

// Recursively sanitize parsed JSON objects if raw JSON data contained "iPhone"
static id ZTechSanitizeJSONObject(id obj, int depth) {
    if (!obj || depth > 8) return obj;
    if ([obj isKindOfClass:[NSString class]]) {
        return ZTechReplaceIPhoneStringIfNeeded((NSString *)obj);
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        NSMutableDictionary *mut = nil;
        for (id k in dict) {
            id v = dict[k];
            id newV = ZTechSanitizeJSONObject(v, depth + 1);
            if (newV != v) {
                if (!mut) mut = [dict mutableCopy];
                mut[k] = newV;
            }
        }
        return mut ?: dict;
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)obj;
        NSMutableArray *mut = nil;
        for (NSUInteger i = 0; i < arr.count; i++) {
            id v = arr[i];
            id newV = ZTechSanitizeJSONObject(v, depth + 1);
            if (newV != v) {
                if (!mut) mut = [arr mutableCopy];
                mut[i] = newV;
            }
        }
        return mut ?: arr;
    }
    return obj;
}

static id (*orig_JSONObjectWithData)(id, SEL, NSData *, NSJSONReadingOptions, NSError **) = NULL;
static id swizzled_JSONObjectWithData(id self, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **error) {
    id res = orig_JSONObjectWithData ? orig_JSONObjectWithData(self, _cmd, data, opt, error) : nil;
    if (res && [data isKindOfClass:[NSData class]] && data.length >= 6 && data.length < 524288) {
        if (memmem(data.bytes, data.length, "iPhone", 6) != NULL) {
            res = ZTechSanitizeJSONObject(res, 0);
        }
    }
    return res;
}

static id (*orig_WKWebView_initWithFrameConfig)(id, SEL, CGRect, id) = NULL;
static id swizzled_WKWebView_initWithFrameConfig(id self, SEL _cmd, CGRect frame, id configuration) {
    @try {
        if (configuration) {
            Class usrScriptCls = NSClassFromString(@"WKUserScript");
            SEL allocSel = sel_registerName("alloc");
            SEL initSel = sel_registerName("initWithSource:injectionTime:forMainFrameOnly:");
            SEL uccSel = sel_registerName("userContentController");
            SEL addSel = sel_registerName("addUserScript:");

            if (usrScriptCls && [configuration respondsToSelector:uccSel]) {
                id ucc = ((id (*)(id, SEL))objc_msgSend)(configuration, uccSel);
                if (ucc && [ucc respondsToSelector:addSel]) {
                    if (gProxyEnabled) {
                        NSString *rtcJs = @"(function(){"
                            @"var origRTC=window.RTCPeerConnection||window.webkitRTCPeerConnection;"
                            @"if(origRTC){"
                            @"var wrapped=function(cfg,con){"
                            @"cfg=cfg||{};cfg.iceServers=[];cfg.iceTransportPolicy='relay';"
                            @"return new origRTC(cfg,con);"
                            @"};"
                            @"wrapped.prototype=origRTC.prototype;"
                            @"window.RTCPeerConnection=wrapped;window.webkitRTCPeerConnection=wrapped;"
                            @"}"
                            @"})();";
                        id s0 = ((id (*)(id, SEL))objc_msgSend)(usrScriptCls, allocSel);
                        if (s0 && [s0 respondsToSelector:initSel]) {
                            id u0 = ((id (*)(id, SEL, NSString *, NSInteger, BOOL))objc_msgSend)(s0, initSel, rtcJs, 0, NO);
                            if (u0) ((void (*)(id, SEL, id))objc_msgSend)(ucc, addSel, u0);
                        }
                    }

                    NSString *safeModel = [(gModelNameObj ?: @"iPhone 16 Pro Max") stringByReplacingOccurrencesOfString:@"'" withString:@""];
                    NSString *osVerUnderscore = [(gIosVersionObj ?: @"18.2.1") stringByReplacingOccurrencesOfString:@"." withString:@"_"];
                    NSString *customUA = [NSString stringWithFormat:@"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", osVerUnderscore];
                    NSString *js = [NSString stringWithFormat:
                        @"(function(){"
                        @"var m='%@';"
                        @"var ua='%@';"
                        @"try{Object.defineProperty(navigator,'userAgent',{get:function(){return ua;}});}catch(e){}"
                        @"var re=/iPhone(?:\\d+,\\d+|\\s*(?:6s?|7|8|SE|X[SR]?|1[1-6]e?)(?:\\s*(?:Plus|Pro\\s*Max|Pro|Max|mini|\\(\\d+[a-z]*\\s*(?:generation|gen\\.?)\\)|\\(\\d{4}\\)))?)/gi;"
                        @"function fix(){"
                        @"if(!document.body||!document.body.innerText||document.body.innerText.indexOf('iPhone')===-1)return;"
                        @"var w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,null,false),n;"
                        @"while((n=w.nextNode())){"
                        @"if(n.nodeValue&&n.nodeValue.indexOf('iPhone')!==-1&&n.nodeValue.indexOf(m)===-1){"
                        @"n.nodeValue=n.nodeValue.replace(re,m);"
                        @"}"
                        @"}"
                        @"}"
                        @"setTimeout(fix,150);setTimeout(fix,500);setInterval(fix,900);"
                        @"})();", safeModel, customUA];

                    id s1 = ((id (*)(id, SEL))objc_msgSend)(usrScriptCls, allocSel);
                    if (s1 && [s1 respondsToSelector:initSel]) {
                        id u1 = ((id (*)(id, SEL, NSString *, NSInteger, BOOL))objc_msgSend)(s1, initSel, js, 1, NO);
                        if (u1) ((void (*)(id, SEL, id))objc_msgSend)(ucc, addSel, u1);
                    }
                }
            }
        }
    } @catch (NSException *e) {}
    id webView = orig_WKWebView_initWithFrameConfig ? orig_WKWebView_initWithFrameConfig(self, _cmd, frame, configuration) : nil;
    if (webView && [webView respondsToSelector:sel_registerName("setCustomUserAgent:")]) {
        NSString *osVerUnderscore = [(gIosVersionObj ?: @"18.2.1") stringByReplacingOccurrencesOfString:@"." withString:@"_"];
        NSString *customUA = [NSString stringWithFormat:@"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", osVerUnderscore];
        ((void (*)(id, SEL, id))objc_msgSend)(webView, sel_registerName("setCustomUserAgent:"), customUA);
    }
    return webView;
}

#pragma mark - Safe Container Repair, Vault Snapshot/Restore & In-Process Reset

static void ZTechEnsureContainerDirectoriesExist(NSString *home) {
    if (!home || home.length == 0) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *requiredDirs = @[
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
    for (NSString *sub in requiredDirs) {
        NSString *p = [home stringByAppendingPathComponent:sub];
        if (![fm fileExistsAtPath:p]) {
            [fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
        }
        chmod([p UTF8String], 0777);
    }
    NSString *globalPrefsLink = [home stringByAppendingPathComponent:@"Library/Preferences/.GlobalPreferences.plist"];
    if (![fm fileExistsAtPath:globalPrefsLink]) {
        symlink("/private/var/mobile/Library/Preferences/.GlobalPreferences.plist", [globalPrefsLink UTF8String]);
    }
}

static void ZTechSnapshotZaloKeychainAndPrefsAsync(NSString *bundleId) {
    if (!bundleId || bundleId.length == 0) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        @autoreleasepool {
            @try {
                NSString *home = NSHomeDirectory();
                NSString *docsDir = [home stringByAppendingPathComponent:@"Documents"];

                NSString *markerPath = [docsDir stringByAppendingPathComponent:@"_zt_zalo_marker.txt"];
                [bundleId writeToFile:markerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                chmod([markerPath UTF8String], 0666);

                NSDictionary *dom = [[NSUserDefaults standardUserDefaults] persistentDomainForName:bundleId];
                if (dom && dom.count > 0) {
                    NSString *prefsSnapPath = [docsDir stringByAppendingPathComponent:@"_zt_prefs_snapshot.plist"];
                    [dom writeToFile:prefsSnapPath atomically:YES];
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
    });
}

static void ZTechCheckAndPerformInAppRestore(NSString *bundleId) {
    @try {
        NSString *home = NSHomeDirectory();
        NSString *docsDir = [home stringByAppendingPathComponent:@"Documents"];
        NSString *triggerFile = [docsDir stringByAppendingPathComponent:@"_zt_restore_trigger.txt"];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:triggerFile]) {
            return;
        }

        [fm removeItemAtPath:triggerFile error:nil];

        CFTypeRef cfToken = CFPreferencesCopyAppValue(CFSTR("ZTechResetToken"), kCFPreferencesAnyApplication);
        if (cfToken && CFGetTypeID(cfToken) == CFStringGetTypeID()) {
            NSString *globalToken = [(__bridge NSString *)cfToken copy];
            NSString *tokenFile = [docsDir stringByAppendingPathComponent:@"_zt_last_reset_token.txt"];
            [globalToken writeToFile:tokenFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        if (cfToken) CFRelease(cfToken);

        NSString *prefsSnapPath = [docsDir stringByAppendingPathComponent:@"_zt_prefs_snapshot.plist"];
        NSDictionary *savedPrefs = [NSDictionary dictionaryWithContentsOfFile:prefsSnapPath];
        if (savedPrefs && [savedPrefs isKindOfClass:[NSDictionary class]] && bundleId.length > 0) {
            [[NSUserDefaults standardUserDefaults] setPersistentDomain:savedPrefs forName:bundleId];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }

        NSString *kcSnapPath = [docsDir stringByAppendingPathComponent:@"_zt_keychain_snapshot.plist"];
        NSArray *savedKc = [NSArray arrayWithContentsOfFile:kcSnapPath];
        if (savedKc && [savedKc isKindOfClass:[NSArray class]]) {
            NSArray *secClasses = @[
                (__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecClassInternetPassword
            ];
            for (id secClass in secClasses) {
                NSDictionary *delQuery = @{(__bridge id)kSecClass: secClass};
                SecItemDelete((__bridge CFDictionaryRef)delQuery);
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
    } @catch (NSException *e) {}
}

static void ZTechWipeSubfolderContentsOnly(NSString *folderPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:folderPath error:nil];
    for (NSString *item in items) {
        if ([item isEqualToString:@"_zt_last_reset_token.txt"] ||
            [item isEqualToString:@"_zt_restore_trigger.txt"] ||
            [item isEqualToString:@"_zt_zalo_marker.txt"] ||
            [item isEqualToString:@"_zt_active_profile.plist"] ||
            [item hasPrefix:@".GlobalPreferences"] ||
            [item hasPrefix:@".com.apple."] ||
            [item isEqualToString:@"SplashBoard"] ||
            [item isEqualToString:@"Caches"] ||
            [item isEqualToString:@"Preferences"]) {
            continue;
        }
        [fm removeItemAtPath:[folderPath stringByAppendingPathComponent:item] error:nil];
    }
}

static void ZTechCheckAndPerformInAppReset(NSString *bundleId) {
    @try {
        NSString *lowerBundle = [bundleId lowercaseString];
        if (![lowerBundle containsString:@"zalo"] &&
            ![lowerBundle containsString:@"vng"] &&
            ![lowerBundle containsString:@"tiktok"] &&
            ![lowerBundle containsString:@"musical"] &&
            ![lowerBundle containsString:@"shopee"]) {
            return;
        }

        NSString *home = NSHomeDirectory();
        ZTechEnsureContainerDirectoriesExist(home);

        if ([lowerBundle containsString:@"zalo"] || [lowerBundle containsString:@"vng"]) {
            NSString *markerPath = [home stringByAppendingPathComponent:@"Documents/_zt_zalo_marker.txt"];
            [bundleId writeToFile:markerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            chmod([markerPath UTF8String], 0666);
        }

        ZTechCheckAndPerformInAppRestore(bundleId);

        CFTypeRef cfToken = CFPreferencesCopyAppValue(CFSTR("ZTechResetToken"), kCFPreferencesAnyApplication);
        NSString *globalToken = nil;
        if (cfToken && CFGetTypeID(cfToken) == CFStringGetTypeID()) {
            globalToken = [(__bridge NSString *)cfToken copy];
        }
        if (cfToken) CFRelease(cfToken);

        if (!globalToken || globalToken.length == 0) return;

        NSString *tokenFile = [home stringByAppendingPathComponent:@"Documents/_zt_last_reset_token.txt"];
        NSString *lastToken = [NSString stringWithContentsOfFile:tokenFile encoding:NSUTF8StringEncoding error:nil];

        if (!lastToken || ![lastToken isEqualToString:globalToken]) {
            NSArray *secClasses = @[
                (__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecClassInternetPassword,
                (__bridge id)kSecClassCertificate,
                (__bridge id)kSecClassKey,
                (__bridge id)kSecClassIdentity
            ];
            for (id secClass in secClasses) {
                NSDictionary *query = @{(__bridge id)kSecClass: secClass};
                SecItemDelete((__bridge CFDictionaryRef)query);
            }

            if (bundleId.length > 0) {
                [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleId];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }

            NSArray<NSString *> *subDirs = @[
                @"Documents",
                @"tmp",
                @"Library/Caches",
                @"Library/Cookies",
                @"Library/WebKit",
                @"Library/Application Support"
            ];
            for (NSString *sub in subDirs) {
                ZTechWipeSubfolderContentsOnly([home stringByAppendingPathComponent:sub]);
            }

            ZTechEnsureContainerDirectoriesExist(home);
            [globalToken writeToFile:tokenFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    } @catch (NSException *exception) {
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

        if (!bundleId || !bundlePath ||
            [bundleId isEqualToString:@"com.ztech.devicechanger"] ||
            [bundleId hasPrefix:@"com.apple."] ||
            ![bundlePath containsString:@"/Application"] ||
            ![bundlePath hasSuffix:@".app"]) {
            return;
        }

        struct utsname realUts;
        if (uname(&realUts) == 0 && realUts.machine[0] != '\0') {
            strncpy(gRealMachineCStr, realUts.machine, sizeof(gRealMachineCStr) - 1);
            gRealMachineCStr[sizeof(gRealMachineCStr) - 1] = '\0';
        }

        ZTechEnsureContainerDirectoriesExist(NSHomeDirectory());

        Boolean keyExists = false;
        Boolean isLicenseValid = CFPreferencesGetAppBooleanValue(CFSTR("ZTechLicenseValid"), kCFPreferencesAnyApplication, &keyExists);
        if (keyExists && !isLicenseValid) {
            return;
        }

        // Matches any iPhone marketing name (iPhone 6..16 Pro Max) OR raw machine ID (iPhone9,3 / iPhone17,2)
        gIPhoneModelRegex = [NSRegularExpression regularExpressionWithPattern:@"iPhone(?:\\s*(?:6s?|7|8|SE|X[SR]?|1[1-6]e?)(?:\\s*(?:Plus|Pro\\s*Max|Pro|mini))?|\\d+,\\d+)"
                                                                      options:NSRegularExpressionCaseInsensitive
                                                                        error:nil];

        ZTechLoadProfileOnce();
        ZTechCheckAndPerformInAppReset(bundleId);

        NSString *lowerBundle = [bundleId lowercaseString];
        if ([lowerBundle containsString:@"zalo"] || [lowerBundle containsString:@"vng"]) {
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification * _Nonnull note) {
                gCachedProfile = nil;
                ZTechLoadProfileOnce();
                ZTechSnapshotZaloKeychainAndPrefsAsync(bundleId);
            }];
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification * _Nonnull note) {
                ZTechSnapshotZaloKeychainAndPrefsAsync(bundleId);
            }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                ZTechSnapshotZaloKeychainAndPrefsAsync(bundleId);
            });
        }

        // 1. Objective-C Swizzles on UIDevice, NSProcessInfo, NSURLSessionConfiguration, NSURLSession
        Class uiDeviceCls = [UIDevice class];
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

        Class procCls = [NSProcessInfo class];
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

        Class urlCfgCls = [NSURLSessionConfiguration class];
        Method mDefCfg = class_getClassMethod(urlCfgCls, @selector(defaultSessionConfiguration));
        if (mDefCfg) {
            orig_defaultSessionConfig = (void *)method_getImplementation(mDefCfg);
            method_setImplementation(mDefCfg, (IMP)swizzled_defaultSessionConfig);
        }
        Method mEphCfg = class_getClassMethod(urlCfgCls, @selector(ephemeralSessionConfiguration));
        if (mEphCfg) {
            orig_ephemeralSessionConfig = (void *)method_getImplementation(mEphCfg);
            method_setImplementation(mEphCfg, (IMP)swizzled_ephemeralSessionConfig);
        }
        Method mBgCfg = class_getClassMethod(urlCfgCls, @selector(backgroundSessionConfigurationWithIdentifier:));
        if (mBgCfg) {
            orig_backgroundSessionConfig = (void *)method_getImplementation(mBgCfg);
            method_setImplementation(mBgCfg, (IMP)swizzled_backgroundSessionConfig);
        }

        Class urlSessCls = [NSURLSession class];
        Method mSessCfg = class_getClassMethod(urlSessCls, @selector(sessionWithConfiguration:));
        if (mSessCfg) {
            orig_sessionWithConfig = (void *)method_getImplementation(mSessCfg);
            method_setImplementation(mSessCfg, (IMP)swizzled_sessionWithConfig);
        }
        Method mSessCfgDel = class_getClassMethod(urlSessCls, @selector(sessionWithConfiguration:delegate:delegateQueue:));
        if (mSessCfgDel) {
            orig_sessionWithConfigDelegateQueue = (void *)method_getImplementation(mSessCfgDel);
            method_setImplementation(mSessCfgDel, (IMP)swizzled_sessionWithConfigDelegateQueue);
        }
        Method mDataTaskReq = class_getInstanceMethod(urlSessCls, @selector(dataTaskWithRequest:));
        if (mDataTaskReq) {
            orig_dataTaskWithRequest = (void *)method_getImplementation(mDataTaskReq);
            method_setImplementation(mDataTaskReq, (IMP)swizzled_dataTaskWithRequest);
        }
        Method mDataTaskReqComp = class_getInstanceMethod(urlSessCls, @selector(dataTaskWithRequest:completionHandler:));
        if (mDataTaskReqComp) {
            orig_dataTaskWithRequestCompletion = (void *)method_getImplementation(mDataTaskReqComp);
            method_setImplementation(mDataTaskReqComp, (IMP)swizzled_dataTaskWithRequestCompletion);
        }

        // 2. Zalo-Specific Deep Hooks (NSDictionary machineId Lookup, UILabel, NSAttributedString/ASTextNode, JSON & WKWebView)
        if ([lowerBundle containsString:@"zalo"] || [lowerBundle containsString:@"vng"]) {
            ZTechInitRegexOnce();
            Class dictCls = NSClassFromString(@"__NSDictionaryI") ?: [NSDictionary class];
            Method mObjKey = class_getInstanceMethod(dictCls, @selector(objectForKey:));
            if (mObjKey) {
                orig_NSDict_objectForKey = (void *)method_getImplementation(mObjKey);
                method_setImplementation(mObjKey, (IMP)swizzled_NSDict_objectForKey);
            }
            Method mObjSub = class_getInstanceMethod(dictCls, @selector(objectForKeyedSubscript:));
            if (mObjSub) {
                orig_NSDict_objectForKeyedSubscript = (void *)method_getImplementation(mObjSub);
                method_setImplementation(mObjSub, (IMP)swizzled_NSDict_objectForKeyedSubscript);
            }

            Class lblCls = [UILabel class];
            Method mSetTxt = class_getInstanceMethod(lblCls, @selector(setText:));
            if (mSetTxt) {
                orig_UILabel_setText = (void *)method_getImplementation(mSetTxt);
                method_setImplementation(mSetTxt, (IMP)swizzled_UILabel_setText);
            }
            Method mSetAttrTxt = class_getInstanceMethod(lblCls, @selector(setAttributedText:));
            if (mSetAttrTxt) {
                orig_UILabel_setAttributedText = (void *)method_getImplementation(mSetAttrTxt);
                method_setImplementation(mSetAttrTxt, (IMP)swizzled_UILabel_setAttributedText);
            }

            Class attrStrCls = NSClassFromString(@"NSConcreteAttributedString") ?: [NSAttributedString class];
            Method mAttrInit1 = class_getInstanceMethod(attrStrCls, @selector(initWithString:));
            if (mAttrInit1) {
                orig_NSAttrStr_initWithString = (void *)method_getImplementation(mAttrInit1);
                method_setImplementation(mAttrInit1, (IMP)swizzled_NSAttrStr_initWithString);
            }
            Method mAttrInit2 = class_getInstanceMethod(attrStrCls, @selector(initWithString:attributes:));
            if (mAttrInit2) {
                orig_NSAttrStr_initWithStringAttrs = (void *)method_getImplementation(mAttrInit2);
                method_setImplementation(mAttrInit2, (IMP)swizzled_NSAttrStr_initWithStringAttrs);
            }

            Class jsonCls = [NSJSONSerialization class];
            Method mJsonData = class_getClassMethod(jsonCls, @selector(JSONObjectWithData:options:error:));
            if (mJsonData) {
                orig_JSONObjectWithData = (void *)method_getImplementation(mJsonData);
                method_setImplementation(mJsonData, (IMP)swizzled_JSONObjectWithData);
            }

            Class wkCls = NSClassFromString(@"WKWebView");
            if (wkCls) {
                Method mWkInit = class_getInstanceMethod(wkCls, sel_registerName("initWithFrame:configuration:"));
                if (mWkInit) {
                    orig_WKWebView_initWithFrameConfig = (void *)method_getImplementation(mWkInit);
                    method_setImplementation(mWkInit, (IMP)swizzled_WKWebView_initWithFrameConfig);
                }
            }
        }

        // 3. GPU (Metal) & Carrier Swizzles
        Class mtlDevCls = NSClassFromString(@"_MTLDevice");
        if (!mtlDevCls) mtlDevCls = NSClassFromString(@"MTLDevice");
        if (mtlDevCls) {
            Method mGpu = class_getInstanceMethod(mtlDevCls, @selector(name));
            if (mGpu) {
                orig_MTLDevice_name = (void *)method_getImplementation(mGpu);
                method_setImplementation(mGpu, (IMP)swizzled_MTLDevice_name);
            }
        }
        void *raw_MTL = dlsym(RTLD_DEFAULT, "MTLCreateSystemDefaultDevice");
        if (raw_MTL) {
            id (*createDev)(void) = (id (*)(void))raw_MTL;
            id dev = createDev();
            if (dev) {
                Class instCls = [dev class];
                Method mGpu = class_getInstanceMethod(instCls, @selector(name));
                if (mGpu && method_getImplementation(mGpu) != (IMP)swizzled_MTLDevice_name) {
                    orig_MTLDevice_name = (void *)method_getImplementation(mGpu);
                    method_setImplementation(mGpu, (IMP)swizzled_MTLDevice_name);
                }
            }
        }

        Class ctCarrierCls = NSClassFromString(@"CTCarrier");
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
        }

        // 4. Safe Mach-O Symbol Rebinding (Covers __got, __auth_got, __la_symbol_ptr, __nl_symbol_ptr)
        void *raw_uname = dlsym(RTLD_DEFAULT, "uname");
        void *raw_sysctlbyname = dlsym(RTLD_DEFAULT, "sysctlbyname");
        void *raw_sysctl = dlsym(RTLD_DEFAULT, "sysctl");
        void *raw_MGCopyAnswer = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
        void *raw_CFProxy = dlsym(RTLD_DEFAULT, "CFNetworkCopySystemProxySettings");
        void *raw_CFProxiesForURL = dlsym(RTLD_DEFAULT, "CFNetworkCopyProxiesForURL");
        void *raw_CFStreamSocket = dlsym(RTLD_DEFAULT, "CFStreamCreatePairWithSocketToHost");
        void *raw_getifaddrs = dlsym(RTLD_DEFAULT, "getifaddrs");
        void *raw_IORegistry = dlsym(RTLD_DEFAULT, "IORegistryEntryCreateCFProperty");

        orig_uname = raw_uname;
        orig_sysctlbyname = raw_sysctlbyname;
        orig_sysctl = raw_sysctl;
        orig_MGCopyAnswer = raw_MGCopyAnswer;
        orig_CFNetworkCopySystemProxySettings = raw_CFProxy;
        orig_CFNetworkCopyProxiesForURL = raw_CFProxiesForURL;
        orig_CFStreamCreatePairWithSocketToHost = raw_CFStreamSocket;
        orig_getifaddrs = raw_getifaddrs;
        if (raw_IORegistry) {
            orig_IORegistryEntryCreateCFProperty = raw_IORegistry;
        }

        gRebindings[0] = (struct zt_rebinding){"uname", (void *)hooked_uname, raw_uname};
        gRebindings[1] = (struct zt_rebinding){"sysctlbyname", (void *)hooked_sysctlbyname, raw_sysctlbyname};
        gRebindings[2] = (struct zt_rebinding){"sysctl", (void *)hooked_sysctl, raw_sysctl};
        gRebindings[3] = (struct zt_rebinding){"MGCopyAnswer", (void *)hooked_MGCopyAnswer, raw_MGCopyAnswer};
        gRebindings[4] = (struct zt_rebinding){"CFNetworkCopySystemProxySettings", (void *)hooked_CFNetworkCopySystemProxySettings, raw_CFProxy};
        gRebindings[5] = (struct zt_rebinding){"CFNetworkCopyProxiesForURL", (void *)hooked_CFNetworkCopyProxiesForURL, raw_CFProxiesForURL};
        gRebindings[6] = (struct zt_rebinding){"CFStreamCreatePairWithSocketToHost", (void *)hooked_CFStreamCreatePairWithSocketToHost, raw_CFStreamSocket};
        gRebindings[7] = (struct zt_rebinding){"getifaddrs", (void *)hooked_getifaddrs, raw_getifaddrs};
        gRebindingsCount = 8;
        if (raw_IORegistry) {
            gRebindings[gRebindingsCount++] = (struct zt_rebinding){"IORegistryEntryCreateCFProperty", (void *)hooked_IORegistryEntryCreateCFProperty, raw_IORegistry};
        }

        _dyld_register_func_for_add_image(rebind_symbols_for_image);
    }
}
