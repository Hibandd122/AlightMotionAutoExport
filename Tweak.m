#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

#define AUTO_TEXT_BUTTON_TAG 998877

static NSMutableArray<NSString *> *pendingTextLines = nil;
static NSInteger currentLineIndex = 0;
static UIButton *globalAutoTextBtn = nil;
static NSTimer *batchAutoSplitTimer = nil;

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

static BOOL sendSelectorToHierarchy(UIViewController *vc, SEL sel) {
    if (!vc) return NO;
    if ([vc respondsToSelector:sel]) {
        IMP imp = [vc methodForSelector:sel];
        void (*func)(id, SEL) = (void *)imp;
        func(vc, sel);
        return YES;
    }
    for (UIViewController *child in vc.childViewControllers) {
        if (sendSelectorToHierarchy(child, sel)) return YES;
    }
    if (vc.parentViewController && [vc.parentViewController respondsToSelector:sel]) {
        IMP imp = [vc.parentViewController methodForSelector:sel];
        void (*func)(id, SEL) = (void *)imp;
        func(vc.parentViewController, sel);
        return YES;
    }
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

static void triggerGlobalAction(SEL primarySel, SEL fallbackSel, NSString *keyword) {
    UIViewController *topVC = getTopViewController();
    UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
    UIViewController *winRoot = keyWin ? keyWin.rootViewController : nil;
    
    BOOL done = sendSelectorToHierarchy(topVC, primarySel);
    if (!done && fallbackSel) {
        done = sendSelectorToHierarchy(topVC, fallbackSel);
    }
    if (!done && winRoot && winRoot != topVC) {
        done = sendSelectorToHierarchy(winRoot, primarySel);
        if (!done && fallbackSel) {
            done = sendSelectorToHierarchy(winRoot, fallbackSel);
        }
    }
    
    if (!done && keyword) {
        if (topVC.view) sendActionToButtonsInView(topVC.view, keyword);
        if (winRoot && winRoot.view) sendActionToButtonsInView(winRoot.view, keyword);
    }
}

static void jumpToNextKeyframe() {
    triggerGlobalAction(@selector(onTapNextKeyframe), @selector(onTapBookmark), @"keyframe");
}

static void triggerAutoSplitLayer() {
    triggerGlobalAction(@selector(onTapSplit), @selector(onTapSplitTimeline), @"split");
}

static void updateButtonState() {
    if (!globalAutoTextBtn) return;
    if (pendingTextLines && pendingTextLines.count > 0 && currentLineIndex < pendingTextLines.count) {
        NSString *title = [NSString stringWithFormat:@"⚡ KEYFRAME (%ld/%lu)", (long)(currentLineIndex + 1), (unsigned long)pendingTextLines.count];
        [globalAutoTextBtn setTitle:title forState:UIControlStateNormal];
        globalAutoTextBtn.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.95];
    } else {
        [globalAutoTextBtn setTitle:@"⚡ AUTO TEXT" forState:UIControlStateNormal];
        globalAutoTextBtn.backgroundColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:0.95];
    }
}

static void applyCurrentLineToInput(UIViewController *parentVC) {
    if (!pendingTextLines || currentLineIndex >= pendingTextLines.count) return;
    
    NSString *line = pendingTextLines[currentLineIndex];
    [UIPasteboard generalPasteboard].string = line;
    
    UIView *inputView = findTargetInputView(parentVC.view);
    if (!inputView && parentVC.parentViewController) {
        inputView = findTargetInputView(parentVC.parentViewController.view);
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
    
    currentLineIndex++;
    if (currentLineIndex >= pendingTextLines.count) {
        pendingTextLines = nil;
        currentLineIndex = 0;
    }
    updateButtonState();
}

static void executeOneStep(UIViewController *topVC) {
    if (!pendingTextLines || currentLineIndex >= pendingTextLines.count) {
        if (batchAutoSplitTimer) {
            [batchAutoSplitTimer invalidate];
            batchAutoSplitTimer = nil;
        }
        return;
    }
    
    if (currentLineIndex > 0) {
        jumpToNextKeyframe();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            triggerAutoSplitLayer();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                applyCurrentLineToInput(topVC);
            });
        });
    } else {
        applyCurrentLineToInput(topVC);
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
        if (batchAutoSplitTimer) [batchAutoSplitTimer invalidate];
        batchAutoSplitTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 repeats:YES block:^(NSTimer * _Nonnull t) {
            UIViewController *top = getTopViewController();
            executeOneStep(top);
        }];
    } else {
        applyCurrentLineToInput(parentVC);
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
    subLbl.text = @"Tự động Cắt Layer và Nạp chữ theo các mốc Keyframe trên Timeline:";
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
    
    UIButton *btnAutoAll = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnAutoAll setTitle:@"⚡ TÁCH TOÀN BỘ KEYFRAME" forState:UIControlStateNormal];
    [btnAutoAll setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    btnAutoAll.backgroundColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:1.0];
    btnAutoAll.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    btnAutoAll.layer.cornerRadius = 10.0;
    btnAutoAll.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:btnAutoAll];
    
    UIButton *btnCancel = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnCancel setTitle:@"HỦY" forState:UIControlStateNormal];
    [btnCancel setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
    btnCancel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    btnCancel.titleLabel.font = [UIFont systemFontOfSize:14.0];
    btnCancel.layer.cornerRadius = 10.0;
    btnCancel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:btnCancel];
    
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:modalVC.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:modalVC.view.centerYAnchor constant:-30],
        [card.widthAnchor constraintEqualToConstant:320],
        [card.heightAnchor constraintEqualToConstant:310],
        
        [titleLbl.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [titleLbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [titleLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        
        [subLbl.topAnchor constraintEqualToAnchor:titleLbl.bottomAnchor constant:6],
        [subLbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [subLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        
        [textView.topAnchor constraintEqualToAnchor:subLbl.bottomAnchor constant:12],
        [textView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [textView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [textView.heightAnchor constraintEqualToConstant:120],
        
        [btnAutoAll.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [btnAutoAll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [btnAutoAll.widthAnchor constraintEqualToConstant:200],
        [btnAutoAll.heightAnchor constraintEqualToConstant:40],
        
        [btnCancel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [btnCancel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [btnCancel.trailingAnchor constraintEqualToAnchor:btnAutoAll.leadingAnchor constant:-10],
        [btnCancel.heightAnchor constraintEqualToConstant:40]
    ]];
    
    [btnCancel addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [modalVC dismissViewControllerAnimated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [btnAutoAll addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        NSString *raw = textView.text;
        startSequentialTextProcess(parentVC, raw, YES);
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
static BOOL isDragging = NO;

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
        executeOneStep(top);
    } else {
        presentAutoTextModal(top);
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    if (pan.state == UIGestureRecognizerStateBegan) {
        panStartPoint = btn.center;
        isDragging = NO;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:btn.superview];
        if (hypot(translation.x, translation.y) > 4.0) {
            isDragging = YES;
        }
        btn.center = CGPointMake(panStartPoint.x + translation.x, panStartPoint.y + translation.y);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (!isDragging) {
            [self buttonTapped:(UIButton *)btn];
        }
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
    
    // 2. Add DRAGGABLE AUTOMATIC KEYFRAME SPLIT "⚡ AUTO TEXT" button
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
            [autoTextBtn addGestureRecognizer:pan];
            
            [self.view addSubview:autoTextBtn];
            [self.view bringSubviewToFront:autoTextBtn];
        }
    }
}

__attribute__((constructor)) static void initHooks() {
    Class vcClass = objc_getClass("UIViewController");
    Method m = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    orig_viewDidAppear = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_viewDidAppear);
}
