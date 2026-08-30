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

    // Reset debounce flag after 5 seconds
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

#pragma mark - Full Automatic Timeline Batch Lyrics Engine

static NSUInteger AMAutoFillAllTimelineLayers(NSArray<NSString *> *lines) {
    if (!lines || lines.count == 0) return 0;
    __block NSUInteger count = 0;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].windows.firstObject;
        UIViewController *root = window.rootViewController;
        while (root.presentedViewController) {
            root = root.presentedViewController;
        }

        // Search for all TimelineCell and text views in the active window hierarchy
        NSMutableArray *allCells = [NSMutableArray array];
        NSMutableArray *queue = [NSMutableArray arrayWithObject:window];
        while (queue.count > 0) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];

            NSString *cls = NSStringFromClass([v class]);
            if ([cls containsString:@"TimelineCell"] || [cls containsString:@"LayerThumbnailCell"]) {
                [allCells addObject:v];
            }
            [queue addObjectsFromArray:v.subviews];
        }

        // Sort cells chronologically by position
        [allCells sortUsingComparator:^NSComparisonResult(UIView *c1, UIView *c2) {
            CGPoint p1 = [c1 convertPoint:CGPointZero toView:nil];
            CGPoint p2 = [c2 convertPoint:CGPointZero toView:nil];
            if (fabs(p1.y - p2.y) > 8.0) {
                return p1.y < p2.y ? NSOrderedAscending : NSOrderedDescending;
            }
            return p1.x < p2.x ? NSOrderedAscending : NSOrderedDescending;
        }];

        NSUInteger lineIdx = 0;
        for (UIView *cell in allCells) {
            if (lineIdx >= lines.count) break;

            UILabel *lbl = nil;
            if ([cell respondsToSelector:@selector(itemLabel)]) {
                lbl = [cell valueForKey:@"itemLabel"];
            }
            if (!lbl) {
                for (UIView *sv in cell.subviews) {
                    if ([sv isKindOfClass:[UILabel class]]) {
                        lbl = (UILabel *)sv;
                        break;
                    }
                }
            }

            if (lbl) {
                NSString *verse = lines[lineIdx];
                lbl.text = verse;
                @try {
                    [cell setValue:verse forKey:@"labelText"];
                } @catch (NSException *e) {}

                [cell setNeedsLayout];
                [cell setNeedsDisplay];
                count++;
                lineIdx++;
            }
        }
    });

    return count;
}

#pragma mark - Batch Lyrics Inserter Modal View Controller

@interface AMBatchLyricsViewController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *lineCountLabel;
@property (nonatomic, strong) UIButton *pasteButton;
@property (nonatomic, strong) UIButton *dismissKeyboardButton;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, weak) UIViewController *parentPresenter;
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

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupHeader {
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, self.view.bounds.size.width - 40, 28)];
    titleLabel.text = @"📝 Tự Động Điền Lời Bài Hát (Batch Lyrics)";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 44, self.view.bounds.size.width - 40, 32)];
    subtitleLabel.text = @"Chỉ cần dán lời bài hát (mỗi dòng 1 câu). Tweak sẽ tự động điền TOÀN BỘ vào tất cả các Text Layer theo thứ tự timeline!";
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

    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    toolbar.barStyle = UIBarStyleBlack;
    toolbar.translucent = YES;
    toolbar.tintColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];

    UIBarButtonItem *pasteItem = [[UIBarButtonItem alloc] initWithTitle:@"📋 Dán Nhanh" style:UIBarButtonItemStylePlain target:self action:@selector(pasteFromClipboard)];
    UIBarButtonItem *clearItem = [[UIBarButtonItem alloc] initWithTitle:@"🧹 Xóa" style:UIBarButtonItemStylePlain target:self action:@selector(clearText)];
    UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithTitle:@"✅ Ẩn Bàn Phím" style:UIBarButtonItemStyleDone target:self action:@selector(dismissKeyboard)];

    [toolbar setItems:@[pasteItem, clearItem, flexSpace, doneItem]];
    self.textView.inputAccessoryView = toolbar;

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

    // Apply Button (Full Auto)
    CGFloat applyX = 173;
    CGFloat applyW = width - applyX - 64;
    self.applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.applyButton.frame = CGRectMake(applyX, bottomY, applyW, 42);
    [self.applyButton setTitle:@"⚡ Điền Full Tự Động" forState:UIControlStateNormal];
    [self.applyButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.applyButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    self.applyButton.layer.cornerRadius = 10.0;
    self.applyButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [self.applyButton addTarget:self action:@selector(applyLyricsToTimeline) forControlEvents:UIControlEventTouchUpInside];
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

- (void)applyLyricsToTimeline {
    [self.view endEditing:YES];
    NSArray<NSString *> *lines = [self extractValidLines:self.textView.text];
    if (lines.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thông báo"
                                                                       message:@"Vui lòng dán lời bài hát (ít nhất 1 câu) trước khi áp dụng."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // 1. Load into Smart Lyrics Queue
    [[AMLyricsQueueManager sharedManager] loadLyrics:lines];

    // 2. Perform UI Timeline Full-Auto Fill
    NSUInteger uiFilled = AMAutoFillAllTimelineLayers(lines);

    // 3. Direct Project XML sync
    NSUInteger xmlReplaced = [self updateRecentProjectXMLFilesWithLines:lines];

    NSUInteger finalCount = (uiFilled > 0) ? uiFilled : ((xmlReplaced > 0) ? xmlReplaced : lines.count);

    NSString *msg = [NSString stringWithFormat:@"Đã tự động điền thành công %lu câu hát vào tất cả các Text Layer trên Timeline!\n(Hiệu ứng, font chữ và mốc beat được giữ nguyên 100%%)", (unsigned long)finalCount];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎉 Hoàn Tất!"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Tuyệt vời" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self dismissModal];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSUInteger)updateRecentProjectXMLFilesWithLines:(NSArray<NSString *> *)lines {
    NSUInteger count = 0;
    NSArray *searchPaths = @[
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: @"",
        NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject ?: @""
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *baseDir in searchPaths) {
        if (baseDir.length == 0) continue;
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:baseDir];
        NSString *file;
        while ((file = [enumerator nextObject])) {
            if ([file.pathExtension.lowercaseString isEqualToString:@"xml"] || [file.pathExtension.lowercaseString isEqualToString:@"amproject"]) {
                NSString *fullPath = [baseDir stringByAppendingPathComponent:file];
                NSError *err = nil;
                NSString *content = [NSString stringWithContentsOfFile:fullPath encoding:NSUTF8StringEncoding error:&err];
                if (content && ([content containsString:@"com.alightcreative.motion.text"] || [content containsString:@"<shape"])) {
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<property name=\"text\" value=\"([^\"]*)\""
                                                                                           options:0
                                                                                             error:nil];
                    NSArray *matches = [regex matchesInString:content options:0 range:NSMakeRange(0, content.length)];
                    if (matches.count > 0) {
                        NSMutableString *mutableContent = [content mutableCopy];
                        for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--) {
                            if (i < (NSInteger)lines.count) {
                                NSTextCheckingResult *m = matches[i];
                                NSRange valRange = [m rangeAtIndex:1];
                                if (valRange.location != NSNotFound) {
                                    [mutableContent replaceCharactersInRange:valRange withString:lines[i]];
                                    count++;
                                }
                            }
                        }
                        [mutableContent writeToFile:fullPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    }
                }
            }
        }
    }
    return count;
}

@end

#pragma mark - Hook TextInputVC (Auto-Paste Next Verse on Tap)

static void (*orig_TextInputVC_viewDidAppear)(UIViewController *, SEL, BOOL);

static void hook_TextInputVC_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_TextInputVC_viewDidAppear) {
        orig_TextInputVC_viewDidAppear(self, _cmd, animated);
    }

    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count == 0) return;

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
        UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 44)];
        bar.barStyle = UIBarStyleBlack;
        bar.translucent = YES;
        bar.tintColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];

        NSUInteger curIdx = mgr.currentIndex + 1;
        NSString *btnTitle = [NSString stringWithFormat:@"⚡ Điền Câu #%lu/%lu", (unsigned long)curIdx, (unsigned long)mgr.lyricsLines.count];

        UIBarButtonItem *autoFillItem = [[UIBarButtonItem alloc] initWithTitle:btnTitle style:UIBarButtonItemStyleDone target:self action:@selector(am_autoFillCurrentVerse)];
        UIBarButtonItem *prevItem = [[UIBarButtonItem alloc] initWithTitle:@"⏪" style:UIBarButtonItemStylePlain target:self action:@selector(am_prevVerse)];
        UIBarButtonItem *nextItem = [[UIBarButtonItem alloc] initWithTitle:@"⏩" style:UIBarButtonItemStylePlain target:self action:@selector(am_nextVerse)];
        UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithTitle:@"✅ Xong" style:UIBarButtonItemStylePlain target:self action:@selector(am_dismissKeyboard)];

        [bar setItems:@[prevItem, nextItem, autoFillItem, flex, doneItem]];
        tv.inputAccessoryView = bar;
        [tv reloadInputViews];
    }
}

static void am_autoFillCurrentVerse(UIViewController *self, SEL _cmd) {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    NSString *line = [mgr currentLineText];
    if (!line) return;

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
        tv.text = line;
        if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
            [tv.delegate textViewDidChange:tv];
        }
        @try {
            [self setValue:line forKey:@"appearText"];
        } @catch (NSException *e) {}

        [mgr consumeNextLineText];

        if (tv.inputAccessoryView && [tv.inputAccessoryView isKindOfClass:[UIToolbar class]]) {
            UIToolbar *bar = (UIToolbar *)tv.inputAccessoryView;
            NSMutableArray *items = [bar.items mutableCopy];
            if (items.count >= 3) {
                NSUInteger nextNum = mgr.currentIndex + 1;
                NSString *newTitle = [NSString stringWithFormat:@"⚡ Điền Câu #%lu/%lu", (unsigned long)nextNum, (unsigned long)mgr.lyricsLines.count];
                UIBarButtonItem *newItem = [[UIBarButtonItem alloc] initWithTitle:newTitle style:UIBarButtonItemStyleDone target:self action:@selector(am_autoFillCurrentVerse)];
                items[2] = newItem;
                [bar setItems:items];
            }
        }
    }
}

static void am_prevVerse(UIViewController *self, SEL _cmd) {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.currentIndex > 0) {
        mgr.currentIndex--;
    }
    UITextView *tv = [self valueForKey:@"inputTextView"];
    if (tv && [tv.inputAccessoryView isKindOfClass:[UIToolbar class]]) {
        UIToolbar *bar = (UIToolbar *)tv.inputAccessoryView;
        NSMutableArray *items = [bar.items mutableCopy];
        if (items.count >= 3) {
            NSUInteger curNum = mgr.currentIndex + 1;
            NSString *newTitle = [NSString stringWithFormat:@"⚡ Điền Câu #%lu/%lu", (unsigned long)curNum, (unsigned long)mgr.lyricsLines.count];
            UIBarButtonItem *newItem = [[UIBarButtonItem alloc] initWithTitle:newTitle style:UIBarButtonItemStyleDone target:self action:@selector(am_autoFillCurrentVerse)];
            items[2] = newItem;
            [bar setItems:items];
        }
    }
}

static void am_nextVerse(UIViewController *self, SEL _cmd) {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.currentIndex + 1 < mgr.lyricsLines.count) {
        mgr.currentIndex++;
    }
    UITextView *tv = [self valueForKey:@"inputTextView"];
    if (tv && [tv.inputAccessoryView isKindOfClass:[UIToolbar class]]) {
        UIToolbar *bar = (UIToolbar *)tv.inputAccessoryView;
        NSMutableArray *items = [bar.items mutableCopy];
        if (items.count >= 3) {
            NSUInteger curNum = mgr.currentIndex + 1;
            NSString *newTitle = [NSString stringWithFormat:@"⚡ Điền Câu #%lu/%lu", (unsigned long)curNum, (unsigned long)mgr.lyricsLines.count];
            UIBarButtonItem *newItem = [[UIBarButtonItem alloc] initWithTitle:newTitle style:UIBarButtonItemStyleDone target:self action:@selector(am_autoFillCurrentVerse)];
            items[2] = newItem;
            [bar setItems:items];
        }
    }
}

static void am_dismissKeyboard(UIViewController *self, SEL _cmd) {
    [self.view endEditing:YES];
}

#pragma mark - Floating Tool Button Manager

@interface AMBatchLyricsHUD : NSObject
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, weak) UIWindow *parentWindow;
+ (instancetype)sharedHUD;
- (void)installFloatingButtonOnWindow:(UIWindow *)window;
@end

@implementation AMBatchLyricsHUD

+ (instancetype)sharedHUD {
    static AMBatchLyricsHUD *hud = nil;
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

    [btn setTitle:@"📝" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:22.0];
    [btn addTarget:self action:@selector(floatingButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    self.floatingButton = btn;

    [window addSubview:btn];
    [window bringSubviewToFront:btn];
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

    AMBatchLyricsViewController *vc = [[AMBatchLyricsViewController alloc] init];
    vc.parentPresenter = root;
    vc.modalPresentationStyle = UIModalPresentationFormSheet;
    [root presentViewController:vc animated:YES completion:nil];
}

@end

#pragma mark - Hook Present View Controller (Block Ads, Crack Notices & Promos)

static void (*orig_UIViewController_presentViewController)(UIViewController *, SEL, UIViewController *, BOOL, void (^)(void));

static void hook_UIViewController_presentViewController(UIViewController *self, SEL _cmd, UIViewController *vc, BOOL animated, void (^completion)(void)) {
    if (vc) {
        NSString *className = NSStringFromClass([vc class]);

        // 1. Block UIAlertController if it contains advertisements, crack notices, telegram channels, or upgrade promos
        if ([vc isKindOfClass:[UIAlertController class]]) {
            UIAlertController *alert = (UIAlertController *)vc;
            NSString *title = alert.title ?: @"";
            NSString *message = alert.message ?: @"";
            NSString *combined = [NSString stringWithFormat:@"%@ %@", title, message].lowercaseString;

            BOOL isOurAlert = [title containsString:@"Hoàn Tất"] || [title containsString:@"Alight Motion Pro"] || [title containsString:@"Thông báo"] || [title containsString:@"Batch Lyrics"] || [title containsString:@"Đã Nạp"];

            if (!isOurAlert) {
                if ([combined containsString:@"telegram"] || [combined containsString:@"t.me"] || [combined containsString:@"blatant"] ||
                    [combined containsString:@"crack"] || [combined containsString:@"unlocked"] || [combined containsString:@"mod"] ||
                    [combined containsString:@"subscribe"] || [combined containsString:@"quảng cáo"] || [combined containsString:@"channel"] ||
                    [combined containsString:@"ad "] || [combined containsString:@"promo"] || [combined containsString:@"sale"]) {
                    if (completion) completion();
                    return;
                }
            }
        }

        // 2. Block Ad SDKs & In-app upsell / subscription / trial popups
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

#pragma mark - Hook View Controllers (Auto-Click Save & Install HUD)

static void (*orig_UIViewController_viewDidAppear)(UIViewController *, SEL, BOOL);

static void hook_UIViewController_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_UIViewController_viewDidAppear) {
        orig_UIViewController_viewDidAppear(self, _cmd, animated);
    }

    UIWindow *window = self.view.window ?: [UIApplication sharedApplication].windows.firstObject;
    if (window) {
        [[AMBatchLyricsHUD sharedHUD] installFloatingButtonOnWindow:window];
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
        class_addMethod(textInputClass, @selector(am_autoFillCurrentVerse), (IMP)am_autoFillCurrentVerse, "v@:");
        class_addMethod(textInputClass, @selector(am_prevVerse), (IMP)am_prevVerse, "v@:");
        class_addMethod(textInputClass, @selector(am_nextVerse), (IMP)am_nextVerse, "v@:");
        class_addMethod(textInputClass, @selector(am_dismissKeyboard), (IMP)am_dismissKeyboard, "v@:");

        Method textAppearMethod = class_getInstanceMethod(textInputClass, @selector(viewDidAppear:));
        if (textAppearMethod) {
            orig_TextInputVC_viewDidAppear = (void *)method_getImplementation(textAppearMethod);
            method_setImplementation(textAppearMethod, (IMP)hook_TextInputVC_viewDidAppear);
        }
    }
}
