#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

static void sendExportNotification() {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Alight Motion";
    content.body = @"Xuất video hoàn tất. Đã tự động lưu vào Cuộn Camera.";
    content.sound = [UNNotificationSound defaultSound];
    
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1.0 repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:content trigger:trigger];
    
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

static BOOL hasSavedRecentVideo = NO;

static id (*orig_initWithActivityItems)(UIActivityViewController *, SEL, NSArray *, NSArray *);
static id hook_initWithActivityItems(UIActivityViewController *self, SEL _cmd, NSArray *activityItems, NSArray *applicationActivities) {
    for (id item in activityItems) {
        if ([item isKindOfClass:[NSURL class]]) {
            NSURL *url = (NSURL *)item;
            NSString *ext = url.pathExtension.lowercaseString;
            if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"]) {
                if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path) && !hasSavedRecentVideo) {
                    UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, NULL, NULL);
                    
                    [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge) completionHandler:^(BOOL granted, NSError * _Nullable error) {
                        if (granted) {
                            sendExportNotification();
                        }
                    }];
                    
                    hasSavedRecentVideo = YES;
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        hasSavedRecentVideo = NO;
                    });
                }
            }
        }
    }
    return orig_initWithActivityItems(self, _cmd, activityItems, applicationActivities);
}

__attribute__((constructor)) static void initHooks() {
    Class cls = objc_getClass("UIActivityViewController");
    SEL sel = @selector(initWithActivityItems:applicationActivities:);
    Method m = class_getInstanceMethod(cls, sel);
    
    orig_initWithActivityItems = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_initWithActivityItems);
}
