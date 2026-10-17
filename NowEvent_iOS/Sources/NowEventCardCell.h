#import <UIKit/UIKit.h>

@interface NowEventItem : NSObject
@property (nonatomic, copy) NSString *eventId;
@property (nonatomic, copy) NSString *tenSuKien;
@property (nonatomic, copy) NSString *thoiGian;
@property (nonatomic, copy) NSString *trangThai;
@property (nonatomic, assign) NSInteger soLuongHienTai;
@property (nonatomic, assign) NSInteger soLuongToiDa;
@property (nonatomic, assign) BOOL conSlot;

- (CGFloat)progressFraction;
@end

@interface NowEventCardCell : UITableViewCell

- (void)configureWithEvent:(NowEventItem *)event;

@end
