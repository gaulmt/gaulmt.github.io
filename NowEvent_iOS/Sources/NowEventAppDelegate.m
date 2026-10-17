#import "NowEventAppDelegate.h"
#import "NowEventViewController.h"

@implementation NowEventAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    NowEventViewController *rootVC = [[NowEventViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:rootVC];
    
    // Style Navigation Bar
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor colorWithRed:0.06 green:0.09 blue:0.16 alpha:1.0]; // Deep IUH Blue
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSFontAttributeName: [UIFont boldSystemFontOfSize:17]
        };
        nav.navigationBar.standardAppearance = appearance;
        nav.navigationBar.scrollEdgeAppearance = appearance;
    } else {
        nav.navigationBar.barTintColor = [UIColor colorWithRed:0.06 green:0.09 blue:0.16 alpha:1.0];
        nav.navigationBar.tintColor = [UIColor whiteColor];
        nav.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};
    }
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.90 green:0.75 blue:0.48 alpha:1.0]; // Gold Accent
    
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
