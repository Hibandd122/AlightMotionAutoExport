#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

static NSMutableSet *seenFiles;
static dispatch_source_t timer;

static void sendExportNotification() {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Alight Motion MOD";
    content.body = @"Đã tự động lưu video vào Camera Roll!";
    content.sound = [UNNotificationSound defaultSound];
    
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1.0 repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:content trigger:trigger];
    
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

// Hook UIViewController viewDidAppear to auto-tap the Save button on ExportPreviewVC
static void (*orig_viewDidAppear)(UIViewController *, SEL, BOOL);
static void hook_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"ExportPreviewVC"] || [className containsString:@"ExportVC"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // 1. Try invoking didTapSave methods
            if ([self respondsToSelector:@selector(didTapSave:)]) {
                [self performSelector:@selector(didTapSave:) withObject:nil];
            } else if ([self respondsToSelector:@selector(didTapSave)]) {
                [self performSelector:@selector(didTapSave)];
            }
            
            // 2. Try triggering actions on saveButton property if available
            if ([self respondsToSelector:@selector(saveButton)]) {
                IMP imp = [self methodForSelector:@selector(saveButton)];
                UIButton *(*func)(id, SEL) = (void *)imp;
                UIButton *btn = func(self, @selector(saveButton));
                if ([btn isKindOfClass:[UIButton class]]) {
                    [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                }
            }
        });
    }
}

// Backup filesystem watcher
static void checkNewVideos() {
    NSArray *dirs = @[ 
        NSTemporaryDirectory(), 
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject],
        [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject],
        [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject]
    ];
    
    for (NSString *dir in dirs) {
        if (!dir) continue;
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:dir];
        for (NSString *file in enumerator) {
            if ([file.lowercaseString hasSuffix:@".mp4"] || [file.lowercaseString hasSuffix:@".mov"]) {
                NSString *fullPath = [dir stringByAppendingPathComponent:file];
                
                if (![seenFiles containsObject:fullPath]) {
                    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:nil];
                    NSDate *modDate = [attrs fileModificationDate];
                    unsigned long long size = [attrs fileSize];
                    
                    if (size > 1024 && [[NSDate date] timeIntervalSinceDate:modDate] > 1.5) {
                        [seenFiles addObject:fullPath];
                        
                        if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(fullPath)) {
                            UISaveVideoAtPathToSavedPhotosAlbum(fullPath, nil, NULL, NULL);
                            
                            [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge) completionHandler:^(BOOL granted, NSError * _Nullable error) {
                                if (granted) {
                                    sendExportNotification();
                                }
                            }];
                        }
                    }
                }
            }
        }
    }
}

__attribute__((constructor)) static void initHooks() {
    // 1. Hook viewDidAppear on UIViewController
    Class vcClass = objc_getClass("UIViewController");
    Method m = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    orig_viewDidAppear = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_viewDidAppear);
    
    // 2. Setup filesystem watcher
    seenFiles = [[NSMutableSet alloc] init];
    NSArray *dirs = @[ 
        NSTemporaryDirectory(), 
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject],
        [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject],
        [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject]
    ];
    for (NSString *dir in dirs) {
        if (!dir) continue;
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:dir];
        for (NSString *file in enumerator) {
            if ([file.lowercaseString hasSuffix:@".mp4"] || [file.lowercaseString hasSuffix:@".mov"]) {
                [seenFiles addObject:[dir stringByAppendingPathComponent:file]];
            }
        }
    }
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), 2.0 * NSEC_PER_SEC, 0.5 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        checkNewVideos();
    });
    dispatch_resume(timer);
}
