#import <UIKit/UIKit.h>

@interface NowEventTheme : NSObject

// Palette from colors.xml
+ (UIColor *)primaryDark;        // #1F1736
+ (UIColor *)primaryBlue;        // #1976D2
+ (UIColor *)accentOrange;       // #EC7200
+ (UIColor *)brightOrange;       // #FF8800
+ (UIColor *)screenBackground;   // #F8F9FC
+ (UIColor *)cardBackground;     // #FFFFFF
+ (UIColor *)textMuted;          // #6E6A7C
+ (UIColor *)textMutedLight;     // #7C788A
+ (UIColor *)badgeOpenText;      // #2E7D32
+ (UIColor *)badgeOpenBg;        // #E8F5E9
+ (UIColor *)badgeFullText;      // #C62828
+ (UIColor *)badgeFullBg;        // #FFEBEE
+ (UIColor *)dangerRed;          // #D32F2F
+ (UIColor *)grooveColor;        // #E5E6EE
+ (UIColor *)coreOffColor;       // #1E1E28
+ (UIColor *)warningColor;       // #FFB300
+ (UIColor *)progressBackground; // #ECEFF1

+ (UIColor *)colorFromHex:(NSString *)hexString;
+ (UIImage *)drawZaloIconWithSize:(CGSize)size;
+ (UIImage *)drawPowerIconWithSize:(CGSize)size color:(UIColor *)color;
+ (UIImage *)drawRadarIconWithSize:(CGSize)size color:(UIColor *)color;

@end
