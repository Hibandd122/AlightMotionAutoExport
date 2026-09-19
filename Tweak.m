#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#import "fishhook.h"

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

#pragma mark - Settings & Persistence Storage

static BOOL AMIsAutoSaveEnabled(void) {
    NSNumber *val = [[NSUserDefaults standardUserDefaults] objectForKey:@"AM_AutoSaveToPhotos"];
    if (val == nil) return YES;
    return [val boolValue];
}

static void AMSetAutoSaveEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"AM_AutoSaveToPhotos"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL AMIsAutoAdvanceLyricsEnabled(void) {
    NSNumber *val = [[NSUserDefaults standardUserDefaults] objectForKey:@"AM_AutoAdvanceLyrics"];
    if (val == nil) return YES; // Bật sẵn để người dùng chạm vào text là tự động điền câu kế tiếp!
    return [val boolValue];
}

static void AMSetAutoAdvanceLyricsEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"AM_AutoAdvanceLyrics"];
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

#pragma mark - Lyrics Queue Manager (With Async Non-Blocking Disk Persistence)

@interface AMLyricsQueueManager : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *lyricsLines;
@property (nonatomic, assign) NSUInteger currentIndex;
+ (instancetype)sharedManager;
- (void)loadLyrics:(NSArray<NSString *> *)lines;
- (void)clearLyrics;
- (void)resetToFirstVerse;
- (void)jumpToVerseIndex:(NSUInteger)index;
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
        
        NSArray *cached = [[NSUserDefaults standardUserDefaults] objectForKey:@"AM_CachedLyrics"];
        if (cached && [cached isKindOfClass:[NSArray class]]) {
            [mgr.lyricsLines addObjectsFromArray:cached];
        }
        mgr.currentIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"AM_CachedLyricsIndex"];
        if (mgr.currentIndex >= mgr.lyricsLines.count) {
            mgr.currentIndex = 0;
        }
    });
    return mgr;
}

- (void)saveToDisk {
    NSArray *linesCopy = [self.lyricsLines copy];
    NSUInteger indexCopy = self.currentIndex;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [[NSUserDefaults standardUserDefaults] setObject:linesCopy forKey:@"AM_CachedLyrics"];
        [[NSUserDefaults standardUserDefaults] setInteger:indexCopy forKey:@"AM_CachedLyricsIndex"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    });
}

- (void)loadLyrics:(NSArray<NSString *> *)lines {
    [self.lyricsLines removeAllObjects];
    if (lines) {
        [self.lyricsLines addObjectsFromArray:lines];
    }
    self.currentIndex = 0;
    [self saveToDisk];
}

- (void)clearLyrics {
    [self.lyricsLines removeAllObjects];
    self.currentIndex = 0;
    [self saveToDisk];
}

- (void)resetToFirstVerse {
    self.currentIndex = 0;
    [self saveToDisk];
}

- (void)jumpToVerseIndex:(NSUInteger)index {
    if (index < self.lyricsLines.count) {
        self.currentIndex = index;
        [self saveToDisk];
    }
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
        if (self.currentIndex + 1 < self.lyricsLines.count) {
            self.currentIndex++;
            [self saveToDisk];
        }
        return line;
    }
    return nil;
}

- (BOOL)hasNextLine {
    return self.currentIndex < self.lyricsLines.count;
}

- (NSString *)allLyricsFullText {
    if (self.lyricsLines.count == 0) return nil;
    return [self.lyricsLines componentsJoinedByString:@"\n"];
}

- (NSString *)allRemainingLyricsText {
    if (self.lyricsLines.count == 0 || self.currentIndex >= self.lyricsLines.count) return nil;
    NSArray *sub = [self.lyricsLines subarrayWithRange:NSMakeRange(self.currentIndex, self.lyricsLines.count - self.currentIndex)];
    return [sub componentsJoinedByString:@"\n"];
}

@end

#pragma mark - Floating Toast HUD (iOS 18 Liquid Glass Style)

static void AMShowToast(NSString *message) {
    if (!message || message.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
        if (!window) return;

        UIView *existing = [window viewWithTag:987654];
        if (existing) [existing removeFromSuperview];

        UIVisualEffectView *toast = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        toast.tag = 987654;
        toast.layer.cornerRadius = 18.0;
        toast.layer.borderWidth = 1.2;
        toast.layer.borderColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.75].CGColor;
        toast.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.4].CGColor;
        toast.layer.shadowRadius = 8.0;
        toast.layer.shadowOpacity = 0.8;
        toast.layer.shadowOffset = CGSizeMake(0, 2);
        toast.clipsToBounds = YES;
        toast.alpha = 0.0;

        UILabel *lbl = [[UILabel alloc] init];
        lbl.text = message;
        lbl.textColor = [UIColor whiteColor];
        lbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.numberOfLines = 1;
        [toast.contentView addSubview:lbl];

        CGSize textSize = [message sizeWithAttributes:@{NSFontAttributeName: lbl.font}];
        CGFloat toastW = MIN(window.bounds.size.width - 32.0, textSize.width + 36.0);
        CGFloat toastH = 36.0;
        CGFloat topY = (window.safeAreaInsets.top > 0) ? (window.safeAreaInsets.top + 6.0) : 34.0;

        toast.frame = CGRectMake((window.bounds.size.width - toastW) / 2.0, topY, toastW, toastH);
        lbl.frame = toast.contentView.bounds;

        [window addSubview:toast];
        [window bringSubviewToFront:toast];

        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.6 options:0 animations:^{
            toast.alpha = 1.0;
            toast.transform = CGAffineTransformMakeScale(1.03, 1.03);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.2 animations:^{
                toast.transform = CGAffineTransformIdentity;
            }];
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                toast.alpha = 0.0;
                toast.transform = CGAffineTransformMakeTranslation(0, -10);
            } completion:^(BOOL finished) {
                [toast removeFromSuperview];
            }];
        });
    });
}

#pragma mark - Unified Text Injection Engine

static UITextView *AMFindActiveTextViewInHierarchy(UIViewController *vc) {
    if (!vc) return nil;
    if ([vc respondsToSelector:@selector(inputTextView)]) {
        id tv = [vc valueForKey:@"inputTextView"];
        if ([tv isKindOfClass:[UITextView class]]) return (UITextView *)tv;
    }
    for (UIView *sub in vc.view.subviews) {
        if ([sub isKindOfClass:[UITextView class]]) {
            return (UITextView *)sub;
        }
    }
    return nil;
}

static BOOL AMInjectTextToActiveInput(NSString *text, UIViewController *targetVC) {
    if (!text || text.length == 0) return NO;

    UITextView *tv = AMFindActiveTextViewInHierarchy(targetVC);

    if (!tv) {
        UIWindow *window = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
        for (UIView *sub in window.subviews) {
            if ([sub isFirstResponder] && [sub isKindOfClass:[UITextView class]]) {
                tv = (UITextView *)sub;
                break;
            }
        }
    }

    if (tv) {
        tv.text = text;
        if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
            [tv.delegate textViewDidChange:tv];
        }
        if ([tv.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
            [tv.delegate textView:tv shouldChangeTextInRange:NSMakeRange(0, tv.text.length) replacementText:text];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];

        if (targetVC) {
            @try {
                [targetVC setValue:text forKey:@"appearText"];
            } @catch (NSException *e) {}
            @try {
                if ([targetVC respondsToSelector:@selector(textDidChange:)]) {
                    [targetVC performSelector:@selector(textDidChange:) withObject:tv];
                }
            } @catch (NSException *e) {}
        }

        AudioServicesPlaySystemSound(1519);
        return YES;
    }
    return NO;
}

#pragma mark - Batch Project Timeline Text Injector Engine

static NSInteger AMBatchInjectAllProjectTextLayers(UIViewController *parentVC) {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count == 0) return 0;

    __block NSInteger injectedCount = 0;
    __block NSUInteger lineIndex = 0;

    UIWindow *window = parentVC.view.window ?: [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;

    NSMutableArray *viewsToScan = [NSMutableArray array];
    if (parentVC.view) [viewsToScan addObject:parentVC.view];
    if (window && ![viewsToScan containsObject:window]) [viewsToScan addObject:window];

    NSMutableArray *foundCells = [NSMutableArray array];

    while (viewsToScan.count > 0) {
        UIView *v = viewsToScan.firstObject;
        [viewsToScan removeObjectAtIndex:0];

        NSString *clsName = NSStringFromClass([v class]);
        if ([clsName containsString:@"TimelineCell"]) {
            [foundCells addObject:v];
        }

        for (UIView *child in v.subviews) {
            [viewsToScan addObject:child];
        }
    }

    for (UIView *cell in foundCells) {
        if (lineIndex >= mgr.lyricsLines.count) break;
        NSString *line = mgr.lyricsLines[lineIndex];

        BOOL cellUpdated = NO;

        @try {
            [cell setValue:line forKey:@"labelText"];
            cellUpdated = YES;
        } @catch (NSException *e) {}

        @try {
            if ([cell respondsToSelector:@selector(itemLabel)]) {
                id lbl = [cell valueForKey:@"itemLabel"];
                if ([lbl isKindOfClass:[UILabel class]]) {
                    [(UILabel *)lbl setText:line];
                    cellUpdated = YES;
                }
            }
        } @catch (NSException *e) {}

        if (cellUpdated) {
            injectedCount++;
            lineIndex++;
        }
    }

    UITextView *tv = AMFindActiveTextViewInHierarchy(parentVC);
    if (!tv && window) {
        for (UIView *sub in window.subviews) {
            if ([sub isFirstResponder] && [sub isKindOfClass:[UITextView class]]) {
                tv = (UITextView *)sub;
                break;
            }
        }
    }

    if (tv) {
        NSString *allText = [mgr allLyricsFullText];
        if (allText) {
            AMInjectTextToActiveInput(allText, parentVC);
            if (injectedCount == 0) injectedCount = 1;
        }
    }

    if (injectedCount > 0) {
        AudioServicesPlaySystemSound(1519);
    }

    return injectedCount;
}

#pragma mark - Modern Liquid Glass Batch Lyrics Modal (Studio Edition)

@interface AMBatchLyricsViewController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UIVisualEffectView *blurBackgroundView;
@property (nonatomic, strong) UIView *containerCard;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *statusBadgeLabel;
@property (nonatomic, strong) UIView *switchContainerView;
@property (nonatomic, strong) UISwitch *autoAdvanceSwitch;
@property (nonatomic, strong) UILabel *autoAdvanceLabel;
@property (nonatomic, strong) UIButton *pasteBtn;
@property (nonatomic, strong) UIButton *cleanLrcBtn;
@property (nonatomic, strong) UIButton *demoBtn;
@property (nonatomic, strong) UIButton *clearBtn;
@property (nonatomic, strong) UIButton *batchApplyAllBtn;
@property (nonatomic, strong) UIButton *batchApplyLayersBtn;
@property (nonatomic, strong) UIButton *saveQueueBtn;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, weak) UIViewController *parentTargetVC;
@property (nonatomic, copy) void (^onLyricsLoaded)(void);
@end

@implementation AMBatchLyricsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:0.85];

    // Background blur
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurBackgroundView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.blurBackgroundView.frame = self.view.bounds;
    self.blurBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.blurBackgroundView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];

    [self setupHeader];
    [self setupToolbar];
    [self setupEditor];
    [self setupActionButtons];

    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count > 0) {
        self.textView.text = [mgr.lyricsLines componentsJoinedByString:@"\n"];
        [self updateStatusLabel];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupHeader {
    CGFloat w = self.view.bounds.size.width;

    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, 170, 20)];
    badge.text = @"⚡ PRO AUTO TEXT & LYRICS";
    badge.textColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0];
    badge.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    badge.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:badge];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 36, w - 80, 26)];
    titleLabel.text = @"🎵 Studio Lời & Nhập Văn Bản";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:titleLabel];

    // Close Button top-right
    self.closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeBtn.frame = CGRectMake(w - 48, 20, 32, 32);
    [self.closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
    self.closeBtn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.8];
    self.closeBtn.layer.cornerRadius = 16.0;
    self.closeBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [self.closeBtn addTarget:self action:@selector(dismissModal) forControlEvents:UIControlEventTouchUpInside];
    self.closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:self.closeBtn];
}

- (void)setupToolbar {
    CGFloat y = 68;
    CGFloat h = 32;

    // 1. Paste Button
    self.pasteBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.pasteBtn.frame = CGRectMake(16, y, 76, h);
    [self.pasteBtn setTitle:@"📋 Dán" forState:UIControlStateNormal];
    [self.pasteBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pasteBtn.backgroundColor = [UIColor colorWithWhite:0.20 alpha:0.85];
    self.pasteBtn.layer.cornerRadius = 10.0;
    self.pasteBtn.layer.borderWidth = 0.8;
    self.pasteBtn.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.5].CGColor;
    self.pasteBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.pasteBtn addTarget:self action:@selector(pasteFromClipboard) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.pasteBtn];

    // 2. Clean LRC Button
    self.cleanLrcBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.cleanLrcBtn.frame = CGRectMake(98, y, 92, h);
    [self.cleanLrcBtn setTitle:@"🧹 Lọc LRC" forState:UIControlStateNormal];
    [self.cleanLrcBtn setTitleColor:[UIColor colorWithRed:0.30 green:0.85 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    self.cleanLrcBtn.backgroundColor = [UIColor colorWithRed:0.10 green:0.20 blue:0.30 alpha:0.8];
    self.cleanLrcBtn.layer.cornerRadius = 10.0;
    self.cleanLrcBtn.layer.borderWidth = 0.8;
    self.cleanLrcBtn.layer.borderColor = [UIColor colorWithRed:0.20 green:0.60 blue:0.90 alpha:0.5].CGColor;
    self.cleanLrcBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.cleanLrcBtn addTarget:self action:@selector(cleanLrcTimestamps) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cleanLrcBtn];

    // 3. Demo Button
    self.demoBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.demoBtn.frame = CGRectMake(196, y, 74, h);
    [self.demoBtn setTitle:@"✨ Mẫu" forState:UIControlStateNormal];
    [self.demoBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:1.0] forState:UIControlStateNormal];
    self.demoBtn.backgroundColor = [UIColor colorWithWhite:0.20 alpha:0.85];
    self.demoBtn.layer.cornerRadius = 10.0;
    self.demoBtn.layer.borderWidth = 0.8;
    self.demoBtn.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.5].CGColor;
    self.demoBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.demoBtn addTarget:self action:@selector(insertDemoLyrics) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.demoBtn];

    // 4. Clear Button
    self.clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearBtn.frame = CGRectMake(self.view.bounds.size.width - 86, y, 70, h);
    [self.clearBtn setTitle:@"🗑️ Xóa" forState:UIControlStateNormal];
    [self.clearBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.45 blue:0.45 alpha:1.0] forState:UIControlStateNormal];
    self.clearBtn.backgroundColor = [UIColor colorWithRed:0.35 green:0.12 blue:0.12 alpha:0.75];
    self.clearBtn.layer.cornerRadius = 10.0;
    self.clearBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.clearBtn addTarget:self action:@selector(clearQueue) forControlEvents:UIControlEventTouchUpInside];
    self.clearBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:self.clearBtn];
}

- (void)setupEditor {
    CGFloat yPos = 108;
    CGFloat bottomMargin = 164;
    CGFloat h = self.view.bounds.size.height - yPos - bottomMargin;
    if (h < 110) h = 110;

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(16, yPos, self.view.bounds.size.width - 32, h)];
    self.textView.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.9];
    self.textView.textColor = [UIColor whiteColor];
    self.textView.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium];
    self.textView.layer.cornerRadius = 14.0;
    self.textView.layer.borderWidth = 1.2;
    self.textView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.55].CGColor;
    self.textView.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.3].CGColor;
    self.textView.layer.shadowRadius = 8.0;
    self.textView.layer.shadowOpacity = 0.5;
    self.textView.layer.shadowOffset = CGSizeMake(0, 3);
    self.textView.textContainerInset = UIEdgeInsetsMake(10, 12, 10, 12);
    self.textView.delegate = self;
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.textView];

    self.statusBadgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, yPos + h + 4, self.view.bounds.size.width - 40, 20)];
    self.statusBadgeLabel.text = @"📊 Hàng đợi: 0 câu hát sẵn sàng";
    self.statusBadgeLabel.textColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0];
    self.statusBadgeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    self.statusBadgeLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.statusBadgeLabel];
}

- (void)setupActionButtons {
    CGFloat w = self.view.bounds.size.width;
    CGFloat bottomY = self.view.bounds.size.height - 134;

    // Switch row: Auto-Advance Toggle
    UIView *switchRow = [[UIView alloc] initWithFrame:CGRectMake(16, bottomY, w - 32, 32)];
    switchRow.backgroundColor = [UIColor colorWithRed:0.10 green:0.12 blue:0.16 alpha:0.8];
    switchRow.layer.cornerRadius = 8.0;
    switchRow.layer.borderWidth = 0.8;
    switchRow.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
    switchRow.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:switchRow];
    self.switchContainerView = switchRow;

    UILabel *swLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, w - 32 - 70, 20)];
    swLabel.text = @"⚡ Tự động điền câu kế tiếp khi chạm text layer";
    swLabel.textColor = [UIColor whiteColor];
    swLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
    [switchRow addSubview:swLabel];
    self.autoAdvanceLabel = swLabel;

    UISwitch *advSw = [[UISwitch alloc] initWithFrame:CGRectMake(w - 32 - 58, 1, 51, 31)];
    advSw.onTintColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0];
    advSw.on = AMIsAutoAdvanceLyricsEnabled();
    advSw.transform = CGAffineTransformMakeScale(0.85, 0.85);
    [advSw addTarget:self action:@selector(toggleAutoAdvance:) forControlEvents:UIControlEventValueChanged];
    [switchRow addSubview:advSw];
    self.autoAdvanceSwitch = advSw;

    // Row 1: Super Action: 1-Chạm Nhập Toàn Bộ Vào Text Đang Chọn
    self.batchApplyAllBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.batchApplyAllBtn.frame = CGRectMake(16, bottomY + 38, w - 32, 42);
    [self.batchApplyAllBtn setTitle:@"🚀 1-Chạm Nhập Toàn Bộ Vào Text Đang Chọn" forState:UIControlStateNormal];
    [self.batchApplyAllBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.batchApplyAllBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0];
    self.batchApplyAllBtn.layer.cornerRadius = 13.0;
    self.batchApplyAllBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightHeavy];
    self.batchApplyAllBtn.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.6].CGColor;
    self.batchApplyAllBtn.layer.shadowRadius = 6.0;
    self.batchApplyAllBtn.layer.shadowOpacity = 0.6;
    self.batchApplyAllBtn.layer.shadowOffset = CGSizeMake(0, 2);
    [self.batchApplyAllBtn addTarget:self action:@selector(batchApplyAllToActiveLayer) forControlEvents:UIControlEventTouchUpInside];
    self.batchApplyAllBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.batchApplyAllBtn];

    // Row 2: Two dual actions
    CGFloat halfW = (w - 40) / 2.0;
    self.batchApplyLayersBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.batchApplyLayersBtn.frame = CGRectMake(16, bottomY + 86, halfW, 38);
    [self.batchApplyLayersBtn setTitle:@"⚡ Phân Bổ Layers" forState:UIControlStateNormal];
    [self.batchApplyLayersBtn setTitleColor:[UIColor colorWithRed:0.25 green:0.85 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    self.batchApplyLayersBtn.backgroundColor = [UIColor colorWithRed:0.10 green:0.18 blue:0.28 alpha:0.95];
    self.batchApplyLayersBtn.layer.cornerRadius = 12.0;
    self.batchApplyLayersBtn.layer.borderWidth = 1.0;
    self.batchApplyLayersBtn.layer.borderColor = [UIColor colorWithRed:0.20 green:0.60 blue:0.90 alpha:0.5].CGColor;
    self.batchApplyLayersBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [self.batchApplyLayersBtn addTarget:self action:@selector(batchApplyToAllLayersAction) forControlEvents:UIControlEventTouchUpInside];
    self.batchApplyLayersBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.batchApplyLayersBtn];

    self.saveQueueBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.saveQueueBtn.frame = CGRectMake(16 + halfW + 8, bottomY + 86, halfW, 38);
    [self.saveQueueBtn setTitle:@"💾 Lưu Từng Câu" forState:UIControlStateNormal];
    [self.saveQueueBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.saveQueueBtn.backgroundColor = [UIColor colorWithRed:0.18 green:0.22 blue:0.30 alpha:0.95];
    self.saveQueueBtn.layer.cornerRadius = 12.0;
    self.saveQueueBtn.layer.borderWidth = 1.0;
    self.saveQueueBtn.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.5].CGColor;
    self.saveQueueBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [self.saveQueueBtn addTarget:self action:@selector(applyLyricsToQueue) forControlEvents:UIControlEventTouchUpInside];
    self.saveQueueBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:self.saveQueueBtn];
}

- (void)toggleAutoAdvance:(UISwitch *)sw {
    AMSetAutoAdvanceLyricsEnabled(sw.on);
    AMShowToast(sw.on ? @"✅ Đã bật Tự động điền câu kế tiếp" : @"⏸️ Đã tắt Tự động điền");
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)clearQueue {
    self.textView.text = @"";
    [self updateStatusLabel];
    [[AMLyricsQueueManager sharedManager] clearLyrics];
    if (self.onLyricsLoaded) {
        self.onLyricsLoaded();
    }
    AMShowToast(@"🗑️ Đã xóa sạch hàng đợi lời bài hát");
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat keyboardHeight = keyboardFrame.size.height;
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    [UIView animateWithDuration:duration animations:^{
        CGRect frame = self.textView.frame;
        frame.size.height = self.view.bounds.size.height - 108 - keyboardHeight - 14;
        if (frame.size.height < 70) frame.size.height = 70;
        self.textView.frame = frame;
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    [UIView animateWithDuration:duration animations:^{
        CGRect frame = self.textView.frame;
        frame.size.height = self.view.bounds.size.height - 108 - 164;
        self.textView.frame = frame;
    }];
}

- (void)textViewDidChange:(UITextView *)textView {
    [self updateStatusLabel];
}

- (void)updateStatusLabel {
    NSArray *lines = [self extractValidLines:self.textView.text];
    self.statusBadgeLabel.text = [NSString stringWithFormat:@"📊 Hàng đợi: %lu câu hát đã sẵn sàng", (unsigned long)lines.count];
}

- (NSArray<NSString *> *)extractValidLines:(NSString *)rawText {
    if (!rawText || rawText.length == 0) return @[];
    NSArray *all = [rawText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *valid = [NSMutableArray array];

    static NSRegularExpression *lrcRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lrcRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\[\\d{1,2}:\\d{2}(?:[\\.:]\\d{1,3})?\\]\\s*" options:0 error:nil];
    });

    for (NSString *s in all) {
        NSString *trimmed = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            if (lrcRegex) {
                trimmed = [lrcRegex stringByReplacingMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length) withTemplate:@""];
                trimmed = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            }
            if (trimmed.length > 0) {
                [valid addObject:trimmed];
            }
        }
    }
    return valid;
}

- (void)pasteFromClipboard {
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    if (pb.string && pb.string.length > 0) {
        self.textView.text = pb.string;
        [self cleanLrcTimestamps];
        [self updateStatusLabel];
        AMShowToast(@"📋 Đã dán và tự động chuẩn hóa!");
    } else {
        AMShowToast(@"⚠️ Bộ nhớ tạm đang trống!");
    }
}

- (void)cleanLrcTimestamps {
    NSArray<NSString *> *lines = [self extractValidLines:self.textView.text];
    if (lines.count > 0) {
        self.textView.text = [lines componentsJoinedByString:@"\n"];
        [self updateStatusLabel];
        AMShowToast(@"🧹 Đã lọc sạch toàn bộ timestamp LRC!");
    }
}

- (void)insertDemoLyrics {
    self.textView.text = @"Em ơi có biết ngoài kia gió đang về\nNghe từng hạt mưa rơi bên hiên não nề\nTình yêu thuở nào giờ trôi theo mây gió\nChỉ còn nỗi nhớ đong đầy nơi góc phố xưa";
    [self updateStatusLabel];
    AMShowToast(@"✨ Đã nạp lời bài hát demo!");
}

- (void)dismissModal {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

// SUPER FEATURE 1: 1-Chạm Nhập Toàn Bộ Text Vào Layer Đang Chọn
- (void)batchApplyAllToActiveLayer {
    [self.view endEditing:YES];
    NSArray<NSString *> *lines = [self extractValidLines:self.textView.text];
    if (lines.count == 0) {
        AMShowToast(@"⚠️ Vui lòng nhập hoặc dán lời bài hát!");
        return;
    }

    [[AMLyricsQueueManager sharedManager] loadLyrics:lines];
    if (self.onLyricsLoaded) {
        self.onLyricsLoaded();
    }

    NSString *allText = [lines componentsJoinedByString:@"\n"];
    BOOL injected = AMInjectTextToActiveInput(allText, self.parentTargetVC);

    [self dismissViewControllerAnimated:YES completion:^{
        if (injected) {
            AMShowToast([NSString stringWithFormat:@"🚀 Đã 1-chạm nhập toàn bộ %lu câu!", (unsigned long)lines.count]);
        } else {
            AMShowToast(@"💾 Đã lưu hàng đợi! Hãy mở một Text Layer để chèn.");
        }
    }];
}

// SUPER FEATURE 2: 1-Chạm Phân Bổ Toàn Bộ Layers Trên Timeline Dự Án
- (void)batchApplyToAllLayersAction {
    [self.view endEditing:YES];
    NSArray<NSString *> *lines = [self extractValidLines:self.textView.text];
    if (lines.count == 0) {
        AMShowToast(@"⚠️ Vui lòng nhập lời trước khi phân bổ!");
        return;
    }

    [[AMLyricsQueueManager sharedManager] loadLyrics:lines];
    if (self.onLyricsLoaded) {
        self.onLyricsLoaded();
    }

    NSInteger count = AMBatchInjectAllProjectTextLayers(self.parentTargetVC);
    [self dismissViewControllerAnimated:YES completion:^{
        if (count > 0) {
            AMShowToast([NSString stringWithFormat:@"✨ Đã 1-chạm điền %ld layer trong dự án!", (long)count]);
        } else {
            AMShowToast(@"💾 Đã lưu hàng đợi! Chạm vào layer text để điền tự động.");
        }
    }];
}

- (void)applyLyricsToQueue {
    [self.view endEditing:YES];
    NSArray<NSString *> *lines = [self extractValidLines:self.textView.text];
    if (lines.count == 0) {
        AMShowToast(@"⚠️ Vui lòng nhập lời trước khi lưu!");
        return;
    }

    [[AMLyricsQueueManager sharedManager] loadLyrics:lines];
    if (self.onLyricsLoaded) {
        self.onLyricsLoaded();
    }

    [self dismissViewControllerAnimated:YES completion:^{
        AMShowToast([NSString stringWithFormat:@"✨ Đã nạp %lu câu vào hàng đợi!", (unsigned long)lines.count]);
    }];
}

@end

#pragma mark - Home Settings Dashboard Modal (Modern Liquid Glass)

@interface AMHomeSettingsViewController : UIViewController
@property (nonatomic, strong) UILabel *lyricsStatusLabel;
@end

@implementation AMHomeSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.06 blue:0.09 alpha:0.98];

    CGFloat w = self.view.bounds.size.width;

    // Header
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, w - 40, 28)];
    titleLabel.text = @"⚙️ Cài Đặt Alight Motion Pro";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    [self.view addSubview:titleLabel];

    // Card 1: Batch Lyrics Manager (Nạp & Xóa Hàng Đợi)
    UIView *card1 = [[UIView alloc] initWithFrame:CGRectMake(16, 60, w - 32, 100)];
    card1.backgroundColor = [UIColor colorWithRed:0.10 green:0.12 blue:0.16 alpha:0.95];
    card1.layer.cornerRadius = 16.0;
    card1.layer.borderWidth = 1.0;
    card1.layer.borderColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.4].CGColor;
    card1.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:card1];

    UILabel *l1 = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, card1.bounds.size.width - 32, 22)];
    l1.text = @"📝 Studio Auto Lyrics & Text Queue";
    l1.textColor = [UIColor whiteColor];
    l1.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [card1 addSubview:l1];

    self.lyricsStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, card1.bounds.size.width - 190, 52)];
    self.lyricsStatusLabel.textColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0];
    self.lyricsStatusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.lyricsStatusLabel.numberOfLines = 2;
    [card1 addSubview:self.lyricsStatusLabel];
    [self refreshLyricsStatus];

    // Nạp Mới Button
    UIButton *loadBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    loadBtn.frame = CGRectMake(card1.bounds.size.width - 180, 44, 88, 38);
    [loadBtn setTitle:@"📝 Mở Studio" forState:UIControlStateNormal];
    [loadBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    loadBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0];
    loadBtn.layer.cornerRadius = 12.0;
    loadBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightHeavy];
    loadBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [loadBtn addTarget:self action:@selector(openLyricsModal) forControlEvents:UIControlEventTouchUpInside];
    [card1 addSubview:loadBtn];

    // Xóa Hàng Đợi Button
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(card1.bounds.size.width - 84, 44, 72, 38);
    [clearBtn setTitle:@"🗑️ Xóa" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.45 blue:0.45 alpha:1.0] forState:UIControlStateNormal];
    clearBtn.backgroundColor = [UIColor colorWithRed:0.35 green:0.12 blue:0.12 alpha:0.8];
    clearBtn.layer.cornerRadius = 12.0;
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    clearBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [clearBtn addTarget:self action:@selector(clearQueueAction) forControlEvents:UIControlEventTouchUpInside];
    [card1 addSubview:clearBtn];

    // Card 2: Auto Save to Camera Roll
    UIView *card2 = [[UIView alloc] initWithFrame:CGRectMake(16, 172, w - 32, 72)];
    card2.backgroundColor = [UIColor colorWithRed:0.10 green:0.12 blue:0.16 alpha:0.95];
    card2.layer.cornerRadius = 16.0;
    card2.layer.borderWidth = 1.0;
    card2.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.5].CGColor;
    card2.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:card2];

    UILabel *l2 = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, card2.bounds.size.width - 100, 20)];
    l2.text = @"🎬 Tự Động Lưu Vào Cuộn Camera";
    l2.textColor = [UIColor whiteColor];
    l2.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [card2 addSubview:l2];

    UILabel *l2Sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 38, card2.bounds.size.width - 100, 20)];
    l2Sub.text = @"Tự động lưu video sau khi render xong";
    l2Sub.textColor = [UIColor lightGrayColor];
    l2Sub.font = [UIFont systemFontOfSize:11];
    [card2 addSubview:l2Sub];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(card2.bounds.size.width - 66, 20, 51, 31)];
    sw.onTintColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0];
    sw.on = AMIsAutoSaveEnabled();
    sw.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [sw addTarget:self action:@selector(toggleAutoSave:) forControlEvents:UIControlEventValueChanged];
    [card2 addSubview:sw];

    // Card 3: Pro & Effects Status
    UIView *card3 = [[UIView alloc] initWithFrame:CGRectMake(16, 256, w - 32, 86)];
    card3.backgroundColor = [UIColor colorWithRed:0.10 green:0.12 blue:0.16 alpha:0.95];
    card3.layer.cornerRadius = 16.0;
    card3.layer.borderWidth = 1.0;
    card3.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.5].CGColor;
    card3.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:card3];

    UILabel *l3 = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, card3.bounds.size.width - 32, 22)];
    l3.text = @"👑 Trạng Thái Hệ Thống";
    l3.textColor = [UIColor whiteColor];
    l3.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [card3 addSubview:l3];

    UILabel *l3Sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, card3.bounds.size.width - 32, 42)];
    l3Sub.text = @"🟢 Full Premium Pro v6.2.56 Unlocked (4K, Không Logo)\n🟢 1.182 Hiệu ứng & Presets từ bản V2 sẵn sàng\n🟢 Đã triệt tiêu 100% Popup & Quảng cáo Blatant";
    l3Sub.textColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0];
    l3Sub.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
    l3Sub.numberOfLines = 3;
    [card3 addSubview:l3Sub];

    // Close Button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(16, self.view.bounds.size.height - 58, w - 32, 46);
    [closeBtn setTitle:@"Đóng Cài Đặt" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor colorWithWhite:0.22 alpha:0.9];
    closeBtn.layer.cornerRadius = 14.0;
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    closeBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [closeBtn addTarget:self action:@selector(dismissSelf) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeBtn];
}

- (void)refreshLyricsStatus {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count == 0) {
        self.lyricsStatusLabel.text = @"Trạng thái: Trống (chưa có câu nào).";
        self.lyricsStatusLabel.textColor = [UIColor lightGrayColor];
    } else {
        self.lyricsStatusLabel.text = [NSString stringWithFormat:@"Đang có %lu câu trong hàng đợi.\n(Hiện tại: #%lu/%lu)", (unsigned long)mgr.lyricsLines.count, (unsigned long)(mgr.currentIndex + 1), (unsigned long)mgr.lyricsLines.count];
        self.lyricsStatusLabel.textColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0];
    }
}

- (void)clearQueueAction {
    [[AMLyricsQueueManager sharedManager] clearLyrics];
    [self refreshLyricsStatus];
    AMShowToast(@"🗑️ Đã xóa sạch hàng đợi!");
}

- (void)toggleAutoSave:(UISwitch *)sw {
    AMSetAutoSaveEnabled(sw.on);
    AMShowToast(sw.on ? @"✅ Đã bật Tự Động Lưu Video" : @"⏸️ Đã tắt Tự Động Lưu Video");
}

- (void)openLyricsModal {
    AMBatchLyricsViewController *modal = [[AMBatchLyricsViewController alloc] init];
    modal.modalPresentationStyle = UIModalPresentationFormSheet;
    __weak typeof(self) weakSelf = self;
    modal.onLyricsLoaded = ^{
        [weakSelf refreshLyricsStatus];
    };
    [self presentViewController:modal animated:YES completion:nil];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Next-Gen iOS 18 Liquid Glass Lyrics Bar (With 1-Tap Batch Text Inserter)

@interface AMMinimalLyricsBar : UIView
@property (nonatomic, weak) UIViewController *targetVC;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *capsule;
@property (nonatomic, strong) UIButton *prevBtn;
@property (nonatomic, strong) UIButton *nextBtn;
@property (nonatomic, strong) UIButton *versePillBtn;
@property (nonatomic, strong) UIButton *batchAllBtn;
@property (nonatomic, strong) UIButton *menuBtn;
@property (nonatomic, strong) UIButton *closeBtn;
+ (instancetype)barForViewController:(UIViewController *)vc;
- (void)refreshDisplay;
@end

@implementation AMMinimalLyricsBar

+ (instancetype)barForViewController:(UIViewController *)vc {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    AMMinimalLyricsBar *bar = [[self alloc] initWithFrame:CGRectMake(0, 0, screenW, 44.0)];
    bar.targetVC = vc;
    bar.backgroundColor = [UIColor clearColor];

    // Capsule container with Liquid Glass Blur & Neon Border
    UIView *capsule = [[UIView alloc] initWithFrame:CGRectMake(8.0, 3.0, screenW - 16.0, 38.0)];
    capsule.layer.cornerRadius = 19.0;
    capsule.layer.borderWidth = 1.2;
    capsule.layer.borderColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.55].CGColor;
    capsule.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.4].CGColor;
    capsule.layer.shadowRadius = 8.0;
    capsule.layer.shadowOpacity = 0.6;
    capsule.layer.shadowOffset = CGSizeMake(0, 2);
    capsule.clipsToBounds = YES;
    [bar addSubview:capsule];
    bar.capsule = capsule;

    // Blur Effect
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = capsule.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [capsule addSubview:blurView];
    bar.blurView = blurView;

    // Subtle Tint View inside blur
    UIView *tintView = [[UIView alloc] initWithFrame:blurView.contentView.bounds];
    tintView.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.12 alpha:0.75];
    tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [blurView.contentView addSubview:tintView];

    // 1. Prev Button [‹]
    UIButton *prev = [UIButton buttonWithType:UIButtonTypeSystem];
    [prev setTitle:@"‹" forState:UIControlStateNormal];
    [prev setTitleColor:[UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0] forState:UIControlStateNormal];
    prev.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    prev.backgroundColor = [UIColor colorWithWhite:0.20 alpha:0.65];
    prev.layer.cornerRadius = 15.0;
    [prev addTarget:bar action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];
    [blurView.contentView addSubview:prev];
    bar.prevBtn = prev;

    // 2. Next Button [›]
    UIButton *next = [UIButton buttonWithType:UIButtonTypeSystem];
    [next setTitle:@"›" forState:UIControlStateNormal];
    [next setTitleColor:[UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0] forState:UIControlStateNormal];
    next.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    next.backgroundColor = [UIColor colorWithWhite:0.20 alpha:0.65];
    next.layer.cornerRadius = 15.0;
    [next addTarget:bar action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [blurView.contentView addSubview:next];
    bar.nextBtn = next;

    // 3. Central Verse Pill Button [⚡ #1/N: "Lời câu..."]
    UIButton *verse = [UIButton buttonWithType:UIButtonTypeSystem];
    verse.backgroundColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.20];
    verse.layer.cornerRadius = 15.0;
    verse.layer.borderWidth = 1.0;
    verse.layer.borderColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.6].CGColor;
    [verse setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    verse.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    verse.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    verse.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    [verse addTarget:bar action:@selector(verseTapped) forControlEvents:UIControlEventTouchUpInside];
    [blurView.contentView addSubview:verse];
    bar.versePillBtn = verse;

    // 4. Batch All Inserter Button [🚀 Hết] (1-CHẠM NHẬP TOÀN BỘ TEXT)
    UIButton *batchAll = [UIButton buttonWithType:UIButtonTypeSystem];
    [batchAll setTitle:@"🚀 Hết" forState:UIControlStateNormal];
    [batchAll setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    batchAll.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightHeavy];
    batchAll.backgroundColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0];
    batchAll.layer.cornerRadius = 15.0;
    batchAll.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.5].CGColor;
    batchAll.layer.shadowRadius = 4.0;
    batchAll.layer.shadowOpacity = 0.6;
    [batchAll addTarget:bar action:@selector(batchAllTapped) forControlEvents:UIControlEventTouchUpInside];
    [blurView.contentView addSubview:batchAll];
    bar.batchAllBtn = batchAll;

    // 5. Menu Button [📋] (Studio & Quản Lý)
    UIButton *menu = [UIButton buttonWithType:UIButtonTypeSystem];
    [menu setTitle:@"📋" forState:UIControlStateNormal];
    menu.titleLabel.font = [UIFont systemFontOfSize:14];
    menu.backgroundColor = [UIColor colorWithWhite:0.20 alpha:0.65];
    menu.layer.cornerRadius = 15.0;
    [menu addTarget:bar action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    [blurView.contentView addSubview:menu];
    bar.menuBtn = menu;

    // 6. Close Button [✕]
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithWhite:0.75 alpha:1.0] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    close.backgroundColor = [UIColor colorWithWhite:0.20 alpha:0.65];
    close.layer.cornerRadius = 15.0;
    [close addTarget:bar action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [blurView.contentView addSubview:close];
    bar.closeBtn = close;

    [bar setNeedsLayout];
    [bar refreshDisplay];
    return bar;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 44.0);
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, 44.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets insets = self.safeAreaInsets;
    CGFloat w = self.bounds.size.width;
    CGFloat padLeft = MAX(8.0, insets.left);
    CGFloat padRight = MAX(8.0, insets.right);

    CGFloat capW = w - padLeft - padRight;
    if (capW < 100.0) capW = [UIScreen mainScreen].bounds.size.width - 16.0;

    self.capsule.frame = CGRectMake(padLeft, 3.0, capW, 38.0);
    self.blurView.frame = self.capsule.bounds;

    CGFloat btnH = 30.0;
    CGFloat btnY = 4.0;

    // Left controls: Prev (30), Next (30)
    self.prevBtn.frame = CGRectMake(4.0, btnY, 30.0, btnH);
    self.nextBtn.frame = CGRectMake(38.0, btnY, 30.0, btnH);

    // Right controls: Close (30), Menu (30), BatchAll (54)
    CGFloat rightX = capW - 34.0;
    self.closeBtn.frame = CGRectMake(rightX, btnY, 30.0, btnH);
    rightX -= 34.0;
    self.menuBtn.frame = CGRectMake(rightX, btnY, 30.0, btnH);
    rightX -= 58.0;
    self.batchAllBtn.frame = CGRectMake(rightX, btnY, 54.0, btnH);

    // Center pill occupies remaining width
    CGFloat centerStartX = 72.0;
    CGFloat centerW = rightX - centerStartX - 4.0;
    if (centerW < 60.0) centerW = 60.0;
    self.versePillBtn.frame = CGRectMake(centerStartX, btnY, centerW, btnH);
}

- (void)refreshDisplay {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];

    self.prevBtn.hidden = NO;
    self.nextBtn.hidden = NO;
    self.versePillBtn.hidden = NO;
    self.batchAllBtn.hidden = NO;
    self.menuBtn.hidden = NO;
    self.closeBtn.hidden = NO;

    if (mgr.lyricsLines.count == 0) {
        self.prevBtn.enabled = NO;
        self.prevBtn.alpha = 0.35;
        self.nextBtn.enabled = NO;
        self.nextBtn.alpha = 0.35;
        self.batchAllBtn.enabled = NO;
        self.batchAllBtn.alpha = 0.35;
        [self.versePillBtn setTitle:@"📋 Chạm để Nạp Lời Bài Hát" forState:UIControlStateNormal];
        [self.versePillBtn setTitleColor:[UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0] forState:UIControlStateNormal];
    } else {
        self.prevBtn.enabled = (mgr.currentIndex > 0);
        self.prevBtn.alpha = (mgr.currentIndex > 0) ? 1.0 : 0.4;

        self.nextBtn.enabled = (mgr.currentIndex + 1 < mgr.lyricsLines.count);
        self.nextBtn.alpha = (mgr.currentIndex + 1 < mgr.lyricsLines.count) ? 1.0 : 0.4;

        self.batchAllBtn.enabled = YES;
        self.batchAllBtn.alpha = 1.0;

        NSUInteger cur = mgr.currentIndex + 1;
        NSString *line = [mgr currentLineText] ?: @"";
        NSString *title = [NSString stringWithFormat:@"⚡ %lu/%lu: \"%@\"", (unsigned long)cur, (unsigned long)mgr.lyricsLines.count, line];
        [self.versePillBtn setTitle:title forState:UIControlStateNormal];
        [self.versePillBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
}

// 1-Tap Verse Pill: Chèn 1 câu và tự động chuyển sang câu tiếp theo
- (void)verseTapped {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count == 0) {
        [self loadTapped];
        return;
    }

    NSString *line = [mgr currentLineText];
    if (!line) return;

    if (AMInjectTextToActiveInput(line, self.targetVC)) {
        [mgr consumeNextLineText];
        [self refreshDisplay];
    }
}

// 1-TAP BATCH ALL INSERTER: Chèn toàn bộ bài hát/toàn bộ các câu vào text layer đang chọn chỉ với 1-chạm!
- (void)batchAllTapped {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count == 0) {
        [self loadTapped];
        return;
    }

    NSString *allText = [mgr allLyricsFullText];
    if (!allText) return;

    if (AMInjectTextToActiveInput(allText, self.targetVC)) {
        AMShowToast([NSString stringWithFormat:@"🚀 Đã 1-chạm nhập toàn bộ %lu câu!", (unsigned long)mgr.lyricsLines.count]);
    }
}

- (void)prevTapped {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.currentIndex > 0) {
        mgr.currentIndex--;
        [mgr saveToDisk];
    }
    [self refreshDisplay];
}

- (void)nextTapped {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.currentIndex + 1 < mgr.lyricsLines.count) {
        mgr.currentIndex++;
        [mgr saveToDisk];
    }
    [self refreshDisplay];
}

- (void)closeTapped {
    [self.targetVC.view endEditing:YES];
}

- (void)menuTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"🎵 Quản Lý Auto Text & Lyrics"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"📝 Mở Studio Lời (Nạp / Sửa)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self loadTapped];
    }]];

    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count > 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"🚀 1-Chạm Nhập Toàn Bộ Vào Text Này" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self batchAllTapped];
        }]];

        [sheet addAction:[UIAlertAction actionWithTitle:@"🔄 Bắt Đầu Lại Từ Câu #1" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [mgr resetToFirstVerse];
            [self refreshDisplay];
            AMShowToast(@"🔄 Đã quay về câu #1");
        }]];

        [sheet addAction:[UIAlertAction actionWithTitle:@"🎯 Chọn Câu Cụ Thể Trong Danh Sách" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self openVersePicker];
        }]];

        [sheet addAction:[UIAlertAction actionWithTitle:@"🗑️ Xóa Sạch Hàng Đợi" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [mgr clearLyrics];
            [self refreshDisplay];
            AMShowToast(@"🗑️ Đã xóa sạch hàng đợi!");
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];

    [self.targetVC presentViewController:sheet animated:YES completion:nil];
}

- (void)openVersePicker {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Chọn Câu Hát Bắt Đầu"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSUInteger i = 0; i < mgr.lyricsLines.count && i < 25; i++) {
        NSString *verseTitle = [NSString stringWithFormat:@"#%lu: \"%@\"", (unsigned long)(i + 1), mgr.lyricsLines[i]];
        [picker addAction:[UIAlertAction actionWithTitle:verseTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [mgr jumpToVerseIndex:i];
            [self refreshDisplay];
        }]];
    }

    [picker addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self.targetVC presentViewController:picker animated:YES completion:nil];
}

- (void)loadTapped {
    AMBatchLyricsViewController *modal = [[AMBatchLyricsViewController alloc] init];
    modal.modalPresentationStyle = UIModalPresentationFormSheet;
    modal.parentTargetVC = self.targetVC;
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

#pragma mark - Project Editor Floating Lyrics HUD (CHỈ HIỆN KHI Ở TRONG DỰ ÁN)

@interface AMProjectLyricsHUD : NSObject
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, weak) UIWindow *parentWindow;
+ (instancetype)sharedHUD;
- (void)installFloatingButtonOnWindow:(UIWindow *)window;
- (void)setFloatingButtonVisible:(BOOL)visible;
@end

@implementation AMProjectLyricsHUD

+ (instancetype)sharedHUD {
    static AMProjectLyricsHUD *hud = nil;
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
    btn.frame = CGRectMake(window.bounds.size.width - 64.0, 72.0, 48.0, 48.0);
    btn.layer.cornerRadius = 24.0;
    btn.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.12 alpha:0.92];
    btn.layer.borderWidth = 1.5;
    btn.layer.borderColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.85].CGColor;
    btn.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:0.6].CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 3);
    btn.layer.shadowRadius = 8.0;
    btn.layer.shadowOpacity = 0.8;

    [btn setTitle:@"🎵" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:22.0];
    [btn addTarget:self action:@selector(floatingButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    self.floatingButton = btn;

    [window addSubview:btn];
    [window bringSubviewToFront:btn];
    btn.hidden = YES;
}

- (void)setFloatingButtonVisible:(BOOL)visible {
    if (self.floatingButton) {
        self.floatingButton.hidden = !visible;
        if (visible) {
            [self.floatingButton.superview bringSubviewToFront:self.floatingButton];
        }
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

    AMBatchLyricsViewController *vc = [[AMBatchLyricsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationFormSheet;
    vc.parentTargetVC = root;
    [root presentViewController:vc animated:YES completion:nil];
}

@end

#pragma mark - Hook TextInputVC & UITextView (Seamless Automatic Accessory Bar Binding & Auto-Advance)

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

        // ⚡ AUTO-ADVANCE SUPER ENGINE:
        if (AMIsAutoAdvanceLyricsEnabled()) {
            AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
            if ([mgr hasNextLine]) {
                NSString *line = [mgr currentLineText];
                if (line && line.length > 0) {
                    AMInjectTextToActiveInput(line, self);
                    [mgr consumeNextLineText];
                    [bar refreshDisplay];
                    AMShowToast([NSString stringWithFormat:@"⚡ Tự động điền: \"%@\"", line]);
                }
            }
        }
    }
}

static BOOL (*orig_UITextView_becomeFirstResponder)(UITextView *, SEL);

static BOOL hook_UITextView_becomeFirstResponder(UITextView *self, SEL _cmd) {
    if (self.inputAccessoryView == nil) {
        UIResponder *responder = self;
        while ((responder = [responder nextResponder])) {
            if ([responder isKindOfClass:[UIViewController class]]) {
                break;
            }
        }
        if (responder) {
            NSString *vcName = NSStringFromClass([responder class]);
            if ([vcName containsString:@"TextInput"] || [vcName containsString:@"Edit"] || [vcName containsString:@"Text"]) {
                AMMinimalLyricsBar *bar = [AMMinimalLyricsBar barForViewController:(UIViewController *)responder];
                self.inputAccessoryView = bar;
            }
        }
    }
    if (orig_UITextView_becomeFirstResponder) {
        return orig_UITextView_becomeFirstResponder(self, _cmd);
    }
    return YES;
}

#pragma mark - 6-Layer Bulletproof Anti-Telegram, Anti-Ads & 10s Vibration Annihilator

static BOOL AMIsForbiddenString(NSString *str) {
    if (!str || str.length == 0) return NO;
    NSString *low = str.lowercaseString;
    return [low containsString:@"telegram"] ||
           [low containsString:@"t.me"] ||
           [low containsString:@"tg://"] ||
           [low containsString:@"blatant"] ||
           [low containsString:@"fastdecrypt"] ||
           [low containsString:@"crack"] ||
           [low containsString:@"unlocked by"] ||
           [low containsString:@"quảng cáo"] ||
           [low containsString:@"countdown"];
}

// 1. Hook C Vibration APIs via Fishhook (Permanently Stop Infinite 10s Countdown Vibration)
static void (*orig_AudioServicesPlaySystemSound)(SystemSoundID inSystemSoundID);
static void hook_AudioServicesPlaySystemSound(SystemSoundID inSystemSoundID) {
    if (inSystemSoundID == 1519) {
        if (orig_AudioServicesPlaySystemSound) {
            orig_AudioServicesPlaySystemSound(inSystemSoundID);
        }
        return;
    }
    // Block all crack infinite countdown vibrations & alert sounds
}

static void (*orig_AudioServicesPlayAlertSound)(SystemSoundID inSystemSoundID);
static void hook_AudioServicesPlayAlertSound(SystemSoundID inSystemSoundID) {
    // Block crack alert chime/vibration
}

static void (*orig_AudioServicesPlaySystemSoundWithCompletion)(SystemSoundID inSystemSoundID, void (^inCompletionBlock)(void));
static void hook_AudioServicesPlaySystemSoundWithCompletion(SystemSoundID inSystemSoundID, void (^inCompletionBlock)(void)) {
    if (inSystemSoundID == 1519) {
        if (orig_AudioServicesPlaySystemSoundWithCompletion) {
            orig_AudioServicesPlaySystemSoundWithCompletion(inSystemSoundID, inCompletionBlock);
        } else if (inCompletionBlock) inCompletionBlock();
        return;
    }
    if (inCompletionBlock) inCompletionBlock();
}

// Hook UIFeedbackGenerator / UIImpactFeedbackGenerator / UINotificationFeedbackGenerator
static void (*orig_UIImpactFeedbackGenerator_impactOccurred)(UIImpactFeedbackGenerator *, SEL);
static void hook_UIImpactFeedbackGenerator_impactOccurred(UIImpactFeedbackGenerator *self, SEL _cmd) {
    // Suppress unwanted crack impact vibrations
}

static void (*orig_UINotificationFeedbackGenerator_notificationOccurred)(UINotificationFeedbackGenerator *, SEL, UINotificationFeedbackType);
static void hook_UINotificationFeedbackGenerator_notificationOccurred(UINotificationFeedbackGenerator *self, SEL _cmd, UINotificationFeedbackType type) {
    // Suppress unwanted crack notification vibrations
}

// 2. Hook UIWindow makeKeyAndVisible & setHidden (NEVER hide keyboard / text system windows!)
static void (*orig_UIWindow_makeKeyAndVisible)(UIWindow *, SEL);

static void hook_UIWindow_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    NSString *clsName = NSStringFromClass([self class]);
    // ALWAYS preserve keyboard and text system windows!
    if ([clsName containsString:@"Keyboard"] || 
        [clsName containsString:@"TextEffects"] || 
        [clsName containsString:@"InputSet"] ||
        [clsName containsString:@"Remote"] ||
        [clsName containsString:@"Interactive"] ||
        [clsName isEqualToString:@"UIWindow"]) {
        if (orig_UIWindow_makeKeyAndVisible) {
            orig_UIWindow_makeKeyAndVisible(self, _cmd);
        }
        return;
    }

    if (self.windowLevel >= UIWindowLevelAlert) {
        UIViewController *root = self.rootViewController;
        NSString *rootName = root ? NSStringFromClass([root class]) : @"";
        if ([rootName containsString:@"5qG"] || [rootName containsString:@"fQG"] || [rootName containsString:@"Blatant"] || [rootName containsString:@"Alert"]) {
            self.hidden = YES;
            self.frame = CGRectZero;
            return;
        }
    }

    if (orig_UIWindow_makeKeyAndVisible) {
        orig_UIWindow_makeKeyAndVisible(self, _cmd);
    }
}

static void (*orig_UIWindow_setHidden)(UIWindow *, SEL, BOOL);

static void hook_UIWindow_setHidden(UIWindow *self, SEL _cmd, BOOL hidden) {
    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName containsString:@"Keyboard"] || 
        [clsName containsString:@"TextEffects"] || 
        [clsName containsString:@"InputSet"] ||
        [clsName containsString:@"Remote"] ||
        [clsName containsString:@"Interactive"] ||
        [clsName isEqualToString:@"UIWindow"]) {
        if (orig_UIWindow_setHidden) {
            orig_UIWindow_setHidden(self, _cmd, hidden);
        }
        return;
    }

    if (!hidden && self.windowLevel >= UIWindowLevelAlert) {
        UIViewController *root = self.rootViewController;
        NSString *rootName = root ? NSStringFromClass([root class]) : @"";
        if ([rootName containsString:@"5qG"] || [rootName containsString:@"fQG"] || [rootName containsString:@"Blatant"]) {
            hidden = YES;
        }
    }
    if (orig_UIWindow_setHidden) {
        orig_UIWindow_setHidden(self, _cmd, hidden);
    }
}

// 3. Hook UIAlertController creation
static UIAlertController *(*orig_UIAlertController_alertControllerWithTitle)(id, SEL, NSString *, NSString *, UIAlertControllerStyle);

static UIAlertController *hook_UIAlertController_alertControllerWithTitle(id self, SEL _cmd, NSString *title, NSString *message, UIAlertControllerStyle preferredStyle) {
    if (AMIsForbiddenString(title) || AMIsForbiddenString(message)) {
        return orig_UIAlertController_alertControllerWithTitle(self, _cmd, @"", @"", UIAlertControllerStyleAlert);
    }
    return orig_UIAlertController_alertControllerWithTitle(self, _cmd, title, message, preferredStyle);
}

// 4. Hook UIViewController presentViewController
static void (*orig_UIViewController_presentViewController)(UIViewController *, SEL, UIViewController *, BOOL, void (^)(void));

static void hook_UIViewController_presentViewController(UIViewController *self, SEL _cmd, UIViewController *vc, BOOL animated, void (^completion)(void)) {
    if (vc) {
        NSString *className = NSStringFromClass([vc class]);

        if ([vc isKindOfClass:[UIAlertController class]]) {
            UIAlertController *alert = (UIAlertController *)vc;
            NSString *title = alert.title ?: @"";
            NSString *message = alert.message ?: @"";
            NSString *combined = [NSString stringWithFormat:@"%@ %@", title, message];

            BOOL isOurAlert = [title containsString:@"Alight Motion Pro"] || [title containsString:@"Thông báo"] || [title containsString:@"Lyrics"] || [title containsString:@"Cài Đặt"] || [title containsString:@"Quản Lý Lời"] || [title containsString:@"Chọn Câu"];

            if (!isOurAlert && AMIsForbiddenString(combined)) {
                if (completion) completion();
                return;
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

// 5. Hook UIApplication openURL (Block opening telegram links externally)
static BOOL (*orig_UIApplication_openURL)(UIApplication *, SEL, NSURL *);

static BOOL hook_UIApplication_openURL(UIApplication *self, SEL _cmd, NSURL *url) {
    if (url && AMIsForbiddenString(url.absoluteString)) {
        return NO;
    }
    if (orig_UIApplication_openURL) {
        return orig_UIApplication_openURL(self, _cmd, url);
    }
    return NO;
}

static void (*orig_UIApplication_openURL_options_completionHandler)(UIApplication *, SEL, NSURL *, NSDictionary *, void (^)(BOOL));

static void hook_UIApplication_openURL_options_completionHandler(UIApplication *self, SEL _cmd, NSURL *url, NSDictionary *options, void (^completion)(BOOL)) {
    if (url && AMIsForbiddenString(url.absoluteString)) {
        if (completion) completion(NO);
        return;
    }
    if (orig_UIApplication_openURL_options_completionHandler) {
        orig_UIApplication_openURL_options_completionHandler(self, _cmd, url, options, completion);
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
        [[AMProjectLyricsHUD sharedHUD] installFloatingButtonOnWindow:window];
    }

    NSString *className = NSStringFromClass([self class]);

    BOOL isHomeScreen = [className containsString:@"Home"] || [className containsString:@"TabBarController"];
    BOOL isEditorScreen = [className containsString:@"ProjectEdit"] || [className containsString:@"Timeline"] || [className containsString:@"EditText"] || [className containsString:@"Inspector"] || [className containsString:@"TextInput"];

    if (isEditorScreen) {
        [[AMHomeSettingsHUD sharedHUD] setFloatingButtonVisible:NO];
        [[AMProjectLyricsHUD sharedHUD] setFloatingButtonVisible:YES];
    } else if (isHomeScreen) {
        [[AMHomeSettingsHUD sharedHUD] setFloatingButtonVisible:YES];
        [[AMProjectLyricsHUD sharedHUD] setFloatingButtonVisible:NO];
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

    // 1. Rebind C AudioServices vibration functions via Fishhook
    rebind_symbols((struct rebinding[3]){
        {"AudioServicesPlaySystemSound", (void *)hook_AudioServicesPlaySystemSound, (void **)&orig_AudioServicesPlaySystemSound},
        {"AudioServicesPlayAlertSound", (void *)hook_AudioServicesPlayAlertSound, (void **)&orig_AudioServicesPlayAlertSound},
        {"AudioServicesPlaySystemSoundWithCompletion", (void *)hook_AudioServicesPlaySystemSoundWithCompletion, (void **)&orig_AudioServicesPlaySystemSoundWithCompletion}
    }, 3);

    // 2. Hook UIFeedbackGenerator / UIImpactFeedbackGenerator / UINotificationFeedbackGenerator
    Class impactClass = objc_getClass("UIImpactFeedbackGenerator");
    if (impactClass) {
        Method m = class_getInstanceMethod(impactClass, @selector(impactOccurred));
        if (m) {
            orig_UIImpactFeedbackGenerator_impactOccurred = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_UIImpactFeedbackGenerator_impactOccurred);
        }
    }

    Class notifClass = objc_getClass("UINotificationFeedbackGenerator");
    if (notifClass) {
        Method m = class_getInstanceMethod(notifClass, @selector(notificationOccurred:));
        if (m) {
            orig_UINotificationFeedbackGenerator_notificationOccurred = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_UINotificationFeedbackGenerator_notificationOccurred);
        }
    }

    // 3. Hook UIWindow (Exempting keyboard and text system windows)
    Class windowClass = [UIWindow class];
    Method makeKeyMethod = class_getInstanceMethod(windowClass, @selector(makeKeyAndVisible));
    if (makeKeyMethod) {
        orig_UIWindow_makeKeyAndVisible = (void *)method_getImplementation(makeKeyMethod);
        method_setImplementation(makeKeyMethod, (IMP)hook_UIWindow_makeKeyAndVisible);
    }

    Method setHiddenMethod = class_getInstanceMethod(windowClass, @selector(setHidden:));
    if (setHiddenMethod) {
        orig_UIWindow_setHidden = (void *)method_getImplementation(setHiddenMethod);
        method_setImplementation(setHiddenMethod, (IMP)hook_UIWindow_setHidden);
    }

    // 4. Hook UIActivityViewController
    Class activityVCClass = [UIActivityViewController class];
    Method initActivityMethod = class_getInstanceMethod(activityVCClass, @selector(initWithActivityItems:applicationActivities:));
    if (initActivityMethod) {
        orig_UIActivityViewController_initWithActivityItems = (void *)method_getImplementation(initActivityMethod);
        method_setImplementation(initActivityMethod, (IMP)hook_UIActivityViewController_initWithActivityItems);
    }

    // 5. Hook UIViewController viewDidAppear & presentViewController
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

    // 6. Hook UIAlertController factory
    Class alertClass = objc_getClass("UIAlertController");
    if (alertClass) {
        Method alertCreateMethod = class_getClassMethod(alertClass, @selector(alertControllerWithTitle:message:preferredStyle:));
        if (alertCreateMethod) {
            orig_UIAlertController_alertControllerWithTitle = (void *)method_getImplementation(alertCreateMethod);
            method_setImplementation(alertCreateMethod, (IMP)hook_UIAlertController_alertControllerWithTitle);
        }
    }

    // 7. Hook UIApplication openURL
    Class appClass = [UIApplication class];
    Method openURLMethod = class_getInstanceMethod(appClass, @selector(openURL:));
    if (openURLMethod) {
        orig_UIApplication_openURL = (void *)method_getImplementation(openURLMethod);
        method_setImplementation(openURLMethod, (IMP)hook_UIApplication_openURL);
    }

    Method openURLOptMethod = class_getInstanceMethod(appClass, @selector(openURL:options:completionHandler:));
    if (openURLOptMethod) {
        orig_UIApplication_openURL_options_completionHandler = (void *)method_getImplementation(openURLOptMethod);
        method_setImplementation(openURLOptMethod, (IMP)hook_UIApplication_openURL_options_completionHandler);
    }

    // 8. Hook TextInputVC & UITextView
    Class textInputClass = objc_getClass("_TtC12AlightMotion11TextInputVC");
    if (textInputClass) {
        Method textAppearMethod = class_getInstanceMethod(textInputClass, @selector(viewDidAppear:));
        if (textAppearMethod) {
            orig_TextInputVC_viewDidAppear = (void *)method_getImplementation(textAppearMethod);
            method_setImplementation(textAppearMethod, (IMP)hook_TextInputVC_viewDidAppear);
        }
    }

    Class tvClass = [UITextView class];
    if (tvClass) {
        Method becomeMethod = class_getInstanceMethod(tvClass, @selector(becomeFirstResponder));
        if (becomeMethod) {
            orig_UITextView_becomeFirstResponder = (void *)method_getImplementation(becomeMethod);
            method_setImplementation(becomeMethod, (IMP)hook_UITextView_becomeFirstResponder);
        }
    }
}
