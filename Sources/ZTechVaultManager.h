#import <Foundation/Foundation.h>
#import "ZTechDeviceDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZTechVaultAccount : NSObject

@property (nonatomic, copy) NSString *accountId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *proxyString;
@property (nonatomic, copy) NSString *createdAt;
@property (nonatomic, strong) NSDictionary *deviceProfileDict;

- (NSDictionary *)toDictionary;
+ (nullable instancetype)fromDictionary:(NSDictionary *)dict;
- (NSString *)shortDeviceSummary;
- (NSString *)proxyDisplayText;

@end

@interface ZTechVaultManager : NSObject

+ (NSArray<ZTechVaultAccount *> *)listSavedAccounts;
+ (nullable NSString *)activeAccountId;

+ (nullable ZTechVaultAccount *)saveCurrentZaloSessionWithTitle:(nullable NSString *)title
                                                          proxy:(nullable NSString *)proxyString
                                                        profile:(ZTechDeviceProfile *)profile
                                                          error:(NSError **)error;

+ (BOOL)restoreAndLaunchAccount:(ZTechVaultAccount *)account
                     outProfile:(ZTechDeviceProfile * _Nullable * _Nullable)outProfile
                          error:(NSError **)error;

+ (BOOL)updateAccount:(NSString *)accountId
                title:(nullable NSString *)title
          proxyString:(nullable NSString *)proxyString;

+ (BOOL)deleteAccountWithId:(NSString *)accountId;

+ (nullable NSString *)findZaloDataContainerPath;
+ (nullable NSString *)findAIDA64DataContainerPath;
+ (NSDictionary<NSString *, NSString *> *)findZaloAppGroupContainers;

+ (void)killZaloProcess;
+ (void)cleanSafariCookiesAndWebsiteData;
+ (void)launchZaloApp;

+ (void)setSystemAirplaneMode:(BOOL)enabled;
+ (BOOL)isSystemAirplaneModeEnabled;

@end

NS_ASSUME_NONNULL_END
