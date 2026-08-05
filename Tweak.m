#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

extern void AMInstallFPS120ForController(UIViewController *controller);
extern void AMInstallShareLinkImportForController(UIViewController *controller);

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
static UITraitCollection *(*orig_viewTraitCollection)(UIView *, SEL);
static UITraitCollection *(*orig_viewControllerTraitCollection)(UIViewController *, SEL);

static UITraitCollection *darkTraitCollection(UITraitCollection *original) {
    UITraitCollection *dark = [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark];
    if (!original) return dark;
    if (original.userInterfaceStyle == UIUserInterfaceStyleDark) return original;
    return [UITraitCollection traitCollectionWithTraitsFromCollections:@[original, dark]];
}

static UITraitCollection *hook_viewTraitCollection(UIView *self, SEL _cmd) {
    UITraitCollection *original = orig_viewTraitCollection ? orig_viewTraitCollection(self, _cmd) : nil;
    return darkTraitCollection(original);
}

static UITraitCollection *hook_viewControllerTraitCollection(UIViewController *self, SEL _cmd) {
    UITraitCollection *original = orig_viewControllerTraitCollection ? orig_viewControllerTraitCollection(self, _cmd) : nil;
    return darkTraitCollection(original);
}

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
    AMInstallFPS120ForController(self);
    AMInstallShareLinkImportForController(self);
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
    Method viewTraitMethod = class_getInstanceMethod([UIView class], @selector(traitCollection));
    if (viewTraitMethod) {
        orig_viewTraitCollection = (void *)method_getImplementation(viewTraitMethod);
        method_setImplementation(viewTraitMethod, (IMP)hook_viewTraitCollection);
    }

    Method viewControllerTraitMethod = class_getInstanceMethod([UIViewController class], @selector(traitCollection));
    if (viewControllerTraitMethod) {
        orig_viewControllerTraitCollection = (void *)method_getImplementation(viewControllerTraitMethod);
        method_setImplementation(viewControllerTraitMethod, (IMP)hook_viewControllerTraitCollection);
    }

    Class vcClass = objc_getClass("UIViewController");
    Method method = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    if (!method) return;

    orig_viewDidAppear = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)hook_viewDidAppear);

    dispatch_async(dispatch_get_main_queue(), ^{
        forceDarkMode();
    });
}
