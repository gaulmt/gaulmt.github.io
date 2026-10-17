#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, NowEventChargeState) {
    NowEventChargeStateStandby,
    NowEventChargeStateCharging,
    NowEventChargeStateAborting,
    NowEventChargeStateActive
};

@protocol NowEventHoldToChargeViewDelegate <NSObject>
@optional
- (void)holdToChargeViewDidStartCharging;
- (void)holdToChargeViewDidChangeProgress:(NSInteger)percent;
- (void)holdToChargeViewDidAbort;
- (void)holdToChargeViewDidCompleteCharge;
- (void)holdToChargeViewDidIgniteSuccess;
@end

@interface NowEventHoldToChargeView : UIView

@property (nonatomic, weak) id<NowEventHoldToChargeViewDelegate> delegate;
@property (nonatomic, assign, readonly) NowEventChargeState currentState;
@property (nonatomic, assign, readonly) CGFloat progress;

- (void)performSuccessIgnition;
- (void)resetToStandby;

@end
