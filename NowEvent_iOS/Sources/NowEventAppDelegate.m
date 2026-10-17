#import "NowEventAppDelegate.h"
#import "NowEventSplashViewController.h"
#import "NowEventTheme.h"

@implementation NowEventAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [NowEventTheme screenBackground];
    
    NowEventSplashViewController *splashVC = [[NowEventSplashViewController alloc] init];
    self.window.rootViewController = splashVC;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
