#import "NowEventCardCell.h"
#import "NowEventTheme.h"

@implementation NowEventItem
- (CGFloat)progressFraction {
    if (self.soLuongToiDa <= 0) return 0.0;
    CGFloat f = (CGFloat)self.soLuongHienTai / (CGFloat)self.soLuongToiDa;
    return MIN(1.0, MAX(0.0, f));
}
@end

@interface NowEventCardCell ()

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *badgeView;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UILabel *capacityLabel;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) NSLayoutConstraint *progressWidthConstraint;
@property (nonatomic, strong) UILabel *titleLabel;

@end

@implementation NowEventCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // Card container (white, rounded 14pt, shadow)
    self.cardView = [[UIView alloc] init];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.backgroundColor = [NowEventTheme cardBackground];
    self.cardView.layer.cornerRadius = 14.0;
    self.cardView.layer.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.06].CGColor;
    self.cardView.layer.shadowOpacity = 1.0;
    self.cardView.layer.shadowRadius = 8.0;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 3);
    [self.contentView addSubview:self.cardView];
    
    // Status Badge Container
    self.badgeView = [[UIView alloc] init];
    self.badgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.badgeView.layer.cornerRadius = 6.0;
    self.badgeView.clipsToBounds = YES;
    [self.cardView addSubview:self.badgeView];
    
    self.badgeLabel = [[UILabel alloc] init];
    self.badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.badgeLabel.font = [UIFont boldSystemFontOfSize:12];
    [self.badgeView addSubview:self.badgeLabel];
    
    // Capacity Label: "400 / 400"
    self.capacityLabel = [[UILabel alloc] init];
    self.capacityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.capacityLabel.font = [UIFont boldSystemFontOfSize:13];
    self.capacityLabel.textColor = [NowEventTheme primaryDark];
    [self.cardView addSubview:self.capacityLabel];
    
    // Progress Bar Track
    self.progressTrack = [[UIView alloc] init];
    self.progressTrack.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressTrack.backgroundColor = [NowEventTheme progressBackground];
    self.progressTrack.layer.cornerRadius = 4.0;
    self.progressTrack.clipsToBounds = YES;
    [self.cardView addSubview:self.progressTrack];
    
    // Progress Bar Fill
    self.progressFill = [[UIView alloc] init];
    self.progressFill.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressFill.backgroundColor = [NowEventTheme accentOrange];
    self.progressFill.layer.cornerRadius = 4.0;
    [self.progressTrack addSubview:self.progressFill];
    
    // Event Title Label
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.titleLabel.textColor = [NowEventTheme primaryDark];
    self.titleLabel.numberOfLines = 2;
    [self.cardView addSubview:self.titleLabel];
    
    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [self.cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
        
        // Badge
        [self.badgeView.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:16],
        [self.badgeView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:16],
        [self.badgeView.heightAnchor constraintEqualToConstant:24],
        
        [self.badgeLabel.topAnchor constraintEqualToAnchor:self.badgeView.topAnchor constant:3],
        [self.badgeLabel.bottomAnchor constraintEqualToAnchor:self.badgeView.bottomAnchor constant:-3],
        [self.badgeLabel.leadingAnchor constraintEqualToAnchor:self.badgeView.leadingAnchor constant:10],
        [self.badgeLabel.trailingAnchor constraintEqualToAnchor:self.badgeView.trailingAnchor constant:-10],
        
        // Capacity
        [self.capacityLabel.centerYAnchor constraintEqualToAnchor:self.badgeView.centerYAnchor],
        [self.capacityLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16],
        
        // Progress Track
        [self.progressTrack.topAnchor constraintEqualToAnchor:self.badgeView.bottomAnchor constant:12],
        [self.progressTrack.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:16],
        [self.progressTrack.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16],
        [self.progressTrack.heightAnchor constraintEqualToConstant:8],
        
        // Progress Fill
        [self.progressFill.topAnchor constraintEqualToAnchor:self.progressTrack.topAnchor],
        [self.progressFill.bottomAnchor constraintEqualToAnchor:self.progressTrack.bottomAnchor],
        [self.progressFill.leadingAnchor constraintEqualToAnchor:self.progressTrack.leadingAnchor],
        
        // Title
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.progressTrack.bottomAnchor constant:12],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:16],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16],
        [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-16]
    ]];
    
    self.progressWidthConstraint = [self.progressFill.widthAnchor constraintEqualToConstant:0];
    self.progressWidthConstraint.active = YES;
}

- (void)configureWithEvent:(NowEventItem *)event {
    self.titleLabel.text = event.tenSuKien;
    self.capacityLabel.text = [NSString stringWithFormat:@"%ld / %ld", (long)event.soLuongHienTai, (long)event.soLuongToiDa];
    
    if (event.conSlot) {
        self.badgeLabel.text = (event.trangThai && event.trangThai.length > 0) ? event.trangThai : @"Còn slot";
        self.badgeLabel.textColor = [NowEventTheme badgeOpenText];
        self.badgeView.backgroundColor = [NowEventTheme badgeOpenBg];
    } else {
        self.badgeLabel.text = (event.trangThai && event.trangThai.length > 0) ? event.trangThai : @"Đã đầy";
        self.badgeLabel.textColor = [NowEventTheme badgeFullText];
        self.badgeView.backgroundColor = [NowEventTheme badgeFullBg];
    }
    
    [self layoutIfNeeded];
    CGFloat trackWidth = self.progressTrack.bounds.size.width;
    if (trackWidth <= 0) {
        trackWidth = [UIScreen mainScreen].bounds.size.width - 64;
    }
    self.progressWidthConstraint.constant = trackWidth * [event progressFraction];
}

@end
