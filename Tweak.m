#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>

#pragma mark - Notification Helper

static void AMNotifyUser(NSString *title, NSString *body) {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title ?: @"Alight Motion Pro";
    content.body = body ?: @"Xuất video hoàn tất! Đã tự động lưu vào Cuộn Camera.";
    content.sound = [UNNotificationSound defaultSound];

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
                                                                            content:content
                                                                            trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                                  withCompletionHandler:nil];
}

#pragma mark - Settings Storage

static BOOL AMIsAutoSaveEnabled(void) {
    NSNumber *val = [[NSUserDefaults standardUserDefaults] objectForKey:@"AM_AutoSaveToPhotos"];
    if (val == nil) return YES;
    return [val boolValue];
}

static void AMSetAutoSaveEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"AM_AutoSaveToPhotos"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Auto Save To Camera Roll Engine

static BOOL hasSavedRecentVideo = NO;

static void AMAutoSaveVideoAtPath(NSString *filePath) {
    if (!AMIsAutoSaveEnabled()) return;
    if (!filePath || filePath.length == 0) return;
    if (hasSavedRecentVideo) return;

    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) return;

    if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(filePath)) {
        return;
    }

    hasSavedRecentVideo = YES;
    UISaveVideoAtPathToSavedPhotosAlbum(filePath, nil, NULL, NULL);
    AMNotifyUser(@"Alight Motion Pro", @"Video đã được tự động lưu vào Cuộn Camera (Photos) thành công!");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        hasSavedRecentVideo = NO;
    });
}

#pragma mark - Hook UIActivityViewController (Share/Export Sheet)

static id (*orig_UIActivityViewController_initWithActivityItems)(id, SEL, NSArray *, NSArray *);

static id hook_UIActivityViewController_initWithActivityItems(id self, SEL _cmd, NSArray *activityItems, NSArray *applicationActivities) {
    if (activityItems) {
        for (id item in activityItems) {
            if ([item isKindOfClass:[NSURL class]]) {
                NSURL *url = (NSURL *)item;
                NSString *ext = url.pathExtension.lowercaseString;
                if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"]) {
                    AMAutoSaveVideoAtPath(url.path);
                }
            } else if ([item isKindOfClass:[NSString class]]) {
                NSString *str = (NSString *)item;
                NSString *ext = str.pathExtension.lowercaseString;
                if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"]) {
                    AMAutoSaveVideoAtPath(str);
                }
            }
        }
    }
    return orig_UIActivityViewController_initWithActivityItems(self, _cmd, activityItems, applicationActivities);
}

#pragma mark - Lyrics Queue Manager

@interface AMLyricsQueueManager : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *lyricsLines;
@property (nonatomic, assign) NSUInteger currentIndex;
+ (instancetype)sharedManager;
- (void)loadLyrics:(NSArray<NSString *> *)lines;
- (void)clearLyrics;
- (NSString *)currentLineText;
- (NSString *)consumeNextLineText;
- (BOOL)hasNextLine;
@end

@implementation AMLyricsQueueManager

+ (instancetype)sharedManager {
    static AMLyricsQueueManager *mgr = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mgr = [[self alloc] init];
        mgr.lyricsLines = [NSMutableArray array];
        mgr.currentIndex = 0;
    });
    return mgr;
}

- (void)loadLyrics:(NSArray<NSString *> *)lines {
    [self.lyricsLines removeAllObjects];
    if (lines) {
        [self.lyricsLines addObjectsFromArray:lines];
    }
    self.currentIndex = 0;
}

- (void)clearLyrics {
    [self.lyricsLines removeAllObjects];
    self.currentIndex = 0;
}

- (NSString *)currentLineText {
    if (self.currentIndex < self.lyricsLines.count) {
        return self.lyricsLines[self.currentIndex];
    }
    return nil;
}

- (NSString *)consumeNextLineText {
    if (self.currentIndex < self.lyricsLines.count) {
        NSString *line = self.lyricsLines[self.currentIndex];
        self.currentIndex++;
        return line;
    }
    return nil;
}

- (BOOL)hasNextLine {
    return self.currentIndex < self.lyricsLines.count;
}

@end

#pragma mark - Batch Lyrics Inserter Modal View Controller

@interface AMBatchLyricsViewController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *lineCountLabel;
@property (nonatomic, strong) UIButton *pasteButton;
@property (nonatomic, strong) UIButton *dismissKeyboardButton;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, copy) void (^onLyricsLoaded)(void);
@end

@implementation AMBatchLyricsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.10 alpha:0.98];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];

    [self setupHeader];
    [self setupTextView];
    [self setupButtons];

    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count > 0) {
        self.textView.text = [mgr.lyricsLines componentsJoinedByString:@"\n"];
        [self updateLineCount];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupHeader {
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, self.view.bounds.size.width - 40, 28)];
    titleLabel.text = @"📝 Nạp Lời Bài Hát (Lyrics)";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 44, self.view.bounds.size.width - 40, 32)];
    subtitleLabel.text = @"Dán danh sách câu hát (mỗi dòng 1 câu). Thanh công cụ mini trên bàn phím sẽ hiển thị câu tiếp theo.";
    subtitleLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    subtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:subtitleLabel];
}

- (void)setupTextView {
    CGFloat yPos = 82;
    CGFloat bottomMargin = 110;
    CGFloat h = self.view.bounds.size.height - yPos - bottomMargin;
    if (h < 150) h = 150;

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(16, yPos, self.view.bounds.size.width - 32, h)];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    self.textView.textColor = [UIColor whiteColor];
    self.textView.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.textView.layer.cornerRadius = 12.0;
    self.textView.layer.borderWidth = 1.2;
    self.textView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.5].CGColor;
    self.textView.delegate = self;
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.textView];

    self.lineCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, yPos + h + 6, self.view.bounds.size.width - 40, 20)];
    self.lineCountLabel.text = @"📊 Số dòng: 0 câu hát đã nhập";
    self.lineCountLabel.textColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    self.lineCountLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.lineCountLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.lineCountLabel];
}

- (void)setupButtons {
    CGFloat bottomY = self.view.bounds.size.height - 54;
    CGFloat width = self.view.bounds.size.width;

    self.pasteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.pasteButton.frame = CGRectMake(16, bottomY, 70, 42);
    [self.pasteButton setTitle:@"📋 Dán" forState:UIControlStateNormal];
    [self.pasteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pasteButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.pasteButton.layer.cornerRadius = 10.0;
    self.pasteButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.pasteButton addTarget:self action:@selector(pasteFromClipboard) forControlEvents:UIControlEventTouchUpInside];
    self.pasteButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.pasteButton];

    self.dismissKeyboardButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.dismissKeyboardButton.frame = CGRectMake(92, bottomY, 75, 42);
    [self.dismissKeyboardButton setTitle:@"⌨️ Ẩn phím" forState:UIControlStateNormal];
    [self.dismissKeyboardButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.dismissKeyboardButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.dismissKeyboardButton.layer.cornerRadius = 10.0;
    self.dismissKeyboardButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.dismissKeyboardButton addTarget:self action:@selector(dismissKeyboard) forControlEvents:UIControlEventTouchUpInside];
    self.dismissKeyboardButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.dismissKeyboardButton];

    CGFloat applyX = 173;
    CGFloat applyW = width - applyX - 64;
    self.applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.applyButton.frame = CGRectMake(applyX, bottomY, applyW, 42);
    [self.applyButton setTitle:@"⚡ Lưu Hàng Đợi" forState:UIControlStateNormal];
    [self.applyButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.applyButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    self.applyButton.layer.cornerRadius = 10.0;
    self.applyButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [self.applyButton addTarget:self action:@selector(applyLyricsToQueue) forControlEvents:UIControlEventTouchUpInside];
    self.applyButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.applyButton];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(width - 58, bottomY, 46, 42);
    [self.closeButton setTitle:@"Đóng" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(dismissModal) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:self.closeButton];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)clearText {
    self.textView.text = @"";
    [self updateLineCount];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat keyboardHeight = keyboardFrame.size.height;
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    [UIView animateWithDuration:duration animations:^{
        CGRect frame = self.textView.frame;
        frame.size.height = self.view.bounds.size.height - 82 - keyboardHeight - 10;
        if (frame.size.height < 100) frame.size.height = 100;
        self.textView.frame = frame;
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    [UIView animateWithDuration:duration animations:^{
        CGRect frame = self.textView.frame;
        frame.size.height = self.view.bounds.size.height - 82 - 110;
        self.textView.frame = frame;
    }];
}

- (void)textViewDidChange:(UITextView *)textView {
    [self updateLineCount];
}

- (void)updateLineCount {
    NSArray *lines = [self extractValidLines:self.textView.text];
    self.lineCountLabel.text = [NSString stringWithFormat:@"📊 Số dòng: %lu câu hát đã nhập", (unsigned long)lines.count];
}

- (NSArray<NSString *> *)extractValidLines:(NSString *)rawText {
    if (!rawText || rawText.length == 0) return @[];
    NSArray *all = [rawText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *valid = [NSMutableArray array];
    for (NSString *s in all) {
        NSString *trimmed = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            [valid addObject:trimmed];
        }
    }
    return valid;
}

- (void)pasteFromClipboard {
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    if (pb.string && pb.string.length > 0) {
        self.textView.text = pb.string;
        [self updateLineCount];
    }
}

- (void)dismissModal {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyLyricsToQueue {
    [self.view endEditing:YES];
    NSArray<NSString *> *lines = [self extractValidLines:self.textView.text];
    if (lines.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thông báo"
                                                                       message:@"Vui lòng dán lời bài hát (ít nhất 1 câu) trước khi lưu."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    [[AMLyricsQueueManager sharedManager] loadLyrics:lines];

    if (self.onLyricsLoaded) {
        self.onLyricsLoaded();
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Home Settings Dashboard Modal (Mở từ nút nổi ở Trang Chủ)

@interface AMHomeSettingsViewController : UIViewController
@end

@implementation AMHomeSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.11 alpha:0.98];

    CGFloat w = self.view.bounds.size.width;

    // Header
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, w - 40, 28)];
    titleLabel.text = @"⚙️ Cài Đặt Alight Motion Pro";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    [self.view addSubview:titleLabel];

    // Card 1: Batch Lyrics Manager
    UIView *card1 = [[UIView alloc] initWithFrame:CGRectMake(16, 60, w - 32, 90)];
    card1.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    card1.layer.cornerRadius = 14.0;
    card1.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:card1];

    UILabel *l1 = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, card1.bounds.size.width - 32, 22)];
    l1.text = @"📝 Quản Lý Lời Bài Hát (Batch Lyrics)";
    l1.textColor = [UIColor whiteColor];
    l1.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [card1 addSubview:l1];

    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    UILabel *l1Sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, card1.bounds.size.width - 150, 42)];
    l1Sub.text = [NSString stringWithFormat:@"Trạng thái: Đang có %lu câu trong hàng đợi mini bar.", (unsigned long)mgr.lyricsLines.count];
    l1Sub.textColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    l1Sub.font = [UIFont systemFontOfSize:12];
    l1Sub.numberOfLines = 2;
    [card1 addSubview:l1Sub];

    UIButton *loadBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    loadBtn.frame = CGRectMake(card1.bounds.size.width - 120, 36, 108, 36);
    [loadBtn setTitle:@"📝 Nạp Lời" forState:UIControlStateNormal];
    [loadBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    loadBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    loadBtn.layer.cornerRadius = 10.0;
    loadBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    loadBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [loadBtn addTarget:self action:@selector(openLyricsModal) forControlEvents:UIControlEventTouchUpInside];
    [card1 addSubview:loadBtn];

    // Card 2: Auto Save to Camera Roll
    UIView *card2 = [[UIView alloc] initWithFrame:CGRectMake(16, 162, w - 32, 70)];
    card2.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    card2.layer.cornerRadius = 14.0;
    card2.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:card2];

    UILabel *l2 = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, card2.bounds.size.width - 100, 20)];
    l2.text = @"🎬 Tự Động Lưu Vào Cuộn Camera";
    l2.textColor = [UIColor whiteColor];
    l2.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [card2 addSubview:l2];

    UILabel *l2Sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, card2.bounds.size.width - 100, 20)];
    l2Sub.text = @"Tự động lưu video sau khi render xong";
    l2Sub.textColor = [UIColor lightGrayColor];
    l2Sub.font = [UIFont systemFontOfSize:11];
    [card2 addSubview:l2Sub];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(card2.bounds.size.width - 66, 19, 51, 31)];
    sw.onTintColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    sw.on = AMIsAutoSaveEnabled();
    sw.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [sw addTarget:self action:@selector(toggleAutoSave:) forControlEvents:UIControlEventValueChanged];
    [card2 addSubview:sw];

    // Card 3: Pro & Effects Status
    UIView *card3 = [[UIView alloc] initWithFrame:CGRectMake(16, 244, w - 32, 80)];
    card3.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    card3.layer.cornerRadius = 14.0;
    card3.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:card3];

    UILabel *l3 = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, card3.bounds.size.width - 32, 22)];
    l3.text = @"👑 Trạng Thái Hệ Thống";
    l3.textColor = [UIColor whiteColor];
    l3.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [card3 addSubview:l3];

    UILabel *l3Sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, card3.bounds.size.width - 32, 36)];
    l3Sub.text = @"🟢 Full Premium Pro v6.2.56 Unlocked (4K, No Watermark)\n🟢 1.182 Hiệu ứng & Presets từ bản V2 sẵn sàng";
    l3Sub.textColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    l3Sub.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    l3Sub.numberOfLines = 2;
    [card3 addSubview:l3Sub];

    // Close Button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(16, self.view.bounds.size.height - 56, w - 32, 44);
    [closeBtn setTitle:@"Đóng Cài Đặt" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    closeBtn.layer.cornerRadius = 12.0;
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    closeBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [closeBtn addTarget:self action:@selector(dismissSelf) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeBtn];
}

- (void)toggleAutoSave:(UISwitch *)sw {
    AMSetAutoSaveEnabled(sw.on);
}

- (void)openLyricsModal {
    AMBatchLyricsViewController *modal = [[AMBatchLyricsViewController alloc] init];
    modal.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:modal animated:YES completion:nil];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Sleek Glassmorphic Minimal Lyrics Accessory Bar

@interface AMMinimalLyricsBar : UIView
@property (nonatomic, weak) UIViewController *targetVC;
@property (nonatomic, strong) UIButton *prevBtn;
@property (nonatomic, strong) UIButton *nextBtn;
@property (nonatomic, strong) UIButton *versePillBtn;
@property (nonatomic, strong) UIButton *loadBtn;
@property (nonatomic, strong) UIButton *closeBtn;
+ (instancetype)barForViewController:(UIViewController *)vc;
- (void)refreshDisplay;
@end

@implementation AMMinimalLyricsBar

+ (instancetype)barForViewController:(UIViewController *)vc {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    AMMinimalLyricsBar *bar = [[self alloc] initWithFrame:CGRectMake(0, 0, screenW, 40.0)];
    bar.targetVC = vc;
    bar.backgroundColor = [UIColor clearColor];

    UIView *capsule = [[UIView alloc] initWithFrame:CGRectMake(8.0, 3.0, screenW - 16.0, 34.0)];
    capsule.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.94];
    capsule.layer.cornerRadius = 17.0;
    capsule.layer.borderWidth = 1.0;
    capsule.layer.borderColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.35].CGColor;
    capsule.clipsToBounds = YES;
    capsule.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [bar addSubview:capsule];

    CGFloat capW = capsule.bounds.size.width;

    UIButton *prev = [UIButton buttonWithType:UIButtonTypeSystem];
    prev.frame = CGRectMake(4.0, 3.0, 28.0, 28.0);
    [prev setTitle:@"‹" forState:UIControlStateNormal];
    [prev setTitleColor:[UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0] forState:UIControlStateNormal];
    prev.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    prev.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
    prev.layer.cornerRadius = 14.0;
    [prev addTarget:bar action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:prev];
    bar.prevBtn = prev;

    UIButton *next = [UIButton buttonWithType:UIButtonTypeSystem];
    next.frame = CGRectMake(36.0, 3.0, 28.0, 28.0);
    [next setTitle:@"›" forState:UIControlStateNormal];
    [next setTitleColor:[UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0] forState:UIControlStateNormal];
    next.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    next.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
    next.layer.cornerRadius = 14.0;
    [next addTarget:bar action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:next];
    bar.nextBtn = next;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(capW - 32.0, 3.0, 28.0, 28.0);
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    close.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
    close.layer.cornerRadius = 14.0;
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [close addTarget:bar action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:close];
    bar.closeBtn = close;

    UIButton *load = [UIButton buttonWithType:UIButtonTypeSystem];
    load.frame = CGRectMake(capW - 64.0, 3.0, 28.0, 28.0);
    [load setTitle:@"📋" forState:UIControlStateNormal];
    load.titleLabel.font = [UIFont systemFontOfSize:14];
    load.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
    load.layer.cornerRadius = 14.0;
    load.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [load addTarget:bar action:@selector(loadTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:load];
    bar.loadBtn = load;

    CGFloat centerStartX = 68.0;
    CGFloat centerW = capW - 68.0 - 68.0;
    UIButton *verse = [UIButton buttonWithType:UIButtonTypeSystem];
    verse.frame = CGRectMake(centerStartX, 3.0, centerW, 28.0);
    verse.backgroundColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.18];
    verse.layer.cornerRadius = 14.0;
    verse.layer.borderWidth = 0.8;
    verse.layer.borderColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.5].CGColor;
    [verse setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    verse.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    verse.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    verse.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    verse.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [verse addTarget:bar action:@selector(verseTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:verse];
    bar.versePillBtn = verse;

    [bar refreshDisplay];
    return bar;
}

- (void)refreshDisplay {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count == 0) {
        self.prevBtn.hidden = YES;
        self.nextBtn.hidden = YES;
        [self.versePillBtn setTitle:@"📋 Chạm để Nạp Lời Bài Hát" forState:UIControlStateNormal];
        [self.versePillBtn setTitleColor:[UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0] forState:UIControlStateNormal];
    } else {
        self.prevBtn.hidden = NO;
        self.nextBtn.hidden = NO;
        NSUInteger cur = mgr.currentIndex + 1;
        NSString *line = [mgr currentLineText] ?: @"";
        NSString *title = [NSString stringWithFormat:@"⚡ %lu/%lu: \"%@\"", (unsigned long)cur, (unsigned long)mgr.lyricsLines.count, line];
        [self.versePillBtn setTitle:title forState:UIControlStateNormal];
        [self.versePillBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
}

- (void)verseTapped {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count == 0) {
        [self loadTapped];
        return;
    }

    NSString *line = [mgr currentLineText];
    if (!line) return;

    UITextView *tv = nil;
    if ([self.targetVC respondsToSelector:@selector(inputTextView)]) {
        tv = [self.targetVC valueForKey:@"inputTextView"];
    }
    if (!tv) {
        for (UIView *sub in self.targetVC.view.subviews) {
            if ([sub isKindOfClass:[UITextView class]]) {
                tv = (UITextView *)sub;
                break;
            }
        }
    }

    if (tv) {
        // Complete, deep text injection to ensure internal Swift / KVO updates
        tv.text = line;
        if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
            [tv.delegate textViewDidChange:tv];
        }
        if ([tv.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
            [tv.delegate textView:tv shouldChangeTextInRange:NSMakeRange(0, tv.text.length) replacementText:line];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];

        @try {
            [self.targetVC setValue:line forKey:@"appearText"];
        } @catch (NSException *e) {}

        // Advance to next verse for next layer
        [mgr consumeNextLineText];
        [self refreshDisplay];

        // Haptic feedback
        AudioServicesPlaySystemSound(1519);
    }
}

- (void)prevTapped {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.currentIndex > 0) {
        mgr.currentIndex--;
    }
    [self refreshDisplay];
}

- (void)nextTapped {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.currentIndex + 1 < mgr.lyricsLines.count) {
        mgr.currentIndex++;
    }
    [self refreshDisplay];
}

- (void)closeTapped {
    [self.targetVC.view endEditing:YES];
}

- (void)loadTapped {
    AMBatchLyricsViewController *modal = [[AMBatchLyricsViewController alloc] init];
    modal.modalPresentationStyle = UIModalPresentationFormSheet;
    __weak typeof(self) weakSelf = self;
    modal.onLyricsLoaded = ^{
        [weakSelf refreshDisplay];
    };
    [self.targetVC presentViewController:modal animated:YES completion:nil];
}

@end

#pragma mark - Home Screen Floating Settings HUD (CHỈ HIỆN Ở TRANG CHỦ)

@interface AMHomeSettingsHUD : NSObject
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, weak) UIWindow *parentWindow;
+ (instancetype)sharedHUD;
- (void)installFloatingButtonOnWindow:(UIWindow *)window;
- (void)setFloatingButtonVisible:(BOOL)visible;
@end

@implementation AMHomeSettingsHUD

+ (instancetype)sharedHUD {
    static AMHomeSettingsHUD *hud = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hud = [[self alloc] init];
    });
    return hud;
}

- (void)installFloatingButtonOnWindow:(UIWindow *)window {
    if (self.floatingButton || !window) return;
    self.parentWindow = window;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(16.0, window.bounds.size.height - 140.0, 48.0, 48.0);
    btn.layer.cornerRadius = 24.0;
    btn.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.9];
    btn.layer.borderWidth = 1.5;
    btn.layer.borderColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.8].CGColor;
    btn.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.5].CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 4);
    btn.layer.shadowRadius = 8.0;
    btn.layer.shadowOpacity = 0.8;

    [btn setTitle:@"⚙️" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:22.0];
    [btn addTarget:self action:@selector(floatingButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    self.floatingButton = btn;

    [window addSubview:btn];
    [window bringSubviewToFront:btn];
}

- (void)setFloatingButtonVisible:(BOOL)visible {
    if (self.floatingButton) {
        self.floatingButton.hidden = !visible;
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    UIWindow *window = self.parentWindow ?: [UIApplication sharedApplication].windows.firstObject;
    if (!view || !window) return;

    CGPoint translation = [pan translationInView:window];
    CGPoint center = view.center;
    center.x += translation.x;
    center.y += translation.y;

    CGFloat halfW = view.bounds.size.width / 2.0;
    CGFloat halfH = view.bounds.size.height / 2.0;
    CGFloat minX = halfW + 8.0;
    CGFloat maxX = window.bounds.size.width - halfW - 8.0;
    CGFloat minY = halfH + window.safeAreaInsets.top + 8.0;
    CGFloat maxY = window.bounds.size.height - halfH - window.safeAreaInsets.bottom - 8.0;

    center.x = MAX(minX, MIN(maxX, center.x));
    center.y = MAX(minY, MIN(maxY, center.y));
    view.center = center;
    [pan setTranslation:CGPointZero inView:window];

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat snapX = (center.x < window.bounds.size.width / 2.0) ? minX : maxX;
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            view.center = CGPointMake(snapX, center.y);
        } completion:nil];
    }
}

- (void)floatingButtonTapped:(UIButton *)sender {
    UIWindow *window = self.parentWindow ?: [UIApplication sharedApplication].windows.firstObject;
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }

    AMHomeSettingsViewController *vc = [[AMHomeSettingsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationFormSheet;
    [root presentViewController:vc animated:YES completion:nil];
}

@end

#pragma mark - Hook TextInputVC (Install Sleek Minimalist Accessory Bar)

static void (*orig_TextInputVC_viewDidAppear)(UIViewController *, SEL, BOOL);

static void hook_TextInputVC_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_TextInputVC_viewDidAppear) {
        orig_TextInputVC_viewDidAppear(self, _cmd, animated);
    }

    UITextView *tv = nil;
    if ([self respondsToSelector:@selector(inputTextView)]) {
        tv = [self valueForKey:@"inputTextView"];
    }
    if (!tv) {
        for (UIView *sub in self.view.subviews) {
            if ([sub isKindOfClass:[UITextView class]]) {
                tv = (UITextView *)sub;
                break;
            }
        }
    }

    if (tv) {
        AMMinimalLyricsBar *bar = [AMMinimalLyricsBar barForViewController:self];
        tv.inputAccessoryView = bar;
        [tv reloadInputViews];
    }
}

#pragma mark - Hook Present View Controller (Block Ads, Crack Notices & Promos)

static void (*orig_UIViewController_presentViewController)(UIViewController *, SEL, UIViewController *, BOOL, void (^)(void));

static void hook_UIViewController_presentViewController(UIViewController *self, SEL _cmd, UIViewController *vc, BOOL animated, void (^completion)(void)) {
    if (vc) {
        NSString *className = NSStringFromClass([vc class]);

        if ([vc isKindOfClass:[UIAlertController class]]) {
            UIAlertController *alert = (UIAlertController *)vc;
            NSString *title = alert.title ?: @"";
            NSString *message = alert.message ?: @"";
            NSString *combined = [NSString stringWithFormat:@"%@ %@", title, message].lowercaseString;

            BOOL isOurAlert = [title containsString:@"Hoàn Tất"] || [title containsString:@"Alight Motion Pro"] || [title containsString:@"Thông báo"] || [title containsString:@"Batch Lyrics"] || [title containsString:@"Nạp Lời"] || [title containsString:@"Cài Đặt"];

            if (!isOurAlert) {
                if ([combined containsString:@"telegram"] || [combined containsString:@"t.me"] || [combined containsString:@"blatant"] ||
                    [combined containsString:@"crack"] || [combined containsString:@"unlocked"] || [combined containsString:@"mod"] ||
                    [combined containsString:@"subscribe"] || [combined containsString:@"quảng cáo"] || [combined containsString:@"channel"] ||
                    [combined containsString:@"fastdecrypt"] || [combined containsString:@"sale"]) {
                    if (completion) completion();
                    return;
                }
            }
        }

        if ([className containsString:@"GAD"] || 
            [className containsString:@"IronSource"] || 
            [className containsString:@"Vungle"] || 
            [className containsString:@"StoreSubscription"] || 
            [className containsString:@"StorePromo"] || 
            [className containsString:@"StoreAnnualSale"] || 
            [className containsString:@"StoreTrial"] || 
            [className containsString:@"TrialEndSoon"] || 
            [className containsString:@"WatermarkPopup"] ||
            [className containsString:@"SKStoreProductViewController"]) {
            if (completion) completion();
            return;
        }
    }

    if (orig_UIViewController_presentViewController) {
        orig_UIViewController_presentViewController(self, _cmd, vc, animated, completion);
    }
}

#pragma mark - Hook View Controllers (Auto-Click Save & Manage Home-Only Floating Button)

static void (*orig_UIViewController_viewDidAppear)(UIViewController *, SEL, BOOL);

static void hook_UIViewController_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_UIViewController_viewDidAppear) {
        orig_UIViewController_viewDidAppear(self, _cmd, animated);
    }

    UIWindow *window = self.view.window ?: [UIApplication sharedApplication].windows.firstObject;
    if (window) {
        [[AMHomeSettingsHUD sharedHUD] installFloatingButtonOnWindow:window];
    }

    NSString *className = NSStringFromClass([self class]);

    // Show floating button ONLY on Home Screen, hide on Editor / Timeline / Export
    BOOL isHomeScreen = [className containsString:@"Home"] || [className containsString:@"TabBarController"];
    BOOL isEditorScreen = [className containsString:@"Edit"] || [className containsString:@"Timeline"] || [className containsString:@"Export"] || [className containsString:@"Inspector"] || [className containsString:@"Shape"];

    if (isEditorScreen) {
        [[AMHomeSettingsHUD sharedHUD] setFloatingButtonVisible:NO];
    } else if (isHomeScreen) {
        [[AMHomeSettingsHUD sharedHUD] setFloatingButtonVisible:YES];
    }

    if ([className containsString:@"ExportPreviewVC"] || [className containsString:@"ExportVC"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self respondsToSelector:@selector(storeButton)]) {
                IMP imp = [self methodForSelector:@selector(storeButton)];
                UIButton *(*getButton)(id, SEL) = (void *)imp;
                UIButton *button = getButton(self, @selector(storeButton));
                if ([button isKindOfClass:[UIButton class]]) {
                    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
                }
            }
        });
    }
}

#pragma mark - Tweak Constructor & Permissions

__attribute__((constructor)) static void initAutoExportAndBatchLyricsMod() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 14, *)) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {}];
        } else {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {}];
        }

        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                              completionHandler:^(BOOL granted, NSError * _Nullable error) {}];
    });

    Class activityVCClass = [UIActivityViewController class];
    Method initActivityMethod = class_getInstanceMethod(activityVCClass, @selector(initWithActivityItems:applicationActivities:));
    if (initActivityMethod) {
        orig_UIActivityViewController_initWithActivityItems = (void *)method_getImplementation(initActivityMethod);
        method_setImplementation(initActivityMethod, (IMP)hook_UIActivityViewController_initWithActivityItems);
    }

    Class vcClass = objc_getClass("UIViewController");
    Method viewDidAppearMethod = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    if (viewDidAppearMethod) {
        orig_UIViewController_viewDidAppear = (void *)method_getImplementation(viewDidAppearMethod);
        method_setImplementation(viewDidAppearMethod, (IMP)hook_UIViewController_viewDidAppear);
    }

    Method presentVCMethod = class_getInstanceMethod(vcClass, @selector(presentViewController:animated:completion:));
    if (presentVCMethod) {
        orig_UIViewController_presentViewController = (void *)method_getImplementation(presentVCMethod);
        method_setImplementation(presentVCMethod, (IMP)hook_UIViewController_presentViewController);
    }

    Class textInputClass = objc_getClass("_TtC12AlightMotion11TextInputVC");
    if (textInputClass) {
        Method textAppearMethod = class_getInstanceMethod(textInputClass, @selector(viewDidAppear:));
        if (textAppearMethod) {
            orig_TextInputVC_viewDidAppear = (void *)method_getImplementation(textAppearMethod);
            method_setImplementation(textAppearMethod, (IMP)hook_TextInputVC_viewDidAppear);
        }
    }
}
