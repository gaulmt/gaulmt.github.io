#import "NowEventActivationViewController.h"
#import "NowEventTheme.h"
#import "NowEventHoldToChargeView.h"
#import "NowEventHomeTabBarController.h"

@interface NowEventActivationViewController () <NowEventHoldToChargeViewDelegate>

@property (nonatomic, strong) NowEventHoldToChargeView *chargeView;
@property (nonatomic, strong) UIView *statusPill;
@property (nonatomic, strong) UIView *liveDot;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *btnEnterEvents;
@property (nonatomic, strong) UILabel *bottomHint;

@property (nonatomic, strong) NSTimer *statusResetTimer;

@end

@implementation NowEventActivationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [NowEventTheme screenBackground];
    
    [self setupUI];
}

- (void)setupUI {
    // 1. Header Container
    UIView *headerView = [[UIView alloc] init];
    headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:headerView];
    
    // Logo Small (48x48)
    UIImageView *logoView = [[UIImageView alloc] init];
    logoView.translatesAutoresizingMaskIntoConstraints = NO;
    logoView.image = [UIImage imageNamed:@"logo.png"];
    logoView.contentMode = UIViewContentModeScaleAspectFit;
    logoView.layer.cornerRadius = 10.0;
    logoView.clipsToBounds = YES;
    [headerView addSubview:logoView];
    
    // Title: "TRẠM KÍCH HOẠT HỆ THỐNG"
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"TRẠM KÍCH HOẠT HỆ THỐNG";
    titleLabel.textColor = [NowEventTheme primaryDark];
    titleLabel.font = [UIFont boldSystemFontOfSize:19];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [headerView addSubview:titleLabel];
    
    // Subtitle: "Ấn giữ để cấp năng lượng và kích hoạt radar săn sự kiện tự động."
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = @"Ấn giữ để cấp năng lượng và kích hoạt radar săn sự kiện tự động.";
    subtitleLabel.textColor = [NowEventTheme textMutedLight];
    subtitleLabel.font = [UIFont systemFontOfSize:13];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.numberOfLines = 2;
    [headerView addSubview:subtitleLabel];
    
    // 2. Center Hero Button (HoldToChargeView: 280x280)
    self.chargeView = [[NowEventHoldToChargeView alloc] init];
    self.chargeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chargeView.delegate = self;
    [self.view addSubview:self.chargeView];
    
    // 3. Status Badge Pill
    self.statusPill = [[UIView alloc] init];
    self.statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusPill.backgroundColor = [UIColor colorWithRed:0.92 green:0.93 blue:0.96 alpha:1.0];
    self.statusPill.layer.cornerRadius = 16.0;
    self.statusPill.layer.borderWidth = 1.0;
    self.statusPill.layer.borderColor = [UIColor colorWithRed:0.85 green:0.86 blue:0.90 alpha:1.0].CGColor;
    [self.view addSubview:self.statusPill];
    
    // Live Dot (Green circle)
    self.liveDot = [[UIView alloc] init];
    self.liveDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.liveDot.backgroundColor = [UIColor colorWithRed:0.18 green:0.75 blue:0.35 alpha:1.0];
    self.liveDot.layer.cornerRadius = 4.0;
    self.liveDot.hidden = YES;
    [self.statusPill addSubview:self.liveDot];
    
    // Status Label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = @"GIỮ ĐỂ KÍCH HOẠT";
    self.statusLabel.textColor = [NowEventTheme textMutedLight];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:13];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.statusPill addSubview:self.statusLabel];
    
    // 4. Bottom Section
    UIView *bottomContainer = [[UIView alloc] init];
    bottomContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bottomContainer];
    
    // Enter Events Button
    self.btnEnterEvents = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btnEnterEvents.translatesAutoresizingMaskIntoConstraints = NO;
    self.btnEnterEvents.backgroundColor = [NowEventTheme accentOrange];
    self.btnEnterEvents.layer.cornerRadius = 27.0;
    self.btnEnterEvents.layer.shadowColor = [NowEventTheme accentOrange].CGColor;
    self.btnEnterEvents.layer.shadowOpacity = 0.3;
    self.btnEnterEvents.layer.shadowRadius = 8.0;
    self.btnEnterEvents.layer.shadowOffset = CGSizeMake(0, 4);
    
    [self.btnEnterEvents setTitle:@"BẮT ĐẦU VÀO SỰ KIỆN" forState:UIControlStateNormal];
    [self.btnEnterEvents setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.btnEnterEvents.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.btnEnterEvents.alpha = 0.35;
    self.btnEnterEvents.enabled = NO;
    [self.btnEnterEvents addTarget:self action:@selector(handleEnterEvents) forControlEvents:UIControlEventTouchUpInside];
    [bottomContainer addSubview:self.btnEnterEvents];
    
    // Bottom hint
    self.bottomHint = [[UILabel alloc] init];
    self.bottomHint.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomHint.text = @"";
    self.bottomHint.textColor = [NowEventTheme textMutedLight];
    self.bottomHint.font = [UIFont systemFontOfSize:12];
    self.bottomHint.textAlignment = NSTextAlignmentCenter;
    [bottomContainer addSubview:self.bottomHint];
    
    // Layout Constraints
    [NSLayoutConstraint activateConstraints:@[
        // Header
        [headerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],
        [headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        
        [logoView.centerXAnchor constraintEqualToAnchor:headerView.centerXAnchor],
        [logoView.topAnchor constraintEqualToAnchor:headerView.topAnchor],
        [logoView.widthAnchor constraintEqualToConstant:48],
        [logoView.heightAnchor constraintEqualToConstant:48],
        
        [titleLabel.topAnchor constraintEqualToAnchor:logoView.bottomAnchor constant:12],
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor],
        
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:8],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-8],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor],
        
        // Center Charge View
        [self.chargeView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.chargeView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:10],
        [self.chargeView.widthAnchor constraintEqualToConstant:280],
        [self.chargeView.heightAnchor constraintEqualToConstant:280],
        
        // Status Badge Pill
        [self.statusPill.topAnchor constraintEqualToAnchor:self.chargeView.bottomAnchor constant:20],
        [self.statusPill.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.statusPill.heightAnchor constraintEqualToConstant:34],
        [self.statusPill.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.statusPill.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],
        
        [self.liveDot.leadingAnchor constraintEqualToAnchor:self.statusPill.leadingAnchor constant:14],
        [self.liveDot.centerYAnchor constraintEqualToAnchor:self.statusPill.centerYAnchor],
        [self.liveDot.widthAnchor constraintEqualToConstant:8],
        [self.liveDot.heightAnchor constraintEqualToConstant:8],
        
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusPill.leadingAnchor constant:18],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.statusPill.trailingAnchor constant:-18],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.statusPill.centerYAnchor],
        
        // Bottom Section
        [bottomContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [bottomContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [bottomContainer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        
        [self.btnEnterEvents.topAnchor constraintEqualToAnchor:bottomContainer.topAnchor],
        [self.btnEnterEvents.leadingAnchor constraintEqualToAnchor:bottomContainer.leadingAnchor],
        [self.btnEnterEvents.trailingAnchor constraintEqualToAnchor:bottomContainer.trailingAnchor],
        [self.btnEnterEvents.heightAnchor constraintEqualToConstant:54],
        
        [self.bottomHint.topAnchor constraintEqualToAnchor:self.btnEnterEvents.bottomAnchor constant:10],
        [self.bottomHint.leadingAnchor constraintEqualToAnchor:bottomContainer.leadingAnchor],
        [self.bottomHint.trailingAnchor constraintEqualToAnchor:bottomContainer.trailingAnchor],
        [self.bottomHint.bottomAnchor constraintEqualToAnchor:bottomContainer.bottomAnchor]
    ]];
}

#pragma mark - HoldToChargeViewDelegate

- (void)holdToChargeViewDidStartCharging {
    [self.statusResetTimer invalidate];
    self.statusResetTimer = nil;
    
    self.liveDot.hidden = YES;
    self.statusLabel.text = @"ĐANG NẠP NĂNG LƯỢNG...";
    self.statusLabel.textColor = [NowEventTheme accentOrange];
}

- (void)holdToChargeViewDidChangeProgress:(NSInteger)percent {
    self.statusLabel.text = [NSString stringWithFormat:@"ĐANG NẠP NĂNG LƯỢNG... %ld%%", (long)percent];
}

- (void)holdToChargeViewDidAbort {
    self.liveDot.hidden = YES;
    self.statusLabel.text = @"CHƯA ĐỦ NĂNG LƯỢNG — HÃY GIỮ NGUYÊN";
    self.statusLabel.textColor = [NowEventTheme dangerRed];
    
    [self.statusResetTimer invalidate];
    self.statusResetTimer = [NSTimer scheduledTimerWithTimeInterval:2.5 repeats:NO block:^(NSTimer * _Nonnull timer) {
        self.statusLabel.text = @"GIỮ ĐỂ KÍCH HOẠT";
        self.statusLabel.textColor = [NowEventTheme textMutedLight];
    }];
}

- (void)holdToChargeViewDidCompleteCharge {
    // Ignition Success!
    [self.chargeView performSuccessIgnition];
}

- (void)holdToChargeViewDidIgniteSuccess {
    [self.statusResetTimer invalidate];
    self.statusResetTimer = nil;
    
    self.liveDot.hidden = NO;
    self.statusLabel.text = @"HỆ THỐNG ĐANG LẮNG NGHE";
    self.statusLabel.textColor = [NowEventTheme accentOrange];
    
    // Adjust layout for live dot
    [UIView animateWithDuration:0.4 animations:^{
        self.btnEnterEvents.enabled = YES;
        self.btnEnterEvents.alpha = 1.0;
        self.bottomHint.text = @"Hệ thống radar đã được kích hoạt và đang vận hành!";
    }];
}

- (void)handleEnterEvents {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
    [haptic impactOccurred];
    
    // Save activation state
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:@"kNowEventActivated"];
    [defaults synchronize];
    
    NowEventHomeTabBarController *homeVC = [[NowEventHomeTabBarController alloc] init];
    UIWindow *window = self.view.window ?: [UIApplication sharedApplication].keyWindow;
    [UIView transitionWithView:window duration:0.4 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        window.rootViewController = homeVC;
    } completion:nil];
}

@end
