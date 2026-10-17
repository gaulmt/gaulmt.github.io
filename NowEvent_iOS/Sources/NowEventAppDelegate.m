#import "NowEventAppDelegate.h"
#import "NowEventHomeTabBarController.h"
#import "NowEventTheme.h"

@implementation NowEventAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [NowEventTheme screenBackground];
    
    // Set default session flags
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:@"kNowEventLoggedIn"];
    [defaults setBool:YES forKey:@"kNowEventActivated"];
    if (![defaults objectForKey:@"kNowEventUserName"]) {
        [defaults setObject:@"Đoàn viên IUH" forKey:@"kNowEventUserName"];
    }
    if (![defaults objectForKey:@"kNowEventZaloUID"]) {
        [defaults setObject:@"4146895302344471" forKey:@"kNowEventZaloUID"];
    }
    [defaults synchronize];
    
    // Launch directly into the main interface
    NowEventHomeTabBarController *homeVC = [[NowEventHomeTabBarController alloc] init];
    self.window.rootViewController = homeVC;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
