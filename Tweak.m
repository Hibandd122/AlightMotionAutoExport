#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

#define AUTO_TEXT_BUTTON_TAG 998877

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

static void applyTextToAlightMotion(UIViewController *parentVC, NSString *rawText) {
    if (rawText.length == 0) return;
    
    NSArray<NSString *> *lines = [rawText componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *validLines = [NSMutableArray array];
    for (NSString *l in lines) {
        NSString *trimmed = [l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [validLines addObject:trimmed];
        }
    }
    if (validLines.count == 0) return;
    
    NSString *joinedText = [validLines componentsJoinedByString:@"\n"];
    [UIPasteboard generalPasteboard].string = joinedText;
    
    UIView *inputView = findTargetInputView(parentVC.view);
    if (!inputView && parentVC.parentViewController) {
        inputView = findTargetInputView(parentVC.parentViewController.view);
    }
    
    if ([inputView isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)inputView;
        tv.text = joinedText;
        if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
            [tv.delegate textViewDidChange:tv];
        }
    } else if ([inputView isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)inputView;
        tf.text = [validLines firstObject];
        [tf sendActionsForControlEvents:UIControlEventEditingChanged];
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
    subLbl.text = @"Dán văn bản nhiều dòng bên dưới để tự động nạp vào Alight Motion:";
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
    
    UIButton *btnProcess = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnProcess setTitle:@"TÁCH & NẠP TEXT" forState:UIControlStateNormal];
    [btnProcess setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    btnProcess.backgroundColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:1.0];
    btnProcess.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
    btnProcess.layer.cornerRadius = 10.0;
    btnProcess.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:btnProcess];
    
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
        
        [btnProcess.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [btnProcess.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [btnProcess.widthAnchor constraintEqualToConstant:160],
        [btnProcess.heightAnchor constraintEqualToConstant:40],
        
        [btnCancel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [btnCancel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [btnCancel.trailingAnchor constraintEqualToAnchor:btnProcess.leadingAnchor constant:-10],
        [btnCancel.heightAnchor constraintEqualToConstant:40]
    ]];
    
    [btnCancel addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [modalVC dismissViewControllerAnimated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [btnProcess addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        NSString *raw = textView.text;
        applyTextToAlightMotion(parentVC, raw);
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
    presentAutoTextModal(top);
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
    
    // 2. Add DRAGGABLE "⚡ AUTO TEXT" button
    if ([className containsString:@"EditTextInspectorVC"] || [className containsString:@"EditTextPanelVC"] || [className containsString:@"MainEditor"] || [className containsString:@"ProjectEditor"]) {
        if (![self.view viewWithTag:AUTO_TEXT_BUTTON_TAG]) {
            UIButton *autoTextBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            autoTextBtn.tag = AUTO_TEXT_BUTTON_TAG;
            [autoTextBtn setTitle:@"⚡ AUTO TEXT" forState:UIControlStateNormal];
            [autoTextBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            autoTextBtn.backgroundColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:0.95];
            autoTextBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
            autoTextBtn.layer.cornerRadius = 14.0;
            autoTextBtn.layer.shadowColor = [UIColor blackColor].CGColor;
            autoTextBtn.layer.shadowOffset = CGSizeMake(0, 2);
            autoTextBtn.layer.shadowOpacity = 0.4;
            autoTextBtn.layer.shadowRadius = 4.0;
            autoTextBtn.userInteractionEnabled = YES;
            
            CGFloat screenWidth = self.view.bounds.size.width;
            autoTextBtn.frame = CGRectMake(screenWidth - 115.0, 85.0, 100.0, 32.0);
            
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
