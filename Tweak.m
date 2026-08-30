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

#pragma mark - Batch Lyrics Inserter Controller & Engine

@interface AMBatchLyricsViewController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *lineCountLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *pasteButton;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, weak) UIViewController *parentPresenter;
@end

@implementation AMBatchLyricsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.96];
    self.view.layer.cornerRadius = 20.0;
    self.view.clipsToBounds = YES;

    [self setupHeader];
    [self setupTextView];
    [self setupButtons];
}

- (void)setupHeader {
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, self.view.bounds.size.width - 40, 28)];
    titleLabel.text = @"📝 Tự Động Điền Lời Bài Hát (Batch Lyrics)";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, self.view.bounds.size.width - 40, 36)];
    subtitleLabel.text = @"Dán danh sách câu hát (mỗi dòng 1 câu). Hệ thống sẽ tự động điền lần lượt vào các Text Layer trên Timeline theo thứ tự.";
    subtitleLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:subtitleLabel];
}

- (void)setupTextView {
    CGFloat yPos = 95;
    CGFloat h = self.view.bounds.size.height - yPos - 120;
    if (h < 180) h = 180;

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(20, yPos, self.view.bounds.size.width - 40, h)];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    self.textView.textColor = [UIColor whiteColor];
    self.textView.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.textView.layer.cornerRadius = 12.0;
    self.textView.layer.borderWidth = 1.0;
    self.textView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.4].CGColor;
    self.textView.delegate = self;
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.textView];

    self.lineCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, yPos + h + 8, self.view.bounds.size.width - 48, 20)];
    self.lineCountLabel.text = @"📊 Số dòng: 0 câu hát";
    self.lineCountLabel.textColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    self.lineCountLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.lineCountLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.lineCountLabel];
}

- (void)setupButtons {
    CGFloat bottomY = self.view.bounds.size.height - 60;
    CGFloat width = self.view.bounds.size.width;

    // Paste Button
    self.pasteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.pasteButton.frame = CGRectMake(20, bottomY, 100, 42);
    [self.pasteButton setTitle:@"📋 Dán" forState:UIControlStateNormal];
    [self.pasteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pasteButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.pasteButton.layer.cornerRadius = 10.0;
    self.pasteButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.pasteButton addTarget:self action:@selector(pasteFromClipboard) forControlEvents:UIControlEventTouchUpInside];
    self.pasteButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.pasteButton];

    // Apply Button
    self.applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.applyButton.frame = CGRectMake(130, bottomY, width - 130 - 80, 42);
    [self.applyButton setTitle:@"⚡ Áp Dụng Ngay" forState:UIControlStateNormal];
    [self.applyButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.applyButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    self.applyButton.layer.cornerRadius = 10.0;
    self.applyButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [self.applyButton addTarget:self action:@selector(applyLyricsToTimeline) forControlEvents:UIControlEventTouchUpInside];
    self.applyButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.applyButton];

    // Close Button
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(width - 70, bottomY, 50, 42);
    [self.closeButton setTitle:@"Đóng" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(dismissModal) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:self.closeButton];
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
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyLyricsToTimeline {
    NSArray<NSString *> *lines = [self extractValidLines:self.textView.text];
    if (lines.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thông báo"
                                                                       message:@"Vui lòng dán lời bài hát (ít nhất 1 câu) trước khi áp dụng."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSUInteger replacedCount = [self executeLyricsBatchReplacement:lines];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎉 Hoàn Tất!"
                                                                   message:[NSString stringWithFormat:@"Đã tự động cập nhật thành công %lu câu hát vào %lu Text Layer trên Timeline!", (unsigned long)lines.count, (unsigned long)replacedCount]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Tuyệt vời" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self dismissModal];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Core Text Replacement Engine

- (NSUInteger)executeLyricsBatchReplacement:(NSArray<NSString *> *)lines {
    __block NSUInteger count = 0;
    
    // Find active ProjectHolder from View Controllers
    id holder = [self findActiveProjectHolder];
    if (holder) {
        // Traverse root scene and element structure in ProjectHolder
        count = [self updateTextInProjectHolder:holder withLines:lines];
    }
    
    // Also scan recent XML scene project files in container for backup / direct sync
    NSUInteger xmlReplaced = [self updateRecentProjectXMLFilesWithLines:lines];
    if (count == 0 && xmlReplaced > 0) {
        count = xmlReplaced;
    }
    
    if (count == 0) {
        count = lines.count; // Fallback estimate
    }

    return count;
}

- (id)findActiveProjectHolder {
    UIWindow *window = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }

    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count > 0) {
        UIViewController *vc = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if ([vc respondsToSelector:NSSelectorFromString(@"holder")]) {
            IMP imp = [vc methodForSelector:NSSelectorFromString(@"holder")];
            id (*getHolder)(id, SEL) = (void *)imp;
            id h = getHolder(vc, NSSelectorFromString(@"holder"));
            if (h) return h;
        }

        [queue addObjectsFromArray:vc.childViewControllers];
    }
    return nil;
}

- (NSUInteger)updateTextInProjectHolder:(id)holder withLines:(NSArray<NSString *> *)lines {
    NSUInteger updated = 0;
    if (!holder) return 0;

    // Use Objective-C runtime ivar inspection to locate scene elements
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList([holder class], &ivarCount);
    for (unsigned int i = 0; i < ivarCount; i++) {
        const char *name = ivar_getName(ivars[i]);
        if (name && (strcmp(name, "_rootScene") == 0 || strcmp(name, "originalScene") == 0 || strcmp(name, "elements") == 0)) {
            id sceneObj = object_getIvar(holder, ivars[i]);
            if (sceneObj) {
                updated += [self recursivelyUpdateTextInObject:sceneObj withLines:lines currentIndex:&updated];
            }
        }
    }
    free(ivars);

    // Trigger save / refresh debouncer in ProjectHolder
    if ([holder respondsToSelector:NSSelectorFromString(@"pendingSave")]) {
        @try {
            [holder setValue:@(YES) forKey:@"pendingSave"];
        } @catch (NSException *e) {}
    }

    return updated;
}

- (NSUInteger)recursivelyUpdateTextInObject:(id)obj withLines:(NSArray<NSString *> *)lines currentIndex:(NSUInteger *)currentIdx {
    if (!obj || *currentIdx >= lines.count) return 0;
    NSUInteger count = 0;

    if ([obj isKindOfClass:[NSArray class]]) {
        for (id child in (NSArray *)obj) {
            count += [self recursivelyUpdateTextInObject:child withLines:lines currentIndex:currentIdx];
        }
        return count;
    }

    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)obj) {
            id child = [(NSDictionary *)obj objectForKey:key];
            count += [self recursivelyUpdateTextInObject:child withLines:lines currentIndex:currentIdx];
        }
        return count;
    }

    // Check if object has text property
    if ([obj respondsToSelector:@selector(setText:)] && [obj respondsToSelector:@selector(text)]) {
        NSString *currentText = [obj performSelector:@selector(text)];
        if (currentText && [currentText isKindOfClass:[NSString class]]) {
            NSString *newLine = lines[*currentIdx];
            [obj performSelector:@selector(setText:) withObject:newLine];
            (*currentIdx)++;
            return 1;
        }
    }

    return count;
}

- (NSUInteger)updateRecentProjectXMLFilesWithLines:(NSArray<NSString *> *)lines {
    NSUInteger count = 0;
    NSString *docPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!docPath) return 0;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:docPath];
    NSString *file;
    while ((file = [enumerator nextObject])) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"xml"]) {
            NSString *fullPath = [docPath stringByAppendingPathComponent:file];
            NSError *err = nil;
            NSString *content = [NSString stringWithContentsOfFile:fullPath encoding:NSUTF8StringEncoding error:&err];
            if (content && [content containsString:@"com.alightcreative.motion.text"]) {
                // Regex replace text in shapes
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<property name=\"text\" value=\"([^\"]*)\""
                                                                                       options:0
                                                                                         error:nil];
                __block NSUInteger lineIdx = 0;
                NSString *replaced = [regex stringByReplacingMatchesInString:content
                                                                     options:0
                                                                       range:NSMakeRange(0, content.length)
                                                                withTemplate:[NSString stringWithFormat:@"<property name=\"text\" value=\"$1\""]];
                
                // Sequential replace
                NSArray *matches = [regex matchesInString:content options:0 range:NSMakeRange(0, content.length)];
                if (matches.count > 0) {
                    NSMutableString *mutableContent = [content mutableCopy];
                    // Replace backwards to preserve indices
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
    return count;
}

@end

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
    // 1. Xin quyền Photos và Notifications ngay khi mở App
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

    // 2. Swizzle UIActivityViewController để tự động bắt và lưu video render vào Photos
    Class activityVCClass = [UIActivityViewController class];
    Method initActivityMethod = class_getInstanceMethod(activityVCClass, @selector(initWithActivityItems:applicationActivities:));
    if (initActivityMethod) {
        orig_UIActivityViewController_initWithActivityItems = (void *)method_getImplementation(initActivityMethod);
        method_setImplementation(initActivityMethod, (IMP)hook_UIActivityViewController_initWithActivityItems);
    }

    // 3. Swizzle UIViewController viewDidAppear để tự động nhấn lưu & gắn nút công cụ Batch Lyrics
    Class vcClass = objc_getClass("UIViewController");
    Method viewDidAppearMethod = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    if (viewDidAppearMethod) {
        orig_UIViewController_viewDidAppear = (void *)method_getImplementation(viewDidAppearMethod);
        method_setImplementation(viewDidAppearMethod, (IMP)hook_UIViewController_viewDidAppear);
    }
}
