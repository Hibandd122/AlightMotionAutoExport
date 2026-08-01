#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

static void sendExportNotification() {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Alight Motion";
    content.body = @"Export completed and video saved automatically.";
    content.sound = [UNNotificationSound defaultSound];
    
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1.0 repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:content trigger:trigger];
    
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

static BOOL hasSavedRecentVideo = NO;

%hook UIActivityViewController

- (instancetype)initWithActivityItems:(NSArray *)activityItems applicationActivities:(NSArray<UIActivity *> *)applicationActivities {
    for (id item in activityItems) {
        if ([item isKindOfClass:[NSURL class]]) {
            NSURL *url = (NSURL *)item;
            NSString *ext = url.pathExtension.lowercaseString;
            if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"]) {
                if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path) && !hasSavedRecentVideo) {
                    UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, NULL, NULL);
                    sendExportNotification();
                    hasSavedRecentVideo = YES;
                    
                    // Reset flag after 5 seconds to allow future saves
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        hasSavedRecentVideo = NO;
                    });
                }
            }
        }
    }
    return %orig;
}

%end

%hook UIApplication

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                          completionHandler:^(BOOL granted, NSError * _Nullable error) {}];
    return %orig;
}

%end
