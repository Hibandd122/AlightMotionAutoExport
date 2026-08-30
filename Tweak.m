#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>
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

#pragma mark - Auto Save To Camera Roll Engine

static BOOL hasSavedRecentVideo = NO;

static void AMAutoSaveVideoAtPath(NSString *filePath) {
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

    // Paste Button
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

    // Hide Keyboard Button
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

    // Apply Button
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

    // Close Button
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

    // Inner sleek capsule container
    UIView *capsule = [[UIView alloc] initWithFrame:CGRectMake(8.0, 3.0, screenW - 16.0, 34.0)];
    capsule.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.94];
    capsule.layer.cornerRadius = 17.0;
    capsule.layer.borderWidth = 1.0;
    capsule.layer.borderColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.35].CGColor;
    capsule.clipsToBounds = YES;
    capsule.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [bar addSubview:capsule];

    CGFloat capW = capsule.bounds.size.width;

    // Previous Chevron [‹]
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

    // Next Chevron [›]
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

    // Close Button [✕]
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

    // Load Lyrics Button [📋]
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

    // Center Verse Pill Button [⚡ 1/12: "Lời câu hát..."]
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
        tv.text = line;
        if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
            [tv.delegate textViewDidChange:tv];
        }
        @try {
            [self.targetVC setValue:line forKey:@"appearText"];
        } @catch (NSException *e) {}

        // Advance to next verse for the next layer
        [mgr consumeNextLineText];
        [self refreshDisplay];
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

            BOOL isOurAlert = [title containsString:@"Hoàn Tất"] || [title containsString:@"Alight Motion Pro"] || [title containsString:@"Thông báo"] || [title containsString:@"Batch Lyrics"] || [title containsString:@"Nạp Lời"];

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

#pragma mark - Hook View Controllers (Auto-Click Save on Export)

static void (*orig_UIViewController_viewDidAppear)(UIViewController *, SEL, BOOL);

static void hook_UIViewController_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_UIViewController_viewDidAppear) {
        orig_UIViewController_viewDidAppear(self, _cmd, animated);
    }

    NSString *className = NSStringFromClass([self class]);
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
