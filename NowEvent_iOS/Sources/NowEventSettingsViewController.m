#import "NowEventSettingsViewController.h"
#import "NowEventTheme.h"

@interface NowEventSettingsViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UISwitch *switchNewEvents;
@property (nonatomic, strong) UISwitch *switchSlots;
@property (nonatomic, strong) UIView *historyCard;
@property (nonatomic, strong) UILabel *historyEmptyLabel;

@end

@implementation NowEventSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [NowEventTheme screenBackground];
    
    [self setupUI];
}

- (void)setupUI {
    // ScrollView
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];
    
    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:contentView];
    
    // Top Bar Title: "Cài Đặt"
    UILabel *titleHeader = [[UILabel alloc] init];
    titleHeader.translatesAutoresizingMaskIntoConstraints = NO;
    titleHeader.text = @"Cài Đặt";
    titleHeader.textColor = [NowEventTheme primaryDark];
    titleHeader.font = [UIFont boldSystemFontOfSize:22];
    [contentView addSubview:titleHeader];
    
    // 1. Profile Card Container
    UIView *profileCard = [[UIView alloc] init];
    profileCard.translatesAutoresizingMaskIntoConstraints = NO;
    profileCard.backgroundColor = [NowEventTheme cardBackground];
    profileCard.layer.cornerRadius = 14.0;
    profileCard.layer.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.06].CGColor;
    profileCard.layer.shadowOpacity = 1.0;
    profileCard.layer.shadowRadius = 8.0;
    profileCard.layer.shadowOffset = CGSizeMake(0, 3);
    [contentView addSubview:profileCard];
    
    // Avatar
    UIImageView *avatarView = [[UIImageView alloc] init];
    avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarView.image = [UIImage imageNamed:@"logo.png"];
    avatarView.contentMode = UIViewContentModeScaleAspectFit;
    avatarView.layer.cornerRadius = 40.0;
    avatarView.clipsToBounds = YES;
    avatarView.layer.borderWidth = 3.0;
    avatarView.layer.borderColor = [NowEventTheme accentOrange].CGColor;
    [profileCard addSubview:avatarView];
    
    // User Name: "Đoàn viên IUH"
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.text = @"Đoàn viên IUH";
    nameLabel.textColor = [NowEventTheme primaryDark];
    nameLabel.font = [UIFont boldSystemFontOfSize:18];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    [profileCard addSubview:nameLabel];
    
    // Zalo UID
    UILabel *uidLabel = [[UILabel alloc] init];
    uidLabel.translatesAutoresizingMaskIntoConstraints = NO;
    uidLabel.text = @"Zalo UID: 4146895302344471";
    uidLabel.textColor = [NowEventTheme textMuted];
    uidLabel.font = [UIFont systemFontOfSize:14];
    uidLabel.textAlignment = NSTextAlignmentCenter;
    [profileCard addSubview:uidLabel];
    
    // Version
    UILabel *verLabel = [[UILabel alloc] init];
    verLabel.translatesAutoresizingMaskIntoConstraints = NO;
    verLabel.text = @"Version: 2.1 (iOS Edition)";
    verLabel.textColor = [NowEventTheme textMuted];
    verLabel.font = [UIFont systemFontOfSize:13];
    verLabel.textAlignment = NSTextAlignmentCenter;
    [profileCard addSubview:verLabel];
    
    // 2. Section Header: "CẤU HÌNH"
    UILabel *lblConfig = [[UILabel alloc] init];
    lblConfig.translatesAutoresizingMaskIntoConstraints = NO;
    lblConfig.text = @"CẤU HÌNH";
    lblConfig.textColor = [NowEventTheme textMuted];
    lblConfig.font = [UIFont boldSystemFontOfSize:12];
    [contentView addSubview:lblConfig];
    
    // Config Card
    UIView *configCard = [[UIView alloc] init];
    configCard.translatesAutoresizingMaskIntoConstraints = NO;
    configCard.backgroundColor = [NowEventTheme cardBackground];
    configCard.layer.cornerRadius = 14.0;
    configCard.layer.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.06].CGColor;
    configCard.layer.shadowOpacity = 1.0;
    configCard.layer.shadowRadius = 8.0;
    configCard.layer.shadowOffset = CGSizeMake(0, 3);
    [contentView addSubview:configCard];
    
    // Row 1: New Events Switch
    UILabel *lblNewEvents = [[UILabel alloc] init];
    lblNewEvents.translatesAutoresizingMaskIntoConstraints = NO;
    lblNewEvents.text = @"Thông báo sự kiện mới";
    lblNewEvents.textColor = [NowEventTheme primaryDark];
    lblNewEvents.font = [UIFont boldSystemFontOfSize:15];
    [configCard addSubview:lblNewEvents];
    
    UILabel *lblNewEventsSub = [[UILabel alloc] init];
    lblNewEventsSub.translatesAutoresizingMaskIntoConstraints = NO;
    lblNewEventsSub.text = @"Nhận tin tức ngay khi Đoàn trường đăng tải sự kiện";
    lblNewEventsSub.textColor = [NowEventTheme textMuted];
    lblNewEventsSub.font = [UIFont systemFontOfSize:12];
    [configCard addSubview:lblNewEventsSub];
    
    self.switchNewEvents = [[UISwitch alloc] init];
    self.switchNewEvents.translatesAutoresizingMaskIntoConstraints = NO;
    self.switchNewEvents.on = YES;
    self.switchNewEvents.onTintColor = [NowEventTheme accentOrange];
    [configCard addSubview:self.switchNewEvents];
    
    UIView *divider = [[UIView alloc] init];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = [NowEventTheme progressBackground];
    [configCard addSubview:divider];
    
    // Row 2: Available Slots Switch
    UILabel *lblSlots = [[UILabel alloc] init];
    lblSlots.translatesAutoresizingMaskIntoConstraints = NO;
    lblSlots.text = @"Cảnh báo nhả slot trống";
    lblSlots.textColor = [NowEventTheme primaryDark];
    lblSlots.font = [UIFont boldSystemFontOfSize:15];
    [configCard addSubview:lblSlots];
    
    UILabel *lblSlotsSub = [[UILabel alloc] init];
    lblSlotsSub.translatesAutoresizingMaskIntoConstraints = NO;
    lblSlotsSub.text = @"Nhận cảnh báo khi số lượng còn ít";
    lblSlotsSub.textColor = [NowEventTheme textMuted];
    lblSlotsSub.font = [UIFont systemFontOfSize:12];
    [configCard addSubview:lblSlotsSub];
    
    self.switchSlots = [[UISwitch alloc] init];
    self.switchSlots.translatesAutoresizingMaskIntoConstraints = NO;
    self.switchSlots.on = YES;
    self.switchSlots.onTintColor = [NowEventTheme accentOrange];
    [configCard addSubview:self.switchSlots];
    
    // 3. Section Header: "LỊCH SỬ" + "Xóa lịch sử"
    UILabel *lblHistory = [[UILabel alloc] init];
    lblHistory.translatesAutoresizingMaskIntoConstraints = NO;
    lblHistory.text = @"LỊCH SỬ";
    lblHistory.textColor = [NowEventTheme textMuted];
    lblHistory.font = [UIFont boldSystemFontOfSize:12];
    [contentView addSubview:lblHistory];
    
    UIButton *btnClearHistory = [UIButton buttonWithType:UIButtonTypeSystem];
    btnClearHistory.translatesAutoresizingMaskIntoConstraints = NO;
    [btnClearHistory setTitle:@"Xóa lịch sử" forState:UIControlStateNormal];
    [btnClearHistory setTitleColor:[NowEventTheme dangerRed] forState:UIControlStateNormal];
    btnClearHistory.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [btnClearHistory addTarget:self action:@selector(handleClearHistory) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:btnClearHistory];
    
    // History Card
    self.historyCard = [[UIView alloc] init];
    self.historyCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.historyCard.backgroundColor = [NowEventTheme cardBackground];
    self.historyCard.layer.cornerRadius = 14.0;
    self.historyCard.layer.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.06].CGColor;
    self.historyCard.layer.shadowOpacity = 1.0;
    self.historyCard.layer.shadowRadius = 8.0;
    self.historyCard.layer.shadowOffset = CGSizeMake(0, 3);
    [contentView addSubview:self.historyCard];
    
    self.historyEmptyLabel = [[UILabel alloc] init];
    self.historyEmptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.historyEmptyLabel.text = @"Chưa có thông báo nào được lưu\nKhi hệ thống phát hiện slot mới, thông báo sẽ hiển thị tại đây";
    self.historyEmptyLabel.textColor = [NowEventTheme textMuted];
    self.historyEmptyLabel.font = [UIFont systemFontOfSize:13];
    self.historyEmptyLabel.textAlignment = NSTextAlignmentCenter;
    self.historyEmptyLabel.numberOfLines = 2;
    [self.historyCard addSubview:self.historyEmptyLabel];
    
    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        [contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
        
        // Title
        [titleHeader.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:54],
        [titleHeader.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        
        // Profile Card
        [profileCard.topAnchor constraintEqualToAnchor:titleHeader.bottomAnchor constant:16],
        [profileCard.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [profileCard.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        [avatarView.topAnchor constraintEqualToAnchor:profileCard.topAnchor constant:20],
        [avatarView.centerXAnchor constraintEqualToAnchor:profileCard.centerXAnchor],
        [avatarView.widthAnchor constraintEqualToConstant:80],
        [avatarView.heightAnchor constraintEqualToConstant:80],
        
        [nameLabel.topAnchor constraintEqualToAnchor:avatarView.bottomAnchor constant:12],
        [nameLabel.leadingAnchor constraintEqualToAnchor:profileCard.leadingAnchor constant:16],
        [nameLabel.trailingAnchor constraintEqualToAnchor:profileCard.trailingAnchor constant:-16],
        
        [uidLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:4],
        [uidLabel.leadingAnchor constraintEqualToAnchor:profileCard.leadingAnchor constant:16],
        [uidLabel.trailingAnchor constraintEqualToAnchor:profileCard.trailingAnchor constant:-16],
        
        [verLabel.topAnchor constraintEqualToAnchor:uidLabel.bottomAnchor constant:4],
        [verLabel.leadingAnchor constraintEqualToAnchor:profileCard.leadingAnchor constant:16],
        [verLabel.trailingAnchor constraintEqualToAnchor:profileCard.trailingAnchor constant:-16],
        [verLabel.bottomAnchor constraintEqualToAnchor:profileCard.bottomAnchor constant:-20],
        
        // Config Header
        [lblConfig.topAnchor constraintEqualToAnchor:profileCard.bottomAnchor constant:24],
        [lblConfig.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        
        // Config Card
        [configCard.topAnchor constraintEqualToAnchor:lblConfig.bottomAnchor constant:8],
        [configCard.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [configCard.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        // Row 1
        [lblNewEvents.topAnchor constraintEqualToAnchor:configCard.topAnchor constant:16],
        [lblNewEvents.leadingAnchor constraintEqualToAnchor:configCard.leadingAnchor constant:16],
        [lblNewEventsSub.topAnchor constraintEqualToAnchor:lblNewEvents.bottomAnchor constant:2],
        [lblNewEventsSub.leadingAnchor constraintEqualToAnchor:configCard.leadingAnchor constant:16],
        [lblNewEventsSub.trailingAnchor constraintLessThanOrEqualToAnchor:self.switchNewEvents.leadingAnchor constant:-10],
        
        [self.switchNewEvents.centerYAnchor constraintEqualToAnchor:lblNewEvents.bottomAnchor],
        [self.switchNewEvents.trailingAnchor constraintEqualToAnchor:configCard.trailingAnchor constant:-16],
        
        [divider.topAnchor constraintEqualToAnchor:lblNewEventsSub.bottomAnchor constant:14],
        [divider.leadingAnchor constraintEqualToAnchor:configCard.leadingAnchor constant:16],
        [divider.trailingAnchor constraintEqualToAnchor:configCard.trailingAnchor constant:-16],
        [divider.heightAnchor constraintEqualToConstant:1],
        
        // Row 2
        [lblSlots.topAnchor constraintEqualToAnchor:divider.bottomAnchor constant:14],
        [lblSlots.leadingAnchor constraintEqualToAnchor:configCard.leadingAnchor constant:16],
        [lblSlotsSub.topAnchor constraintEqualToAnchor:lblSlots.bottomAnchor constant:2],
        [lblSlotsSub.leadingAnchor constraintEqualToAnchor:configCard.leadingAnchor constant:16],
        [lblSlotsSub.trailingAnchor constraintLessThanOrEqualToAnchor:self.switchSlots.leadingAnchor constant:-10],
        [lblSlotsSub.bottomAnchor constraintEqualToAnchor:configCard.bottomAnchor constant:-16],
        
        [self.switchSlots.centerYAnchor constraintEqualToAnchor:lblSlots.bottomAnchor],
        [self.switchSlots.trailingAnchor constraintEqualToAnchor:configCard.trailingAnchor constant:-16],
        
        // History Header
        [lblHistory.topAnchor constraintEqualToAnchor:configCard.bottomAnchor constant:24],
        [lblHistory.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        
        [btnClearHistory.centerYAnchor constraintEqualToAnchor:lblHistory.centerYAnchor],
        [btnClearHistory.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        // History Card
        [self.historyCard.topAnchor constraintEqualToAnchor:lblHistory.bottomAnchor constant:8],
        [self.historyCard.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.historyCard.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        [self.historyEmptyLabel.topAnchor constraintEqualToAnchor:self.historyCard.topAnchor constant:24],
        [self.historyEmptyLabel.leadingAnchor constraintEqualToAnchor:self.historyCard.leadingAnchor constant:16],
        [self.historyEmptyLabel.trailingAnchor constraintEqualToAnchor:self.historyCard.trailingAnchor constant:-16],
        [self.historyEmptyLabel.bottomAnchor constraintEqualToAnchor:self.historyCard.bottomAnchor constant:-24],
        [self.historyCard.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-30]
    ]];
}

- (void)handleClearHistory {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    self.historyEmptyLabel.text = @"Đã xóa toàn bộ lịch sử thông báo!";
}

- (void)scrollToTop {
    [self.scrollView setContentOffset:CGPointZero animated:YES];
}

@end
