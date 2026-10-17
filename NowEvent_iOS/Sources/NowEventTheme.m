#import "NowEventTheme.h"

@implementation NowEventTheme

+ (UIColor *)colorFromHex:(NSString *)hexString {
    NSString *clean = [[hexString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([clean hasPrefix:@"#"]) {
        clean = [clean substringFromIndex:1];
    }
    
    unsigned int rgbValue = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&rgbValue];
    
    if (clean.length == 8) {
        // AARRGGBB
        CGFloat a = ((rgbValue & 0xFF000000) >> 24) / 255.0;
        CGFloat r = ((rgbValue & 0x00FF0000) >> 16) / 255.0;
        CGFloat g = ((rgbValue & 0x0000FF00) >> 8) / 255.0;
        CGFloat b = (rgbValue & 0x000000FF) / 255.0;
        return [UIColor colorWithRed:r green:g blue:b alpha:a];
    } else {
        // RRGGBB
        CGFloat r = ((rgbValue & 0xFF0000) >> 16) / 255.0;
        CGFloat g = ((rgbValue & 0x00FF00) >> 8) / 255.0;
        CGFloat b = (rgbValue & 0x0000FF) / 255.0;
        return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
    }
}

+ (UIColor *)primaryDark { return [self colorFromHex:@"#1F1736"]; }
+ (UIColor *)primaryBlue { return [self colorFromHex:@"#1976D2"]; }
+ (UIColor *)accentOrange { return [self colorFromHex:@"#EC7200"]; }
+ (UIColor *)brightOrange { return [self colorFromHex:@"#FF8800"]; }
+ (UIColor *)screenBackground { return [self colorFromHex:@"#F8F9FC"]; }
+ (UIColor *)cardBackground { return [UIColor whiteColor]; }
+ (UIColor *)textMuted { return [self colorFromHex:@"#6E6A7C"]; }
+ (UIColor *)textMutedLight { return [self colorFromHex:@"#7C788A"]; }
+ (UIColor *)badgeOpenText { return [self colorFromHex:@"#2E7D32"]; }
+ (UIColor *)badgeOpenBg { return [self colorFromHex:@"#E8F5E9"]; }
+ (UIColor *)badgeFullText { return [self colorFromHex:@"#C62828"]; }
+ (UIColor *)badgeFullBg { return [self colorFromHex:@"#FFEBEE"]; }
+ (UIColor *)dangerRed { return [self colorFromHex:@"#D32F2F"]; }
+ (UIColor *)grooveColor { return [self colorFromHex:@"#E5E6EE"]; }
+ (UIColor *)coreOffColor { return [self colorFromHex:@"#1E1E28"]; }
+ (UIColor *)warningColor { return [self colorFromHex:@"#FFB300"]; }
+ (UIColor *)progressBackground { return [self colorFromHex:@"#ECEFF1"]; }

+ (UIImage *)drawZaloIconWithSize:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Draw rounded background white or blue badge
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:size.width * 0.22];
    [[UIColor colorWithRed:0.0 green:0.41 blue:1.0 alpha:1.0] setFill];
    [path fill];
    
    // Draw white letter 'Z'
    NSString *text = @"Z";
    UIFont *font = [UIFont boldSystemFontOfSize:size.width * 0.65];
    NSDictionary *attr = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };
    CGSize textSize = [text sizeWithAttributes:attr];
    CGPoint textPoint = CGPointMake((size.width - textSize.width) / 2.0, (size.height - textSize.height) / 2.0 - 1.0);
    [text drawAtPoint:textPoint withAttributes:attr];
    
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (UIImage *)drawPowerIconWithSize:(CGSize)size color:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    
    CGFloat w = size.width;
    CGFloat h = size.height;
    CGFloat stroke = MAX(2.0, w * 0.08);
    
    // Power Arc
    CGFloat radius = (w - stroke * 2.5) / 2.0;
    CGPoint center = CGPointMake(w / 2.0, h / 2.0 + stroke * 0.5);
    
    // Arc from -55 deg to 235 deg
    CGFloat startAngle = -M_PI_2 + 0.65;
    CGFloat endAngle = -M_PI_2 - 0.65 + 2 * M_PI;
    UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:startAngle endAngle:endAngle clockwise:YES];
    arc.lineWidth = stroke;
    arc.lineCapStyle = kCGLineCapRound;
    [color setStroke];
    [arc stroke];
    
    // Vertical stem
    UIBezierPath *stem = [UIBezierPath bezierPath];
    [stem moveToPoint:CGPointMake(center.x, center.y - radius * 1.15)];
    [stem addLineToPoint:CGPointMake(center.x, center.y - radius * 0.15)];
    stem.lineWidth = stroke;
    stem.lineCapStyle = kCGLineCapRound;
    [stem stroke];
    
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (UIImage *)drawRadarIconWithSize:(CGSize)size color:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    
    CGFloat w = size.width;
    CGFloat h = size.height;
    CGPoint center = CGPointMake(w / 2.0, h / 2.0);
    CGFloat stroke = MAX(2.0, w * 0.06);
    
    // Center dot
    UIBezierPath *dot = [UIBezierPath bezierPathWithArcCenter:center radius:w * 0.1 startAngle:0 endAngle:2 * M_PI clockwise:YES];
    [color setFill];
    [dot fill];
    
    // Inner ring
    UIBezierPath *ring1 = [UIBezierPath bezierPathWithArcCenter:center radius:w * 0.26 startAngle:0 endAngle:2 * M_PI clockwise:YES];
    ring1.lineWidth = stroke;
    [color setStroke];
    [ring1 stroke];
    
    // Outer ring
    UIBezierPath *ring2 = [UIBezierPath bezierPathWithArcCenter:center radius:w * 0.42 startAngle:0 endAngle:2 * M_PI clockwise:YES];
    ring2.lineWidth = stroke;
    [ring2 stroke];
    
    // Sweep line
    UIBezierPath *sweep = [UIBezierPath bezierPath];
    [sweep moveToPoint:center];
    [sweep addLineToPoint:CGPointMake(center.x + w * 0.38, center.y - h * 0.38)];
    sweep.lineWidth = stroke;
    sweep.lineCapStyle = kCGLineCapRound;
    [sweep stroke];
    
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end
