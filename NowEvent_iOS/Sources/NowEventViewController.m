#import "NowEventViewController.h"
#import <AudioToolbox/AudioToolbox.h>

@interface NowEventViewController ()
@property (strong, nonatomic) WKWebView *webView;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (strong, nonatomic) UIRefreshControl *refreshControl;
@end

@implementation NowEventViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IUH Sự Kiện";
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.05 alpha:1.0];
    
    // Setup Navigation Items
    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadPage)];
    self.navigationItem.rightBarButtonItem = refreshBtn;
    
    // Setup WKWebView Configuration
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.preferences.javaScriptEnabled = YES;
    @try {
        [config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
    } @catch (NSException *e) {}
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.05 alpha:1.0];
    self.webView.opaque = NO;
    self.webView.scrollView.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.05 alpha:1.0];
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
    
    // Load Event Dashboard
    [self loadEvents];
}

- (void)loadEvents {
    [self.spinner startAnimating];
    
    NSURL *localURL = [[NSBundle mainBundle] URLForResource:@"dashboard" withExtension:@"html"];
    if (localURL) {
        [self.webView loadFileURL:localURL allowingReadAccessToURL:[localURL URLByDeletingLastPathComponent]];
        return;
    }
    
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *filePath = [bundlePath stringByAppendingPathComponent:@"dashboard.html"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        [self.webView loadFileURL:fileURL allowingReadAccessToURL:[NSURL fileURLWithPath:bundlePath]];
        return;
    }
    
    // Fallback: try remote endpoint
    NSURL *remoteURL = [NSURL URLWithString:@"https://taile-home.tailb889f1.ts.net/"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:remoteURL]];
}

- (void)reloadPage {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    
    [self.webView evaluateJavaScript:@"if (typeof refreshData === 'function') { refreshData(); }" completionHandler:nil];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.refreshControl endRefreshing];
    });
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [self.spinner startAnimating];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.spinner stopAnimating];
    [self.refreshControl endRefreshing];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
    [self.refreshControl endRefreshing];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
    [self.refreshControl endRefreshing];
}

@end
