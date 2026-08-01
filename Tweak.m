#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

static void sendCompletionNotification() {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Alight Motion MOD";
    content.body = @"Xuất video hoàn tất! Đã tự động lưu vào Cuộn Camera.";
    content.sound = [UNNotificationSound defaultSound];
    
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:content trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
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
    subLbl.text = @"Dán văn bản nhiều dòng bên dưới để tách theo mốc Keyframe:";
    subLbl.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    subLbl.font = [UIFont systemFontOfSize:13.0];
    subLbl.numberOfLines = 0;
    subLbl.textAlignment = NSTextAlignmentCenter;
    subLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:subLbl];
    
    UITextView *textView = [[UITextView alloc] init];
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
    [btnProcess setTitle:@"TÁCH KEYFRAME" forState:UIControlStateNormal];
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
        [modalVC dismissViewControllerAnimated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [parentVC presentViewController:modalVC animated:YES completion:nil];
}

// 1. Hook iOS 14+ UIMenu factory method (for UIMenu native 3-dots menus)
static UIMenu *(*orig_menuWithTitle_children)(Class, SEL, NSString *, NSArray<UIMenuElement *> *);
static UIMenu *hook_menuWithTitle_children(Class self, SEL _cmd, NSString *title, NSArray<UIMenuElement *> *children) {
    BOOL alreadyAdded = NO;
    for (UIMenuElement *e in children) {
        if ([e isKindOfClass:[UIAction class]] && [((UIAction *)e).title containsString:@"Auto Text"]) {
            alreadyAdded = YES;
            break;
        }
    }
    
    if (!alreadyAdded && children.count > 0) {
        UIAction *autoTextAction = [UIAction actionWithTitle:@"⚡ Auto Text (Tách Keyframe)" image:nil identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
            UIViewController *topVC = nil;
            NSArray *windows = [UIApplication sharedApplication].windows;
            for (UIWindow *win in windows) {
                if (win.isKeyWindow) {
                    topVC = win.rootViewController;
                    break;
                }
            }
            if (!topVC && windows.count > 0) {
                UIWindow *firstWin = (UIWindow *)windows.firstObject;
                topVC = firstWin.rootViewController;
            }
            while (topVC.presentedViewController) {
                topVC = topVC.presentedViewController;
            }
            presentAutoTextModal(topVC);
        }];
        
        NSMutableArray *newChildren = [children mutableCopy];
        [newChildren addObject:autoTextAction];
        children = [newChildren copy];
    }
    
    return orig_menuWithTitle_children(self, _cmd, title, children);
}

// 2. Hook UIAlertController ActionSheet fallback
static void (*orig_presentViewController)(UIViewController *, SEL, UIViewController *, BOOL, id);
static void hook_presentViewController(UIViewController *self, SEL _cmd, UIViewController *vcToPresent, BOOL flag, id completion) {
    if ([vcToPresent isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)vcToPresent;
        if (alert.preferredStyle == UIAlertControllerStyleActionSheet) {
            BOOL alreadyAdded = NO;
            for (UIAlertAction *act in alert.actions) {
                if ([act.title containsString:@"Auto Text"]) {
                    alreadyAdded = YES;
                    break;
                }
            }
            if (!alreadyAdded) {
                __weak typeof(self) weakSelf = self;
                UIAlertAction *autoTextAction = [UIAlertAction actionWithTitle:@"⚡ Auto Text (Tách Keyframe)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    presentAutoTextModal(weakSelf);
                }];
                [alert addAction:autoTextAction];
            }
        }
    }
    orig_presentViewController(self, _cmd, vcToPresent, flag, completion);
}

// 3. Hook UIViewController viewDidAppear for auto-save
static void (*orig_viewDidAppear)(UIViewController *, SEL, BOOL);
static void hook_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    
    NSString *className = NSStringFromClass([self class]);
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
}

__attribute__((constructor)) static void initHooks() {
    Class vcClass = objc_getClass("UIViewController");
    
    // Hook viewDidAppear
    Method m1 = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    orig_viewDidAppear = (void *)method_getImplementation(m1);
    method_setImplementation(m1, (IMP)hook_viewDidAppear);
    
    // Hook presentViewController
    Method m2 = class_getInstanceMethod(vcClass, @selector(presentViewController:animated:completion:));
    orig_presentViewController = (void *)method_getImplementation(m2);
    method_setImplementation(m2, (IMP)hook_presentViewController);
    
    // Hook UIMenu menuWithTitle:children: (iOS 14+ native 3-dots menus)
    Class menuClass = objc_getClass("UIMenu");
    if (menuClass) {
        Method m3 = class_getClassMethod(menuClass, @selector(menuWithTitle:children:));
        if (m3) {
            orig_menuWithTitle_children = (void *)method_getImplementation(m3);
            method_setImplementation(m3, (IMP)hook_menuWithTitle_children);
        }
    }
}
