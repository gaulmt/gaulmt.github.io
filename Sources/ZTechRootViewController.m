#import "ZTechRootViewController.h"
#import "ZTechDeviceDatabase.h"
#import "ZTechLicenseManager.h"
#import "ZTechVaultManager.h"
#import "ZTechVectorIcons.h"

#pragma mark - Crash-Proof Native TextField & Multi-Fallback Clipboard Reader

static NSString *ZTechReadClipboardSafely(void) {
    // 1. Primary: UIPasteboard (with writable TMPDIR=/tmp and kTCCServicePasteboard entitlement)
    @try {
        UIPasteboard *pb = [UIPasteboard generalPasteboard];
        if (pb) {
            NSString *s = pb.string;
            if ([s isKindOfClass:[NSString class]] && s.length > 0) {
                return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
            NSArray<NSString *> *arr = pb.strings;
            if ([arr isKindOfClass:[NSArray class]] && arr.count > 0 && [arr.firstObject isKindOfClass:[NSString class]]) {
                NSString *first = [arr.firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (first.length > 0) return first;
            }
            NSArray<NSString *> *types = @[@"public.utf8-plain-text", @"public.plain-text", @"public.text", @"NSStringPboardType"];
            for (NSString *t in types) {
                NSData *d = [pb dataForPasteboardType:t];
                if ([d isKindOfClass:[NSData class]] && d.length > 0) {
                    NSString *decoded = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
                    if (decoded.length > 0) {
                        return [decoded stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    }
                }
            }
        }
    } @catch (NSException *e) {}

    // 2. Fallback: Direct scan of iOS pboardd cache (/var/mobile/Library/Caches/com.apple.Pasteboard)
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray<NSString *> *pbRoots = @[
            @"/var/mobile/Library/Caches/com.apple.Pasteboard",
            @"/private/var/mobile/Library/Caches/com.apple.Pasteboard",
            @"/var/jb/var/mobile/Library/Caches/com.apple.Pasteboard"
        ];
        NSString *newestFile = nil;
        NSDate *newestDate = nil;

        for (NSString *root in pbRoots) {
            NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
            NSString *rel = nil;
            while ((rel = [en nextObject])) {
                NSString *full = [root stringByAppendingPathComponent:rel];
                NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
                if ([attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
                    unsigned long long fSize = [attrs[NSFileSize] unsignedLongLongValue];
                    if (fSize > 0 && fSize < 4096 && ![rel hasSuffix:@".plist"] && ![rel hasSuffix:@".db"]) {
                        NSDate *mDate = attrs[NSFileModificationDate];
                        if (!newestDate || (mDate && [mDate compare:newestDate] == NSOrderedDescending)) {
                            newestDate = mDate;
                            newestFile = full;
                        }
                    }
                }
            }
        }
        if (newestFile) {
            NSData *raw = [NSData dataWithContentsOfFile:newestFile];
            if (raw.length > 0) {
                NSString *txt = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
                if (txt.length > 0) {
                    NSString *clean = [txt stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (clean.length > 0) return clean;
                }
            }
        }
    } @catch (NSException *e) {}

    return @"";
}

@interface ZTechSafeTextField : UITextField
@property (nonatomic, assign) UIEdgeInsets textInsets;
@end

@implementation ZTechSafeTextField

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _textInsets = UIEdgeInsetsMake(0, 14, 0, 78);
        if (@available(iOS 11.0, *)) {
            self.pasteConfiguration = nil;
            if (self.textDragInteraction) {
                self.textDragInteraction.enabled = NO;
            }
        }
        if (@available(iOS 15.0, *)) {
            self.inputAssistantItem.leadingBarButtonGroups = @[];
            self.inputAssistantItem.trailingBarButtonGroups = @[];
        }
    }
    return self;
}

- (CGRect)textRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, self.textInsets);
}

- (CGRect)editingRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, self.textInsets);
}

- (CGRect)placeholderRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, self.textInsets);
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(paste:)) return YES;
    if (action == @selector(copy:) || action == @selector(cut:) || action == @selector(selectAll:)) {
        return [super canPerformAction:action withSender:sender];
    }
    return NO;
}

- (void)paste:(id)sender {
    NSString *clip = ZTechReadClipboardSafely();
    if (clip.length > 0) {
        self.text = clip;
        [self sendActionsForControlEvents:UIControlEventEditingChanged];
    }
}

@end

typedef NS_ENUM(NSInteger, ZTechMainTab) {
    ZTechMainTabFeatures = 0,
    ZTechMainTabVault = 1,
    ZTechMainTabLicense = 2
};

@interface ZTechRootViewController () <UITextFieldDelegate>

@property (nonatomic, strong) ZTechDeviceProfile *currentProfile;
@property (nonatomic, assign) ZTechModelTierFilter currentModelTier;
@property (nonatomic, assign) ZTechMainTab activeTab;
@property (nonatomic, assign) BOOL isLightMode;

// Top Bar & Toast Banner
@property (nonatomic, strong) UIView *topHeaderBar;
@property (nonatomic, strong) UIButton *themeToggleButton;
@property (nonatomic, strong) UIView *headerLicenseBadge;
@property (nonatomic, strong) UIImageView *headerLicenseIcon;
@property (nonatomic, strong) UILabel *headerLicenseText;
@property (nonatomic, strong) UIView *toastBannerView;
@property (nonatomic, strong) UILabel *toastBannerLabel;

// Smooth Full-Screen Loading HUD Overlay
@property (nonatomic, strong) UIView *loadingOverlayView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@property (nonatomic, strong) UILabel *loadingTitleLabel;
@property (nonatomic, strong) UILabel *loadingSubLabel;

// ScrollView & 3 Tab Containers
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIStackView *tabFeaturesStack;
@property (nonatomic, strong) UIStackView *tabVaultStack;
@property (nonatomic, strong) UIStackView *tabLicenseStack;

// Bottom Custom Tab Bar
@property (nonatomic, strong) UIView *bottomTabBar;
@property (nonatomic, strong) NSArray<UIControl *> *tabButtons;
@property (nonatomic, strong) NSArray<UIImageView *> *tabIcons;
@property (nonatomic, strong) NSArray<UILabel *> *tabLabels;
@property (nonatomic, strong) NSArray<UIView *> *tabIndicators;

// TAB 1: Features UI
@property (nonatomic, strong) UILabel *modelHeroLabel;
@property (nonatomic, strong) UILabel *machineBadgeLabel;
@property (nonatomic, strong) UILabel *iosBadgeLabel;
@property (nonatomic, strong) UILabel *uuidMonoLabel;
@property (nonatomic, strong) UILabel *specChipValueLabel;
@property (nonatomic, strong) UILabel *specScreenValueLabel;
@property (nonatomic, strong) UILabel *specNetValueLabel;
@property (nonatomic, strong) UILabel *specBatValueLabel;
@property (nonatomic, strong) NSArray<UIButton *> *tierSegmentButtons;

@property (nonatomic, strong) UIButton *changeDeviceButton;
@property (nonatomic, strong) UIButton *cleanResetButton;
@property (nonatomic, strong) UIButton *syncIPButton;
@property (nonatomic, strong) UIButton *openZaloButton;
@property (nonatomic, strong) UIButton *btnCopyReport;

@property (nonatomic, strong) UISwitch *lockModelSwitch;
@property (nonatomic, strong) UILabel *lockModelSubLabel;
@property (nonatomic, strong) UISwitch *respringSwitch;
@property (nonatomic, strong) UILabel *respringSubLabel;
@property (nonatomic, strong) UISwitch *sameScreenSwitch;
@property (nonatomic, strong) UILabel *sameScreenSubLabel;
@property (nonatomic, strong) UISwitch *matchChipSwitch;
@property (nonatomic, strong) UILabel *matchChipSubLabel;
@property (nonatomic, strong) UILabel *checkDetailLabel;

// TAB 2: Vault & Proxy UI
@property (nonatomic, strong) UILabel *vaultCountBadgeLabel;
@property (nonatomic, strong) UILabel *activeProxyStatusLabel;
@property (nonatomic, strong) UIImageView *activeProxyIconView;
@property (nonatomic, strong) UIStackView *vaultItemsStack;
@property (nonatomic, strong) NSArray<ZTechVaultAccount *> *vaultAccounts;
@property (nonatomic, copy) NSString *pendingDeleteAccountId;

// TAB 3: License UI
@property (nonatomic, strong) UIImageView *licShieldIconView;
@property (nonatomic, strong) UILabel *licMainStateLabel;
@property (nonatomic, strong) UILabel *licKeyUsedValueLabel;
@property (nonatomic, strong) UILabel *licPlanDetailValueLabel;
@property (nonatomic, strong) UIButton *btnRefreshLicenseCloud;

// Minimalist Key Input Overlay (Only Key Input Box + Confirm Button)
@property (nonatomic, strong) UIView *lockOverlayView;
@property (nonatomic, strong) ZTechSafeTextField *keyInputField;
@property (nonatomic, strong) UILabel *lockStatusMsgLabel;
@property (nonatomic, strong) UIButton *btnActivateKey;
@property (nonatomic, strong) UIButton *btnCloseKeyOverlay;

// Vault / Proxy Editor Modal Overlay
@property (nonatomic, strong) UIView *vaultModalOverlay;
@property (nonatomic, strong) UILabel *vaultModalTitleLabel;
@property (nonatomic, strong) ZTechSafeTextField *vaultNameInputField;
@property (nonatomic, strong) ZTechSafeTextField *vaultProxyInputField;
@property (nonatomic, strong) UIButton *btnVaultSaveConfirm;
@property (nonatomic, assign) BOOL isSavingNewVaultAccount;
@property (nonatomic, copy) NSString *editingVaultAccountId;

// Airplane Mode IP Rotation Modal & State
@property (nonatomic, strong) UIView *airplaneModalOverlay;
@property (nonatomic, strong) UIImageView *airplaneModalIcon;
@property (nonatomic, strong) UILabel *airplaneModalTitle;
@property (nonatomic, strong) UILabel *airplaneModalDesc;
@property (nonatomic, strong) UILabel *airplaneCountdownLabel;
@property (nonatomic, strong) UIProgressView *airplaneProgressBar;
@property (nonatomic, strong) UIButton *airplaneSkipButton;
@property (nonatomic, strong) UIButton *airplaneCancelButton;
@property (nonatomic, strong) UIButton *airplaneSettingsButton;
@property (nonatomic, strong) NSTimer *airplaneTimer;
@property (nonatomic, assign) NSInteger airplaneRemainingSeconds;

@end

@implementation ZTechRootViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    if (self.isLightMode) {
        if (@available(iOS 13.0, *)) {
            return UIStatusBarStyleDarkContent;
        }
        return UIStatusBarStyleDefault;
    }
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if (![prefs boolForKey:@"ZTech_V51_LightModeDefaultSet"]) {
        [prefs setBool:YES forKey:@"ZTech_V51_LightModeDefaultSet"];
        [prefs setBool:YES forKey:@"ZTech_LightMode"];
        [prefs synchronize];
    }
    self.isLightMode = [prefs boolForKey:@"ZTech_LightMode"];

    if (![prefs boolForKey:@"ZTech_V46_IP16_Initialized"]) {
        [prefs setBool:YES forKey:@"ZTech_V46_IP16_Initialized"];
        [prefs setBool:YES forKey:@"ZTech_SwitchInitialized"];
        [prefs setBool:NO forKey:@"ZTech_LockModel"];
        [prefs setBool:NO forKey:@"ZTech_SameScreen"];
        [prefs setBool:NO forKey:@"ZTech_MatchChip"];
        [prefs setInteger:ZTechModelTierIPhone16 forKey:@"ZTech_ModelTier"];
        [prefs synchronize];
        self.currentModelTier = ZTechModelTierIPhone16;
        self.currentProfile = [ZTechDeviceDatabase generateProfileWithLockRealModel:NO
                                                                         sameScreen:NO
                                                                          matchChip:NO
                                                                          modelTier:ZTechModelTierIPhone16
                                                                        currentCity:nil];
    } else {
        self.currentModelTier = (ZTechModelTierFilter)[prefs integerForKey:@"ZTech_ModelTier"];
        self.currentProfile = [ZTechDeviceDatabase loadOrCreateDefaultProfile];
    }

    self.activeTab = ZTechMainTabFeatures;
    [self buildCompleteInterface];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onAppBecameActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [self onAppBecameActive];
}

- (void)buildCompleteInterface {
    for (UIView *sub in [self.view.subviews copy]) {
        [sub removeFromSuperview];
    }
    self.view.backgroundColor = [self appBackgroundColor];

    [self buildTopHeaderBar];
    [self buildBottomTabBar];
    [self buildMainScrollContainer];

    [self buildTab1FeaturesView];
    [self buildTab2VaultView];
    [self buildTab3LicenseView];

    [self buildToastBanner];
    [self buildVaultEditorModal];
    [self buildLockScreenOverlay];
    [self buildLoadingOverlay];

    [self onSwitchChanged:nil];
    [self refreshModelTierSegments];
    [self refreshUIWithCurrentProfile];
    [self reloadVaultListUI];
    [self updateLicenseUIState];
    [self switchToTab:self.activeTab animated:NO];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)onTapToggleTheme {
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [gen impactOccurred];

    self.isLightMode = !self.isLightMode;
    [[NSUserDefaults standardUserDefaults] setBool:self.isLightMode forKey:@"ZTech_LightMode"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [UIView transitionWithView:self.view
                      duration:0.22
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        [self buildCompleteInterface];
    } completion:^(BOOL finished) {
        [self showToast:(self.isLightMode
            ? @"Đã chuyển sang giao diện Sáng (Trắng - Xanh Dương)"
            : @"Đã chuyển sang giao diện Tối (Đen - Vàng Gold)") isError:NO];
    }];
}

- (void)onAppBecameActive {
    if (![ZTechLicenseManager isLicenseCurrentlyValid]) {
        if (self.keyInputField && self.keyInputField.text.length == 0) {
            NSString *clip = ZTechReadClipboardSafely();
            if (clip.length >= 6 && clip.length <= 48 && [clip rangeOfString:@" "].location == NSNotFound) {
                self.keyInputField.text = [clip uppercaseString];
            }
        }
    }
    if ([ZTechLicenseManager savedLicenseKey].length > 0) {
        [ZTechLicenseManager refreshSavedLicenseInBackgroundWithCompletion:^(BOOL isValid, NSString * _Nonnull statusText) {
            [self updateLicenseUIState];
        }];
    }
}

#pragma mark - Dual Theme Palette (Light Mode: White & Royal Blue | Dark Mode: Obsidian & Gold)

- (UIColor *)appBackgroundColor {
    return self.isLightMode
        ? [UIColor colorWithRed:0.94 green:0.96 blue:1.00 alpha:1.0]
        : [UIColor colorWithRed:0.04 green:0.05 blue:0.04 alpha:1.0];
}

- (UIColor *)barSurfaceColor {
    return self.isLightMode
        ? [UIColor colorWithRed:1.00 green:1.00 blue:1.00 alpha:1.0]
        : [UIColor colorWithRed:0.05 green:0.06 blue:0.05 alpha:1.0];
}

- (UIColor *)surfaceCardColor {
    return self.isLightMode
        ? [UIColor colorWithRed:1.00 green:1.00 blue:1.00 alpha:1.0]
        : [UIColor colorWithRed:0.08 green:0.09 blue:0.08 alpha:1.0];
}

- (UIColor *)surfaceInsetColor {
    return self.isLightMode
        ? [UIColor colorWithRed:0.95 green:0.97 blue:1.00 alpha:1.0]
        : [UIColor colorWithRed:0.05 green:0.06 blue:0.05 alpha:1.0];
}

- (UIColor *)borderSubtleColor {
    return self.isLightMode
        ? [UIColor colorWithRed:0.82 green:0.88 blue:0.97 alpha:1.0]
        : [UIColor colorWithRed:0.18 green:0.20 blue:0.16 alpha:1.0];
}

- (UIColor *)goldAccentColor {
    // Primary Accent: Royal Zalo Blue (#0068FF) in Light Mode, Gold in Dark Mode
    return self.isLightMode
        ? [UIColor colorWithRed:0.00 green:0.41 blue:1.00 alpha:1.0]
        : [UIColor colorWithRed:0.88 green:0.78 blue:0.52 alpha:1.0];
}

- (UIColor *)creamPrimaryColor {
    // Primary Action Button Background: Royal Blue (#0068FF) in Light Mode, Cream Gold in Dark Mode
    return self.isLightMode
        ? [UIColor colorWithRed:0.00 green:0.41 blue:1.00 alpha:1.0]
        : [UIColor colorWithRed:0.93 green:0.88 blue:0.73 alpha:1.0];
}

- (UIColor *)darkInkColor {
    // Primary Action Button Text/Icon Color: Pure White in Light Mode, Dark Ink in Dark Mode
    return self.isLightMode
        ? [UIColor whiteColor]
        : [UIColor colorWithRed:0.12 green:0.11 blue:0.08 alpha:1.0];
}

- (UIColor *)secondaryTintButtonBgColor {
    return self.isLightMode
        ? [UIColor colorWithRed:0.90 green:0.95 blue:1.00 alpha:1.0]
        : [UIColor colorWithRed:0.15 green:0.13 blue:0.08 alpha:1.0];
}

- (UIColor *)primaryTextColor {
    return self.isLightMode
        ? [UIColor colorWithRed:0.06 green:0.11 blue:0.22 alpha:1.0]
        : [UIColor whiteColor];
}

- (UIColor *)mutedTextColor {
    return self.isLightMode
        ? [UIColor colorWithRed:0.38 green:0.47 blue:0.60 alpha:1.0]
        : [UIColor colorWithRed:0.60 green:0.63 blue:0.60 alpha:1.0];
}

- (UIColor *)emeraldColor {
    return self.isLightMode
        ? [UIColor colorWithRed:0.02 green:0.58 blue:0.38 alpha:1.0]
        : [UIColor colorWithRed:0.30 green:0.85 blue:0.50 alpha:1.0];
}

- (UIColor *)emeraldBadgeBgColor {
    return self.isLightMode
        ? [UIColor colorWithRed:0.89 green:0.97 blue:0.93 alpha:1.0]
        : [UIColor colorWithRed:0.08 green:0.16 blue:0.11 alpha:1.0];
}

- (UIColor *)dangerCoralColor {
    return self.isLightMode
        ? [UIColor colorWithRed:0.86 green:0.18 blue:0.20 alpha:1.0]
        : [UIColor colorWithRed:0.95 green:0.42 blue:0.40 alpha:1.0];
}

- (UIColor *)dangerBadgeBgColor {
    return self.isLightMode
        ? [UIColor colorWithRed:1.00 green:0.92 blue:0.92 alpha:1.0]
        : [UIColor colorWithRed:0.20 green:0.10 blue:0.10 alpha:1.0];
}

#pragma mark - Tactile Spring Button Feedback & Styling Helpers

- (void)attachSpringTouchFeedbackToButton:(UIButton *)btn {
    [btn addTarget:self action:@selector(onButtonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(onButtonTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
}

- (void)onButtonTouchDown:(UIButton *)sender {
    [UIView animateWithDuration:0.10
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        sender.transform = CGAffineTransformMakeScale(0.95, 0.95);
        sender.alpha = 0.85;
    } completion:nil];
}

- (void)onButtonTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.18
                          delay:0
         usingSpringWithDamping:0.65
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        sender.transform = CGAffineTransformIdentity;
        sender.alpha = 1.0;
    } completion:nil];
}

- (void)styleButton:(UIButton *)btn
              title:(NSString *)title
           iconType:(ZTechCustomIconType)iconType
          tintColor:(UIColor *)tintColor
               font:(UIFont *)font {
    [btn setTitleColor:tintColor forState:UIControlStateNormal];
    btn.titleLabel.font = font;
    UIImage *img = [ZTechVectorIcons iconWithType:iconType size:(font.pointSize + 2.0) color:tintColor];
    if (img) {
        [btn setImage:img forState:UIControlStateNormal];
        [btn setTitle:[NSString stringWithFormat:@"  %@", title] forState:UIControlStateNormal];
    } else {
        [btn setImage:nil forState:UIControlStateNormal];
        [btn setTitle:title forState:UIControlStateNormal];
    }
    [self attachSpringTouchFeedbackToButton:btn];
}

- (UIView *)createCardView {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [self surfaceCardColor];
    card.layer.cornerRadius = 18.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [self borderSubtleColor].CGColor;
    if (self.isLightMode) {
        card.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.25 blue:0.65 alpha:1.0].CGColor;
        card.layer.shadowOpacity = 0.06;
        card.layer.shadowOffset = CGSizeMake(0, 4);
        card.layer.shadowRadius = 10.0;
    }
    return card;
}

- (UIView *)createSectionHeaderWithIcon:(ZTechCustomIconType)iconType title:(NSString *)title rightView:(UIView *)rightView {
    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *iconBadge = [[UIView alloc] init];
    iconBadge.translatesAutoresizingMaskIntoConstraints = NO;
    iconBadge.backgroundColor = [self secondaryTintButtonBgColor];
    iconBadge.layer.cornerRadius = 9.0;
    iconBadge.layer.borderWidth = 1.0;
    iconBadge.layer.borderColor = [self borderSubtleColor].CGColor;

    UIImageView *iv = [[UIImageView alloc] initWithImage:[ZTechVectorIcons iconWithType:iconType size:17.0 color:[self goldAccentColor]]];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    [iconBadge addSubview:iv];

    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = title;
    lbl.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightHeavy];
    lbl.textColor = [self goldAccentColor];

    [header addSubview:iconBadge];
    [header addSubview:lbl];

    [NSLayoutConstraint activateConstraints:@[
        [iconBadge.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [iconBadge.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [iconBadge.widthAnchor constraintEqualToConstant:30.0],
        [iconBadge.heightAnchor constraintEqualToConstant:30.0],
        [header.heightAnchor constraintGreaterThanOrEqualToConstant:30.0],

        [iv.centerXAnchor constraintEqualToAnchor:iconBadge.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:iconBadge.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:17.0],
        [iv.heightAnchor constraintEqualToConstant:17.0],

        [lbl.leadingAnchor constraintEqualToAnchor:iconBadge.trailingAnchor constant:10.0],
        [lbl.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]
    ]];

    if (rightView) {
        rightView.translatesAutoresizingMaskIntoConstraints = NO;
        [header addSubview:rightView];
        [NSLayoutConstraint activateConstraints:@[
            [rightView.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
            [rightView.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [lbl.trailingAnchor constraintLessThanOrEqualToAnchor:rightView.leadingAnchor constant:-8.0]
        ]];
    } else {
        [lbl.trailingAnchor constraintEqualToAnchor:header.trailingAnchor].active = YES;
    }

    return header;
}

#pragma mark - Top Header Bar (With Light/Dark Mode Toggle) & Toast + Loading HUD

- (void)buildTopHeaderBar {
    self.topHeaderBar = [[UIView alloc] init];
    self.topHeaderBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.topHeaderBar.backgroundColor = [self barSurfaceColor];
    [self.view addSubview:self.topHeaderBar];

    UIView *bottomLine = [[UIView alloc] init];
    bottomLine.translatesAutoresizingMaskIntoConstraints = NO;
    bottomLine.backgroundColor = [self borderSubtleColor];
    [self.topHeaderBar addSubview:bottomLine];

    UIImageView *crestLogoView = [[UIImageView alloc] initWithImage:[ZTechVectorIcons brandCrestLogoWithSize:38.0]];
    crestLogoView.translatesAutoresizingMaskIntoConstraints = NO;
    crestLogoView.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *appTitle = [[UILabel alloc] init];
    appTitle.translatesAutoresizingMaskIntoConstraints = NO;
    appTitle.text = @"gaulmt -Tech";
    appTitle.font = [UIFont systemFontOfSize:17.5 weight:UIFontWeightHeavy];
    appTitle.textColor = [self primaryTextColor];
    appTitle.adjustsFontSizeToFitWidth = YES;
    appTitle.minimumScaleFactor = 0.8;
    [appTitle setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UILabel *appSub = [[UILabel alloc] init];
    appSub.translatesAutoresizingMaskIntoConstraints = NO;
    appSub.text = @"Identity & Vault · v5.4.1";
    appSub.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
    appSub.textColor = [self mutedTextColor];
    appSub.adjustsFontSizeToFitWidth = YES;
    appSub.minimumScaleFactor = 0.8;
    [appSub setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.themeToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.themeToggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.themeToggleButton.backgroundColor = [self secondaryTintButtonBgColor];
    self.themeToggleButton.layer.cornerRadius = 13.0;
    self.themeToggleButton.layer.borderWidth = 1.0;
    self.themeToggleButton.layer.borderColor = [self borderSubtleColor].CGColor;
    [self.themeToggleButton setTitle:(self.isLightMode ? @"☀️ Sáng" : @"🌙 Tối") forState:UIControlStateNormal];
    [self.themeToggleButton setTitleColor:[self goldAccentColor] forState:UIControlStateNormal];
    self.themeToggleButton.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    self.themeToggleButton.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    [self.themeToggleButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.themeToggleButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self attachSpringTouchFeedbackToButton:self.themeToggleButton];
    [self.themeToggleButton addTarget:self action:@selector(onTapToggleTheme) forControlEvents:UIControlEventTouchUpInside];

    self.headerLicenseBadge = [[UIView alloc] init];
    self.headerLicenseBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerLicenseBadge.backgroundColor = [self emeraldBadgeBgColor];
    self.headerLicenseBadge.layer.cornerRadius = 13.0;
    self.headerLicenseBadge.layer.borderWidth = 1.0;
    self.headerLicenseBadge.layer.borderColor = [self emeraldColor].CGColor;

    self.headerLicenseIcon = [[UIImageView alloc] initWithImage:[ZTechVectorIcons iconWithType:ZTechIconShieldCheck size:13.0 color:[self emeraldColor]]];
    self.headerLicenseIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerLicenseIcon.contentMode = UIViewContentModeScaleAspectFit;

    self.headerLicenseText = [[UILabel alloc] init];
    self.headerLicenseText.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerLicenseText.text = @"ACTIVE";
    self.headerLicenseText.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightHeavy];
    self.headerLicenseText.textColor = [self emeraldColor];
    [self.headerLicenseText setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.headerLicenseText setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    [self.headerLicenseBadge addSubview:self.headerLicenseIcon];
    [self.headerLicenseBadge addSubview:self.headerLicenseText];

    [self.topHeaderBar addSubview:crestLogoView];
    [self.topHeaderBar addSubview:appTitle];
    [self.topHeaderBar addSubview:appSub];
    [self.topHeaderBar addSubview:self.themeToggleButton];
    [self.topHeaderBar addSubview:self.headerLicenseBadge];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.topHeaderBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.topHeaderBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topHeaderBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.topHeaderBar.heightAnchor constraintEqualToConstant:58.0],

        [bottomLine.leadingAnchor constraintEqualToAnchor:self.topHeaderBar.leadingAnchor],
        [bottomLine.trailingAnchor constraintEqualToAnchor:self.topHeaderBar.trailingAnchor],
        [bottomLine.bottomAnchor constraintEqualToAnchor:self.topHeaderBar.bottomAnchor],
        [bottomLine.heightAnchor constraintEqualToConstant:1.0],

        [crestLogoView.leadingAnchor constraintEqualToAnchor:self.topHeaderBar.leadingAnchor constant:12.0],
        [crestLogoView.centerYAnchor constraintEqualToAnchor:self.topHeaderBar.centerYAnchor],
        [crestLogoView.widthAnchor constraintEqualToConstant:36.0],
        [crestLogoView.heightAnchor constraintEqualToConstant:36.0],

        [appTitle.topAnchor constraintEqualToAnchor:crestLogoView.topAnchor constant:0.0],
        [appTitle.leadingAnchor constraintEqualToAnchor:crestLogoView.trailingAnchor constant:8.0],
        [appTitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.themeToggleButton.leadingAnchor constant:-6.0],

        [appSub.topAnchor constraintEqualToAnchor:appTitle.bottomAnchor constant:1.0],
        [appSub.leadingAnchor constraintEqualToAnchor:crestLogoView.trailingAnchor constant:8.0],
        [appSub.trailingAnchor constraintLessThanOrEqualToAnchor:self.themeToggleButton.leadingAnchor constant:-6.0],

        [self.headerLicenseBadge.trailingAnchor constraintEqualToAnchor:self.topHeaderBar.trailingAnchor constant:-12.0],
        [self.headerLicenseBadge.centerYAnchor constraintEqualToAnchor:self.topHeaderBar.centerYAnchor],
        [self.headerLicenseBadge.heightAnchor constraintEqualToConstant:26.0],

        [self.headerLicenseIcon.leadingAnchor constraintEqualToAnchor:self.headerLicenseBadge.leadingAnchor constant:7.0],
        [self.headerLicenseIcon.centerYAnchor constraintEqualToAnchor:self.headerLicenseBadge.centerYAnchor],
        [self.headerLicenseIcon.widthAnchor constraintEqualToConstant:13.0],
        [self.headerLicenseIcon.heightAnchor constraintEqualToConstant:13.0],

        [self.headerLicenseText.leadingAnchor constraintEqualToAnchor:self.headerLicenseIcon.trailingAnchor constant:4.0],
        [self.headerLicenseText.trailingAnchor constraintEqualToAnchor:self.headerLicenseBadge.trailingAnchor constant:-8.0],
        [self.headerLicenseText.centerYAnchor constraintEqualToAnchor:self.headerLicenseBadge.centerYAnchor],

        [self.themeToggleButton.trailingAnchor constraintEqualToAnchor:self.headerLicenseBadge.leadingAnchor constant:-6.0],
        [self.themeToggleButton.centerYAnchor constraintEqualToAnchor:self.topHeaderBar.centerYAnchor],
        [self.themeToggleButton.heightAnchor constraintEqualToConstant:26.0]
    ]];
}

- (void)buildToastBanner {
    self.toastBannerView = [[UIView alloc] init];
    self.toastBannerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.toastBannerView.backgroundColor = [self surfaceCardColor];
    self.toastBannerView.layer.cornerRadius = 12.0;
    self.toastBannerView.layer.borderWidth = 1.4;
    self.toastBannerView.layer.borderColor = [self goldAccentColor].CGColor;
    self.toastBannerView.hidden = YES;
    self.toastBannerView.alpha = 0.0;
    [self.view addSubview:self.toastBannerView];

    self.toastBannerLabel = [[UILabel alloc] init];
    self.toastBannerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.toastBannerLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
    self.toastBannerLabel.textColor = [self primaryTextColor];
    self.toastBannerLabel.textAlignment = NSTextAlignmentCenter;
    self.toastBannerLabel.numberOfLines = 2;
    [self.toastBannerView addSubview:self.toastBannerLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.toastBannerView.topAnchor constraintEqualToAnchor:self.topHeaderBar.bottomAnchor constant:8.0],
        [self.toastBannerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [self.toastBannerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],

        [self.toastBannerLabel.topAnchor constraintEqualToAnchor:self.toastBannerView.topAnchor constant:10.0],
        [self.toastBannerLabel.leadingAnchor constraintEqualToAnchor:self.toastBannerView.leadingAnchor constant:12.0],
        [self.toastBannerLabel.trailingAnchor constraintEqualToAnchor:self.toastBannerView.trailingAnchor constant:-12.0],
        [self.toastBannerLabel.bottomAnchor constraintEqualToAnchor:self.toastBannerView.bottomAnchor constant:-10.0]
    ]];
}

- (void)showToast:(NSString *)message isError:(BOOL)isError {
    self.toastBannerLabel.text = message;
    self.toastBannerLabel.textColor = isError ? [self dangerCoralColor] : [self primaryTextColor];
    self.toastBannerView.backgroundColor = isError ? [self dangerBadgeBgColor] : [self surfaceCardColor];
    self.toastBannerView.layer.borderColor = isError ? [self dangerCoralColor].CGColor : [self goldAccentColor].CGColor;
    self.toastBannerView.hidden = NO;

    [UIView animateWithDuration:0.2 animations:^{
        self.toastBannerView.alpha = 1.0;
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{
            self.toastBannerView.alpha = 0.0;
        } completion:^(BOOL finished) {
            if (self.toastBannerView.alpha == 0.0) {
                self.toastBannerView.hidden = YES;
            }
        }];
    });
}

- (void)buildLoadingOverlay {
    self.loadingOverlayView = [[UIView alloc] init];
    self.loadingOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingOverlayView.backgroundColor = self.isLightMode
        ? [UIColor colorWithRed:0.05 green:0.12 blue:0.26 alpha:0.42]
        : [UIColor colorWithRed:0.01 green:0.02 blue:0.01 alpha:0.76];
    self.loadingOverlayView.hidden = YES;
    self.loadingOverlayView.alpha = 0.0;
    [self.view addSubview:self.loadingOverlayView];

    UIView *hudCard = [self createCardView];
    hudCard.layer.borderWidth = 1.5;
    hudCard.layer.borderColor = [self goldAccentColor].CGColor;
    [self.loadingOverlayView addSubview:hudCard];

    if (@available(iOS 13.0, *)) {
        self.loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    } else {
        self.loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    }
    self.loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingSpinner.color = [self goldAccentColor];

    self.loadingTitleLabel = [[UILabel alloc] init];
    self.loadingTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingTitleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightHeavy];
    self.loadingTitleLabel.textColor = [self goldAccentColor];
    self.loadingTitleLabel.textAlignment = NSTextAlignmentCenter;

    self.loadingSubLabel = [[UILabel alloc] init];
    self.loadingSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingSubLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
    self.loadingSubLabel.textColor = [self primaryTextColor];
    self.loadingSubLabel.textAlignment = NSTextAlignmentCenter;
    self.loadingSubLabel.numberOfLines = 2;

    [hudCard addSubview:self.loadingSpinner];
    [hudCard addSubview:self.loadingTitleLabel];
    [hudCard addSubview:self.loadingSubLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.loadingOverlayView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.loadingOverlayView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.loadingOverlayView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.loadingOverlayView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [hudCard.centerXAnchor constraintEqualToAnchor:self.loadingOverlayView.centerXAnchor],
        [hudCard.centerYAnchor constraintEqualToAnchor:self.loadingOverlayView.centerYAnchor],
        [hudCard.widthAnchor constraintEqualToConstant:265.0],

        [self.loadingSpinner.topAnchor constraintEqualToAnchor:hudCard.topAnchor constant:22.0],
        [self.loadingSpinner.centerXAnchor constraintEqualToAnchor:hudCard.centerXAnchor],

        [self.loadingTitleLabel.topAnchor constraintEqualToAnchor:self.loadingSpinner.bottomAnchor constant:14.0],
        [self.loadingTitleLabel.leadingAnchor constraintEqualToAnchor:hudCard.leadingAnchor constant:14.0],
        [self.loadingTitleLabel.trailingAnchor constraintEqualToAnchor:hudCard.trailingAnchor constant:-14.0],

        [self.loadingSubLabel.topAnchor constraintEqualToAnchor:self.loadingTitleLabel.bottomAnchor constant:5.0],
        [self.loadingSubLabel.leadingAnchor constraintEqualToAnchor:hudCard.leadingAnchor constant:14.0],
        [self.loadingSubLabel.trailingAnchor constraintEqualToAnchor:hudCard.trailingAnchor constant:-14.0],
        [self.loadingSubLabel.bottomAnchor constraintEqualToAnchor:hudCard.bottomAnchor constant:-20.0]
    ]];
}

- (void)showLoadingWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self.loadingTitleLabel.text = title;
    self.loadingSubLabel.text = subtitle;
    [self.loadingSpinner startAnimating];
    self.loadingOverlayView.hidden = NO;
    [UIView animateWithDuration:0.15 animations:^{
        self.loadingOverlayView.alpha = 1.0;
    }];
}

- (void)hideLoadingOverlayAfterDelay:(NSTimeInterval)delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.20 animations:^{
            self.loadingOverlayView.alpha = 0.0;
        } completion:^(BOOL finished) {
            [self.loadingSpinner stopAnimating];
            self.loadingOverlayView.hidden = YES;
        }];
    });
}

#pragma mark - Bottom 3-Tab Navigation Bar (Custom Duotone SVG Icons)

- (void)buildBottomTabBar {
    self.bottomTabBar = [[UIView alloc] init];
    self.bottomTabBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomTabBar.backgroundColor = [self barSurfaceColor];
    [self.view addSubview:self.bottomTabBar];

    UIView *topLine = [[UIView alloc] init];
    topLine.translatesAutoresizingMaskIntoConstraints = NO;
    topLine.backgroundColor = [self borderSubtleColor];
    [self.bottomTabBar addSubview:topLine];

    UIStackView *tabsRow = [[UIStackView alloc] init];
    tabsRow.translatesAutoresizingMaskIntoConstraints = NO;
    tabsRow.axis = UILayoutConstraintAxisHorizontal;
    tabsRow.distribution = UIStackViewDistributionFillEqually;
    [self.bottomTabBar addSubview:tabsRow];

    NSArray<NSString *> *tabTitles = @[@"Tính năng", @"Kho Acc & Proxy", @"Bản quyền"];
    ZTechCustomIconType tabIconTypes[3] = {ZTechIconTabSpoof, ZTechIconTabVault, ZTechIconTabLicense};

    NSMutableArray<UIControl *> *btns = [NSMutableArray array];
    NSMutableArray<UIImageView *> *icons = [NSMutableArray array];
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NSMutableArray<UIView *> *indicators = [NSMutableArray array];

    for (NSInteger i = 0; i < 3; i++) {
        UIControl *tabCtrl = [[UIControl alloc] init];
        tabCtrl.translatesAutoresizingMaskIntoConstraints = NO;
        tabCtrl.tag = i;
        [tabCtrl addTarget:self action:@selector(onTapTabBarItem:) forControlEvents:UIControlEventTouchUpInside];

        UIView *pillIndicator = [[UIView alloc] init];
        pillIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        pillIndicator.backgroundColor = [self goldAccentColor];
        pillIndicator.layer.cornerRadius = 1.5;
        [tabCtrl addSubview:pillIndicator];

        UIImageView *iv = [[UIImageView alloc] initWithImage:[ZTechVectorIcons iconWithType:tabIconTypes[i] size:22.0 color:[self goldAccentColor]]];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.contentMode = UIViewContentModeScaleAspectFit;
        [tabCtrl addSubview:iv];

        UILabel *lbl = [[UILabel alloc] init];
        lbl.translatesAutoresizingMaskIntoConstraints = NO;
        lbl.text = tabTitles[i];
        lbl.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
        lbl.textAlignment = NSTextAlignmentCenter;
        [tabCtrl addSubview:lbl];

        [NSLayoutConstraint activateConstraints:@[
            [pillIndicator.topAnchor constraintEqualToAnchor:tabCtrl.topAnchor],
            [pillIndicator.centerXAnchor constraintEqualToAnchor:tabCtrl.centerXAnchor],
            [pillIndicator.widthAnchor constraintEqualToConstant:36.0],
            [pillIndicator.heightAnchor constraintEqualToConstant:3.0],

            [iv.topAnchor constraintEqualToAnchor:tabCtrl.topAnchor constant:8.0],
            [iv.centerXAnchor constraintEqualToAnchor:tabCtrl.centerXAnchor],
            [iv.widthAnchor constraintEqualToConstant:23.0],
            [iv.heightAnchor constraintEqualToConstant:23.0],

            [lbl.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:4.0],
            [lbl.leadingAnchor constraintEqualToAnchor:tabCtrl.leadingAnchor constant:4.0],
            [lbl.trailingAnchor constraintEqualToAnchor:tabCtrl.trailingAnchor constant:-4.0]
        ]];

        [tabsRow addArrangedSubview:tabCtrl];
        [btns addObject:tabCtrl];
        [icons addObject:iv];
        [labels addObject:lbl];
        [indicators addObject:pillIndicator];
    }

    self.tabButtons = btns;
    self.tabIcons = icons;
    self.tabLabels = labels;
    self.tabIndicators = indicators;

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.bottomTabBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomTabBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomTabBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.bottomTabBar.topAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-58.0],

        [topLine.topAnchor constraintEqualToAnchor:self.bottomTabBar.topAnchor],
        [topLine.leadingAnchor constraintEqualToAnchor:self.bottomTabBar.leadingAnchor],
        [topLine.trailingAnchor constraintEqualToAnchor:self.bottomTabBar.trailingAnchor],
        [topLine.heightAnchor constraintEqualToConstant:1.0],

        [tabsRow.topAnchor constraintEqualToAnchor:self.bottomTabBar.topAnchor],
        [tabsRow.leadingAnchor constraintEqualToAnchor:self.bottomTabBar.leadingAnchor],
        [tabsRow.trailingAnchor constraintEqualToAnchor:self.bottomTabBar.trailingAnchor],
        [tabsRow.heightAnchor constraintEqualToConstant:58.0]
    ]];
}

- (void)onTapTabBarItem:(UIControl *)sender {
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];
    [self switchToTab:(ZTechMainTab)sender.tag animated:YES];
}

- (void)switchToTab:(ZTechMainTab)tab animated:(BOOL)animated {
    self.activeTab = tab;
    ZTechCustomIconType tabIconTypes[3] = {ZTechIconTabSpoof, ZTechIconTabVault, ZTechIconTabLicense};
    for (NSInteger i = 0; i < self.tabIcons.count; i++) {
        BOOL selected = (i == tab);
        UIColor *c = selected ? [self goldAccentColor] : [self mutedTextColor];
        self.tabIcons[i].image = [ZTechVectorIcons iconWithType:tabIconTypes[i] size:22.0 color:c];
        self.tabLabels[i].textColor = c;
        self.tabIndicators[i].hidden = !selected;
    }

    self.tabFeaturesStack.hidden = (tab != ZTechMainTabFeatures);
    self.tabVaultStack.hidden = (tab != ZTechMainTabVault);
    self.tabLicenseStack.hidden = (tab != ZTechMainTabLicense);

    [self.scrollView setContentOffset:CGPointZero animated:NO];
    if (tab == ZTechMainTabVault) {
        [self reloadVaultListUI];
    } else if (tab == ZTechMainTabLicense) {
        [self updateLicenseUIState];
    }
}

#pragma mark - Main Scroll Container

- (void)buildMainScrollContainer {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 14.0;
    [self.scrollView addSubview:self.contentStack];

    self.tabFeaturesStack = [[UIStackView alloc] init];
    self.tabFeaturesStack.axis = UILayoutConstraintAxisVertical;
    self.tabFeaturesStack.spacing = 14.0;

    self.tabVaultStack = [[UIStackView alloc] init];
    self.tabVaultStack.axis = UILayoutConstraintAxisVertical;
    self.tabVaultStack.spacing = 14.0;

    self.tabLicenseStack = [[UIStackView alloc] init];
    self.tabLicenseStack.axis = UILayoutConstraintAxisVertical;
    self.tabLicenseStack.spacing = 14.0;

    [self.contentStack addArrangedSubview:self.tabFeaturesStack];
    [self.contentStack addArrangedSubview:self.tabVaultStack];
    [self.contentStack addArrangedSubview:self.tabLicenseStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.topHeaderBar.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.bottomTabBar.topAnchor],

        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:14.0],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:16.0],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-16.0],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-24.0],
        [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-32.0]
    ]];
}

#pragma mark - TAB 1: Features (Device Identity, Actions, Switches, Status)

- (UIView *)createSpecTileWithIcon:(ZTechCustomIconType)iconType title:(NSString *)title outValueLabel:(UILabel **)outVal {
    UIView *tile = [[UIView alloc] init];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    tile.backgroundColor = [self surfaceInsetColor];
    tile.layer.cornerRadius = 12.0;
    tile.layer.borderWidth = 1.0;
    tile.layer.borderColor = [self borderSubtleColor].CGColor;

    UIImageView *iv = [[UIImageView alloc] initWithImage:[ZTechVectorIcons iconWithType:iconType size:15.0 color:[self goldAccentColor]]];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *tLbl = [[UILabel alloc] init];
    tLbl.translatesAutoresizingMaskIntoConstraints = NO;
    tLbl.text = title;
    tLbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    tLbl.textColor = [self mutedTextColor];

    UILabel *vLbl = [[UILabel alloc] init];
    vLbl.translatesAutoresizingMaskIntoConstraints = NO;
    vLbl.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
    vLbl.textColor = [self primaryTextColor];
    vLbl.adjustsFontSizeToFitWidth = YES;
    vLbl.minimumScaleFactor = 0.8;

    [tile addSubview:iv];
    [tile addSubview:tLbl];
    [tile addSubview:vLbl];

    [NSLayoutConstraint activateConstraints:@[
        [tile.heightAnchor constraintEqualToConstant:56.0],
        [iv.topAnchor constraintEqualToAnchor:tile.topAnchor constant:10.0],
        [iv.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:11.0],
        [iv.widthAnchor constraintEqualToConstant:15.0],
        [iv.heightAnchor constraintEqualToConstant:15.0],

        [tLbl.centerYAnchor constraintEqualToAnchor:iv.centerYAnchor],
        [tLbl.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:6.0],
        [tLbl.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-8.0],

        [vLbl.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:5.0],
        [vLbl.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:11.0],
        [vLbl.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-8.0]
    ]];

    if (outVal) *outVal = vLbl;
    return tile;
}

- (void)buildTab1FeaturesView {
    // 1. Device Identity Card
    UIView *idCard = [self createCardView];
    UIStackView *idStack = [[UIStackView alloc] init];
    idStack.translatesAutoresizingMaskIntoConstraints = NO;
    idStack.axis = UILayoutConstraintAxisVertical;
    idStack.spacing = 12.0;
    [idCard addSubview:idStack];

    self.btnCopyReport = [UIButton buttonWithType:UIButtonTypeSystem];
    self.btnCopyReport.backgroundColor = [self secondaryTintButtonBgColor];
    self.btnCopyReport.layer.cornerRadius = 8.0;
    self.btnCopyReport.layer.borderWidth = 1.0;
    self.btnCopyReport.layer.borderColor = [self borderSubtleColor].CGColor;
    self.btnCopyReport.contentEdgeInsets = UIEdgeInsetsMake(5.0, 10.0, 5.0, 10.0);
    [self styleButton:self.btnCopyReport
                title:@"Sao chép"
             iconType:ZTechIconCopyClone
            tintColor:[self goldAccentColor]
                 font:[UIFont systemFontOfSize:11.5 weight:UIFontWeightBold]];
    [self.btnCopyReport addTarget:self action:@selector(onTapCopyReport) forControlEvents:UIControlEventTouchUpInside];

    UIView *idHeader = [self createSectionHeaderWithIcon:ZTechIconDevicePhone
                                                   title:@"CẤU HÌNH MÁY ẢO ĐANG CHẠY"
                                               rightView:self.btnCopyReport];
    [idStack addArrangedSubview:idHeader];

    // Hero Model Box
    UIView *heroBox = [[UIView alloc] init];
    heroBox.translatesAutoresizingMaskIntoConstraints = NO;
    heroBox.backgroundColor = [self surfaceInsetColor];
    heroBox.layer.cornerRadius = 14.0;
    heroBox.layer.borderWidth = 1.2;
    heroBox.layer.borderColor = [self borderSubtleColor].CGColor;

    self.modelHeroLabel = [[UILabel alloc] init];
    self.modelHeroLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.modelHeroLabel.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightHeavy];
    self.modelHeroLabel.textColor = [self primaryTextColor];
    self.modelHeroLabel.adjustsFontSizeToFitWidth = YES;

    self.machineBadgeLabel = [[UILabel alloc] init];
    self.machineBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.machineBadgeLabel.backgroundColor = [self secondaryTintButtonBgColor];
    self.machineBadgeLabel.layer.cornerRadius = 6.0;
    self.machineBadgeLabel.layer.masksToBounds = YES;
    self.machineBadgeLabel.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightBold];
    self.machineBadgeLabel.textColor = [self goldAccentColor];
    self.machineBadgeLabel.textAlignment = NSTextAlignmentCenter;

    self.iosBadgeLabel = [[UILabel alloc] init];
    self.iosBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.iosBadgeLabel.backgroundColor = [self emeraldBadgeBgColor];
    self.iosBadgeLabel.layer.cornerRadius = 6.0;
    self.iosBadgeLabel.layer.masksToBounds = YES;
    self.iosBadgeLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
    self.iosBadgeLabel.textColor = [self emeraldColor];
    self.iosBadgeLabel.textAlignment = NSTextAlignmentCenter;

    self.uuidMonoLabel = [[UILabel alloc] init];
    self.uuidMonoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.uuidMonoLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.uuidMonoLabel.textColor = [self mutedTextColor];
    self.uuidMonoLabel.adjustsFontSizeToFitWidth = YES;
    self.uuidMonoLabel.minimumScaleFactor = 0.7;

    [heroBox addSubview:self.modelHeroLabel];
    [heroBox addSubview:self.machineBadgeLabel];
    [heroBox addSubview:self.iosBadgeLabel];
    [heroBox addSubview:self.uuidMonoLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.modelHeroLabel.topAnchor constraintEqualToAnchor:heroBox.topAnchor constant:12.0],
        [self.modelHeroLabel.leadingAnchor constraintEqualToAnchor:heroBox.leadingAnchor constant:14.0],

        [self.iosBadgeLabel.centerYAnchor constraintEqualToAnchor:self.modelHeroLabel.centerYAnchor],
        [self.iosBadgeLabel.trailingAnchor constraintEqualToAnchor:heroBox.trailingAnchor constant:-12.0],
        [self.iosBadgeLabel.heightAnchor constraintEqualToConstant:22.0],

        [self.machineBadgeLabel.centerYAnchor constraintEqualToAnchor:self.modelHeroLabel.centerYAnchor],
        [self.machineBadgeLabel.trailingAnchor constraintEqualToAnchor:self.iosBadgeLabel.leadingAnchor constant:-6.0],
        [self.machineBadgeLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.modelHeroLabel.trailingAnchor constant:8.0],
        [self.machineBadgeLabel.heightAnchor constraintEqualToConstant:22.0],

        [self.uuidMonoLabel.topAnchor constraintEqualToAnchor:self.modelHeroLabel.bottomAnchor constant:6.0],
        [self.uuidMonoLabel.leadingAnchor constraintEqualToAnchor:heroBox.leadingAnchor constant:14.0],
        [self.uuidMonoLabel.trailingAnchor constraintEqualToAnchor:heroBox.trailingAnchor constant:-14.0],
        [self.uuidMonoLabel.bottomAnchor constraintEqualToAnchor:heroBox.bottomAnchor constant:-12.0]
    ]];
    [idStack addArrangedSubview:heroBox];

    // 2x2 Spec Grid
    UILabel *cVal = nil; UILabel *sVal = nil; UILabel *nVal = nil; UILabel *bVal = nil;
    UIView *t1 = [self createSpecTileWithIcon:ZTechIconChipCpu title:@"CHIP & BỘ NHỚ RAM" outValueLabel:&cVal];
    UIView *t2 = [self createSpecTileWithIcon:ZTechIconDisplayScreen title:@"ĐỘ PHÂN GIẢI MÀN" outValueLabel:&sVal];
    UIView *t3 = [self createSpecTileWithIcon:ZTechIconSignalRadar title:@"NHÀ MẠNG & VỊ TRÍ" outValueLabel:&nVal];
    UIView *t4 = [self createSpecTileWithIcon:ZTechIconBatteryBolt title:@"PIN & DANH BẠ ẢO" outValueLabel:&bVal];
    self.specChipValueLabel = cVal;
    self.specScreenValueLabel = sVal;
    self.specNetValueLabel = nVal;
    self.specBatValueLabel = bVal;

    UIStackView *gridRow1 = [[UIStackView alloc] initWithArrangedSubviews:@[t1, t2]];
    gridRow1.axis = UILayoutConstraintAxisHorizontal;
    gridRow1.distribution = UIStackViewDistributionFillEqually;
    gridRow1.spacing = 8.0;

    UIStackView *gridRow2 = [[UIStackView alloc] initWithArrangedSubviews:@[t3, t4]];
    gridRow2.axis = UILayoutConstraintAxisHorizontal;
    gridRow2.distribution = UIStackViewDistributionFillEqually;
    gridRow2.spacing = 8.0;

    [idStack addArrangedSubview:gridRow1];
    [idStack addArrangedSubview:gridRow2];

    // 3-Button Model Tier Segmented Bar
    UILabel *tierCaption = [[UILabel alloc] init];
    tierCaption.text = @"CHỌN PHÂN KHÚC ĐỜI MÁY KHI RANDOM:";
    tierCaption.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    tierCaption.textColor = [self mutedTextColor];
    [idStack addArrangedSubview:tierCaption];

    UIStackView *segRow = [[UIStackView alloc] init];
    segRow.axis = UILayoutConstraintAxisHorizontal;
    segRow.distribution = UIStackViewDistributionFillEqually;
    segRow.spacing = 6.0;
    [segRow.heightAnchor constraintEqualToConstant:36.0].active = YES;

    NSArray<NSString *> *segTitles = @[@"Chỉ iPhone 16", @"Đời Cao 14–16", @"Tất cả (6s–16)"];
    NSArray<NSNumber *> *segTags = @[@(ZTechModelTierIPhone16), @(ZTechModelTierHighEnd), @(ZTechModelTierAll)];
    NSMutableArray<UIButton *> *segBtns = [NSMutableArray array];

    for (NSInteger i = 0; i < segTitles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = [segTags[i] integerValue];
        b.layer.cornerRadius = 9.0;
        b.layer.borderWidth = 1.0;
        [b setTitle:segTitles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
        [self attachSpringTouchFeedbackToButton:b];
        [b addTarget:self action:@selector(onTapSelectModelTierSegment:) forControlEvents:UIControlEventTouchUpInside];
        [segRow addArrangedSubview:b];
        [segBtns addObject:b];
    }
    self.tierSegmentButtons = segBtns;
    [idStack addArrangedSubview:segRow];

    [NSLayoutConstraint activateConstraints:@[
        [idStack.topAnchor constraintEqualToAnchor:idCard.topAnchor constant:16.0],
        [idStack.leadingAnchor constraintEqualToAnchor:idCard.leadingAnchor constant:16.0],
        [idStack.trailingAnchor constraintEqualToAnchor:idCard.trailingAnchor constant:-16.0],
        [idStack.bottomAnchor constraintEqualToAnchor:idCard.bottomAnchor constant:-16.0]
    ]];
    [self.tabFeaturesStack addArrangedSubview:idCard];

    // 2. Primary Action Card
    UIView *actCard = [self createCardView];
    UIStackView *actStack = [[UIStackView alloc] init];
    actStack.translatesAutoresizingMaskIntoConstraints = NO;
    actStack.axis = UILayoutConstraintAxisVertical;
    actStack.spacing = 10.0;
    [actCard addSubview:actStack];

    UIView *actHeader = [self createSectionHeaderWithIcon:ZTechIconRefreshMorph
                                                    title:@"THAO TÁC NHANH"
                                                rightView:nil];
    [actStack addArrangedSubview:actHeader];

    self.changeDeviceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.changeDeviceButton.backgroundColor = [self creamPrimaryColor];
    self.changeDeviceButton.layer.cornerRadius = 14.0;
    [self styleButton:self.changeDeviceButton
                title:@"Đổi cấu hình máy ảo mới (Change Device)"
             iconType:ZTechIconRefreshMorph
            tintColor:[self darkInkColor]
                 font:[UIFont systemFontOfSize:15.5 weight:UIFontWeightHeavy]];
    [self.changeDeviceButton.heightAnchor constraintEqualToConstant:50.0].active = YES;
    [self.changeDeviceButton addTarget:self action:@selector(onTapChangeDevice) forControlEvents:UIControlEventTouchUpInside];

    self.cleanResetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.cleanResetButton.backgroundColor = [self secondaryTintButtonBgColor];
    self.cleanResetButton.layer.cornerRadius = 14.0;
    self.cleanResetButton.layer.borderWidth = 1.2;
    self.cleanResetButton.layer.borderColor = [self goldAccentColor].CGColor;
    [self styleButton:self.cleanResetButton
                title:@"Làm mới dữ liệu Zalo & Tạo phiên mới"
             iconType:ZTechIconCleanWipe
            tintColor:[self goldAccentColor]
                 font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightBold]];
    [self.cleanResetButton.heightAnchor constraintEqualToConstant:48.0].active = YES;
    [self.cleanResetButton addTarget:self action:@selector(onTapCleanReset) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *subActRow = [[UIStackView alloc] init];
    subActRow.axis = UILayoutConstraintAxisHorizontal;
    subActRow.distribution = UIStackViewDistributionFillEqually;
    subActRow.spacing = 10.0;
    [subActRow.heightAnchor constraintEqualToConstant:44.0].active = YES;

    self.syncIPButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.syncIPButton.backgroundColor = [self surfaceInsetColor];
    self.syncIPButton.layer.cornerRadius = 12.0;
    self.syncIPButton.layer.borderWidth = 1.0;
    self.syncIPButton.layer.borderColor = [self borderSubtleColor].CGColor;
    [self styleButton:self.syncIPButton
                title:@"Đổi IP"
             iconType:ZTechIconAirplaneFly
            tintColor:[self primaryTextColor]
                 font:[UIFont systemFontOfSize:13.5 weight:UIFontWeightBold]];
    [self.syncIPButton addTarget:self action:@selector(onTapRotateIP) forControlEvents:UIControlEventTouchUpInside];

    self.openZaloButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.openZaloButton.backgroundColor = [self emeraldBadgeBgColor];
    self.openZaloButton.layer.cornerRadius = 12.0;
    self.openZaloButton.layer.borderWidth = 1.0;
    self.openZaloButton.layer.borderColor = [self emeraldColor].CGColor;
    [self styleButton:self.openZaloButton
                title:@"Mở Zalo"
             iconType:ZTechIconRocketLaunch
            tintColor:[self emeraldColor]
                 font:[UIFont systemFontOfSize:13.5 weight:UIFontWeightBold]];
    [self.openZaloButton addTarget:self action:@selector(onTapQuickLaunchZalo) forControlEvents:UIControlEventTouchUpInside];

    [subActRow addArrangedSubview:self.syncIPButton];
    [subActRow addArrangedSubview:self.openZaloButton];

    [actStack addArrangedSubview:self.changeDeviceButton];
    [actStack addArrangedSubview:self.cleanResetButton];
    [actStack addArrangedSubview:subActRow];

    [NSLayoutConstraint activateConstraints:@[
        [actStack.topAnchor constraintEqualToAnchor:actCard.topAnchor constant:16.0],
        [actStack.leadingAnchor constraintEqualToAnchor:actCard.leadingAnchor constant:16.0],
        [actStack.trailingAnchor constraintEqualToAnchor:actCard.trailingAnchor constant:-16.0],
        [actStack.bottomAnchor constraintEqualToAnchor:actCard.bottomAnchor constant:-16.0]
    ]];
    [self.tabFeaturesStack addArrangedSubview:actCard];

    // 3. Switches Card
    UIView *swCard = [self createCardView];
    UIStackView *swStack = [[UIStackView alloc] init];
    swStack.translatesAutoresizingMaskIntoConstraints = NO;
    swStack.axis = UILayoutConstraintAxisVertical;
    swStack.spacing = 10.0;
    [swCard addSubview:swStack];

    UIView *swHeader = [self createSectionHeaderWithIcon:ZTechIconSlidersTune
                                                   title:@"TUỲ CHỈNH CHẾ ĐỘ FAKE"
                                               rightView:nil];
    [swStack addArrangedSubview:swHeader];

    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    BOOL defLock = [prefs boolForKey:@"ZTech_LockModel"];
    BOOL defRespring = [prefs boolForKey:@"ZTech_Respring"];
    BOOL defScreen = [prefs boolForKey:@"ZTech_SameScreen"];
    BOOL defChip = [prefs boolForKey:@"ZTech_MatchChip"];

    UISwitch *sw1 = nil; UILabel *sub1 = nil;
    UIView *row1 = [self createSwitchRowWithIcon:ZTechIconShieldLock
                                           title:@"Khoá đời máy · Giữ model thật"
                                        subtitle:@"OFF: Cho phép đổi sang iPhone 16 Series"
                                       isDefault:defLock
                                       outSwitch:&sw1
                                     outSubLabel:&sub1];
    self.lockModelSwitch = sw1; self.lockModelSubLabel = sub1;

    UISwitch *sw2 = nil; UILabel *sub2 = nil;
    UIView *row2 = [self createSwitchRowWithIcon:ZTechIconRefreshMorph
                                           title:@"Respring sau khi đổi máy"
                                        subtitle:@"OFF: Áp dụng tức thì không cần khởi động lại màn hình"
                                       isDefault:defRespring
                                       outSwitch:&sw2
                                     outSubLabel:&sub2];
    self.respringSwitch = sw2; self.respringSubLabel = sub2;

    UISwitch *sw3 = nil; UILabel *sub3 = nil;
    UIView *row3 = [self createSwitchRowWithIcon:ZTechIconDisplayScreen
                                           title:@"Giới hạn cùng kích thước màn hình"
                                        subtitle:@"OFF: Cho phép giả lập màn hình lớn của Pro Max"
                                       isDefault:defScreen
                                       outSwitch:&sw3
                                     outSubLabel:&sub3];
    self.sameScreenSwitch = sw3; self.sameScreenSubLabel = sub3;

    UISwitch *sw4 = nil; UILabel *sub4 = nil;
    UIView *row4 = [self createSwitchRowWithIcon:ZTechIconChipCpu
                                           title:@"Giới hạn cùng dung lượng RAM máy thật"
                                        subtitle:@"OFF: Cho phép giả lập Chip A18 Pro & RAM 8GB"
                                       isDefault:defChip
                                       outSwitch:&sw4
                                     outSubLabel:&sub4];
    self.matchChipSwitch = sw4; self.matchChipSubLabel = sub4;

    [swStack addArrangedSubview:row1];
    [swStack addArrangedSubview:row2];
    [swStack addArrangedSubview:row3];
    [swStack addArrangedSubview:row4];

    [NSLayoutConstraint activateConstraints:@[
        [swStack.topAnchor constraintEqualToAnchor:swCard.topAnchor constant:16.0],
        [swStack.leadingAnchor constraintEqualToAnchor:swCard.leadingAnchor constant:16.0],
        [swStack.trailingAnchor constraintEqualToAnchor:swCard.trailingAnchor constant:-16.0],
        [swStack.bottomAnchor constraintEqualToAnchor:swCard.bottomAnchor constant:-16.0]
    ]];
    [self.tabFeaturesStack addArrangedSubview:swCard];

    // 4. System Hook Check Card
    UIView *chkCard = [self createCardView];
    UIStackView *chkStack = [[UIStackView alloc] init];
    chkStack.translatesAutoresizingMaskIntoConstraints = NO;
    chkStack.axis = UILayoutConstraintAxisVertical;
    chkStack.spacing = 8.0;
    [chkCard addSubview:chkStack];

    UIView *chkHeader = [self createSectionHeaderWithIcon:ZTechIconShieldCheck
                                                    title:@"TRẠNG THÁI GHI HỆ THỐNG (KERNEL / HOOK)"
                                                rightView:nil];
    self.checkDetailLabel = [[UILabel alloc] init];
    self.checkDetailLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
    self.checkDetailLabel.textColor = [self mutedTextColor];
    self.checkDetailLabel.numberOfLines = 0;

    [chkStack addArrangedSubview:chkHeader];
    [chkStack addArrangedSubview:self.checkDetailLabel];

    [NSLayoutConstraint activateConstraints:@[
        [chkStack.topAnchor constraintEqualToAnchor:chkCard.topAnchor constant:14.0],
        [chkStack.leadingAnchor constraintEqualToAnchor:chkCard.leadingAnchor constant:16.0],
        [chkStack.trailingAnchor constraintEqualToAnchor:chkCard.trailingAnchor constant:-16.0],
        [chkStack.bottomAnchor constraintEqualToAnchor:chkCard.bottomAnchor constant:-14.0]
    ]];
    [self.tabFeaturesStack addArrangedSubview:chkCard];
}

- (UIView *)createSwitchRowWithIcon:(ZTechCustomIconType)iconType
                              title:(NSString *)title
                           subtitle:(NSString *)subtitle
                          isDefault:(BOOL)defaultOn
                          outSwitch:(UISwitch **)outSwitch
                        outSubLabel:(UILabel **)outSubLabel {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [self surfaceInsetColor];
    row.layer.cornerRadius = 12.0;
    row.layer.borderWidth = 1.0;
    row.layer.borderColor = [self borderSubtleColor].CGColor;

    UIImageView *iv = [[UIImageView alloc] initWithImage:[ZTechVectorIcons iconWithType:iconType size:16.0 color:[self goldAccentColor]]];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    titleLabel.textColor = [self primaryTextColor];
    titleLabel.adjustsFontSizeToFitWidth = YES;

    UILabel *subLabel = [[UILabel alloc] init];
    subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subLabel.text = subtitle;
    subLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
    subLabel.textColor = [self mutedTextColor];
    subLabel.numberOfLines = 0;

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.on = defaultOn;
    toggle.onTintColor = [self goldAccentColor];
    [toggle addTarget:self action:@selector(onSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    [row addSubview:iv];
    [row addSubview:titleLabel];
    [row addSubview:subLabel];
    [row addSubview:toggle];

    [NSLayoutConstraint activateConstraints:@[
        [iv.topAnchor constraintEqualToAnchor:row.topAnchor constant:12.0],
        [iv.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12.0],
        [iv.widthAnchor constraintEqualToConstant:16.0],
        [iv.heightAnchor constraintEqualToConstant:16.0],

        [titleLabel.centerYAnchor constraintEqualToAnchor:iv.centerYAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:8.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:toggle.leadingAnchor constant:-10.0],

        [subLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4.0],
        [subLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subLabel.trailingAnchor constraintEqualToAnchor:toggle.leadingAnchor constant:-10.0],
        [subLabel.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-10.0],

        [toggle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [toggle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12.0],
        [toggle.widthAnchor constraintEqualToConstant:51.0]
    ]];

    if (outSwitch) *outSwitch = toggle;
    if (outSubLabel) *outSubLabel = subLabel;
    return row;
}

- (void)refreshModelTierSegments {
    for (UIButton *b in self.tierSegmentButtons) {
        BOOL active = (b.tag == self.currentModelTier);
        b.backgroundColor = active ? [self goldAccentColor] : [self surfaceInsetColor];
        b.layer.borderColor = active ? [self goldAccentColor].CGColor : [self borderSubtleColor].CGColor;
        [b setTitleColor:(active ? [self darkInkColor] : [self primaryTextColor]) forState:UIControlStateNormal];
    }
}

- (void)onTapSelectModelTierSegment:(UIButton *)sender {
    self.currentModelTier = (ZTechModelTierFilter)sender.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:self.currentModelTier forKey:@"ZTech_ModelTier"];
    if (self.currentModelTier == ZTechModelTierIPhone16 || self.currentModelTier == ZTechModelTierHighEnd) {
        if (self.lockModelSwitch.isOn || self.sameScreenSwitch.isOn || self.matchChipSwitch.isOn) {
            [self.lockModelSwitch setOn:NO animated:YES];
            [self.sameScreenSwitch setOn:NO animated:YES];
            [self.matchChipSwitch setOn:NO animated:YES];
            [self onSwitchChanged:self.lockModelSwitch];
        }
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self refreshModelTierSegments];
    [self onTapChangeDevice];
}

- (void)onTapQuickLaunchZalo {
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [gen impactOccurred];
    [self showLoadingWithTitle:@"ĐANG MỞ ZALO" subtitle:[NSString stringWithFormat:@"Đang nạp cấu hình %@ & mở Zalo...", self.currentProfile.modelName ?: @"máy ảo"]];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if (self.currentProfile) {
            [ZTechDeviceDatabase writeProfileFiles:self.currentProfile error:nil];
        }
        [ZTechVaultManager killZaloProcess];
        [NSThread sleepForTimeInterval:0.25];
        dispatch_async(dispatch_get_main_queue(), ^{
            [ZTechVaultManager launchZaloApp];
            [self hideLoadingOverlayAfterDelay:0.45];
        });
    });
}

#pragma mark - TAB 2: Vault & Proxy Manager (Kho Lưu Trữ Acc Zalo)

- (void)buildTab2VaultView {
    UIView *heroCard = [self createCardView];
    UIStackView *hStack = [[UIStackView alloc] init];
    hStack.translatesAutoresizingMaskIntoConstraints = NO;
    hStack.axis = UILayoutConstraintAxisVertical;
    hStack.spacing = 12.0;
    [heroCard addSubview:hStack];

    self.vaultCountBadgeLabel = [[UILabel alloc] init];
    self.vaultCountBadgeLabel.backgroundColor = [self emeraldBadgeBgColor];
    self.vaultCountBadgeLabel.layer.cornerRadius = 8.0;
    self.vaultCountBadgeLabel.layer.masksToBounds = YES;
    self.vaultCountBadgeLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
    self.vaultCountBadgeLabel.textColor = [self emeraldColor];
    self.vaultCountBadgeLabel.textAlignment = NSTextAlignmentCenter;

    UIView *vHeader = [self createSectionHeaderWithIcon:ZTechIconTabVault
                                                  title:@"KHO LƯU TRỮ ACC ZALO & PROXY"
                                              rightView:self.vaultCountBadgeLabel];
    [hStack addArrangedSubview:vHeader];

    UILabel *guideLbl = [[UILabel alloc] init];
    guideLbl.text = @"Lưu trọn bộ dữ liệu phiên đăng nhập Zalo + Cấu hình máy ảo + Proxy riêng (HTTP/SOCKS5 chống lộ IP thật). Khi muốn vào lại Acc nào chỉ cần nhấn [Mở Zalo].";
    guideLbl.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
    guideLbl.textColor = [self mutedTextColor];
    guideLbl.numberOfLines = 0;
    [hStack addArrangedSubview:guideLbl];

    // Active Proxy Info Box
    UIView *proxyBanner = [[UIView alloc] init];
    proxyBanner.translatesAutoresizingMaskIntoConstraints = NO;
    proxyBanner.backgroundColor = [self surfaceInsetColor];
    proxyBanner.layer.cornerRadius = 11.0;
    proxyBanner.layer.borderWidth = 1.0;
    proxyBanner.layer.borderColor = [self borderSubtleColor].CGColor;

    self.activeProxyIconView = [[UIImageView alloc] initWithImage:[ZTechVectorIcons iconWithType:ZTechIconProxyNodes size:16.0 color:[self goldAccentColor]]];
    self.activeProxyIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.activeProxyIconView.contentMode = UIViewContentModeScaleAspectFit;

    self.activeProxyStatusLabel = [[UILabel alloc] init];
    self.activeProxyStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.activeProxyStatusLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightBold];
    self.activeProxyStatusLabel.textColor = [self primaryTextColor];
    self.activeProxyStatusLabel.adjustsFontSizeToFitWidth = YES;

    [proxyBanner addSubview:self.activeProxyIconView];
    [proxyBanner addSubview:self.activeProxyStatusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [proxyBanner.heightAnchor constraintEqualToConstant:38.0],
        [self.activeProxyIconView.leadingAnchor constraintEqualToAnchor:proxyBanner.leadingAnchor constant:12.0],
        [self.activeProxyIconView.centerYAnchor constraintEqualToAnchor:proxyBanner.centerYAnchor],
        [self.activeProxyIconView.widthAnchor constraintEqualToConstant:16.0],
        [self.activeProxyIconView.heightAnchor constraintEqualToConstant:16.0],
        [self.activeProxyStatusLabel.leadingAnchor constraintEqualToAnchor:self.activeProxyIconView.trailingAnchor constant:8.0],
        [self.activeProxyStatusLabel.trailingAnchor constraintEqualToAnchor:proxyBanner.trailingAnchor constant:-12.0],
        [self.activeProxyStatusLabel.centerYAnchor constraintEqualToAnchor:proxyBanner.centerYAnchor]
    ]];
    [hStack addArrangedSubview:proxyBanner];

    // 2 Action Buttons
    UIStackView *btnRow = [[UIStackView alloc] init];
    btnRow.axis = UILayoutConstraintAxisHorizontal;
    btnRow.spacing = 8.0;
    btnRow.distribution = UIStackViewDistributionFillProportionally;
    [btnRow.heightAnchor constraintEqualToConstant:46.0].active = YES;

    UIButton *btnSaveAcc = [UIButton buttonWithType:UIButtonTypeSystem];
    btnSaveAcc.backgroundColor = [self creamPrimaryColor];
    btnSaveAcc.layer.cornerRadius = 12.0;
    [self styleButton:btnSaveAcc
                title:@"Lưu Acc vào Kho"
             iconType:ZTechIconVaultSave
            tintColor:[self darkInkColor]
                 font:[UIFont systemFontOfSize:13.5 weight:UIFontWeightHeavy]];
    [btnSaveAcc addTarget:self action:@selector(onTapOpenSaveVaultModal) forControlEvents:UIControlEventTouchUpInside];

    UIButton *btnSetProxy = [UIButton buttonWithType:UIButtonTypeSystem];
    btnSetProxy.backgroundColor = [self secondaryTintButtonBgColor];
    btnSetProxy.layer.cornerRadius = 12.0;
    btnSetProxy.layer.borderWidth = 1.0;
    btnSetProxy.layer.borderColor = [self goldAccentColor].CGColor;
    [self styleButton:btnSetProxy
                title:@"Cài Proxy"
             iconType:ZTechIconProxyNodes
            tintColor:[self goldAccentColor]
                 font:[UIFont systemFontOfSize:13.0 weight:UIFontWeightBold]];
    [btnSetProxy.widthAnchor constraintEqualToConstant:114.0].active = YES;
    [btnSetProxy addTarget:self action:@selector(onTapEditCurrentSessionProxy) forControlEvents:UIControlEventTouchUpInside];

    [btnRow addArrangedSubview:btnSaveAcc];
    [btnRow addArrangedSubview:btnSetProxy];
    [hStack addArrangedSubview:btnRow];

    [NSLayoutConstraint activateConstraints:@[
        [hStack.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:16.0],
        [hStack.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor constant:16.0],
        [hStack.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-16.0],
        [hStack.bottomAnchor constraintEqualToAnchor:heroCard.bottomAnchor constant:-16.0]
    ]];
    [self.tabVaultStack addArrangedSubview:heroCard];

    // Accounts List Container
    self.vaultItemsStack = [[UIStackView alloc] init];
    self.vaultItemsStack.axis = UILayoutConstraintAxisVertical;
    self.vaultItemsStack.spacing = 12.0;
    [self.tabVaultStack addArrangedSubview:self.vaultItemsStack];
}

- (void)reloadVaultListUI {
    for (UIView *sub in self.vaultItemsStack.arrangedSubviews) {
        [self.vaultItemsStack removeArrangedSubview:sub];
        [sub removeFromSuperview];
    }

    self.vaultAccounts = [ZTechVaultManager listSavedAccounts];
    NSString *activeId = [ZTechVaultManager activeAccountId];
    self.vaultCountBadgeLabel.text = [NSString stringWithFormat:@"  %lu Acc đã lưu  ", (unsigned long)self.vaultAccounts.count];

    if (self.currentProfile.activeProxy.length > 0) {
        self.activeProxyStatusLabel.text = [NSString stringWithFormat:@"Proxy bảo vệ IP: %@", self.currentProfile.activeProxy];
        self.activeProxyStatusLabel.textColor = [self emeraldColor];
        self.activeProxyIconView.image = [ZTechVectorIcons iconWithType:ZTechIconProxyNodes size:16.0 color:[self emeraldColor]];
    } else {
        self.activeProxyStatusLabel.text = @"Mạng hiện tại: Trực tiếp (Không Proxy / 4G)";
        self.activeProxyStatusLabel.textColor = [self primaryTextColor];
        self.activeProxyIconView.image = [ZTechVectorIcons iconWithType:ZTechIconProxyNodes size:16.0 color:[self goldAccentColor]];
    }

    if (self.vaultAccounts.count == 0) {
        UIView *emptyCard = [self createCardView];
        UIStackView *eStack = [[UIStackView alloc] init];
        eStack.translatesAutoresizingMaskIntoConstraints = NO;
        eStack.axis = UILayoutConstraintAxisVertical;
        eStack.alignment = UIStackViewAlignmentCenter;
        eStack.spacing = 8.0;
        [emptyCard addSubview:eStack];

        UIImageView *emptyIv = [[UIImageView alloc] initWithImage:[ZTechVectorIcons iconWithType:ZTechIconTabVault size:38.0 color:[self goldAccentColor]]];
        emptyIv.contentMode = UIViewContentModeScaleAspectFit;

        UILabel *eTitle = [[UILabel alloc] init];
        eTitle.text = @"Kho Lưu Trữ Đang Trống";
        eTitle.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightBold];
        eTitle.textColor = [self primaryTextColor];

        UILabel *eSub = [[UILabel alloc] init];
        eSub.text = @"1. Đăng nhập tài khoản Zalo trên máy.\n2. Quay lại tab này bấm [Lưu Acc vào Kho] và gắn Proxy (nếu cần).\n3. Từ lần sau chỉ cần bấm [Mở Zalo] để vào lại ngay.";
        eSub.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
        eSub.textColor = [self mutedTextColor];
        eSub.textAlignment = NSTextAlignmentCenter;
        eSub.numberOfLines = 0;

        [eStack addArrangedSubview:emptyIv];
        [eStack addArrangedSubview:eTitle];
        [eStack addArrangedSubview:eSub];

        [NSLayoutConstraint activateConstraints:@[
            [eStack.topAnchor constraintEqualToAnchor:emptyCard.topAnchor constant:24.0],
            [eStack.leadingAnchor constraintEqualToAnchor:emptyCard.leadingAnchor constant:20.0],
            [eStack.trailingAnchor constraintEqualToAnchor:emptyCard.trailingAnchor constant:-20.0],
            [eStack.bottomAnchor constraintEqualToAnchor:emptyCard.bottomAnchor constant:-24.0]
        ]];
        [self.vaultItemsStack addArrangedSubview:emptyCard];
        return;
    }

    for (NSUInteger i = 0; i < self.vaultAccounts.count; i++) {
        ZTechVaultAccount *acc = self.vaultAccounts[i];
        BOOL isActive = (activeId && [activeId isEqualToString:acc.accountId]);

        UIView *itemCard = [self createCardView];
        if (isActive) {
            itemCard.layer.borderWidth = 1.5;
            itemCard.layer.borderColor = [self emeraldColor].CGColor;
        }

        UIStackView *cStack = [[UIStackView alloc] init];
        cStack.translatesAutoresizingMaskIntoConstraints = NO;
        cStack.axis = UILayoutConstraintAxisVertical;
        cStack.spacing = 10.0;
        [itemCard addSubview:cStack];

        // Top Title Row
        UIView *topRow = [[UIView alloc] init];
        topRow.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *nameLbl = [[UILabel alloc] init];
        nameLbl.translatesAutoresizingMaskIntoConstraints = NO;
        nameLbl.text = [NSString stringWithFormat:@"#%lu · %@", (unsigned long)(i + 1), acc.title];
        nameLbl.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightHeavy];
        nameLbl.textColor = [self primaryTextColor];
        nameLbl.adjustsFontSizeToFitWidth = YES;

        UILabel *badgeLbl = [[UILabel alloc] init];
        badgeLbl.translatesAutoresizingMaskIntoConstraints = NO;
        badgeLbl.text = isActive ? @"  ĐANG DÙNG  " : [NSString stringWithFormat:@"  %@  ", acc.createdAt];
        badgeLbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
        badgeLbl.textColor = isActive ? [self emeraldColor] : [self mutedTextColor];
        badgeLbl.backgroundColor = isActive ? [self emeraldBadgeBgColor] : [self surfaceInsetColor];
        badgeLbl.layer.cornerRadius = 6.0;
        badgeLbl.layer.masksToBounds = YES;

        [topRow addSubview:nameLbl];
        [topRow addSubview:badgeLbl];
        [NSLayoutConstraint activateConstraints:@[
            [topRow.heightAnchor constraintEqualToConstant:22.0],
            [nameLbl.leadingAnchor constraintEqualToAnchor:topRow.leadingAnchor],
            [nameLbl.centerYAnchor constraintEqualToAnchor:topRow.centerYAnchor],
            [badgeLbl.trailingAnchor constraintEqualToAnchor:topRow.trailingAnchor],
            [badgeLbl.centerYAnchor constraintEqualToAnchor:topRow.centerYAnchor],
            [badgeLbl.heightAnchor constraintEqualToConstant:20.0],
            [nameLbl.trailingAnchor constraintLessThanOrEqualToAnchor:badgeLbl.leadingAnchor constant:-8.0]
        ]];
        [cStack addArrangedSubview:topRow];

        // Info Inset Box
        UIView *infoBox = [[UIView alloc] init];
        infoBox.translatesAutoresizingMaskIntoConstraints = NO;
        infoBox.backgroundColor = [self surfaceInsetColor];
        infoBox.layer.cornerRadius = 11.0;
        infoBox.layer.borderWidth = 1.0;
        infoBox.layer.borderColor = [self borderSubtleColor].CGColor;

        UIImageView *devIv = [[UIImageView alloc] initWithImage:[ZTechVectorIcons iconWithType:ZTechIconDevicePhone size:14.0 color:[self goldAccentColor]]];
        devIv.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *devLbl = [[UILabel alloc] init];
        devLbl.translatesAutoresizingMaskIntoConstraints = NO;
        devLbl.text = [acc shortDeviceSummary];
        devLbl.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightBold];
        devLbl.textColor = [self goldAccentColor];
        devLbl.adjustsFontSizeToFitWidth = YES;

        BOOL hasProxy = (acc.proxyString.length > 0);
        UIColor *prxColor = hasProxy ? [self emeraldColor] : [self mutedTextColor];
        UIImageView *prxIv = [[UIImageView alloc] initWithImage:[ZTechVectorIcons iconWithType:ZTechIconProxyNodes size:14.0 color:prxColor]];
        prxIv.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *prxLbl = [[UILabel alloc] init];
        prxLbl.translatesAutoresizingMaskIntoConstraints = NO;
        prxLbl.text = hasProxy
            ? [NSString stringWithFormat:@"Proxy chống lộ IP: %@", acc.proxyString]
            : @"Mạng trực tiếp (Không gắn Proxy / 4G)";
        prxLbl.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        prxLbl.textColor = prxColor;
        prxLbl.adjustsFontSizeToFitWidth = YES;

        [infoBox addSubview:devIv];
        [infoBox addSubview:devLbl];
        [infoBox addSubview:prxIv];
        [infoBox addSubview:prxLbl];

        [NSLayoutConstraint activateConstraints:@[
            [devIv.topAnchor constraintEqualToAnchor:infoBox.topAnchor constant:9.0],
            [devIv.leadingAnchor constraintEqualToAnchor:infoBox.leadingAnchor constant:10.0],
            [devIv.widthAnchor constraintEqualToConstant:14.0],
            [devIv.heightAnchor constraintEqualToConstant:14.0],
            [devLbl.centerYAnchor constraintEqualToAnchor:devIv.centerYAnchor],
            [devLbl.leadingAnchor constraintEqualToAnchor:devIv.trailingAnchor constant:7.0],
            [devLbl.trailingAnchor constraintEqualToAnchor:infoBox.trailingAnchor constant:-10.0],

            [prxIv.topAnchor constraintEqualToAnchor:devIv.bottomAnchor constant:7.0],
            [prxIv.leadingAnchor constraintEqualToAnchor:infoBox.leadingAnchor constant:10.0],
            [prxIv.widthAnchor constraintEqualToConstant:14.0],
            [prxIv.heightAnchor constraintEqualToConstant:14.0],
            [prxIv.bottomAnchor constraintEqualToAnchor:infoBox.bottomAnchor constant:-9.0],
            [prxLbl.centerYAnchor constraintEqualToAnchor:prxIv.centerYAnchor],
            [prxLbl.leadingAnchor constraintEqualToAnchor:prxIv.trailingAnchor constant:7.0],
            [prxLbl.trailingAnchor constraintEqualToAnchor:infoBox.trailingAnchor constant:-10.0]
        ]];
        [cStack addArrangedSubview:infoBox];

        // Action Buttons Row
        UIStackView *actRow = [[UIStackView alloc] init];
        actRow.axis = UILayoutConstraintAxisHorizontal;
        actRow.spacing = 7.0;
        actRow.distribution = UIStackViewDistributionFillProportionally;
        [actRow.heightAnchor constraintEqualToConstant:40.0].active = YES;

        UIButton *btnOpen = [UIButton buttonWithType:UIButtonTypeSystem];
        btnOpen.tag = (NSInteger)i;
        btnOpen.backgroundColor = [self creamPrimaryColor];
        btnOpen.layer.cornerRadius = 10.0;
        [self styleButton:btnOpen
                    title:@"Mở Zalo"
                 iconType:ZTechIconRocketLaunch
                tintColor:[self darkInkColor]
                     font:[UIFont systemFontOfSize:13.5 weight:UIFontWeightHeavy]];
        [btnOpen addTarget:self action:@selector(onTapRestoreAndOpenVaultAccount:) forControlEvents:UIControlEventTouchUpInside];

        UIButton *btnEdit = [UIButton buttonWithType:UIButtonTypeSystem];
        btnEdit.tag = (NSInteger)i;
        btnEdit.backgroundColor = [self secondaryTintButtonBgColor];
        btnEdit.layer.cornerRadius = 10.0;
        btnEdit.layer.borderWidth = 1.0;
        btnEdit.layer.borderColor = [self goldAccentColor].CGColor;
        [self styleButton:btnEdit
                    title:@"Proxy / Tên"
                 iconType:ZTechIconSlidersTune
                tintColor:[self goldAccentColor]
                     font:[UIFont systemFontOfSize:12.0 weight:UIFontWeightBold]];
        [btnEdit.widthAnchor constraintEqualToConstant:108.0].active = YES;
        [btnEdit addTarget:self action:@selector(onTapEditVaultAccount:) forControlEvents:UIControlEventTouchUpInside];

        UIButton *btnDel = [UIButton buttonWithType:UIButtonTypeSystem];
        btnDel.tag = (NSInteger)i;
        BOOL isConfirmingDel = [self.pendingDeleteAccountId isEqualToString:acc.accountId];
        btnDel.backgroundColor = isConfirmingDel
            ? [self dangerCoralColor]
            : [self dangerBadgeBgColor];
        btnDel.layer.cornerRadius = 10.0;
        [self styleButton:btnDel
                    title:(isConfirmingDel ? @"Xoá?" : @"Xoá")
                 iconType:ZTechIconTrashDelete
                tintColor:(isConfirmingDel ? [UIColor whiteColor] : [self dangerCoralColor])
                     font:[UIFont systemFontOfSize:12.0 weight:UIFontWeightBold]];
        [btnDel.widthAnchor constraintEqualToConstant:70.0].active = YES;
        [btnDel addTarget:self action:@selector(onTapDeleteVaultAccount:) forControlEvents:UIControlEventTouchUpInside];

        [actRow addArrangedSubview:btnOpen];
        [actRow addArrangedSubview:btnEdit];
        [actRow addArrangedSubview:btnDel];
        [cStack addArrangedSubview:actRow];

        [NSLayoutConstraint activateConstraints:@[
            [cStack.topAnchor constraintEqualToAnchor:itemCard.topAnchor constant:14.0],
            [cStack.leadingAnchor constraintEqualToAnchor:itemCard.leadingAnchor constant:14.0],
            [cStack.trailingAnchor constraintEqualToAnchor:itemCard.trailingAnchor constant:-14.0],
            [cStack.bottomAnchor constraintEqualToAnchor:itemCard.bottomAnchor constant:-14.0]
        ]];
        [self.vaultItemsStack addArrangedSubview:itemCard];
    }
}

#pragma mark - TAB 3: User License Management (Quản Lý Bản Quyền)

- (UIView *)createLicenseDetailRowWithLabel:(NSString *)label outValue:(UILabel **)outVal {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [self surfaceInsetColor];
    row.layer.cornerRadius = 11.0;
    row.layer.borderWidth = 1.0;
    row.layer.borderColor = [self borderSubtleColor].CGColor;

    UILabel *kLbl = [[UILabel alloc] init];
    kLbl.translatesAutoresizingMaskIntoConstraints = NO;
    kLbl.text = label;
    kLbl.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
    kLbl.textColor = [self mutedTextColor];

    UILabel *vLbl = [[UILabel alloc] init];
    vLbl.translatesAutoresizingMaskIntoConstraints = NO;
    vLbl.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    vLbl.textColor = [self primaryTextColor];
    vLbl.adjustsFontSizeToFitWidth = YES;

    [row addSubview:kLbl];
    [row addSubview:vLbl];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:52.0],
        [kLbl.topAnchor constraintEqualToAnchor:row.topAnchor constant:8.0],
        [kLbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12.0],
        [kLbl.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12.0],
        [vLbl.topAnchor constraintEqualToAnchor:kLbl.bottomAnchor constant:3.0],
        [vLbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12.0],
        [vLbl.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12.0]
    ]];

    if (outVal) *outVal = vLbl;
    return row;
}

- (void)buildTab3LicenseView {
    UIView *licCard = [self createCardView];
    UIStackView *lStack = [[UIStackView alloc] init];
    lStack.translatesAutoresizingMaskIntoConstraints = NO;
    lStack.axis = UILayoutConstraintAxisVertical;
    lStack.spacing = 12.0;
    [licCard addSubview:lStack];

    UIView *lHeader = [self createSectionHeaderWithIcon:ZTechIconShieldCheck
                                                  title:@"BẢN QUYỀN SỬ DỤNG"
                                              rightView:nil];
    [lStack addArrangedSubview:lHeader];

    // Status Banner Box
    UIView *stateBox = [[UIView alloc] init];
    stateBox.translatesAutoresizingMaskIntoConstraints = NO;
    stateBox.backgroundColor = [self surfaceInsetColor];
    stateBox.layer.cornerRadius = 14.0;
    stateBox.layer.borderWidth = 1.2;
    stateBox.layer.borderColor = [self goldAccentColor].CGColor;

    self.licShieldIconView = [[UIImageView alloc] initWithImage:[ZTechVectorIcons iconWithType:ZTechIconShieldCheck size:32.0 color:[self emeraldColor]]];
    self.licShieldIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.licShieldIconView.contentMode = UIViewContentModeScaleAspectFit;

    self.licMainStateLabel = [[UILabel alloc] init];
    self.licMainStateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.licMainStateLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightHeavy];
    self.licMainStateLabel.textColor = [self emeraldColor];
    self.licMainStateLabel.numberOfLines = 2;

    [stateBox addSubview:self.licShieldIconView];
    [stateBox addSubview:self.licMainStateLabel];
    [NSLayoutConstraint activateConstraints:@[
        [stateBox.heightAnchor constraintEqualToConstant:64.0],
        [self.licShieldIconView.leadingAnchor constraintEqualToAnchor:stateBox.leadingAnchor constant:16.0],
        [self.licShieldIconView.centerYAnchor constraintEqualToAnchor:stateBox.centerYAnchor],
        [self.licShieldIconView.widthAnchor constraintEqualToConstant:32.0],
        [self.licShieldIconView.heightAnchor constraintEqualToConstant:32.0],
        [self.licMainStateLabel.leadingAnchor constraintEqualToAnchor:self.licShieldIconView.trailingAnchor constant:12.0],
        [self.licMainStateLabel.trailingAnchor constraintEqualToAnchor:stateBox.trailingAnchor constant:-14.0],
        [self.licMainStateLabel.centerYAnchor constraintEqualToAnchor:stateBox.centerYAnchor]
    ]];
    [lStack addArrangedSubview:stateBox];

    UILabel *vKey = nil; UILabel *vPlan = nil;
    UIView *rKey = [self createLicenseDetailRowWithLabel:@"MÃ KEY ĐANG DÙNG" outValue:&vKey];
    UIView *rPlan = [self createLicenseDetailRowWithLabel:@"THỜI HẠN BẢN QUYỀN" outValue:&vPlan];
    self.licKeyUsedValueLabel = vKey;
    self.licPlanDetailValueLabel = vPlan;
    self.licKeyUsedValueLabel.font = [UIFont monospacedSystemFontOfSize:14.5 weight:UIFontWeightHeavy];
    self.licKeyUsedValueLabel.textColor = [self goldAccentColor];

    [lStack addArrangedSubview:rKey];
    [lStack addArrangedSubview:rPlan];

    UIButton *btnChangeKey = [UIButton buttonWithType:UIButtonTypeSystem];
    btnChangeKey.backgroundColor = [self creamPrimaryColor];
    btnChangeKey.layer.cornerRadius = 13.0;
    [self styleButton:btnChangeKey
                title:@"Nhập / Đổi Key Bản Quyền"
             iconType:ZTechIconKeyVip
            tintColor:[self darkInkColor]
                 font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightHeavy]];
    [btnChangeKey.heightAnchor constraintEqualToConstant:48.0].active = YES;
    [btnChangeKey addTarget:self action:@selector(onTapShowKeyModal) forControlEvents:UIControlEventTouchUpInside];

    self.btnRefreshLicenseCloud = [UIButton buttonWithType:UIButtonTypeSystem];
    self.btnRefreshLicenseCloud.backgroundColor = [self surfaceInsetColor];
    self.btnRefreshLicenseCloud.layer.cornerRadius = 13.0;
    self.btnRefreshLicenseCloud.layer.borderWidth = 1.0;
    self.btnRefreshLicenseCloud.layer.borderColor = [self borderSubtleColor].CGColor;
    [self styleButton:self.btnRefreshLicenseCloud
                title:@"Làm mới trạng thái Key"
             iconType:ZTechIconCloudSync
            tintColor:[self goldAccentColor]
                 font:[UIFont systemFontOfSize:13.5 weight:UIFontWeightBold]];
    [self.btnRefreshLicenseCloud.heightAnchor constraintEqualToConstant:44.0].active = YES;
    [self.btnRefreshLicenseCloud addTarget:self action:@selector(onTapRefreshLicenseCloud) forControlEvents:UIControlEventTouchUpInside];

    [lStack addArrangedSubview:btnChangeKey];
    [lStack addArrangedSubview:self.btnRefreshLicenseCloud];

    [NSLayoutConstraint activateConstraints:@[
        [lStack.topAnchor constraintEqualToAnchor:licCard.topAnchor constant:16.0],
        [lStack.leadingAnchor constraintEqualToAnchor:licCard.leadingAnchor constant:16.0],
        [lStack.trailingAnchor constraintEqualToAnchor:licCard.trailingAnchor constant:-16.0],
        [lStack.bottomAnchor constraintEqualToAnchor:licCard.bottomAnchor constant:-16.0]
    ]];
    [self.tabLicenseStack addArrangedSubview:licCard];
}

- (void)onTapRefreshLicenseCloud {
    [self styleButton:self.btnRefreshLicenseCloud
                title:@"Đang kiểm tra..."
             iconType:ZTechIconCloudSync
            tintColor:[self goldAccentColor]
                 font:[UIFont systemFontOfSize:13.5 weight:UIFontWeightBold]];
    self.btnRefreshLicenseCloud.enabled = NO;

    [ZTechLicenseManager refreshSavedLicenseInBackgroundWithCompletion:^(BOOL isValid, NSString * _Nonnull statusText) {
        self.btnRefreshLicenseCloud.enabled = YES;
        [self styleButton:self.btnRefreshLicenseCloud
                    title:@"Làm mới trạng thái Key"
                 iconType:ZTechIconCloudSync
                tintColor:[self goldAccentColor]
                     font:[UIFont systemFontOfSize:13.5 weight:UIFontWeightBold]];
        [self updateLicenseUIState];
        [self showToast:statusText isError:!isValid];
    }];
}

#pragma mark - Vault & Proxy Editor Modal (Clean Native Input + 1-Tap Paste)

- (void)buildVaultEditorModal {
    self.vaultModalOverlay = [[UIView alloc] init];
    self.vaultModalOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    self.vaultModalOverlay.backgroundColor = self.isLightMode
        ? [UIColor colorWithRed:0.05 green:0.12 blue:0.26 alpha:0.55]
        : [UIColor colorWithRed:0.02 green:0.03 blue:0.02 alpha:0.96];
    self.vaultModalOverlay.hidden = YES;
    [self.view addSubview:self.vaultModalOverlay];

    UIControl *bgDismiss = [[UIControl alloc] init];
    bgDismiss.translatesAutoresizingMaskIntoConstraints = NO;
    [bgDismiss addTarget:self action:@selector(dismissAllKeyboards) forControlEvents:UIControlEventTouchUpInside];
    [self.vaultModalOverlay addSubview:bgDismiss];

    UIView *box = [self createCardView];
    box.layer.borderWidth = 1.5;
    box.layer.borderColor = [self goldAccentColor].CGColor;
    [self.vaultModalOverlay addSubview:box];

    self.vaultModalTitleLabel = [[UILabel alloc] init];
    self.vaultModalTitleLabel.font = [UIFont systemFontOfSize:16.5 weight:UIFontWeightHeavy];
    self.vaultModalTitleLabel.textColor = [self goldAccentColor];
    self.vaultModalTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.vaultModalTitleLabel.numberOfLines = 0;

    self.vaultNameInputField = [[ZTechSafeTextField alloc] init];
    self.vaultNameInputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.vaultNameInputField.textInsets = UIEdgeInsetsMake(0, 14, 0, 14);
    self.vaultNameInputField.backgroundColor = [self surfaceInsetColor];
    self.vaultNameInputField.layer.cornerRadius = 12.0;
    self.vaultNameInputField.layer.borderWidth = 1.0;
    self.vaultNameInputField.layer.borderColor = [self borderSubtleColor].CGColor;
    self.vaultNameInputField.textColor = [self primaryTextColor];
    self.vaultNameInputField.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    self.vaultNameInputField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.vaultNameInputField.returnKeyType = UIReturnKeyDone;
    self.vaultNameInputField.delegate = self;
    self.vaultNameInputField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Tên gợi nhớ Acc Zalo..."
                                                                                     attributes:@{NSForegroundColorAttributeName: [self mutedTextColor]}];
    NSLayoutConstraint *vaultNameH = [self.vaultNameInputField.heightAnchor constraintEqualToConstant:46.0];
    vaultNameH.priority = UILayoutPriorityDefaultHigh;
    vaultNameH.active = YES;

    UIView *proxyFieldWrap = [[UIView alloc] init];
    proxyFieldWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [proxyFieldWrap.heightAnchor constraintEqualToConstant:48.0].active = YES;

    self.vaultProxyInputField = [[ZTechSafeTextField alloc] init];
    self.vaultProxyInputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.vaultProxyInputField.textInsets = UIEdgeInsetsMake(0, 14, 0, 82);
    self.vaultProxyInputField.backgroundColor = [self surfaceInsetColor];
    self.vaultProxyInputField.layer.cornerRadius = 12.0;
    self.vaultProxyInputField.layer.borderWidth = 1.2;
    self.vaultProxyInputField.layer.borderColor = [self goldAccentColor].CGColor;
    self.vaultProxyInputField.textColor = [self emeraldColor];
    self.vaultProxyInputField.font = [UIFont monospacedSystemFontOfSize:13.5 weight:UIFontWeightBold];
    self.vaultProxyInputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.vaultProxyInputField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.vaultProxyInputField.keyboardType = UIKeyboardTypeURL;
    self.vaultProxyInputField.returnKeyType = UIReturnKeyDone;
    self.vaultProxyInputField.delegate = self;
    self.vaultProxyInputField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Proxy (IP:Port:User:Pass hoặc để trống)"
                                                                                      attributes:@{NSForegroundColorAttributeName: [self mutedTextColor]}];
    [proxyFieldWrap addSubview:self.vaultProxyInputField];

    UIButton *btnPasteProxy = [UIButton buttonWithType:UIButtonTypeSystem];
    btnPasteProxy.translatesAutoresizingMaskIntoConstraints = NO;
    btnPasteProxy.backgroundColor = [self emeraldBadgeBgColor];
    btnPasteProxy.layer.cornerRadius = 8.0;
    btnPasteProxy.layer.borderWidth = 1.0;
    btnPasteProxy.layer.borderColor = [self emeraldColor].CGColor;
    [self styleButton:btnPasteProxy
                title:@"Dán"
             iconType:ZTechIconClipboardPaste
            tintColor:[self emeraldColor]
                 font:[UIFont systemFontOfSize:12.0 weight:UIFontWeightBold]];
    [btnPasteProxy addTarget:self action:@selector(onTapPasteProxyFromClipboard) forControlEvents:UIControlEventTouchUpInside];
    [proxyFieldWrap addSubview:btnPasteProxy];

    [NSLayoutConstraint activateConstraints:@[
        [self.vaultProxyInputField.topAnchor constraintEqualToAnchor:proxyFieldWrap.topAnchor],
        [self.vaultProxyInputField.leadingAnchor constraintEqualToAnchor:proxyFieldWrap.leadingAnchor],
        [self.vaultProxyInputField.trailingAnchor constraintEqualToAnchor:proxyFieldWrap.trailingAnchor],
        [self.vaultProxyInputField.bottomAnchor constraintEqualToAnchor:proxyFieldWrap.bottomAnchor],

        [btnPasteProxy.centerYAnchor constraintEqualToAnchor:proxyFieldWrap.centerYAnchor],
        [btnPasteProxy.trailingAnchor constraintEqualToAnchor:proxyFieldWrap.trailingAnchor constant:-7.0],
        [btnPasteProxy.widthAnchor constraintEqualToConstant:66.0],
        [btnPasteProxy.heightAnchor constraintEqualToConstant:34.0]
    ]];

    UIStackView *bottomRow = [[UIStackView alloc] init];
    bottomRow.axis = UILayoutConstraintAxisHorizontal;
    bottomRow.spacing = 10.0;
    bottomRow.distribution = UIStackViewDistributionFillProportionally;
    [bottomRow.heightAnchor constraintEqualToConstant:48.0].active = YES;

    UIButton *btnCancel = [UIButton buttonWithType:UIButtonTypeSystem];
    btnCancel.backgroundColor = [self surfaceInsetColor];
    btnCancel.layer.cornerRadius = 12.0;
    btnCancel.layer.borderWidth = 1.0;
    btnCancel.layer.borderColor = [self borderSubtleColor].CGColor;
    [btnCancel setTitle:@"Đóng" forState:UIControlStateNormal];
    [btnCancel setTitleColor:[self primaryTextColor] forState:UIControlStateNormal];
    btnCancel.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    [btnCancel.widthAnchor constraintEqualToConstant:88.0].active = YES;
    [self attachSpringTouchFeedbackToButton:btnCancel];
    [btnCancel addTarget:self action:@selector(onTapCloseVaultModal) forControlEvents:UIControlEventTouchUpInside];

    self.btnVaultSaveConfirm = [UIButton buttonWithType:UIButtonTypeSystem];
    self.btnVaultSaveConfirm.backgroundColor = [self creamPrimaryColor];
    self.btnVaultSaveConfirm.layer.cornerRadius = 12.0;
    [self styleButton:self.btnVaultSaveConfirm
                title:@"Xác nhận Lưu"
             iconType:ZTechIconShieldCheck
            tintColor:[self darkInkColor]
                 font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightHeavy]];
    [self.btnVaultSaveConfirm addTarget:self action:@selector(onTapConfirmVaultModal) forControlEvents:UIControlEventTouchUpInside];

    [bottomRow addArrangedSubview:btnCancel];
    [bottomRow addArrangedSubview:self.btnVaultSaveConfirm];

    UIStackView *mStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.vaultModalTitleLabel,
        self.vaultNameInputField,
        proxyFieldWrap,
        bottomRow
    ]];
    mStack.translatesAutoresizingMaskIntoConstraints = NO;
    mStack.axis = UILayoutConstraintAxisVertical;
    mStack.spacing = 12.0;
    [box addSubview:mStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.vaultModalOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.vaultModalOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.vaultModalOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.vaultModalOverlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [bgDismiss.topAnchor constraintEqualToAnchor:self.vaultModalOverlay.topAnchor],
        [bgDismiss.leadingAnchor constraintEqualToAnchor:self.vaultModalOverlay.leadingAnchor],
        [bgDismiss.trailingAnchor constraintEqualToAnchor:self.vaultModalOverlay.trailingAnchor],
        [bgDismiss.bottomAnchor constraintEqualToAnchor:self.vaultModalOverlay.bottomAnchor],

        [box.centerYAnchor constraintEqualToAnchor:self.vaultModalOverlay.centerYAnchor constant:-40.0],
        [box.leadingAnchor constraintEqualToAnchor:self.vaultModalOverlay.leadingAnchor constant:18.0],
        [box.trailingAnchor constraintEqualToAnchor:self.vaultModalOverlay.trailingAnchor constant:-18.0],

        [mStack.topAnchor constraintEqualToAnchor:box.topAnchor constant:18.0],
        [mStack.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:16.0],
        [mStack.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-16.0],
        [mStack.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-18.0]
    ]];
}

- (void)onTapPasteProxyFromClipboard {
    NSString *clip = ZTechReadClipboardSafely();
    if (clip.length > 0) {
        self.vaultProxyInputField.text = clip;
    } else {
        [self showToast:@"Bộ nhớ tạm đang trống!" isError:YES];
    }
}

- (void)onTapOpenSaveVaultModal {
    if (![ZTechLicenseManager isLicenseCurrentlyValid]) {
        [self updateLicenseUIState];
        return;
    }
    NSUInteger nextNum = [ZTechVaultManager listSavedAccounts].count + 1;
    self.isSavingNewVaultAccount = YES;
    self.editingVaultAccountId = nil;
    self.vaultNameInputField.hidden = NO;
    self.vaultNameInputField.text = [NSString stringWithFormat:@"Acc Zalo #%lu (%@)", (unsigned long)nextNum, self.currentProfile.modelName ?: @"iPhone 16"];
    self.vaultProxyInputField.text = self.currentProfile.activeProxy ?: @"";
    self.vaultModalTitleLabel.text = @"LƯU ACC ZALO VÀO KHO";
    [self styleButton:self.btnVaultSaveConfirm
                title:@"Lưu vào Kho"
             iconType:ZTechIconShieldCheck
            tintColor:[self darkInkColor]
                 font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightHeavy]];
    self.vaultModalOverlay.hidden = NO;
}

- (void)onTapEditCurrentSessionProxy {
    if (![ZTechLicenseManager isLicenseCurrentlyValid]) {
        [self updateLicenseUIState];
        return;
    }
    self.isSavingNewVaultAccount = NO;
    self.editingVaultAccountId = @"__CURRENT_SESSION__";
    self.vaultNameInputField.hidden = YES;
    self.vaultNameInputField.text = @"Phiên Zalo hiện tại";
    self.vaultProxyInputField.text = self.currentProfile.activeProxy ?: @"";
    self.vaultModalTitleLabel.text = @"GẮN PROXY CHO PHIÊN HIỆN TẠI";
    [self styleButton:self.btnVaultSaveConfirm
                title:@"Xác nhận Proxy"
             iconType:ZTechIconShieldCheck
            tintColor:[self darkInkColor]
                 font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightHeavy]];
    self.vaultModalOverlay.hidden = NO;
    [self.vaultProxyInputField becomeFirstResponder];
}

- (void)onTapEditVaultAccount:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.vaultAccounts.count) return;
    ZTechVaultAccount *acc = self.vaultAccounts[idx];
    self.isSavingNewVaultAccount = NO;
    self.editingVaultAccountId = acc.accountId;
    self.vaultNameInputField.hidden = NO;
    self.vaultNameInputField.text = acc.title ?: @"";
    self.vaultProxyInputField.text = acc.proxyString ?: @"";
    self.vaultModalTitleLabel.text = @"SỬA TÊN ACC & PROXY";
    [self styleButton:self.btnVaultSaveConfirm
                title:@"Lưu thay đổi"
             iconType:ZTechIconShieldCheck
            tintColor:[self darkInkColor]
                 font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightHeavy]];
    self.vaultModalOverlay.hidden = NO;
    [self.vaultProxyInputField becomeFirstResponder];
}

- (void)onTapCloseVaultModal {
    [self dismissAllKeyboards];
    self.vaultModalOverlay.hidden = YES;
}

- (void)onTapConfirmVaultModal {
    [self dismissAllKeyboards];
    self.vaultModalOverlay.hidden = YES;

    NSString *nameText = [self.vaultNameInputField.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *proxyText = [self.vaultProxyInputField.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (self.isSavingNewVaultAccount) {
        [self showLoadingWithTitle:@"ĐANG LƯU VÀO KHO" subtitle:@"Đang lưu phiên, xoá Cookie Safari & tạo máy mới..."];
        ZTechDeviceProfile *profSnap = self.currentProfile;
        BOOL lockOn = self.lockModelSwitch.isOn;
        BOOL screenOn = self.sameScreenSwitch.isOn;
        BOOL chipOn = self.matchChipSwitch.isOn;
        ZTechModelTierFilter tier = self.currentModelTier;

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            NSError *err = nil;
            ZTechVaultAccount *saved = [ZTechVaultManager saveCurrentZaloSessionWithTitle:nameText
                                                                                    proxy:proxyText
                                                                                  profile:profSnap
                                                                                    error:&err];
            ZTechDeviceProfile *newProf = nil;
            if (saved) {
                // 1. Automatically wipe Safari cookies & website cache
                [ZTechVaultManager cleanSafariCookiesAndWebsiteData];
                // 2. Clean Zalo session & cache
                [ZTechDeviceDatabase cleanResetAllProfileDataAndCache];
                // 3. Immediately prepare a fresh device profile for next Zalo session
                newProf = [ZTechDeviceDatabase generateProfileWithLockRealModel:lockOn
                                                                     sameScreen:screenOn
                                                                      matchChip:chipOn
                                                                      modelTier:tier
                                                                    currentCity:nil];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideLoadingOverlayAfterDelay:0.15];
                if (saved && newProf) {
                    self.currentProfile = newProf;
                    [self refreshUIWithCurrentProfile];
                    [self reloadVaultListUI];
                    [self showToast:[NSString stringWithFormat:@"Đã lưu [%@]! Đã xoá Cookie Safari & Tạo phiên Zalo mới (%@)!", saved.title, newProf.modelName] isError:NO];
                } else if (saved) {
                    [self refreshUIWithCurrentProfile];
                    [self reloadVaultListUI];
                    [self showToast:[NSString stringWithFormat:@"Đã lưu [%@] vào Kho thành công!", saved.title] isError:NO];
                } else {
                    [self showToast:(err.localizedDescription ?: @"Lỗi khi lưu Acc vào Kho.") isError:YES];
                }
            });
        });
    } else if ([self.editingVaultAccountId isEqualToString:@"__CURRENT_SESSION__"]) {
        self.currentProfile.activeProxy = proxyText;
        [self showLoadingWithTitle:@"ĐANG ÁP DỤNG PROXY" subtitle:@"Đang khoá đường truyền chống lộ IP thật..."];
        ZTechDeviceProfile *profSnap = self.currentProfile;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [ZTechDeviceDatabase writeProfileFiles:profSnap error:nil];
            [[NSUserDefaults standardUserDefaults] setObject:[profSnap toDictionary] forKey:@"ZTechCurrentProfile"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            // Restart background Zalo process so all sockets immediately route through the new proxy
            [ZTechVaultManager killZaloProcess];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideLoadingOverlayAfterDelay:0.15];
                [self refreshUIWithCurrentProfile];
                [self reloadVaultListUI];
                [self showToast:(self.currentProfile.activeProxy.length > 0
                    ? [NSString stringWithFormat:@"Đã gắn Proxy [%@] & Khoá IP thật!", self.currentProfile.activeProxy]
                    : @"Đã tắt Proxy — Đang dùng mạng gốc / 4G.") isError:NO];
            });
        });
    } else if (self.editingVaultAccountId.length > 0) {
        NSString *editId = self.editingVaultAccountId;
        [self showLoadingWithTitle:@"ĐANG CẬP NHẬT" subtitle:@"Đang lưu cấu hình Proxy cho tài khoản..."];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [ZTechVaultManager updateAccount:editId
                                       title:nameText
                                 proxyString:proxyText];
            ZTechDeviceProfile *reloaded = [ZTechDeviceDatabase loadOrCreateDefaultProfile];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideLoadingOverlayAfterDelay:0.1];
                self.currentProfile = reloaded;
                [self refreshUIWithCurrentProfile];
                [self reloadVaultListUI];
                [self showToast:@"Đã cập nhật Proxy & Tên Acc trong Kho!" isError:NO];
            });
        });
    }
}

- (void)onTapRestoreAndOpenVaultAccount:(UIButton *)sender {
    if (![ZTechLicenseManager isLicenseCurrentlyValid]) {
        [self updateLicenseUIState];
        return;
    }
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.vaultAccounts.count) return;
    ZTechVaultAccount *acc = self.vaultAccounts[idx];

    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
    [gen impactOccurred];

    // Immediate visual feedback on button + Loading HUD
    sender.enabled = NO;
    [self styleButton:sender
                title:@"Đang mở..."
             iconType:ZTechIconCloudSync
            tintColor:[self darkInkColor]
                 font:[UIFont systemFontOfSize:13.0 weight:UIFontWeightHeavy]];

    NSString *subMsg = (acc.proxyString.length > 0)
        ? [NSString stringWithFormat:@"Đang nạp [%@] & khoá Proxy %@...", acc.title, acc.proxyString]
        : [NSString stringWithFormat:@"Đang nạp phiên [%@] & khởi động Zalo...", acc.title];
    [self showLoadingWithTitle:@"ĐANG MỞ ZALO..." subtitle:subMsg];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSError *err = nil;
        ZTechDeviceProfile *restoredProf = nil;
        BOOL ok = [ZTechVaultManager restoreAndLaunchAccount:acc outProfile:&restoredProf error:&err];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok && restoredProf) {
                self.loadingSubLabel.text = @"Đã nạp xong! Đang chuyển sang ứng dụng Zalo...";
                self.currentProfile = restoredProf;
                [self refreshUIWithCurrentProfile];
                [self reloadVaultListUI];
                [self hideLoadingOverlayAfterDelay:0.55];
                [self showToast:[NSString stringWithFormat:@"Đã nạp [%@] — Đang mở Zalo!", acc.title] isError:NO];
            } else {
                [self hideLoadingOverlayAfterDelay:0.05];
                [self reloadVaultListUI];
                [self showToast:(err.localizedDescription ?: @"Không thể mở Acc Zalo.") isError:YES];
            }
        });
    });
}

- (void)onTapDeleteVaultAccount:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.vaultAccounts.count) return;
    ZTechVaultAccount *acc = self.vaultAccounts[idx];

    if ([self.pendingDeleteAccountId isEqualToString:acc.accountId]) {
        self.pendingDeleteAccountId = nil;
        [ZTechVaultManager deleteAccountWithId:acc.accountId];
        [self reloadVaultListUI];
        [self showToast:[NSString stringWithFormat:@"Đã xoá [%@] khỏi Kho.", acc.title] isError:NO];
    } else {
        self.pendingDeleteAccountId = acc.accountId;
        [self reloadVaultListUI];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self.pendingDeleteAccountId isEqualToString:acc.accountId]) {
                self.pendingDeleteAccountId = nil;
                [self reloadVaultListUI];
            }
        });
    }
}

#pragma mark - Minimalist Key Input Overlay (Only Key Input Box + Confirm Button)

- (void)buildLockScreenOverlay {
    self.lockOverlayView = [[UIView alloc] init];
    self.lockOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    self.lockOverlayView.backgroundColor = self.isLightMode
        ? [UIColor colorWithRed:0.05 green:0.12 blue:0.26 alpha:0.55]
        : [UIColor colorWithRed:0.02 green:0.03 blue:0.02 alpha:0.94];
    [self.view addSubview:self.lockOverlayView];

    UIControl *bgDismiss = [[UIControl alloc] init];
    bgDismiss.translatesAutoresizingMaskIntoConstraints = NO;
    [bgDismiss addTarget:self action:@selector(dismissAllKeyboards) forControlEvents:UIControlEventTouchUpInside];
    [self.lockOverlayView addSubview:bgDismiss];

    UIView *box = [self createCardView];
    box.layer.borderWidth = 1.5;
    box.layer.borderColor = [self goldAccentColor].CGColor;
    [self.lockOverlayView addSubview:box];

    UILabel *lockTitle = [[UILabel alloc] init];
    lockTitle.translatesAutoresizingMaskIntoConstraints = NO;
    lockTitle.text = @"NHẬP KEY BẢN QUYỀN";
    lockTitle.font = [UIFont systemFontOfSize:17.5 weight:UIFontWeightHeavy];
    lockTitle.textColor = [self goldAccentColor];
    lockTitle.textAlignment = NSTextAlignmentCenter;
    [box addSubview:lockTitle];

    UIView *keyFieldWrapper = [[UIView alloc] init];
    keyFieldWrapper.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:keyFieldWrapper];

    self.keyInputField = [[ZTechSafeTextField alloc] init];
    self.keyInputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.keyInputField.textInsets = UIEdgeInsetsMake(0, 14, 0, 82);
    self.keyInputField.backgroundColor = [self surfaceInsetColor];
    self.keyInputField.layer.cornerRadius = 13.0;
    self.keyInputField.layer.borderWidth = 1.2;
    self.keyInputField.layer.borderColor = [self goldAccentColor].CGColor;
    self.keyInputField.textColor = [self primaryTextColor];
    self.keyInputField.font = [UIFont monospacedSystemFontOfSize:15.5 weight:UIFontWeightBold];
    self.keyInputField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.keyInputField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.keyInputField.keyboardType = UIKeyboardTypeASCIICapable;
    self.keyInputField.returnKeyType = UIReturnKeyDone;
    self.keyInputField.delegate = self;
    self.keyInputField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Nhập hoặc dán mã Key..."
                                                                               attributes:@{NSForegroundColorAttributeName: [self mutedTextColor]}];
    NSString *savedKey = [ZTechLicenseManager savedLicenseKey];
    if (savedKey.length > 0) {
        self.keyInputField.text = savedKey;
    }
    [keyFieldWrapper addSubview:self.keyInputField];

    UIButton *btnPasteInline = [UIButton buttonWithType:UIButtonTypeSystem];
    btnPasteInline.translatesAutoresizingMaskIntoConstraints = NO;
    btnPasteInline.backgroundColor = [self secondaryTintButtonBgColor];
    btnPasteInline.layer.cornerRadius = 9.0;
    btnPasteInline.layer.borderWidth = 1.0;
    btnPasteInline.layer.borderColor = [self goldAccentColor].CGColor;
    [self styleButton:btnPasteInline
                title:@"Dán"
             iconType:ZTechIconClipboardPaste
            tintColor:[self goldAccentColor]
                 font:[UIFont systemFontOfSize:12.5 weight:UIFontWeightBold]];
    [btnPasteInline addTarget:self action:@selector(onTapPasteKeyInline) forControlEvents:UIControlEventTouchUpInside];
    [keyFieldWrapper addSubview:btnPasteInline];

    self.lockStatusMsgLabel = [[UILabel alloc] init];
    self.lockStatusMsgLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.lockStatusMsgLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.lockStatusMsgLabel.textColor = [self dangerCoralColor];
    self.lockStatusMsgLabel.textAlignment = NSTextAlignmentCenter;
    self.lockStatusMsgLabel.numberOfLines = 0;
    self.lockStatusMsgLabel.text = nil;
    [box addSubview:self.lockStatusMsgLabel];

    UIStackView *actionRow = [[UIStackView alloc] init];
    actionRow.translatesAutoresizingMaskIntoConstraints = NO;
    actionRow.axis = UILayoutConstraintAxisHorizontal;
    actionRow.spacing = 10.0;
    actionRow.distribution = UIStackViewDistributionFillProportionally;
    [box addSubview:actionRow];

    self.btnCloseKeyOverlay = [UIButton buttonWithType:UIButtonTypeSystem];
    self.btnCloseKeyOverlay.backgroundColor = [self surfaceInsetColor];
    self.btnCloseKeyOverlay.layer.cornerRadius = 13.0;
    self.btnCloseKeyOverlay.layer.borderWidth = 1.0;
    self.btnCloseKeyOverlay.layer.borderColor = [self borderSubtleColor].CGColor;
    [self.btnCloseKeyOverlay setTitle:@"Đóng" forState:UIControlStateNormal];
    [self.btnCloseKeyOverlay setTitleColor:[self primaryTextColor] forState:UIControlStateNormal];
    self.btnCloseKeyOverlay.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    NSLayoutConstraint *closeWidth = [self.btnCloseKeyOverlay.widthAnchor constraintEqualToConstant:94.0];
    closeWidth.priority = UILayoutPriorityDefaultHigh;
    closeWidth.active = YES;
    self.btnCloseKeyOverlay.hidden = YES;
    [self attachSpringTouchFeedbackToButton:self.btnCloseKeyOverlay];
    [self.btnCloseKeyOverlay addTarget:self action:@selector(onTapCloseKeyOverlay) forControlEvents:UIControlEventTouchUpInside];

    self.btnActivateKey = [UIButton buttonWithType:UIButtonTypeSystem];
    self.btnActivateKey.backgroundColor = [self creamPrimaryColor];
    self.btnActivateKey.layer.cornerRadius = 13.0;
    [self styleButton:self.btnActivateKey
                title:@"Xác nhận"
             iconType:ZTechIconShieldCheck
            tintColor:[self darkInkColor]
                 font:[UIFont systemFontOfSize:15.5 weight:UIFontWeightHeavy]];
    [self.btnActivateKey addTarget:self action:@selector(onTapActivateKey) forControlEvents:UIControlEventTouchUpInside];

    [actionRow addArrangedSubview:self.btnCloseKeyOverlay];
    [actionRow addArrangedSubview:self.btnActivateKey];

    [NSLayoutConstraint activateConstraints:@[
        [self.lockOverlayView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.lockOverlayView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.lockOverlayView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.lockOverlayView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [bgDismiss.topAnchor constraintEqualToAnchor:self.lockOverlayView.topAnchor],
        [bgDismiss.leadingAnchor constraintEqualToAnchor:self.lockOverlayView.leadingAnchor],
        [bgDismiss.trailingAnchor constraintEqualToAnchor:self.lockOverlayView.trailingAnchor],
        [bgDismiss.bottomAnchor constraintEqualToAnchor:self.lockOverlayView.bottomAnchor],

        [box.centerYAnchor constraintEqualToAnchor:self.lockOverlayView.centerYAnchor constant:-32.0],
        [box.leadingAnchor constraintEqualToAnchor:self.lockOverlayView.leadingAnchor constant:20.0],
        [box.trailingAnchor constraintEqualToAnchor:self.lockOverlayView.trailingAnchor constant:-20.0],

        [lockTitle.topAnchor constraintEqualToAnchor:box.topAnchor constant:22.0],
        [lockTitle.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:18.0],
        [lockTitle.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-18.0],

        [keyFieldWrapper.topAnchor constraintEqualToAnchor:lockTitle.bottomAnchor constant:16.0],
        [keyFieldWrapper.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:18.0],
        [keyFieldWrapper.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-18.0],
        [keyFieldWrapper.heightAnchor constraintEqualToConstant:52.0],

        [self.keyInputField.topAnchor constraintEqualToAnchor:keyFieldWrapper.topAnchor],
        [self.keyInputField.leadingAnchor constraintEqualToAnchor:keyFieldWrapper.leadingAnchor],
        [self.keyInputField.trailingAnchor constraintEqualToAnchor:keyFieldWrapper.trailingAnchor],
        [self.keyInputField.bottomAnchor constraintEqualToAnchor:keyFieldWrapper.bottomAnchor],

        [btnPasteInline.centerYAnchor constraintEqualToAnchor:keyFieldWrapper.centerYAnchor],
        [btnPasteInline.trailingAnchor constraintEqualToAnchor:keyFieldWrapper.trailingAnchor constant:-7.0],
        [btnPasteInline.widthAnchor constraintEqualToConstant:68.0],
        [btnPasteInline.heightAnchor constraintEqualToConstant:36.0],

        [self.lockStatusMsgLabel.topAnchor constraintEqualToAnchor:keyFieldWrapper.bottomAnchor constant:8.0],
        [self.lockStatusMsgLabel.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:18.0],
        [self.lockStatusMsgLabel.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-18.0],

        [actionRow.topAnchor constraintEqualToAnchor:self.lockStatusMsgLabel.bottomAnchor constant:8.0],
        [actionRow.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:18.0],
        [actionRow.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-18.0],
        [actionRow.heightAnchor constraintEqualToConstant:50.0],
        [actionRow.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-22.0]
    ]];
}

- (void)dismissAllKeyboards {
    [self.view endEditing:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    if (textField == self.keyInputField) {
        [self onTapActivateKey];
    }
    return YES;
}

- (void)onTapPasteKeyInline {
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];
    NSString *clip = ZTechReadClipboardSafely();
    if (clip.length > 0) {
        self.keyInputField.text = [clip uppercaseString];
        self.lockStatusMsgLabel.text = nil;
    } else {
        self.lockStatusMsgLabel.text = @"Bộ nhớ tạm đang trống, hãy sao chép Key trước!";
        self.lockStatusMsgLabel.textColor = [self dangerCoralColor];
    }
}

#pragma mark - License State Updates

- (void)updateLicenseUIState {
    BOOL valid = [ZTechLicenseManager isLicenseCurrentlyValid];
    self.lockOverlayView.hidden = valid;
    self.btnCloseKeyOverlay.hidden = !valid;

    NSString *savedKey = [ZTechLicenseManager savedLicenseKey];
    self.licKeyUsedValueLabel.text = (savedKey.length > 0) ? savedKey : @"Chưa kích hoạt";
    self.licPlanDetailValueLabel.text = [ZTechLicenseManager licenseStatusSummary];

    if (valid) {
        [self.keyInputField resignFirstResponder];
        self.headerLicenseText.text = @"ĐÃ KÍCH HOẠT";
        self.headerLicenseText.textColor = [self emeraldColor];
        self.headerLicenseIcon.image = [ZTechVectorIcons iconWithType:ZTechIconShieldCheck size:13.0 color:[self emeraldColor]];
        self.headerLicenseBadge.backgroundColor = [self emeraldBadgeBgColor];
        self.headerLicenseBadge.layer.borderColor = [self emeraldColor].CGColor;

        self.licShieldIconView.image = [ZTechVectorIcons iconWithType:ZTechIconShieldCheck size:32.0 color:[self emeraldColor]];
        self.licMainStateLabel.text = @"BẢN QUYỀN ĐANG HOẠT ĐỘNG\nToàn bộ tính năng đã được mở khoá";
        self.licMainStateLabel.textColor = [self emeraldColor];
    } else {
        self.headerLicenseText.text = @"CHƯA KÍCH HOẠT";
        self.headerLicenseText.textColor = [self dangerCoralColor];
        self.headerLicenseIcon.image = [ZTechVectorIcons iconWithType:ZTechIconShieldLock size:13.0 color:[self dangerCoralColor]];
        self.headerLicenseBadge.backgroundColor = [self dangerBadgeBgColor];
        self.headerLicenseBadge.layer.borderColor = [self dangerCoralColor].CGColor;

        self.licShieldIconView.image = [ZTechVectorIcons iconWithType:ZTechIconShieldLock size:32.0 color:[self dangerCoralColor]];
        self.licMainStateLabel.text = @"CHƯA KÍCH HOẠT BẢN QUYỀN\nVui lòng nhập Key để sử dụng";
        self.licMainStateLabel.textColor = [self dangerCoralColor];
    }
}

- (void)onTapShowKeyModal {
    self.lockOverlayView.hidden = NO;
    self.btnCloseKeyOverlay.hidden = ![ZTechLicenseManager isLicenseCurrentlyValid];
    self.lockStatusMsgLabel.text = nil;
    NSString *savedKey = [ZTechLicenseManager savedLicenseKey];
    if (savedKey.length > 0) {
        self.keyInputField.text = savedKey;
    }
    [self.lockOverlayView setNeedsLayout];
    [self.lockOverlayView layoutIfNeeded];
}

- (void)onTapCloseKeyOverlay {
    [self dismissAllKeyboards];
    if ([ZTechLicenseManager isLicenseCurrentlyValid]) {
        self.lockOverlayView.hidden = YES;
    }
}

- (void)onTapActivateKey {
    [self dismissAllKeyboards];
    NSString *inputKey = [self.keyInputField.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (inputKey.length == 0) {
        NSString *clip = ZTechReadClipboardSafely();
        if (clip.length >= 6 && clip.length <= 48 && [clip rangeOfString:@" "].location == NSNotFound) {
            inputKey = [clip uppercaseString];
            self.keyInputField.text = inputKey;
        }
    }

    self.btnActivateKey.enabled = NO;
    [self styleButton:self.btnActivateKey
                title:@"Đang xác nhận..."
             iconType:ZTechIconCloudSync
            tintColor:[self darkInkColor]
                 font:[UIFont systemFontOfSize:15.5 weight:UIFontWeightHeavy]];
    self.lockStatusMsgLabel.text = nil;

    [ZTechLicenseManager verifyAndActivateKey:inputKey completion:^(BOOL isValid, NSString * _Nonnull message, NSString * _Nullable ownerName, NSString * _Nullable expiryText) {
        self.btnActivateKey.enabled = YES;
        [self styleButton:self.btnActivateKey
                    title:@"Xác nhận"
                 iconType:ZTechIconShieldCheck
                tintColor:[self darkInkColor]
                     font:[UIFont systemFontOfSize:15.5 weight:UIFontWeightHeavy]];
        if (isValid) {
            self.keyInputField.text = [ZTechLicenseManager savedLicenseKey] ?: inputKey;
            self.lockStatusMsgLabel.text = nil;
            [self updateLicenseUIState];
            [self showToast:@"Kích hoạt Key thành công!" isError:NO];
        } else {
            self.lockStatusMsgLabel.text = message;
            self.lockStatusMsgLabel.textColor = [self dangerCoralColor];
            [self updateLicenseUIState];
        }
    }];
}

#pragma mark - Feature Actions & Profile Refresh

- (void)onSwitchChanged:(UISwitch *)sender {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setBool:YES forKey:@"ZTech_SwitchInitialized"];
    [prefs setBool:self.lockModelSwitch.isOn forKey:@"ZTech_LockModel"];
    [prefs setBool:self.respringSwitch.isOn forKey:@"ZTech_Respring"];
    [prefs setBool:self.sameScreenSwitch.isOn forKey:@"ZTech_SameScreen"];
    [prefs setBool:self.matchChipSwitch.isOn forKey:@"ZTech_MatchChip"];
    [prefs synchronize];

    self.lockModelSubLabel.text = self.lockModelSwitch.isOn
        ? @"ON: Giữ nguyên đời máy thật — chỉ đổi ID & thông số phụ"
        : @"OFF: Fake Tất Cả — đổi sang iPhone 16 Series / đời mới";

    self.respringSubLabel.text = self.respringSwitch.isOn
        ? @"ON: Tự động làm mới SpringBoard sau khi đổi máy"
        : @"OFF: Áp dụng tức thì không cần khởi động lại màn hình";

    self.sameScreenSubLabel.text = self.sameScreenSwitch.isOn
        ? @"ON: Chỉ bốc các máy có cùng kích thước màn hình thật"
        : @"OFF: Cho phép bốc mọi màn hình (kể cả iPhone 16 Pro Max)";

    self.matchChipSubLabel.text = self.matchChipSwitch.isOn
        ? @"ON: Chỉ bốc các máy cùng dung lượng RAM máy thật"
        : @"OFF: Cho phép giả lập Chip A18 Pro & RAM 8GB đời mới";

    [self refreshCheckFooterText];
}

- (void)refreshUIWithCurrentProfile {
    self.modelHeroLabel.text = self.currentProfile.modelName ?: @"iPhone 16 Pro Max";
    self.machineBadgeLabel.text = [NSString stringWithFormat:@"  %@  ", self.currentProfile.machineId ?: @"iPhone17,2"];
    self.iosBadgeLabel.text = [NSString stringWithFormat:@"  iOS %@  ", self.currentProfile.iosVersion ?: @"18.2.1"];
    self.uuidMonoLabel.text = [NSString stringWithFormat:@"UUID: %@", self.currentProfile.identifier ?: @""];

    self.specChipValueLabel.text = [NSString stringWithFormat:@"%@ · %ldGB", self.currentProfile.chipName ?: @"A18 Pro", (long)self.currentProfile.ramGB];
    self.specScreenValueLabel.text = [NSString stringWithFormat:@"%@ px (@3x)", self.currentProfile.screenKey ?: @"440x956"];
    self.specNetValueLabel.text = [NSString stringWithFormat:@"%@ · %@", self.currentProfile.carrier ?: @"Viettel", self.currentProfile.city ?: @"Hà Nội"];
    self.specBatValueLabel.text = [NSString stringWithFormat:@"%ld%% · %ld danh bạ", (long)self.currentProfile.batteryPercent, (long)self.currentProfile.contactsCount];

    [self refreshCheckFooterText];
}

- (void)refreshCheckFooterText {
    NSString *modeStr = self.lockModelSwitch.isOn ? @"Chế độ: Khoá Đời Máy" : @"Chế độ: Fake Tất Cả";
    NSString *proxyInfo = (self.currentProfile.activeProxy.length > 0)
        ? [NSString stringWithFormat:@" · Proxy: %@", self.currentProfile.activeProxy]
        : @" · Mạng: Trực tiếp (4G/WiFi)";
    self.checkDetailLabel.text = [NSString stringWithFormat:
        @"Đã ghi thành công %ld/7 file cấu hình hệ thống · %ld/10 mục Hook đang hoạt động.\n%@%@",
        (long)self.currentProfile.writtenFilesCount,
        (long)self.currentProfile.successItemsCount,
        modeStr,
        proxyInfo];
}

- (void)onTapChangeDevice {
    if (![ZTechLicenseManager isLicenseCurrentlyValid]) {
        [self updateLicenseUIState];
        return;
    }
    [self onAppBecameActive];

    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [gen impactOccurred];

    self.currentProfile = [ZTechDeviceDatabase generateProfileWithLockRealModel:self.lockModelSwitch.isOn
                                                                     sameScreen:self.sameScreenSwitch.isOn
                                                                      matchChip:self.matchChipSwitch.isOn
                                                                      modelTier:self.currentModelTier
                                                                    currentCity:self.currentProfile.city];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [ZTechVaultManager killZaloProcess];
    });
    [UIView transitionWithView:self.tabFeaturesStack
                      duration:0.18
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        [self refreshUIWithCurrentProfile];
    } completion:^(BOOL finished) {
        [self showToast:[NSString stringWithFormat:@"Đã đổi sang: %@ (iOS %@)", self.currentProfile.modelName, self.currentProfile.iosVersion] isError:NO];
        if (self.respringSwitch.isOn) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [ZTechDeviceDatabase performRespringIfPossible];
            });
        }
    }];
}

- (void)onTapCleanReset {
    if (![ZTechLicenseManager isLicenseCurrentlyValid]) {
        [self updateLicenseUIState];
        return;
    }
    [self onAppBecameActive];

    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
    [gen impactOccurred];

    BOOL lockOn = self.lockModelSwitch.isOn;
    BOOL screenOn = self.sameScreenSwitch.isOn;
    BOOL chipOn = self.matchChipSwitch.isOn;
    ZTechModelTierFilter tier = self.currentModelTier;

    [self showLoadingWithTitle:@"ĐANG LÀM MỚI ZALO" subtitle:@"Đang xoá bộ nhớ đệm & khởi tạo máy ảo mới..."];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSInteger cleaned = [ZTechDeviceDatabase cleanResetAllProfileDataAndCache];
        ZTechDeviceProfile *newProf = [ZTechDeviceDatabase generateProfileWithLockRealModel:lockOn
                                                                                 sameScreen:screenOn
                                                                                  matchChip:chipOn
                                                                                  modelTier:tier
                                                                                currentCity:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideLoadingOverlayAfterDelay:0.15];
            self.currentProfile = newProf;
            [self refreshUIWithCurrentProfile];
            [self reloadVaultListUI];
            [self showToast:[NSString stringWithFormat:@"Đã làm mới Zalo (%ld mục) & Tạo máy %@!", (long)cleaned, self.currentProfile.modelName] isError:NO];
        });
    });
}

- (void)onTapSyncIP {
    [self onTapRotateIP];
}

- (void)onTapRotateIP {
    if (![ZTechLicenseManager isLicenseCurrentlyValid]) {
        [self updateLicenseUIState];
        return;
    }

    [self showAirplaneRotationModal];
}

- (void)showAirplaneRotationModal {
    if (self.airplaneModalOverlay) {
        [self.airplaneTimer invalidate];
        self.airplaneTimer = nil;
        [self.airplaneModalOverlay removeFromSuperview];
        self.airplaneModalOverlay = nil;
    }

    self.airplaneModalOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    self.airplaneModalOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.airplaneModalOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = self.isLightMode ? [UIColor whiteColor] : [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.98];
    card.layer.cornerRadius = 20.0;
    card.layer.borderWidth = 1.5;
    card.layer.borderColor = [self goldAccentColor].CGColor;
    card.layer.masksToBounds = YES;
    [self.airplaneModalOverlay addSubview:card];

    self.airplaneModalIcon = [[UIImageView alloc] initWithImage:[ZTechVectorIcons iconWithType:ZTechIconAirplaneFly size:36.0 color:[self goldAccentColor]]];
    self.airplaneModalIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.airplaneModalIcon.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:self.airplaneModalIcon];

    self.airplaneModalTitle = [[UILabel alloc] init];
    self.airplaneModalTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.airplaneModalTitle.text = @"ĐỔI IP MẠNG (MÁY BAY)";
    self.airplaneModalTitle.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightHeavy];
    self.airplaneModalTitle.textColor = [self goldAccentColor];
    self.airplaneModalTitle.textAlignment = NSTextAlignmentCenter;
    [card addSubview:self.airplaneModalTitle];

    UIView *countdownBox = [[UIView alloc] init];
    countdownBox.translatesAutoresizingMaskIntoConstraints = NO;
    countdownBox.backgroundColor = [self surfaceInsetColor];
    countdownBox.layer.cornerRadius = 16.0;
    countdownBox.layer.borderWidth = 1.0;
    countdownBox.layer.borderColor = [self borderSubtleColor].CGColor;
    [card addSubview:countdownBox];

    self.airplaneCountdownLabel = [[UILabel alloc] init];
    self.airplaneCountdownLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.airplaneCountdownLabel.text = @"22s";
    self.airplaneCountdownLabel.font = [UIFont systemFontOfSize:38.0 weight:UIFontWeightHeavy];
    self.airplaneCountdownLabel.textColor = [self goldAccentColor];
    self.airplaneCountdownLabel.textAlignment = NSTextAlignmentCenter;
    [countdownBox addSubview:self.airplaneCountdownLabel];

    self.airplaneProgressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.airplaneProgressBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.airplaneProgressBar.progressTintColor = [self goldAccentColor];
    self.airplaneProgressBar.trackTintColor = [self borderSubtleColor];
    self.airplaneProgressBar.layer.cornerRadius = 3.0;
    self.airplaneProgressBar.clipsToBounds = YES;
    self.airplaneProgressBar.progress = 0.0;
    [card addSubview:self.airplaneProgressBar];

    self.airplaneModalDesc = [[UILabel alloc] init];
    self.airplaneModalDesc.translatesAutoresizingMaskIntoConstraints = NO;
    self.airplaneModalDesc.text = @"✈️ Đang BẬT Chế độ máy bay...\nGiữ ngắt sóng 22s để nhà mạng cấp dải IP mới.";
    self.airplaneModalDesc.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
    self.airplaneModalDesc.textColor = [self primaryTextColor];
    self.airplaneModalDesc.textAlignment = NSTextAlignmentCenter;
    self.airplaneModalDesc.numberOfLines = 0;
    [card addSubview:self.airplaneModalDesc];

    UIStackView *topBtnRow = [[UIStackView alloc] init];
    topBtnRow.translatesAutoresizingMaskIntoConstraints = NO;
    topBtnRow.axis = UILayoutConstraintAxisHorizontal;
    topBtnRow.distribution = UIStackViewDistributionFillEqually;
    topBtnRow.spacing = 10.0;
    [card addSubview:topBtnRow];

    self.airplaneSkipButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.airplaneSkipButton.backgroundColor = [self secondaryTintButtonBgColor];
    self.airplaneSkipButton.layer.cornerRadius = 12.0;
    self.airplaneSkipButton.layer.borderWidth = 1.0;
    self.airplaneSkipButton.layer.borderColor = [self borderSubtleColor].CGColor;
    [self.airplaneSkipButton setTitle:@"⚡ Bỏ qua chờ" forState:UIControlStateNormal];
    [self.airplaneSkipButton setTitleColor:[self primaryTextColor] forState:UIControlStateNormal];
    self.airplaneSkipButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
    [self attachSpringTouchFeedbackToButton:self.airplaneSkipButton];
    [self.airplaneSkipButton addTarget:self action:@selector(onTapSkipAirplaneWait) forControlEvents:UIControlEventTouchUpInside];
    [topBtnRow addArrangedSubview:self.airplaneSkipButton];

    self.airplaneSettingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.airplaneSettingsButton.backgroundColor = [self surfaceInsetColor];
    self.airplaneSettingsButton.layer.cornerRadius = 12.0;
    self.airplaneSettingsButton.layer.borderWidth = 1.0;
    self.airplaneSettingsButton.layer.borderColor = [self borderSubtleColor].CGColor;
    [self.airplaneSettingsButton setTitle:@"⚙️ Cài đặt" forState:UIControlStateNormal];
    [self.airplaneSettingsButton setTitleColor:[self mutedTextColor] forState:UIControlStateNormal];
    self.airplaneSettingsButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
    [self attachSpringTouchFeedbackToButton:self.airplaneSettingsButton];
    [self.airplaneSettingsButton addTarget:self action:@selector(onTapOpenAirplaneSettings) forControlEvents:UIControlEventTouchUpInside];
    [topBtnRow addArrangedSubview:self.airplaneSettingsButton];

    self.airplaneCancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.airplaneCancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.airplaneCancelButton.backgroundColor = [UIColor colorWithRed:0.92 green:0.25 blue:0.25 alpha:0.12];
    self.airplaneCancelButton.layer.cornerRadius = 12.0;
    self.airplaneCancelButton.layer.borderWidth = 1.0;
    self.airplaneCancelButton.layer.borderColor = [UIColor colorWithRed:0.92 green:0.25 blue:0.25 alpha:0.35].CGColor;
    [self.airplaneCancelButton setTitle:@"✕ Huỷ bỏ" forState:UIControlStateNormal];
    [self.airplaneCancelButton setTitleColor:[UIColor colorWithRed:0.92 green:0.25 blue:0.25 alpha:1.0] forState:UIControlStateNormal];
    self.airplaneCancelButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
    [self attachSpringTouchFeedbackToButton:self.airplaneCancelButton];
    [self.airplaneCancelButton addTarget:self action:@selector(onTapCancelAirplane) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.airplaneCancelButton];

    UILabel *hintLbl = [[UILabel alloc] init];
    hintLbl.translatesAutoresizingMaskIntoConstraints = NO;
    hintLbl.text = @"💡 Mẹo: Dùng mạng 4G/5G để nhà mạng cấp IP mới.";
    hintLbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular];
    hintLbl.textColor = [self mutedTextColor];
    hintLbl.textAlignment = NSTextAlignmentCenter;
    [card addSubview:hintLbl];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.airplaneModalOverlay.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.airplaneModalOverlay.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:300.0],

        [self.airplaneModalIcon.topAnchor constraintEqualToAnchor:card.topAnchor constant:20.0],
        [self.airplaneModalIcon.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [self.airplaneModalIcon.heightAnchor constraintEqualToConstant:36.0],

        [self.airplaneModalTitle.topAnchor constraintEqualToAnchor:self.airplaneModalIcon.bottomAnchor constant:10.0],
        [self.airplaneModalTitle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [self.airplaneModalTitle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],

        [countdownBox.topAnchor constraintEqualToAnchor:self.airplaneModalTitle.bottomAnchor constant:14.0],
        [countdownBox.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [countdownBox.widthAnchor constraintEqualToConstant:140.0],
        [countdownBox.heightAnchor constraintEqualToConstant:62.0],

        [self.airplaneCountdownLabel.centerXAnchor constraintEqualToAnchor:countdownBox.centerXAnchor],
        [self.airplaneCountdownLabel.centerYAnchor constraintEqualToAnchor:countdownBox.centerYAnchor],

        [self.airplaneProgressBar.topAnchor constraintEqualToAnchor:countdownBox.bottomAnchor constant:14.0],
        [self.airplaneProgressBar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24.0],
        [self.airplaneProgressBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],
        [self.airplaneProgressBar.heightAnchor constraintEqualToConstant:6.0],

        [self.airplaneModalDesc.topAnchor constraintEqualToAnchor:self.airplaneProgressBar.bottomAnchor constant:12.0],
        [self.airplaneModalDesc.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [self.airplaneModalDesc.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],

        [topBtnRow.topAnchor constraintEqualToAnchor:self.airplaneModalDesc.bottomAnchor constant:18.0],
        [topBtnRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [topBtnRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0],
        [topBtnRow.heightAnchor constraintEqualToConstant:40.0],

        [self.airplaneCancelButton.topAnchor constraintEqualToAnchor:topBtnRow.bottomAnchor constant:10.0],
        [self.airplaneCancelButton.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [self.airplaneCancelButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0],
        [self.airplaneCancelButton.heightAnchor constraintEqualToConstant:36.0],

        [hintLbl.topAnchor constraintEqualToAnchor:self.airplaneCancelButton.bottomAnchor constant:12.0],
        [hintLbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [hintLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [hintLbl.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0]
    ]];

    [self.view addSubview:self.airplaneModalOverlay];
    self.airplaneModalOverlay.alpha = 0.0;
    [UIView animateWithDuration:0.2 animations:^{
        self.airplaneModalOverlay.alpha = 1.0;
    }];

    // 1. Activate Airplane Mode ON
    [ZTechVaultManager setSystemAirplaneMode:YES];

    // 2. Start 22s timer
    self.airplaneRemainingSeconds = 22;
    [self.airplaneTimer invalidate];
    self.airplaneTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(onAirplaneTimerTick) userInfo:nil repeats:YES];
}

- (void)onAirplaneTimerTick {
    self.airplaneRemainingSeconds--;
    if (self.airplaneRemainingSeconds > 0) {
        self.airplaneCountdownLabel.text = [NSString stringWithFormat:@"%lds", (long)self.airplaneRemainingSeconds];
        float prog = (float)(22 - self.airplaneRemainingSeconds) / 22.0f;
        [self.airplaneProgressBar setProgress:prog animated:YES];
    } else {
        [self.airplaneTimer invalidate];
        self.airplaneTimer = nil;
        [self performAirplaneReconnectAndSyncIP];
    }
}

- (void)performAirplaneReconnectAndSyncIP {
    [self.airplaneTimer invalidate];
    self.airplaneTimer = nil;

    // 1. Turn Airplane Mode OFF
    [ZTechVaultManager setSystemAirplaneMode:NO];

    self.airplaneSkipButton.enabled = NO;
    self.airplaneSkipButton.alpha = 0.5;
    self.airplaneCountdownLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBold];
    self.airplaneCountdownLabel.text = @"Bắt sóng...";
    self.airplaneProgressBar.progress = 1.0;
    self.airplaneModalDesc.text = @"📶 Đã tắt chế độ máy bay!\nĐang đợi thiết bị bắt sóng và cấp IP mới...";

    // Wait 4 seconds for cellular network to negotiate fresh IP
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.airplaneModalDesc.text = @"🔍 Đang kiểm tra địa chỉ IP mới...";
        [ZTechDeviceDatabase syncLocationByIPWithCompletion:^(NSString *city, NSString *isp, NSError *error) {
            [self dismissAirplaneRotationModal];
            if (city.length > 0) {
                self.currentProfile.city = city;
                if (isp.length > 0) {
                    if ([isp rangeOfString:@"Viettel" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                        self.currentProfile.carrier = @"Viettel";
                    } else if ([isp rangeOfString:@"VNPT" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                               [isp rangeOfString:@"Vina" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                        self.currentProfile.carrier = @"Vinaphone";
                    } else if ([isp rangeOfString:@"Mobi" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                        self.currentProfile.carrier = @"MobiFone";
                    }
                }
                [ZTechDeviceDatabase writeProfileFiles:self.currentProfile error:nil];
                [[NSUserDefaults standardUserDefaults] setObject:[self.currentProfile toDictionary] forKey:@"ZTechCurrentProfile"];
                [self refreshUIWithCurrentProfile];
                [self showToast:[NSString stringWithFormat:@"Đã đổi IP thành công: %@ · %@", self.currentProfile.carrier, city] isError:NO];
            } else {
                [self showToast:@"Đã hoàn tất chu trình 22s đổi IP! Hãy kiểm tra lại mạng 4G/LTE." isError:NO];
            }
        }];
    });
}

- (void)onTapSkipAirplaneWait {
    [self performAirplaneReconnectAndSyncIP];
}

- (void)onTapCancelAirplane {
    [self.airplaneTimer invalidate];
    self.airplaneTimer = nil;
    [ZTechVaultManager setSystemAirplaneMode:NO];
    [self dismissAirplaneRotationModal];
    [self showToast:@"Đã dừng tiến trình đổi IP!" isError:YES];
}

- (void)onTapOpenAirplaneSettings {
    NSURL *url = [NSURL URLWithString:@"App-Prefs:root=AIRPLANE_MODE"];
    if (![[UIApplication sharedApplication] canOpenURL:url]) {
        url = [NSURL URLWithString:@"prefs:root=AIRPLANE_MODE"];
    }
    if (![[UIApplication sharedApplication] canOpenURL:url]) {
        url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    }
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)dismissAirplaneRotationModal {
    [self.airplaneTimer invalidate];
    self.airplaneTimer = nil;
    if (self.airplaneModalOverlay) {
        [UIView animateWithDuration:0.2 animations:^{
            self.airplaneModalOverlay.alpha = 0.0;
        } completion:^(BOOL finished) {
            [self.airplaneModalOverlay removeFromSuperview];
            self.airplaneModalOverlay = nil;
        }];
    }
}

- (void)onTapCopyReport {
    @try {
        NSString *report = [self.currentProfile fullReportTextWithFlags:self.lockModelSwitch.isOn
                                                          respringAfter:self.respringSwitch.isOn
                                                             sameScreen:self.sameScreenSwitch.isOn
                                                              matchChip:self.matchChipSwitch.isOn];
        [UIPasteboard generalPasteboard].string = report;
    } @catch (NSException *e) {}
    [self showToast:@"Đã sao chép báo cáo cấu hình vào bộ nhớ tạm!" isError:NO];
}

@end
