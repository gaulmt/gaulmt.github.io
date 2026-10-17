#import "NowEventSplashViewController.h"
#import "NowEventTheme.h"
#import "NowEventLoginViewController.h"
#import "NowEventActivationViewController.h"
#import "NowEventHomeTabBarController.h"

@interface NowEventSplashViewController ()
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation NowEventSplashViewController

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
    
    // Center Container for Logo + Title + Slogan
    UIView *centerContainer = [[UIView alloc] init];
    centerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:centerContainer];
    
    // Logo (140x140)
    UIImageView *logoView = [[UIImageView alloc] init];
    logoView.translatesAutoresizingMaskIntoConstraints = NO;
    logoView.image = [UIImage imageNamed:@"logo.png"];
    logoView.contentMode = UIViewContentModeScaleAspectFit;
    logoView.layer.cornerRadius = 24.0;
    logoView.clipsToBounds = YES;
    [centerContainer addSubview:logoView];
    
    // App Title: "NOW EVENT NOTIFICATION"
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"NOW EVENT NOTIFICATION";
    titleLabel.textColor = [NowEventTheme primaryDark];
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [centerContainer addSubview:titleLabel];
    
    // Subtitle: "Phụ một chân bước tới thế giới học bổng"
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = @"Phụ một chân bước tới thế giới học bổng";
    subtitleLabel.textColor = [NowEventTheme textMuted];
    subtitleLabel.font = [UIFont systemFontOfSize:14];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [centerContainer addSubview:subtitleLabel];
    
    // Bottom Spinner
    if (@available(iOS 13.0, *)) {
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    } else {
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    }
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = [NowEventTheme primaryDark];
    [self.spinner startAnimating];
    [self.view addSubview:self.spinner];
    
    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [centerContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [centerContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30],
        [centerContainer.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [centerContainer.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
        
        [logoView.centerXAnchor constraintEqualToAnchor:centerContainer.centerXAnchor],
        [logoView.topAnchor constraintEqualToAnchor:centerContainer.topAnchor],
        [logoView.widthAnchor constraintEqualToConstant:140],
        [logoView.heightAnchor constraintEqualToConstant:140],
        
        [titleLabel.topAnchor constraintEqualToAnchor:logoView.bottomAnchor constant:24],
        [titleLabel.leadingAnchor constraintEqualToAnchor:centerContainer.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:centerContainer.trailingAnchor],
        
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:centerContainer.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:centerContainer.trailingAnchor],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:centerContainer.bottomAnchor],
        
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-40]
    ]];
    
    // Schedule check
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self decideNavigation];
    });
}

- (void)decideNavigation {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL loggedIn = [defaults boolForKey:@"kNowEventLoggedIn"];
    BOOL activated = [defaults boolForKey:@"kNowEventActivated"];
    
    UIViewController *targetVC = nil;
    if (!loggedIn) {
        targetVC = [[NowEventLoginViewController alloc] init];
    } else if (!activated) {
        targetVC = [[NowEventActivationViewController alloc] init];
    } else {
        targetVC = [[NowEventHomeTabBarController alloc] init];
    }
    
    UIWindow *window = self.view.window ?: [UIApplication sharedApplication].keyWindow;
    [UIView transitionWithView:window duration:0.4 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        window.rootViewController = targetVC;
    } completion:nil];
}

@end
