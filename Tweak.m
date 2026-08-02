#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

static void sendCompletionNotification() {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Alight Motion MOD";
    content.body = @"Xuất video hoàn tất! Đã tự động lưu vào Cuộn Camera.";
    content.sound = [UNNotificationSound defaultSound];

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
                                                                            content:content
                                                                            trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                                  withCompletionHandler:nil];
}

static void (*orig_viewDidAppear)(UIViewController *, SEL, BOOL);

static void forceDarkMode() {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            forceDarkMode();
        });
        return;
    }

    UIApplication *application = [UIApplication sharedApplication];
    for (UIWindow *window in application.windows) {
        window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        window.rootViewController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        window.rootViewController.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
}

static void hook_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_viewDidAppear) orig_viewDidAppear(self, _cmd, animated);

    // Alight Motion already uses dynamic system colors for its theme. Force
    // the window and every newly presented controller onto the dark trait.
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    forceDarkMode();

    NSString *className = NSStringFromClass([self class]);
    if (![className containsString:@"ExportPreviewVC"] && ![className containsString:@"ExportVC"]) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (![self respondsToSelector:@selector(storeButton)]) return;

        IMP imp = [self methodForSelector:@selector(storeButton)];
        UIButton *(*getButton)(id, SEL) = (void *)imp;
        UIButton *button = getButton(self, @selector(storeButton));
        if (![button isKindOfClass:[UIButton class]]) return;

        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        sendCompletionNotification();
    });
}

__attribute__((constructor)) static void initHooks() {
    Class vcClass = objc_getClass("UIViewController");
    Method method = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    if (!method) return;

    orig_viewDidAppear = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)hook_viewDidAppear);

    dispatch_async(dispatch_get_main_queue(), ^{
        forceDarkMode();
    });
}
