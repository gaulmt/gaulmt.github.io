#import "NowEventLoginViewController.h"
#import "NowEventTheme.h"
#import "NowEventActivationViewController.h"

@interface NowEventLoginViewController ()
@property (nonatomic, strong) UIButton *btnZalo;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation NowEventLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [NowEventTheme screenBackground];
    
    // Background Image
    UIImageView *bgView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    bgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    bgView.image = [UIImage imageNamed:@"bg.png"];
    bgView.contentMode = UIViewContentModeScaleAspectFill;
    bgView.clipsToBounds = YES;
    [self.view addSubview:bgView];
    
    // ScrollView
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:scrollView];
    
    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentView];
    
    // Logo (120x120)
    UIImageView *logoView = [[UIImageView alloc] init];
    logoView.translatesAutoresizingMaskIntoConstraints = NO;
    NSString *loginLogoPath = [[NSBundle mainBundle] pathForResource:@"logo" ofType:@"png"];
    logoView.image = (loginLogoPath ? [UIImage imageWithContentsOfFile:loginLogoPath] : nil) ?: [UIImage imageNamed:@"logo"];
    logoView.backgroundColor = [UIColor whiteColor];
    logoView.contentMode = UIViewContentModeScaleAspectFit;
    logoView.layer.cornerRadius = 24.0;
    logoView.clipsToBounds = YES;
    [contentView addSubview:logoView];
    
    // Title: "NOW EVENT NOTIFICATION", accent_color (#EC7200), 28sp bold
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"NOW EVENT NOTIFICATION";
    titleLabel.textColor = [NowEventTheme accentOrange];
    titleLabel.font = [UIFont boldSystemFontOfSize:26];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 2;
    [contentView addSubview:titleLabel];
    
    // Subtitle: "Phụ một chân bước tới thế giới học bổng"
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = @"Phụ một chân bước tới thế giới học bổng";
    subtitleLabel.textColor = [NowEventTheme textMuted];
    subtitleLabel.font = [UIFont systemFontOfSize:16];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.numberOfLines = 0;
    [contentView addSubview:subtitleLabel];
    
    // Spinner
    if (@available(iOS 13.0, *)) {
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    } else {
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    }
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = [NowEventTheme primaryDark];
    self.spinner.hidesWhenStopped = YES;
    [contentView addSubview:self.spinner];
    
    // Zalo Login Button (52pt pill, #EC7200 background)
    self.btnZalo = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btnZalo.translatesAutoresizingMaskIntoConstraints = NO;
    self.btnZalo.backgroundColor = [NowEventTheme accentOrange];
    self.btnZalo.layer.cornerRadius = 26.0;
    self.btnZalo.layer.shadowColor = [NowEventTheme accentOrange].CGColor;
    self.btnZalo.layer.shadowOpacity = 0.35;
    self.btnZalo.layer.shadowRadius = 8.0;
    self.btnZalo.layer.shadowOffset = CGSizeMake(0, 4);
    
    [self.btnZalo setTitle:@"Đăng Nhập Bằng Zalo" forState:UIControlStateNormal];
    [self.btnZalo setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.btnZalo.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    
    UIImage *zaloIcon = [NowEventTheme drawZaloIconWithSize:CGSizeMake(24, 24)];
    [self.btnZalo setImage:zaloIcon forState:UIControlStateNormal];
    self.btnZalo.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 12);
    self.btnZalo.titleEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 0);
    
    [self.btnZalo addTarget:self action:@selector(handleZaloLogin) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:self.btnZalo];
    
    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        
        [contentView.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],
        
        [logoView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [logoView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:50],
        [logoView.widthAnchor constraintEqualToConstant:120],
        [logoView.heightAnchor constraintEqualToConstant:120],
        
        [titleLabel.topAnchor constraintEqualToAnchor:logoView.bottomAnchor constant:24],
        [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24],
        [titleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24],
        
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:14],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24],
        
        [self.spinner.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:28],
        [self.spinner.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        
        [self.btnZalo.topAnchor constraintGreaterThanOrEqualToAnchor:self.spinner.bottomAnchor constant:36],
        [self.btnZalo.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:28],
        [self.btnZalo.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-28],
        [self.btnZalo.heightAnchor constraintEqualToConstant:52],
        [self.btnZalo.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-40]
    ]];
}

- (void)handleZaloLogin {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    
    [self.spinner startAnimating];
    self.btnZalo.enabled = NO;
    self.btnZalo.alpha = 0.7;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.spinner stopAnimating];
        self.btnZalo.enabled = YES;
        self.btnZalo.alpha = 1.0;
        
        // Save session
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:YES forKey:@"kNowEventLoggedIn"];
        [defaults setObject:@"Đoàn viên IUH" forKey:@"kNowEventUserName"];
        [defaults setObject:@"4146895302344471" forKey:@"kNowEventZaloUID"];
        [defaults setBool:NO forKey:@"kNowEventActivated"];
        [defaults synchronize];
        
        // Transition to Activation Activity
        NowEventActivationViewController *actVC = [[NowEventActivationViewController alloc] init];
        UIWindow *window = self.view.window ?: [UIApplication sharedApplication].keyWindow;
        [UIView transitionWithView:window duration:0.4 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            window.rootViewController = actVC;
        } completion:nil];
    });
}

@end
