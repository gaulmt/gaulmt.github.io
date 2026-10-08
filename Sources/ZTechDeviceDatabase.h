#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ZTechModelTierFilter) {
    ZTechModelTierAll = 0,        // iPhone 6s/SE -> iPhone 16 Pro Max (37 models)
    ZTechModelTierHighEnd = 1,    // iPhone 14 -> iPhone 16 Pro Max
    ZTechModelTierIPhone16 = 2    // Only iPhone 16 / 16 Plus / 16 Pro / 16 Pro Max / 16e
};

@interface ZTechDeviceProfile : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *modelName;
@property (nonatomic, copy) NSString *machineId;
@property (nonatomic, copy) NSString *iosVersion;
@property (nonatomic, assign) NSInteger batteryPercent;
@property (nonatomic, copy) NSString *carrier;
@property (nonatomic, copy) NSString *wifiSsid;
@property (nonatomic, copy) NSString *city;
@property (nonatomic, assign) NSInteger contactsCount;
@property (nonatomic, copy) NSString *chipName;
@property (nonatomic, assign) NSInteger ramGB;
@property (nonatomic, copy) NSString *screenKey;
@property (nonatomic, copy) NSString *activeProxy;
@property (nonatomic, assign) NSInteger writtenFilesCount;
@property (nonatomic, assign) NSInteger successItemsCount;

- (NSString *)summaryLine1;
- (NSString *)summaryLine2;
- (NSString *)fullReportTextWithFlags:(BOOL)lockModel
                          respringAfter:(BOOL)respring
                             sameScreen:(BOOL)sameScreen
                              matchChip:(BOOL)matchChip;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;

@end

@interface ZTechDeviceDatabase : NSObject

+ (ZTechDeviceProfile *)loadOrCreateDefaultProfile;
+ (ZTechDeviceProfile *)generateProfileWithLockRealModel:(BOOL)lockModel
                                              sameScreen:(BOOL)sameScreen
                                               matchChip:(BOOL)matchChip
                                               modelTier:(ZTechModelTierFilter)modelTier
                                             currentCity:(NSString *)currentCity;
+ (BOOL)writeProfileFiles:(ZTechDeviceProfile *)profile error:(NSError **)error;
+ (NSInteger)cleanResetAllProfileDataAndCache;
+ (void)syncLocationByIPWithCompletion:(void (^)(NSString *city, NSString *isp, NSError *error))completion;
+ (void)performRespringIfPossible;

@end
