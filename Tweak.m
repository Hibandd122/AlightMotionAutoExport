#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

#define AUTO_TEXT_BUTTON_TAG 998877

static NSMutableArray<NSString *> *pendingTextLines = nil;
static NSInteger currentLineIndex = 0;
static UIButton *globalAutoTextBtn = nil;
static BOOL isProcessingAutoBatch = NO;

static void sendCompletionNotification() {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Alight Motion MOD";
    content.body = @"Xuất video hoàn tất! Đã tự động lưu vào Cuộn Camera.";
    content.sound = [UNNotificationSound defaultSound];
    
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:content trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

static UIViewController *getTopViewController() {
    UIViewController *top = nil;
    NSArray *windows = [UIApplication sharedApplication].windows;
    for (UIWindow *win in windows) {
        if (win.isKeyWindow) {
            top = win.rootViewController;
            break;
        }
    }
    if (!top && windows.count > 0) {
        UIWindow *firstWin = (UIWindow *)windows.firstObject;
        top = firstWin.rootViewController;
    }
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    return top;
}

static UIViewController *findViewControllerOfClass(UIViewController *root, NSString *targetClassName) {
    if (!root) return nil;
    NSString *clsName = NSStringFromClass([root class]);
    if ([clsName containsString:targetClassName]) {
        return root;
    }
    for (UIViewController *child in root.childViewControllers) {
        UIViewController *found = findViewControllerOfClass(child, targetClassName);
        if (found) return found;
    }
    if (root.parentViewController) {
        NSString *parentCls = NSStringFromClass([root.parentViewController class]);
        if ([parentCls containsString:targetClassName]) {
            return root.parentViewController;
        }
    }
    return nil;
}

static void showHUDLog(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = getTopViewController();
        if (!topVC) return;
        
        UILabel *hud = [topVC.view viewWithTag:997766];
        if (!hud) {
            hud = [[UILabel alloc] init];
            hud.tag = 997766;
            hud.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.92];
            hud.textColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:1.0];
            hud.font = [UIFont boldSystemFontOfSize:11.0];
            hud.numberOfLines = 0;
            hud.textAlignment = NSTextAlignmentCenter;
            hud.layer.cornerRadius = 10.0;
            hud.layer.masksToBounds = YES;
            hud.layer.borderWidth = 1.0;
            hud.layer.borderColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:0.5].CGColor;
            
            CGFloat w = topVC.view.bounds.size.width - 40.0;
            hud.frame = CGRectMake(20.0, topVC.view.bounds.size.height - 110.0, w, 44.0);
            hud.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
            [topVC.view addSubview:hud];
        }
        
        hud.text = [NSString stringWithFormat:@"⚡ AUTO KEYFRAME:\n%@", msg];
        [topVC.view bringSubviewToFront:hud];
        
        [NSObject cancelPreviousPerformRequestsWithTarget:hud selector:@selector(removeFromSuperview) object:nil];
        [hud performSelector:@selector(removeFromSuperview) withObject:nil afterDelay:3.5];
    });
}

static UIView *findTargetInputView(UIView *view) {
    if (!view) return nil;
    if (([view isKindOfClass:[UITextView class]] || [view isKindOfClass:[UITextField class]]) && view.tag != 8899) {
        return view;
    }
    for (UIView *sub in view.subviews) {
        UIView *res = findTargetInputView(sub);
        if (res) return res;
    }
    return nil;
}

static void selectFirstTimelineCell(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)view;
        NSInteger sections = [cv numberOfSections];
        for (NSInteger s = 0; s < sections; s++) {
            if ([cv numberOfItemsInSection:s] > 0) {
                NSIndexPath *ip = [NSIndexPath indexPathForItem:0 inSection:s];
                [cv selectItemAtIndexPath:ip animated:NO scrollPosition:UICollectionViewScrollPositionNone];
                if ([cv.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
                    [cv.delegate collectionView:cv didSelectItemAtIndexPath:ip];
                }
                return;
            }
        }
    } else if ([view isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)view;
        NSInteger sections = [tv numberOfSections];
        for (NSInteger s = 0; s < sections; s++) {
            if ([tv numberOfRowsInSection:s] > 0) {
                NSIndexPath *ip = [NSIndexPath indexPathForRow:0 inSection:s];
                [tv selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
                if ([tv.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
                    [tv.delegate tableView:tv didSelectRowAtIndexPath:ip];
                }
                return;
            }
        }
    }
    for (UIView *sub in view.subviews) {
        selectFirstTimelineCell(sub);
    }
}

static void ensureTimelineLayerSelected() {
    UIViewController *topVC = getTopViewController();
    UIWindow *keyWin = nil;
    NSArray *wins = [UIApplication sharedApplication].windows;
    if (wins.count > 0) keyWin = (UIWindow *)wins.firstObject;
    
    UIViewController *timelineVC = findViewControllerOfClass(topVC, @"TimelineViewController");
    if (!timelineVC && keyWin) timelineVC = findViewControllerOfClass(keyWin.rootViewController, @"TimelineViewController");
    
    if (timelineVC && timelineVC.view) {
        selectFirstTimelineCell(timelineVC.view);
    } else if (topVC && topVC.view) {
        selectFirstTimelineCell(topVC.view);
    }
}

static BOOL callSelectorOnTarget(id target, SEL sel) {
    if (!target) return NO;
    if ([target respondsToSelector:sel]) {
        IMP imp = [target methodForSelector:sel];
        Method m = class_getInstanceMethod([target class], sel);
        int args = m ? method_getNumberOfArguments(m) : 2;
        if (args > 2) {
            void (*func)(id, SEL, id) = (void *)imp;
            func(target, sel, nil);
        } else {
            void (*func)(id, SEL) = (void *)imp;
            func(target, sel);
        }
        return YES;
    }
    return NO;
}

static BOOL searchSelectorInHierarchy(UIViewController *vc, SEL sel) {
    if (!vc) return NO;
    if (callSelectorOnTarget(vc, sel)) return YES;
    for (UIViewController *child in vc.childViewControllers) {
        if (searchSelectorInHierarchy(child, sel)) return YES;
    }
    if (vc.parentViewController && callSelectorOnTarget(vc.parentViewController, sel)) return YES;
    return NO;
}

static BOOL sendActionToButtonsInView(UIView *view, NSString *selectorKeyword) {
    if (!view) return NO;
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        for (id target in [btn allTargets]) {
            NSArray *actions = [btn actionsForTarget:target forControlEvent:UIControlEventTouchUpInside];
            for (NSString *act in actions) {
                if ([act.lowercaseString containsString:selectorKeyword.lowercaseString]) {
                    [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                    return YES;
                }
            }
        }
    }
    for (UIView *sub in view.subviews) {
        if (sendActionToButtonsInView(sub, selectorKeyword)) return YES;
    }
    return NO;
}

static BOOL triggerAutoSplitLayer() {
    UIViewController *topVC = getTopViewController();
    UIWindow *keyWin = nil;
    NSArray *wins = [UIApplication sharedApplication].windows;
    if (wins.count > 0) keyWin = (UIWindow *)wins.firstObject;
    UIViewController *winRoot = keyWin ? keyWin.rootViewController : nil;
    
    // Target EditingPanelVC directly!
    UIViewController *panelVC = findViewControllerOfClass(topVC, @"EditingPanelVC");
    if (!panelVC && winRoot) panelVC = findViewControllerOfClass(winRoot, @"EditingPanelVC");
    
    if (panelVC && [panelVC respondsToSelector:@selector(onTapSplit:)]) {
        IMP imp = [panelVC methodForSelector:@selector(onTapSplit:)];
        void (*func)(id, SEL, id) = (void *)imp;
        func(panelVC, @selector(onTapSplit:), nil);
        return YES;
    }
    
    SEL selectors[] = {
        @selector(onTapSplit:),
        @selector(onTapSplitTimeline:),
        @selector(onTapSplit)
    };
    
    for (size_t i = 0; i < sizeof(selectors)/sizeof(selectors[0]); i++) {
        SEL s = selectors[i];
        if (searchSelectorInHierarchy(topVC, s)) return YES;
        if (winRoot && winRoot != topVC && searchSelectorInHierarchy(winRoot, s)) return YES;
    }
    
    if (topVC.view && sendActionToButtonsInView(topVC.view, @"split")) return YES;
    if (winRoot && winRoot.view && sendActionToButtonsInView(winRoot.view, @"split")) return YES;
    
    return NO;
}

static BOOL jumpToNextMarkerOrKeyframe() {
    UIViewController *topVC = getTopViewController();
    UIWindow *keyWin = nil;
    NSArray *wins = [UIApplication sharedApplication].windows;
    if (wins.count > 0) keyWin = (UIWindow *)wins.firstObject;
    UIViewController *winRoot = keyWin ? keyWin.rootViewController : nil;
    
    // 1. Target PreviewControlBarVC directly!
    UIViewController *previewVC = findViewControllerOfClass(topVC, @"PreviewControlBarVC");
    if (!previewVC && winRoot) previewVC = findViewControllerOfClass(winRoot, @"PreviewControlBarVC");
    
    if (previewVC && [previewVC respondsToSelector:@selector(onTapMoveNext:)]) {
        IMP imp = [previewVC methodForSelector:@selector(onTapMoveNext:)];
        void (*func)(id, SEL, id) = (void *)imp;
        func(previewVC, @selector(onTapMoveNext:), nil);
        return YES;
    }
    
    // 2. Target TimelineViewController
    UIViewController *timelineVC = findViewControllerOfClass(topVC, @"TimelineViewController");
    if (!timelineVC && winRoot) timelineVC = findViewControllerOfClass(winRoot, @"TimelineViewController");
    
    if (timelineVC && [timelineVC respondsToSelector:@selector(onTapTimeLabel:)]) {
        IMP imp = [timelineVC methodForSelector:@selector(onTapTimeLabel:)];
        void (*func)(id, SEL, id) = (void *)imp;
        func(timelineVC, @selector(onTapTimeLabel:), nil);
        return YES;
    }
    
    SEL selectors[] = {
        @selector(onTapMoveNext:),
        @selector(onTapTimeLabel:),
        @selector(seekToMarker),
        @selector(onTapBookmark:),
        @selector(onTapNextKeyframe:)
    };
    
    for (size_t i = 0; i < sizeof(selectors)/sizeof(selectors[0]); i++) {
        SEL s = selectors[i];
        if (searchSelectorInHierarchy(topVC, s)) return YES;
        if (winRoot && winRoot != topVC && searchSelectorInHierarchy(winRoot, s)) return YES;
    }
    
    if (topVC.view) sendActionToButtonsInView(topVC.view, @"movenext");
    if (winRoot && winRoot.view) sendActionToButtonsInView(winRoot.view, @"movenext");
    return NO;
}

static void updateButtonState() {
    if (!globalAutoTextBtn) return;
    if (pendingTextLines && pendingTextLines.count > 0 && currentLineIndex < pendingTextLines.count) {
        NSString *title = [NSString stringWithFormat:@"⚡ CẮT & NẠP (%ld/%lu)", (long)(currentLineIndex + 1), (unsigned long)pendingTextLines.count];
        [globalAutoTextBtn setTitle:title forState:UIControlStateNormal];
        globalAutoTextBtn.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.95];
    } else {
        [globalAutoTextBtn setTitle:@"⚡ AUTO TEXT" forState:UIControlStateNormal];
        globalAutoTextBtn.backgroundColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:0.95];
    }
}

static void applyTextToInputDirectly(UIViewController *parentVC, NSString *line) {
    if (!line || line.length == 0) return;
    
    [UIPasteboard generalPasteboard].string = line;
    
    UIView *inputView = findTargetInputView(parentVC.view);
    if (!inputView && parentVC.parentViewController) {
        inputView = findTargetInputView(parentVC.parentViewController.view);
    }
    if (!inputView) {
        UIViewController *top = getTopViewController();
        if (top) inputView = findTargetInputView(top.view);
    }
    
    if ([inputView isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)inputView;
        tv.text = line;
        if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
            [tv.delegate textViewDidChange:tv];
        }
    } else if ([inputView isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)inputView;
        tf.text = line;
        [tf sendActionsForControlEvents:UIControlEventEditingChanged];
    }
}

static void processLineAtIndex(NSInteger index) {
    if (!pendingTextLines || index >= pendingTextLines.count) {
        pendingTextLines = nil;
        currentLineIndex = 0;
        isProcessingAutoBatch = NO;
        updateButtonState();
        showHUDLog(@"✅ Tách & Nạp Text Hoàn Tất!");
        return;
    }
    
    currentLineIndex = index;
    updateButtonState();
    
    if (index == 0) {
        // Step 1: Nạp dòng 1 vào Layer ban đầu
        UIViewController *top = getTopViewController();
        applyTextToInputDirectly(top, pendingTextLines[0]);
        showHUDLog([NSString stringWithFormat:@"📝 Nạp dòng 1/%lu: %@", (unsigned long)pendingTextLines.count, pendingTextLines[0]]);
        
        // Đợi 0.45s chuyển sang dòng 2
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            processLineAtIndex(index + 1);
        });
    } else {
        // các dòng tiếp theo (Marker 2, Marker 3...):
        // 1. Nhảy mốc Marker tiếp theo
        showHUDLog([NSString stringWithFormat:@"⏩ Nhảy mốc Marker dòng %ld/%lu...", (long)(index + 1), (unsigned long)pendingTextLines.count]);
        jumpToNextMarkerOrKeyframe();
        
        // 2. Đợi 0.30s ➔ Re-select Timeline Layer (đảm bảo Layer được chọn)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ensureTimelineLayerSelected();
            
            // 3. Đợi 0.15s ➔ Gọi Cắt đôi Layer
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                showHUDLog([NSString stringWithFormat:@"✂️ Cắt Layer dòng %ld/%lu...", (long)(index + 1), (unsigned long)pendingTextLines.count]);
                triggerAutoSplitLayer();
                
                // 4. Đợi 0.35s ➔ Nạp câu chữ tương ứng vào Layer mới
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIViewController *top = getTopViewController();
                    applyTextToInputDirectly(top, pendingTextLines[index]);
                    showHUDLog([NSString stringWithFormat:@"📝 Nạp dòng %ld/%lu: %@", (long)(index + 1), (unsigned long)pendingTextLines.count, pendingTextLines[index]]);
                    
                    // 5. Đợi 0.45s ➔ Tiếp tục sang Marker tiếp theo
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        processLineAtIndex(index + 1);
                    });
                });
            });
        });
    }
}

static void startSequentialTextProcess(UIViewController *parentVC, NSString *rawText, BOOL autoBatch) {
    if (rawText.length == 0) return;
    
    NSArray<NSString *> *lines = [rawText componentsSeparatedByString:@"\n"];
    pendingTextLines = [NSMutableArray array];
    for (NSString *l in lines) {
        NSString *trimmed = [l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [pendingTextLines addObject:trimmed];
        }
    }
    currentLineIndex = 0;
    
    if (pendingTextLines.count == 0) {
        updateButtonState();
        return;
    }
    
    if (autoBatch) {
        isProcessingAutoBatch = YES;
        processLineAtIndex(0);
    } else {
        applyTextToInputDirectly(parentVC, pendingTextLines[0]);
        currentLineIndex = 1;
        updateButtonState();
    }
}

static void presentAutoTextModal(UIViewController *parentVC) {
    if (!parentVC) return;
    
    UIViewController *modalVC = [[UIViewController alloc] init];
    modalVC.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    modalVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    modalVC.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.14 alpha:1.0];
    card.layer.cornerRadius = 18.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithRed:0.20 green:0.20 blue:0.25 alpha:1.0].CGColor;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [modalVC.view addSubview:card];
    
    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.text = @"⚡ Auto Keyframe Text";
    titleLbl.textColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:1.0];
    titleLbl.font = [UIFont boldSystemFontOfSize:18.0];
    titleLbl.textAlignment = NSTextAlignmentCenter;
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:titleLbl];
    
    UILabel *subLbl = [[UILabel alloc] init];
    subLbl.text = @"Tự động Cắt Layer và Nạp chữ theo các mốc Bookmark/Marker màu đỏ trên Timeline:";
    subLbl.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    subLbl.font = [UIFont systemFontOfSize:13.0];
    subLbl.numberOfLines = 0;
    subLbl.textAlignment = NSTextAlignmentCenter;
    subLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:subLbl];
    
    UITextView *textView = [[UITextView alloc] init];
    textView.tag = 8899;
    textView.backgroundColor = [UIColor colorWithRed:0.14 green:0.14 blue:0.18 alpha:1.0];
    textView.textColor = [UIColor whiteColor];
    textView.font = [UIFont systemFontOfSize:15.0];
    textView.layer.cornerRadius = 10.0;
    textView.layer.borderWidth = 1.0;
    textView.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:1.0].CGColor;
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.text = @"Text 1\nText 2\nText 3";
    [card addSubview:textView];
    
    UIButton *btnTestSplit = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnTestSplit setTitle:@"✂️ TÁCH LAYER NGAY" forState:UIControlStateNormal];
    [btnTestSplit setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btnTestSplit.backgroundColor = [UIColor colorWithRed:0.90 green:0.20 blue:0.20 alpha:1.0];
    btnTestSplit.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    btnTestSplit.layer.cornerRadius = 10.0;
    btnTestSplit.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:btnTestSplit];
    
    UIButton *btnAutoAll = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnAutoAll setTitle:@"⚡ TÁCH THEO MARKER" forState:UIControlStateNormal];
    [btnAutoAll setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    btnAutoAll.backgroundColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:1.0];
    btnAutoAll.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    btnAutoAll.layer.cornerRadius = 10.0;
    btnAutoAll.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:btnAutoAll];
    
    UIButton *btnCancel = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnCancel setTitle:@"HỦY" forState:UIControlStateNormal];
    [btnCancel setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
    btnCancel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    btnCancel.titleLabel.font = [UIFont systemFontOfSize:13.0];
    btnCancel.layer.cornerRadius = 10.0;
    btnCancel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:btnCancel];
    
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:modalVC.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:modalVC.view.centerYAnchor constant:-30],
        [card.widthAnchor constraintEqualToConstant:330],
        [card.heightAnchor constraintEqualToConstant:320],
        
        [titleLbl.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [titleLbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [titleLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        
        [subLbl.topAnchor constraintEqualToAnchor:titleLbl.bottomAnchor constant:6],
        [subLbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [subLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        
        [textView.topAnchor constraintEqualToAnchor:subLbl.bottomAnchor constant:12],
        [textView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [textView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [textView.heightAnchor constraintEqualToConstant:110],
        
        [btnTestSplit.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [btnTestSplit.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [btnTestSplit.widthAnchor constraintEqualToConstant:130],
        [btnTestSplit.heightAnchor constraintEqualToConstant:40],
        
        [btnAutoAll.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [btnAutoAll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [btnAutoAll.widthAnchor constraintEqualToConstant:160],
        [btnAutoAll.heightAnchor constraintEqualToConstant:40],
        
        [btnCancel.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [btnCancel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [btnCancel.widthAnchor constraintEqualToConstant:50],
        [btnCancel.heightAnchor constraintEqualToConstant:30]
    ]];
    
    [btnCancel addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [modalVC dismissViewControllerAnimated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [btnTestSplit addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        BOOL ok = triggerAutoSplitLayer();
        if (ok) {
            sendCompletionNotification();
        }
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [btnAutoAll addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        NSString *raw = textView.text;
        startSequentialTextProcess(parentVC, raw, NO);
        [modalVC dismissViewControllerAnimated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [parentVC presentViewController:modalVC animated:YES completion:nil];
}

@interface AutoTextButtonHandler : NSObject
+ (instancetype)sharedInstance;
- (void)buttonTapped:(UIButton *)sender;
- (void)handlePan:(UIPanGestureRecognizer *)pan;
@end

@implementation AutoTextButtonHandler
static CGPoint panStartPoint;

+ (instancetype)sharedInstance {
    static AutoTextButtonHandler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AutoTextButtonHandler alloc] init];
    });
    return instance;
}

- (void)buttonTapped:(UIButton *)sender {
    UIViewController *top = getTopViewController();
    if (pendingTextLines && pendingTextLines.count > 0 && currentLineIndex < pendingTextLines.count) {
        NSInteger targetIdx = currentLineIndex;
        currentLineIndex++;
        updateButtonState();
        
        if (targetIdx == 0) {
            applyTextToInputDirectly(top, pendingTextLines[0]);
            showHUDLog([NSString stringWithFormat:@"📝 Nạp dòng 1/%lu: %@", (unsigned long)pendingTextLines.count, pendingTextLines[0]]);
        } else {
            showHUDLog([NSString stringWithFormat:@"✂️ Cắt Layer & Nạp dòng %ld/%lu...", (long)(targetIdx + 1), (unsigned long)pendingTextLines.count]);
            ensureTimelineLayerSelected();
            triggerAutoSplitLayer();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                applyTextToInputDirectly(top, pendingTextLines[targetIdx]);
                showHUDLog([NSString stringWithFormat:@"📝 Nạp dòng %ld/%lu: %@", (long)(targetIdx + 1), (unsigned long)pendingTextLines.count, pendingTextLines[targetIdx]]);
            });
        }
    } else {
        presentAutoTextModal(top);
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    if (pan.state == UIGestureRecognizerStateBegan) {
        panStartPoint = btn.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:btn.superview];
        btn.center = CGPointMake(panStartPoint.x + translation.x, panStartPoint.y + translation.y);
    }
}
@end

static void (*orig_viewDidAppear)(UIViewController *, SEL, BOOL);
static void hook_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    
    NSString *className = NSStringFromClass([self class]);
    
    // 1. Auto-save export completion (ExportPreviewVC)
    if ([className containsString:@"ExportPreviewVC"] || [className containsString:@"ExportVC"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self respondsToSelector:@selector(storeButton)]) {
                IMP imp = [self methodForSelector:@selector(storeButton)];
                UIButton *(*func)(id, SEL) = (void *)imp;
                UIButton *btn = func(self, @selector(storeButton));
                if ([btn isKindOfClass:[UIButton class]]) {
                    [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                    sendCompletionNotification();
                }
            }
        });
    }
    
    // 2. Add DRAGGABLE AUTOMATIC MARKER SPLIT "⚡ AUTO TEXT" button
    if ([className containsString:@"EditTextInspectorVC"] || [className containsString:@"EditTextPanelVC"] || [className containsString:@"MainEditor"] || [className containsString:@"ProjectEditor"]) {
        if (![self.view viewWithTag:AUTO_TEXT_BUTTON_TAG]) {
            UIButton *autoTextBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            autoTextBtn.tag = AUTO_TEXT_BUTTON_TAG;
            globalAutoTextBtn = autoTextBtn;
            
            [autoTextBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            autoTextBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
            autoTextBtn.layer.cornerRadius = 14.0;
            autoTextBtn.layer.shadowColor = [UIColor blackColor].CGColor;
            autoTextBtn.layer.shadowOffset = CGSizeMake(0, 2);
            autoTextBtn.layer.shadowOpacity = 0.4;
            autoTextBtn.layer.shadowRadius = 4.0;
            autoTextBtn.userInteractionEnabled = YES;
            
            CGFloat screenWidth = self.view.bounds.size.width;
            autoTextBtn.frame = CGRectMake(screenWidth - 115.0, 85.0, 100.0, 32.0);
            
            updateButtonState();
            
            [autoTextBtn addTarget:[AutoTextButtonHandler sharedInstance] action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
            
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[AutoTextButtonHandler sharedInstance] action:@selector(handlePan:)];
            pan.cancelsTouchesInView = NO;
            pan.delaysTouchesBegan = NO;
            autoTextBtn.gestureRecognizers = @[pan];
            
            [self.view addSubview:autoTextBtn];
            [self.view bringSubviewToFront:autoTextBtn];
        }
    }
}

__attribute__((constructor)) static void initHooks() {
    // Hook UIViewController viewDidAppear
    Class vcClass = objc_getClass("UIViewController");
    Method m = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    orig_viewDidAppear = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_viewDidAppear);
}
