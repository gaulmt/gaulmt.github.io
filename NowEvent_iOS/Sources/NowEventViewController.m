#import "NowEventViewController.h"
#import <AudioToolbox/AudioToolbox.h>

@interface NowEventViewController ()
@property (strong, nonatomic) WKWebView *webView;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (strong, nonatomic) UIRefreshControl *refreshControl;
@property (strong, nonatomic) UIView *errorView;
@end

@implementation NowEventViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IUH Sự Kiện";
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.07 blue:0.10 alpha:1.0];
    
    // Setup Navigation Items
    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadPage)];
    self.navigationItem.rightBarButtonItem = refreshBtn;
    
    // Setup WKWebView Configuration
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.preferences.javaScriptEnabled = YES;
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.backgroundColor = [UIColor clearColor];
    self.webView.opaque = NO;
    [self.view addSubview:self.webView];
    
    // Pull to Refresh
    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [UIColor colorWithRed:0.90 green:0.75 blue:0.48 alpha:1.0];
    [self.refreshControl addTarget:self action:@selector(reloadPage) forControlEvents:UIControlEventValueChanged];
    self.webView.scrollView.refreshControl = self.refreshControl;
    
    // Loading Spinner
    if (@available(iOS 13.0, *)) {
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    } else {
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    }
    self.spinner.color = [UIColor colorWithRed:0.90 green:0.75 blue:0.48 alpha:1.0];
    self.spinner.center = self.view.center;
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    
    // Load Event URL
    [self loadEvents];
}

- (void)loadEvents {
    [self.spinner startAnimating];
    [self hideErrorView];
    
    // Primary URL: Event Gateway
    NSURL *url = [NSURL URLWithString:@"https://taile-home.tailb889f1.ts.net/iuh"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:15.0];
    [req setValue:@"NowEventNotification-iOS/2.1.0" forHTTPHeaderField:@"User-Agent-Client"];
    [self.webView loadRequest:req];
}

- (void)reloadPage {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    [self.webView reload];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [self.spinner startAnimating];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.spinner stopAnimating];
    [self.refreshControl endRefreshing];
    [self hideErrorView];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
    [self.refreshControl endRefreshing];
    
    if (error.code != NSURLErrorCancelled) {
        [self showErrorView:error.localizedDescription];
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
    [self.refreshControl endRefreshing];
    
    if (error.code != NSURLErrorCancelled) {
        [self showErrorView:error.localizedDescription];
    }
}

#pragma mark - Error Fallback UI

- (void)showErrorView:(NSString *)message {
    if (!self.errorView) {
        self.errorView = [[UIView alloc] initWithFrame:self.view.bounds];
        self.errorView.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.12 alpha:1.0];
        self.errorView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - 72) / 2, 140, 72, 72)];
        iconView.image = [UIImage imageNamed:@"icon.png"];
        iconView.layer.cornerRadius = 18;
        iconView.clipsToBounds = YES;
        iconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [self.errorView addSubview:iconView];
        
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 230, self.view.bounds.size.width - 48, 28)];
        titleLabel.text = @"IUH Now Event Notification";
        titleLabel.textColor = [UIColor whiteColor];
        titleLabel.font = [UIFont boldSystemFontOfSize:20];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self.errorView addSubview:titleLabel];
        
        UILabel *msgLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 268, self.view.bounds.size.width - 48, 60)];
        msgLabel.text = @"Máy chủ thông báo sự kiện đang cập nhật dữ liệu. Vui lòng kiểm tra kết nối mạng và thử lại.";
        msgLabel.textColor = [UIColor colorWithRed:0.6 green:0.65 blue:0.75 alpha:1.0];
        msgLabel.font = [UIFont systemFontOfSize:14];
        msgLabel.numberOfLines = 3;
        msgLabel.textAlignment = NSTextAlignmentCenter;
        msgLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self.errorView addSubview:msgLabel];
        
        UIButton *retryBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        retryBtn.frame = CGRectMake((self.view.bounds.size.width - 200) / 2, 350, 200, 48);
        [retryBtn setTitle:@"🔄 Thử lại kết nối" forState:UIControlStateNormal];
        retryBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        retryBtn.backgroundColor = [UIColor colorWithRed:0.90 green:0.75 blue:0.48 alpha:1.0];
        [retryBtn setTitleColor:[UIColor colorWithRed:0.1 green:0.08 blue:0.05 alpha:1.0] forState:UIControlStateNormal];
        retryBtn.layer.cornerRadius = 14;
        retryBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [retryBtn addTarget:self action:@selector(loadEvents) forControlEvents:UIControlEventTouchUpInside];
        [self.errorView addSubview:retryBtn];
        
        [self.view addSubview:self.errorView];
    }
    self.errorView.hidden = NO;
    [self.view bringSubviewToFront:self.errorView];
}

- (void)hideErrorView {
    if (self.errorView) {
        self.errorView.hidden = YES;
    }
}

@end
