#import "NowEventHoldToChargeView.h"
#import "NowEventTheme.h"
#import <AudioToolbox/AudioToolbox.h>

@interface NowEventHoldToChargeView ()

@property (nonatomic, assign, readwrite) NowEventChargeState currentState;
@property (nonatomic, assign, readwrite) CGFloat progress;

@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) CFTimeInterval chargeStartTime;
@property (nonatomic, assign) CFTimeInterval abortStartTime;
@property (nonatomic, assign) CGFloat abortStartProgress;

@property (nonatomic, assign) CGFloat scaleFactor;
@property (nonatomic, assign) CGFloat shakeX;
@property (nonatomic, assign) CGFloat shakeY;

@property (nonatomic, assign) CGFloat shockwaveProgress;
@property (nonatomic, assign) CFTimeInterval shockwaveStartTime;
@property (nonatomic, assign) CGFloat radarPulseProgress;
@property (nonatomic, assign) CFTimeInterval radarPulseStartTime;

@property (nonatomic, strong) UIImpactFeedbackGenerator *hapticLight;
@property (nonatomic, strong) UIImpactFeedbackGenerator *hapticMedium;
@property (nonatomic, strong) UIImpactFeedbackGenerator *hapticHeavy;
@property (nonatomic, assign) NSTimeInterval lastHapticTime;

@end

@implementation NowEventHoldToChargeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;
    self.currentState = NowEventChargeStateStandby;
    self.progress = 0.0;
    self.scaleFactor = 1.0;
    
    _hapticLight = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    _hapticMedium = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    _hapticHeavy = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
    [_hapticLight prepare];
    [_hapticMedium prepare];
    [_hapticHeavy prepare];
    
    [self startDisplayLink];
}

- (void)startDisplayLink {
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onTick:)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)stopDisplayLink {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (void)dealloc {
    [self stopDisplayLink];
}

- (void)onTick:(CADisplayLink *)link {
    CFTimeInterval now = CACurrentMediaTime();
    
    if (self.currentState == NowEventChargeStateStandby) {
        // Idle breathing: 3.0s cycle
        CGFloat t = fmod(now, 3.0) / 3.0; // 0..1
        CGFloat sine = sin(t * M_PI * 2.0);
        self.scaleFactor = 1.0 + sine * 0.025;
        self.shakeX = 0;
        self.shakeY = 0;
        [self setNeedsDisplay];
    }
    else if (self.currentState == NowEventChargeStateCharging) {
        // Charge duration: 6.0 seconds (optimal for mobile while feeling rich)
        CGFloat elapsed = now - self.chargeStartTime;
        CGFloat rawProgress = elapsed / 6.0;
        if (rawProgress > 1.0) rawProgress = 1.0;
        
        // Decelerate curve
        self.progress = 1.0 - pow(1.0 - rawProgress, 2.0);
        self.scaleFactor = 0.93; // mechanical pressed effect
        
        NSInteger percent = (NSInteger)(self.progress * 100);
        
        // Micro-shake when >= 70%
        if (percent >= 70) {
            CGFloat intensity = 2.0 * ((percent - 70) / 30.0 + 0.5);
            self.shakeX = (((CGFloat)arc4random_uniform(200) / 100.0) - 1.0) * intensity;
            self.shakeY = (((CGFloat)arc4random_uniform(200) / 100.0) - 1.0) * intensity;
        } else {
            self.shakeX = 0;
            self.shakeY = 0;
        }
        
        // Haptic Ramping
        [self handleHaptic:percent];
        
        if ([self.delegate respondsToSelector:@selector(holdToChargeViewDidChangeProgress:)]) {
            [self.delegate holdToChargeViewDidChangeProgress:percent];
        }
        
        [self setNeedsDisplay];
        
        if (self.progress >= 0.999) {
            self.progress = 1.0;
            self.shakeX = 0;
            self.shakeY = 0;
            self.scaleFactor = 1.0;
            [self.hapticHeavy impactOccurred];
            
            if ([self.delegate respondsToSelector:@selector(holdToChargeViewDidCompleteCharge:)]) {
                [self.delegate holdToChargeViewDidCompleteCharge];
            }
        }
    }
    else if (self.currentState == NowEventChargeStateAborting) {
        // Drain to 0 in 350ms
        CGFloat elapsed = now - self.abortStartTime;
        CGFloat t = elapsed / 0.35;
        if (t >= 1.0) {
            self.progress = 0.0;
            self.currentState = NowEventChargeStateStandby;
            self.scaleFactor = 1.0;
        } else {
            self.progress = self.abortStartProgress * (1.0 - t);
        }
        [self setNeedsDisplay];
    }
    else if (self.currentState == NowEventChargeStateActive) {
        // Shockwave
        if (self.shockwaveProgress < 1.0) {
            CGFloat elapsed = now - self.shockwaveStartTime;
            self.shockwaveProgress = elapsed / 0.8;
            if (self.shockwaveProgress > 1.0) self.shockwaveProgress = 1.0;
        }
        
        // Repeating radar pulse every 1.2s
        CGFloat pulseElapsed = now - self.radarPulseStartTime;
        self.radarPulseProgress = fmod(pulseElapsed, 1.2) / 1.2;
        
        self.scaleFactor = 1.0;
        self.shakeX = 0;
        self.shakeY = 0;
        [self setNeedsDisplay];
    }
}

- (void)handleHaptic:(NSInteger)percent {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval interval = 0.50;
    if (percent >= 80) {
        interval = 0.09;
    } else if (percent >= 40) {
        interval = 0.22;
    }
    
    if (now - self.lastHapticTime >= interval) {
        self.lastHapticTime = now;
        if (percent >= 80) {
            [self.hapticHeavy impactOccurred];
        } else if (percent >= 40) {
            [self.hapticMedium impactOccurred];
        } else {
            [self.hapticLight impactOccurred];
        }
    }
}

#pragma mark - Touch Handling

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.currentState == NowEventChargeStateActive) return;
    
    UITouch *touch = [touches anyObject];
    CGPoint pt = [touch locationInView:self];
    CGPoint center = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0);
    CGFloat dist = hypot(pt.x - center.x, pt.y - center.y);
    
    CGFloat maxRadius = (MIN(self.bounds.size.width, self.bounds.size.height) / 2.0) - 20.0;
    if (dist <= maxRadius) {
        self.currentState = NowEventChargeStateCharging;
        self.chargeStartTime = CACurrentMediaTime();
        self.progress = 0.0;
        [self.hapticMedium impactOccurred];
        
        if ([self.delegate respondsToSelector:@selector(holdToChargeViewDidStartCharging)]) {
            [self.delegate holdToChargeViewDidStartCharging];
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.currentState == NowEventChargeStateCharging && self.progress < 0.99) {
        [self abortCharging];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.currentState == NowEventChargeStateCharging && self.progress < 0.99) {
        [self abortCharging];
    }
}

- (void)abortCharging {
    self.currentState = NowEventChargeStateAborting;
    self.abortStartTime = CACurrentMediaTime();
    self.abortStartProgress = self.progress;
    self.shakeX = 0;
    self.shakeY = 0;
    self.scaleFactor = 1.0;
    [self.hapticLight impactOccurred];
    
    if ([self.delegate respondsToSelector:@selector(holdToChargeViewDidAbort)]) {
        [self.delegate holdToChargeViewDidAbort];
    }
}

- (void)performSuccessIgnition {
    self.currentState = NowEventChargeStateActive;
    self.progress = 1.0;
    self.shockwaveStartTime = CACurrentMediaTime();
    self.shockwaveProgress = 0.0;
    self.radarPulseStartTime = CACurrentMediaTime();
    
    // Play notification sound
    static SystemSoundID sIgnitionSound = 0;
    if (sIgnitionSound == 0) {
        NSURL *soundURL = [[NSBundle mainBundle] URLForResource:@"notification_sound" withExtension:@"wav"];
        if (soundURL) {
            AudioServicesCreateSystemSoundID((__bridge CFURLRef)soundURL, &sIgnitionSound);
        }
    }
    if (sIgnitionSound != 0) {
        AudioServicesPlaySystemSound(sIgnitionSound);
    } else {
        AudioServicesPlaySystemSound(1007);
    }
    
    [self.hapticHeavy impactOccurred];
    
    if ([self.delegate respondsToSelector:@selector(holdToChargeViewDidIgniteSuccess)]) {
        [self.delegate holdToChargeViewDidIgniteSuccess];
    }
    [self setNeedsDisplay];
}

- (void)resetToStandby {
    self.currentState = NowEventChargeStateStandby;
    self.progress = 0.0;
    self.scaleFactor = 1.0;
    self.shakeX = 0;
    self.shakeY = 0;
    [self setNeedsDisplay];
}

#pragma mark - Drawing

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGPoint center = CGPointMake(w / 2.0 + self.shakeX, h / 2.0 + self.shakeY);
    
    CGFloat minDim = MIN(w, h);
    CGFloat grooveRadius = (minDim / 2.0) - 30.0;
    CGFloat coreRadius = grooveRadius - 14.0;
    
    CGContextSaveGState(ctx);
    
    // Scale transformation around center
    CGContextTranslateCTM(ctx, center.x, center.y);
    CGContextScaleCTM(ctx, self.scaleFactor, self.scaleFactor);
    CGContextTranslateCTM(ctx, -center.x, -center.y);
    
    // 1. Shockwave if active
    if (self.currentState == NowEventChargeStateActive && self.shockwaveProgress < 1.0) {
        CGFloat swR = grooveRadius + self.shockwaveProgress * 70.0;
        CGFloat swAlpha = (1.0 - self.shockwaveProgress) * 0.8;
        UIColor *swCol = [[NowEventTheme accentOrange] colorWithAlphaComponent:swAlpha];
        [swCol setStroke];
        UIBezierPath *swPath = [UIBezierPath bezierPathWithArcCenter:center radius:swR startAngle:0 endAngle:2 * M_PI clockwise:YES];
        swPath.lineWidth = 5.0 * (1.0 - self.shockwaveProgress);
        [swPath stroke];
    }
    
    // 2. Radar pulse waves if active
    if (self.currentState == NowEventChargeStateActive) {
        CGFloat rWave = grooveRadius + self.radarPulseProgress * 55.0;
        CGFloat aWave = (1.0 - self.radarPulseProgress) * 0.6;
        UIColor *waveCol = [[NowEventTheme accentOrange] colorWithAlphaComponent:aWave];
        [waveCol setStroke];
        UIBezierPath *pulsePath = [UIBezierPath bezierPathWithArcCenter:center radius:rWave startAngle:0 endAngle:2 * M_PI clockwise:YES];
        pulsePath.lineWidth = 2.5;
        [pulsePath stroke];
    }
    
    // 3. Groove track (outer ring)
    UIBezierPath *groove = [UIBezierPath bezierPathWithArcCenter:center radius:grooveRadius startAngle:0 endAngle:2 * M_PI clockwise:YES];
    groove.lineWidth = 6.0;
    [[NowEventTheme grooveColor] setStroke];
    [groove stroke];
    
    // 4. Two symmetrical charging arcs racing from 270° (top) towards 90° (bottom)
    if (self.progress > 0.005) {
        CGFloat sweep = M_PI * self.progress; // 0 to 180 deg
        CGFloat top = -M_PI_2; // 270 deg / top
        
        // Arc 1 (clockwise): top -> top + sweep
        UIBezierPath *arc1 = [UIBezierPath bezierPathWithArcCenter:center radius:grooveRadius startAngle:top endAngle:top + sweep clockwise:YES];
        arc1.lineWidth = 7.0;
        arc1.lineCapStyle = kCGLineCapRound;
        [[NowEventTheme brightOrange] setStroke];
        [arc1 stroke];
        
        // Arc 2 (counter-clockwise): top -> top - sweep
        UIBezierPath *arc2 = [UIBezierPath bezierPathWithArcCenter:center radius:grooveRadius startAngle:top endAngle:top - sweep clockwise:NO];
        arc2.lineWidth = 7.0;
        arc2.lineCapStyle = kCGLineCapRound;
        [arc2 stroke];
    }
    
    // 5. Core circle with dynamic color shift
    UIColor *coreColor;
    if (self.currentState == NowEventChargeStateActive) {
        coreColor = [NowEventTheme accentOrange];
    } else {
        // Interpolate between coreOff (#1E1E28) and accentOrange (#EC7200)
        coreColor = [self interpolateColorFrom:[NowEventTheme coreOffColor] to:[NowEventTheme accentOrange] fraction:self.progress];
    }
    
    // Shadow
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 6), 12.0, [UIColor colorWithWhite:0.0 alpha:0.35].CGColor);
    UIBezierPath *core = [UIBezierPath bezierPathWithArcCenter:center radius:coreRadius startAngle:0 endAngle:2 * M_PI clockwise:YES];
    [coreColor setFill];
    [core fill];
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
    
    // Inner subtle rim
    UIBezierPath *innerRim = [UIBezierPath bezierPathWithArcCenter:center radius:coreRadius - 1.0 startAngle:0 endAngle:2 * M_PI clockwise:YES];
    innerRim.lineWidth = 1.5;
    CGFloat rimAlpha = (self.currentState == NowEventChargeStateActive) ? 0.35 : 0.15;
    [[[UIColor whiteColor] colorWithAlphaComponent:rimAlpha] setStroke];
    [innerRim stroke];
    
    // 6. Center content (Text or Icons)
    if (self.currentState == NowEventChargeStateActive) {
        // Radar Icon
        UIImage *radarImg = [NowEventTheme drawRadarIconWithSize:CGSizeMake(48, 48) color:[UIColor whiteColor]];
        CGRect imgRect = CGRectMake(center.x - 24, center.y - 24, 48, 48);
        [radarImg drawInRect:imgRect];
    }
    else if (self.currentState == NowEventChargeStateCharging || (self.currentState == NowEventChargeStateAborting && self.progress > 0.05)) {
        // Percent Text: e.g. "65%"
        NSInteger pct = (NSInteger)(self.progress * 100);
        NSString *pctStr = [NSString stringWithFormat:@"%ld%%", (long)pct];
        UIFont *pctFont = [UIFont boldSystemFontOfSize:34];
        NSDictionary *pctAttr = @{
            NSFontAttributeName: pctFont,
            NSForegroundColorAttributeName: [UIColor whiteColor]
        };
        CGSize pctSize = [pctStr sizeWithAttributes:pctAttr];
        [pctStr drawAtPoint:CGPointMake(center.x - pctSize.width / 2.0, center.y - pctSize.height / 2.0 - 8.0) withAttributes:pctAttr];
        
        // Subtitle "GIỮ NGUYÊN"
        NSString *lbl = @"GIỮ NGUYÊN";
        UIFont *lblFont = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        NSDictionary *lblAttr = @{
            NSFontAttributeName: lblFont,
            NSForegroundColorAttributeName: [UIColor colorWithRed:0.75 green:0.76 blue:0.82 alpha:1.0],
            NSKernAttributeName: @(1.5)
        };
        CGSize lblSize = [lbl sizeWithAttributes:lblAttr];
        [lbl drawAtPoint:CGPointMake(center.x - lblSize.width / 2.0, center.y + 18.0) withAttributes:lblAttr];
    }
    else {
        // Standby: Power Icon + "GIỮ ĐỂ KÍCH HOẠT"
        UIImage *powerImg = [NowEventTheme drawPowerIconWithSize:CGSizeMake(38, 38) color:[UIColor colorWithRed:0.78 green:0.79 blue:0.83 alpha:1.0]];
        CGRect imgRect = CGRectMake(center.x - 19, center.y - 30, 38, 38);
        [powerImg drawInRect:imgRect];
        
        NSString *lbl = @"GIỮ ĐỂ KÍCH HOẠT";
        UIFont *lblFont = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        NSDictionary *lblAttr = @{
            NSFontAttributeName: lblFont,
            NSForegroundColorAttributeName: [UIColor colorWithRed:0.69 green:0.70 blue:0.76 alpha:1.0],
            NSKernAttributeName: @(1.2)
        };
        CGSize lblSize = [lbl sizeWithAttributes:lblAttr];
        [lbl drawAtPoint:CGPointMake(center.x - lblSize.width / 2.0, center.y + 16.0) withAttributes:lblAttr];
    }
    
    CGContextRestoreGState(ctx);
}

- (UIColor *)interpolateColorFrom:(UIColor *)c1 to:(UIColor *)c2 fraction:(CGFloat)f {
    CGFloat r1, g1, b1, a1;
    CGFloat r2, g2, b2, a2;
    [c1 getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [c2 getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    
    CGFloat r = r1 + (r2 - r1) * f;
    CGFloat g = g1 + (g2 - g1) * f;
    CGFloat b = b1 + (b2 - b1) * f;
    CGFloat a = a1 + (a2 - a1) * f;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

@end
