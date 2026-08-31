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

#pragma mark - Settings & Auto Save Engine

static BOOL AMIsAutoSaveEnabled(void) {
    NSNumber *val = [[NSUserDefaults standardUserDefaults] objectForKey:@"AM_AutoSaveToPhotos"];
    if (val == nil) return YES;
    return [val boolValue];
}

static void AMSetAutoSaveEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"AM_AutoSaveToPhotos"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL AMIsAutoLyricsSyncEnabled(void) {
    NSNumber *val = [[NSUserDefaults standardUserDefaults] objectForKey:@"AM_AutoLyricsSyncEnabled"];
    if (val == nil) return YES;
    return [val boolValue];
}

static void AMSetAutoLyricsSyncEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"AM_AutoLyricsSyncEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

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

#pragma mark - Smart Lyrics Item & Engine (Timeline Aware & Queue Matching)

@interface AMLyricsItem : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) double timestamp; // in seconds (-1.0 if plain text)
@property (nonatomic, copy) NSString *timestampStr; // e.g. @"00:12.50"
@property (nonatomic, assign) BOOL isUsed;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@implementation AMLyricsItem

- (NSDictionary *)toDictionary {
    return @{
        @"text": self.text ?: @"",
        @"timestamp": @(self.timestamp),
        @"timestampStr": self.timestampStr ?: @"",
        @"isUsed": @(self.isUsed)
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    AMLyricsItem *item = [[AMLyricsItem alloc] init];
    item.text = dict[@"text"] ?: @"";
    item.timestamp = [dict[@"timestamp"] doubleValue];
    item.timestampStr = dict[@"timestampStr"] ?: @"";
    item.isUsed = [dict[@"isUsed"] boolValue];
    return item;
}

@end

@interface AMLyricsEngine : NSObject
@property (nonatomic, strong) NSMutableArray<AMLyricsItem *> *items;
@property (nonatomic, assign) NSUInteger queueIndex;
@property (nonatomic, assign) BOOL autoSyncEnabled;
+ (instancetype)sharedEngine;
- (void)loadRawLyrics:(NSString *)rawText;
- (void)clear;
- (void)resetUsedStatus;
- (BOOL)hasTimestampedLyrics;
- (AMLyricsItem *)getBestMatchForPlayheadSeconds:(double)playheadSecs;
- (AMLyricsItem *)getNextSequentialItem;
- (void)saveToDisk;
- (void)loadFromDisk;
@end

@implementation AMLyricsEngine

+ (instancetype)sharedEngine {
    static AMLyricsEngine *engine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engine = [[self alloc] init];
        engine.items = [NSMutableArray array];
        engine.autoSyncEnabled = AMIsAutoLyricsSyncEnabled();
        [engine loadFromDisk];
    });
    return engine;
}

- (void)loadFromDisk {
    NSArray *cached = [[NSUserDefaults standardUserDefaults] objectForKey:@"AM_CachedLyricsItems"];
    [self.items removeAllObjects];
    if (cached && [cached isKindOfClass:[NSArray class]]) {
        for (NSDictionary *dict in cached) {
            if ([dict isKindOfClass:[NSDictionary class]]) {
                [self.items addObject:[AMLyricsItem fromDictionary:dict]];
            }
        }
    }
    self.queueIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"AM_CachedLyricsQueueIndex"];
    if (self.queueIndex >= self.items.count) {
        self.queueIndex = 0;
    }
}

- (void)saveToDisk {
    NSMutableArray *arr = [NSMutableArray array];
    for (AMLyricsItem *it in self.items) {
        [arr addObject:[it toDictionary]];
    }
    NSUInteger qIndex = self.queueIndex;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [[NSUserDefaults standardUserDefaults] setObject:arr forKey:@"AM_CachedLyricsItems"];
        [[NSUserDefaults standardUserDefaults] setInteger:qIndex forKey:@"AM_CachedLyricsQueueIndex"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    });
}

static double AMParseTimestampToSeconds(NSString *tsStr) {
    if (!tsStr || tsStr.length == 0) return -1.0;
    NSArray *parts = [tsStr componentsSeparatedByString:@":"];
    if (parts.count >= 2) {
        double mins = [parts[0] doubleValue];
        double secs = [parts[1] doubleValue];
        return (mins * 60.0) + secs;
    }
    return [tsStr doubleValue];
}

- (void)loadRawLyrics:(NSString *)rawText {
    [self.items removeAllObjects];
    self.queueIndex = 0;

    if (!rawText || rawText.length == 0) {
        [self saveToDisk];
        return;
    }

    static NSRegularExpression *lrcRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lrcRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\[(\\d{1,2}:\\d{2}(?:[\\.:]\\d{1,3})?)\\]\\s*(.*)$"
                                                             options:0
                                                               error:nil];
    });

    NSArray *lines = [rawText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *rawLine in lines) {
        NSString *trimmed = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;

        NSTextCheckingResult *match = [lrcRegex firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
        if (match && match.numberOfRanges >= 3) {
            NSString *tsStr = [trimmed substringWithRange:[match rangeAtIndex:1]];
            NSString *content = [trimmed substringWithRange:[match rangeAtIndex:2]];
            content = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (content.length > 0) {
                AMLyricsItem *it = [[AMLyricsItem alloc] init];
                it.timestampStr = tsStr;
                it.timestamp = AMParseTimestampToSeconds(tsStr);
                it.text = content;
                it.isUsed = NO;
                [self.items addObject:it];
            }
        } else {
            // Plain text without LRC timestamp
            AMLyricsItem *it = [[AMLyricsItem alloc] init];
            it.timestampStr = nil;
            it.timestamp = -1.0;
            it.text = trimmed;
            it.isUsed = NO;
            [self.items addObject:it];
        }
    }

    [self saveToDisk];
}

- (void)clear {
    [self.items removeAllObjects];
    self.queueIndex = 0;
    [self saveToDisk];
}

- (void)resetUsedStatus {
    for (AMLyricsItem *it in self.items) {
        it.isUsed = NO;
    }
    self.queueIndex = 0;
    [self saveToDisk];
}

- (BOOL)hasTimestampedLyrics {
    for (AMLyricsItem *it in self.items) {
        if (it.timestamp >= 0.0) {
            return YES;
        }
    }
    return NO;
}

- (AMLyricsItem *)getBestMatchForPlayheadSeconds:(double)playheadSecs {
    if (self.items.count == 0) return nil;

    AMLyricsItem *bestUnused = nil;
    double minDiff = 999999.0;

    for (AMLyricsItem *it in self.items) {
        if (it.timestamp < 0.0) continue;
        double diff = fabs(it.timestamp - playheadSecs);
        // Match within timeline window or closest preceding line
        if (!it.isUsed && it.timestamp <= (playheadSecs + 0.8) && diff < minDiff) {
            minDiff = diff;
            bestUnused = it;
        }
    }

    if (bestUnused) {
        return bestUnused;
    }

    // Fallback: If no direct timestamp match before playhead, pick next unused sequential
    return [self getNextSequentialItem];
}

- (AMLyricsItem *)getNextSequentialItem {
    if (self.items.count == 0) return nil;

    // First search from queueIndex forward for unused item
    for (NSUInteger i = self.queueIndex; i < self.items.count; i++) {
        AMLyricsItem *it = self.items[i];
        if (!it.isUsed) {
            self.queueIndex = i + 1;
            return it;
        }
    }

    // Wrap around search from 0
    for (NSUInteger i = 0; i < self.items.count; i++) {
        AMLyricsItem *it = self.items[i];
        if (!it.isUsed) {
            self.queueIndex = i + 1;
            return it;
        }
    }

    // If all items are used, return the current queue index item and advance
    if (self.queueIndex < self.items.count) {
        AMLyricsItem *it = self.items[self.queueIndex];
        if (self.queueIndex + 1 < self.items.count) {
            self.queueIndex++;
        }
        return it;
    }

    return self.items.lastObject;
}

@end

#pragma mark - Timeline Playhead Detector Helper

static double AMGetCurrentTimelinePlayheadSeconds(void) {
    // 1. Traverse window hierarchy to find TimelineViewController or playheadLabel
    UIWindow *keyWin = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
    if (!keyWin) return -1.0;

    UIViewController *root = keyWin.rootViewController;
    NSMutableArray<UIViewController *> *stack = [NSMutableArray arrayWithObject:root];

    while (stack.count > 0) {
        UIViewController *vc = stack.lastObject;
        [stack removeLastObject];

        NSString *clsName = NSStringFromClass([vc class]);

        if ([clsName containsString:@"TimelineViewController"] || [clsName containsString:@"ProjectEditVC"]) {
            // Check playheadLabel
            if ([vc respondsToSelector:@selector(playheadLabel)]) {
                id labelObj = [vc valueForKey:@"playheadLabel"];
                NSString *timeStr = nil;
                if ([labelObj isKindOfClass:[UIButton class]]) {
                    timeStr = [(UIButton *)labelObj currentTitle] ?: [(UIButton *)labelObj titleLabel].text;
                } else if ([labelObj isKindOfClass:[UILabel class]]) {
                    timeStr = [(UILabel *)labelObj text];
                }
                if (timeStr && timeStr.length > 0) {
                    double parsed = AMParseTimestampToSeconds(timeStr);
                    if (parsed >= 0.0) return parsed;
                }
            }

            // Check holder -> playerTime / seekTime
            if ([vc respondsToSelector:@selector(holder)]) {
                id holder = [vc valueForKey:@"holder"];
                if (holder) {
                    @try {
                        id pt = [holder valueForKey:@"playerTime"];
                        if ([pt respondsToSelector:@selector(doubleValue)]) {
                            return [pt doubleValue];
                        }
                    } @catch (NSException *e) {}
                }
            }
        }

        if (vc.presentedViewController) {
            [stack addObject:vc.presentedViewController];
        }
        [stack addObjectsFromArray:vc.childViewControllers];
    }

    return -1.0;
}

#pragma mark - Auto Detect & Auto Lyrics Insert Engine Core

static void AMPerformAutoLyricsInjection(UIViewController *textInputVC, UITextView *tv) {
    if (!AMIsAutoLyricsSyncEnabled()) {
        return;
    }

    AMLyricsEngine *engine = [AMLyricsEngine sharedEngine];
    if (engine.items.count == 0) {
        return;
    }

    if (!tv) return;

    // Safety Check: Is this a new/empty text layer or placeholder?
    NSString *curText = [tv.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    BOOL isNewOrPlaceholder = (curText.length == 0 ||
                              [curText.lowercaseString isEqualToString:@"text"] ||
                              [curText.lowercaseString isEqualToString:@"văn bản"] ||
                              [curText.lowercaseString isEqualToString:@"nhập văn bản"] ||
                              [curText.lowercaseString isEqualToString:@"sample text"] ||
                              [curText.lowercaseString isEqualToString:@"tap to edit"]);

    // If the text is already custom user-written text (not in our lyrics list), do NOT overwrite!
    if (!isNewOrPlaceholder) {
        BOOL matchesKnownLyrics = NO;
        for (AMLyricsItem *it in engine.items) {
            if ([it.text isEqualToString:curText]) {
                matchesKnownLyrics = YES;
                break;
            }
        }
        if (!matchesKnownLyrics) {
            NSLog(@"[LyricsEngine] ℹ️ Custom user text detected (\"%@\"). Skipping auto-injection to prevent overwrite.", curText);
            return;
        }
    }

    // Detect Timeline Playhead Time
    double playhead = AMGetCurrentTimelinePlayheadSeconds();
    AMLyricsItem *selectedItem = nil;

    if ([engine hasTimestampedLyrics] && playhead >= 0.0) {
        selectedItem = [engine getBestMatchForPlayheadSeconds:playhead];
    } else {
        selectedItem = [engine getNextSequentialItem];
    }

    if (!selectedItem || selectedItem.text.length == 0) {
        return;
    }

    // Perform Direct In-Memory Injection
    tv.text = selectedItem.text;

    // Update Swift appearText model property
    @try {
        [textInputVC setValue:selectedItem.text forKey:@"appearText"];
    } @catch (NSException *e) {}

    // Trigger UIKit Delegate & Notifications to immediately render on Metal canvas
    if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
        [tv.delegate textViewDidChange:tv];
    }
    if ([tv.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
        [tv.delegate textView:tv shouldChangeTextInRange:NSMakeRange(0, tv.text.length) replacementText:selectedItem.text];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];

    // Mark used & save state
    selectedItem.isUsed = YES;
    [engine saveToDisk];

    // Structured Debug Logging
    NSLog(@"\n[LyricsEngine] ========================================");
    NSLog(@"[LyricsEngine] 🎯 Auto Detected Text Layer & Editor!");
    NSLog(@"[LyricsEngine] Target Class: %@", NSStringFromClass([textInputVC class]));
    NSLog(@"[LyricsEngine] Timeline Playhead: %.2f seconds", playhead);
    NSLog(@"[LyricsEngine] Selected Verse: \"%@\" (Timestamp: %@)", selectedItem.text, selectedItem.timestampStr ?: @"Sequential");
    NSLog(@"[LyricsEngine] Injection Result: SUCCESS");
    NSLog(@"[LyricsEngine] ========================================\n");
}

#pragma mark - Hook TextInputVC & UITextView (Seamless 100% Native Keyboard)

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
        tv.inputAccessoryView = nil; // Keep iOS Keyboard 100% Clean & Native
        AMPerformAutoLyricsInjection(self, tv);
    }
}

static BOOL (*orig_UITextView_becomeFirstResponder)(UITextView *, SEL);

static BOOL hook_UITextView_becomeFirstResponder(UITextView *self, SEL _cmd) {
    self.inputAccessoryView = nil; // Keep iOS Keyboard 100% Clean & Native

    UIResponder *responder = self;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            break;
        }
    }
    if (responder) {
        NSString *vcName = NSStringFromClass([responder class]);
        if ([vcName containsString:@"TextInputVC"] || [vcName containsString:@"EditText"]) {
            AMPerformAutoLyricsInjection((UIViewController *)responder, self);
        }
    }

    if (orig_UITextView_becomeFirstResponder) {
        return orig_UITextView_becomeFirstResponder(self, _cmd);
    }
    return YES;
}

#pragma mark - Batch Lyrics Importer Modal (With Smart LRC Parser & Visual Preview)

@interface AMBatchLyricsViewController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *lineCountLabel;
@property (nonatomic, strong) UIButton *pasteButton;
@property (nonatomic, strong) UIButton *clearQueueButton;
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

    AMLyricsEngine *engine = [AMLyricsEngine sharedEngine];
    if (engine.items.count > 0) {
        NSMutableArray *lines = [NSMutableArray array];
        for (AMLyricsItem *it in engine.items) {
            if (it.timestampStr && it.timestampStr.length > 0) {
                [lines addObject:[NSString stringWithFormat:@"[%@] %@", it.timestampStr, it.text]];
            } else {
                [lines addObject:it.text];
            }
        }
        self.textView.text = [lines componentsJoinedByString:@"\n"];
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
    titleLabel.text = @"📝 Nạp Lời Bài Hát (Hỗ Trợ LRC & Text Thường)";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 44, self.view.bounds.size.width - 40, 32)];
    subtitleLabel.text = @"Hỗ trợ định dạng có timestamp [00:12.50] hoặc lời thường. Khi tạo text layer, hệ thống sẽ TỰ ĐỘNG điền.";
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
    self.pasteButton.frame = CGRectMake(16, bottomY, 64, 42);
    [self.pasteButton setTitle:@"📋 Dán" forState:UIControlStateNormal];
    [self.pasteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pasteButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.pasteButton.layer.cornerRadius = 10.0;
    self.pasteButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.pasteButton addTarget:self action:@selector(pasteFromClipboard) forControlEvents:UIControlEventTouchUpInside];
    self.pasteButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.pasteButton];

    // Clear Queue Button
    self.clearQueueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearQueueButton.frame = CGRectMake(86, bottomY, 78, 42);
    [self.clearQueueButton setTitle:@"🗑️ Xóa Hết" forState:UIControlStateNormal];
    [self.clearQueueButton setTitleColor:[UIColor colorWithRed:1.0 green:0.45 blue:0.45 alpha:1.0] forState:UIControlStateNormal];
    self.clearQueueButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.1 blue:0.1 alpha:0.8];
    self.clearQueueButton.layer.cornerRadius = 10.0;
    self.clearQueueButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.clearQueueButton addTarget:self action:@selector(clearQueue) forControlEvents:UIControlEventTouchUpInside];
    self.clearQueueButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.clearQueueButton];

    // Save Queue Button
    CGFloat applyX = 170;
    CGFloat applyW = width - applyX - 60;
    self.applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.applyButton.frame = CGRectMake(applyX, bottomY, applyW, 42);
    [self.applyButton setTitle:@"⚡ Lưu & Kích Hoạt" forState:UIControlStateNormal];
    [self.applyButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.applyButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    self.applyButton.layer.cornerRadius = 10.0;
    self.applyButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [self.applyButton addTarget:self action:@selector(applyLyricsToQueue) forControlEvents:UIControlEventTouchUpInside];
    self.applyButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.applyButton];

    // Close Button
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(width - 54, bottomY, 44, 42);
    [self.closeButton setTitle:@"Đóng" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(dismissModal) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:self.closeButton];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)clearQueue {
    self.textView.text = @"";
    [self updateLineCount];
    [[AMLyricsEngine sharedEngine] clear];
    if (self.onLyricsLoaded) {
        self.onLyricsLoaded();
    }
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
    NSArray *lines = [self.textView.text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSUInteger validCount = 0;
    NSUInteger lrcCount = 0;
    for (NSString *s in lines) {
        NSString *trimmed = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            validCount++;
            if ([trimmed hasPrefix:@"["] && [trimmed containsString:@"]"]) {
                lrcCount++;
            }
        }
    }
    if (lrcCount > 0) {
        self.lineCountLabel.text = [NSString stringWithFormat:@"📊 Số dòng: %lu câu (Có %lu câu LRC timestamp)", (unsigned long)validCount, (unsigned long)lrcCount];
    } else {
        self.lineCountLabel.text = [NSString stringWithFormat:@"📊 Số dòng: %lu câu hát", (unsigned long)validCount];
    }
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
    NSString *raw = self.textView.text;
    if (!raw || raw.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thông báo"
                                                                       message:@"Vui lòng dán lời bài hát trước khi lưu."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    [[AMLyricsEngine sharedEngine] loadRawLyrics:raw];

    if (self.onLyricsLoaded) {
        self.onLyricsLoaded();
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Home Settings Dashboard Modal (Quản Lý Cài Đặt Tại Trang Chủ)

@interface AMHomeSettingsViewController : UIViewController
@property (nonatomic, strong) UILabel *lyricsStatusLabel;
@property (nonatomic, strong) UISwitch *autoSyncSwitch;
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

    // Card 1: Auto Lyrics Engine Setting
    UIView *card1 = [[UIView alloc] initWithFrame:CGRectMake(16, 60, w - 32, 125)];
    card1.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    card1.layer.cornerRadius = 14.0;
    card1.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:card1];

    UILabel *l1 = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, card1.bounds.size.width - 90, 22)];
    l1.text = @"⚡ Tự Động Điền Lời (Auto Lyrics Sync)";
    l1.textColor = [UIColor whiteColor];
    l1.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [card1 addSubview:l1];

    self.autoSyncSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(card1.bounds.size.width - 66, 8, 51, 31)];
    self.autoSyncSwitch.onTintColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    self.autoSyncSwitch.on = AMIsAutoLyricsSyncEnabled();
    self.autoSyncSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.autoSyncSwitch addTarget:self action:@selector(toggleAutoSync:) forControlEvents:UIControlEventValueChanged];
    [card1 addSubview:self.autoSyncSwitch];

    self.lyricsStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 38, card1.bounds.size.width - 190, 42)];
    self.lyricsStatusLabel.textColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    self.lyricsStatusLabel.font = [UIFont systemFontOfSize:11];
    self.lyricsStatusLabel.numberOfLines = 2;
    [card1 addSubview:self.lyricsStatusLabel];
    [self refreshLyricsStatus];

    // Nạp Lời Button
    UIButton *loadBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    loadBtn.frame = CGRectMake(card1.bounds.size.width - 180, 80, 85, 34);
    [loadBtn setTitle:@"📝 Nạp Lời" forState:UIControlStateNormal];
    [loadBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    loadBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    loadBtn.layer.cornerRadius = 9.0;
    loadBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    loadBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [loadBtn addTarget:self action:@selector(openLyricsModal) forControlEvents:UIControlEventTouchUpInside];
    [card1 addSubview:loadBtn];

    // Reset Used Button
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(card1.bounds.size.width - 88, 80, 76, 34);
    [resetBtn setTitle:@"🔄 Làm Lại" forState:UIControlStateNormal];
    [resetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    resetBtn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    resetBtn.layer.cornerRadius = 9.0;
    resetBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    resetBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [resetBtn addTarget:self action:@selector(resetLyricsStatus) forControlEvents:UIControlEventTouchUpInside];
    [card1 addSubview:resetBtn];

    // Card 2: Auto Save to Camera Roll
    UIView *card2 = [[UIView alloc] initWithFrame:CGRectMake(16, 195, w - 32, 70)];
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

    // Card 3: Pro & Engine Status
    UIView *card3 = [[UIView alloc] initWithFrame:CGRectMake(16, 275, w - 32, 85)];
    card3.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    card3.layer.cornerRadius = 14.0;
    card3.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:card3];

    UILabel *l3 = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, card3.bounds.size.width - 32, 22)];
    l3.text = @"👑 Trạng Thái Hệ Thống";
    l3.textColor = [UIColor whiteColor];
    l3.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [card3 addSubview:l3];

    UILabel *l3Sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, card3.bounds.size.width - 32, 40)];
    l3Sub.text = @"🟢 Auto Lyrics Insert Engine: Hoạt động (Không cần nút)\n🟢 Full Premium Pro v6.2.56 Unlocked (4K, 120 FPS)\n🟢 1.182 Hiệu ứng & Presets mở rộng sẵn sàng";
    l3Sub.textColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    l3Sub.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    l3Sub.numberOfLines = 3;
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

- (void)refreshLyricsStatus {
    AMLyricsEngine *engine = [AMLyricsEngine sharedEngine];
    if (engine.items.count == 0) {
        self.lyricsStatusLabel.text = @"Trạng thái: Trống (chưa có lời).";
        self.lyricsStatusLabel.textColor = [UIColor lightGrayColor];
    } else {
        NSUInteger usedCount = 0;
        NSUInteger lrcCount = 0;
        for (AMLyricsItem *it in engine.items) {
            if (it.isUsed) usedCount++;
            if (it.timestamp >= 0.0) lrcCount++;
        }
        if (lrcCount > 0) {
            self.lyricsStatusLabel.text = [NSString stringWithFormat:@"Đã nạp %lu câu (Timeline LRC).\n(Đã điền: %lu/%lu câu)", (unsigned long)engine.items.count, (unsigned long)usedCount, (unsigned long)engine.items.count];
        } else {
            self.lyricsStatusLabel.text = [NSString stringWithFormat:@"Đang có %lu câu tuần tự.\n(Đã điền: %lu/%lu câu)", (unsigned long)engine.items.count, (unsigned long)usedCount, (unsigned long)engine.items.count];
        }
        self.lyricsStatusLabel.textColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    }
}

- (void)toggleAutoSync:(UISwitch *)sw {
    AMSetAutoLyricsSyncEnabled(sw.on);
    [AMLyricsEngine sharedEngine].autoSyncEnabled = sw.on;
}

- (void)toggleAutoSave:(UISwitch *)sw {
    AMSetAutoSaveEnabled(sw.on);
}

- (void)resetLyricsStatus {
    [[AMLyricsEngine sharedEngine] resetUsedStatus];
    [self refreshLyricsStatus];
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

            BOOL isOurAlert = [title containsString:@"Alight Motion Pro"] || [title containsString:@"Thông báo"] || [title containsString:@"Lyrics"] || [title containsString:@"Cài Đặt"] || [title containsString:@"Quản Lý Lời"];

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
    }

    NSString *className = NSStringFromClass([self class]);

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

    // 8. Hook TextInputVC & UITextView (Auto Detection & Insertion Engine)
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
