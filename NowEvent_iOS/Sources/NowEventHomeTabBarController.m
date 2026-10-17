#import "NowEventHomeTabBarController.h"
#import "NowEventTheme.h"
#import "NowEventEventsViewController.h"
#import "NowEventSettingsViewController.h"

@implementation NowEventHomeTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Events VC
    NowEventEventsViewController *eventsVC = [[NowEventEventsViewController alloc] init];
    eventsVC.tabBarItem.title = @"Sự Kiện";
    if (@available(iOS 13.0, *)) {
        eventsVC.tabBarItem.image = [UIImage systemImageNamed:@"list.bullet.rectangle"];
        eventsVC.tabBarItem.selectedImage = [UIImage systemImageNamed:@"list.bullet.rectangle.fill"];
    } else {
        eventsVC.tabBarItem.image = [NowEventTheme drawPowerIconWithSize:CGSizeMake(24, 24) color:[NowEventTheme textMuted]];
    }
    
    // 2. Settings VC
    NowEventSettingsViewController *settingsVC = [[NowEventSettingsViewController alloc] init];
    settingsVC.tabBarItem.title = @"Cài Đặt";
    if (@available(iOS 13.0, *)) {
        settingsVC.tabBarItem.image = [UIImage systemImageNamed:@"gearshape"];
        settingsVC.tabBarItem.selectedImage = [UIImage systemImageNamed:@"gearshape.fill"];
    } else {
        settingsVC.tabBarItem.image = [NowEventTheme drawRadarIconWithSize:CGSizeMake(24, 24) color:[NowEventTheme textMuted]];
    }
    
    self.viewControllers = @[eventsVC, settingsVC];
    
    // Style TabBar
    self.tabBar.tintColor = [NowEventTheme accentOrange];
    self.tabBar.unselectedItemTintColor = [NowEventTheme textMuted];
    self.tabBar.backgroundColor = [UIColor whiteColor];
    
    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [[UITabBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor whiteColor];
        
        appearance.stackedLayoutAppearance.selected.iconColor = [NowEventTheme accentOrange];
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = @{
            NSForegroundColorAttributeName: [NowEventTheme accentOrange],
            NSFontAttributeName: [UIFont boldSystemFontOfSize:11]
        };
        appearance.stackedLayoutAppearance.normal.iconColor = [NowEventTheme textMuted];
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = @{
            NSForegroundColorAttributeName: [NowEventTheme textMuted],
            NSFontAttributeName: [UIFont systemFontOfSize:11]
        };
        
        self.tabBar.standardAppearance = appearance;
        if (@available(iOS 15.0, *)) {
            self.tabBar.scrollEdgeAppearance = appearance;
        }
    }
}

@end
