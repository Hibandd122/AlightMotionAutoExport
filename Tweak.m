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

static void checkNewVideos() {
    NSArray *dirs = @[ 
        NSTemporaryDirectory(), 
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject],
        [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject],
        [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject]
    ];
    
    for (NSString *dir in dirs) {
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:dir];
        for (NSString *file in enumerator) {
            if ([file.lowercaseString hasSuffix:@".mp4"] || [file.lowercaseString hasSuffix:@".mov"]) {
                NSString *fullPath = [dir stringByAppendingPathComponent:file];
                
                if (![seenFiles containsObject:fullPath]) {
                    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:nil];
                    NSDate *modDate = [attrs fileModificationDate];
                    unsigned long long size = [attrs fileSize];
                    
                    // If file is older than 2 seconds (hasn't been written to) and is a decent size (>1KB)
                    if (size > 1024 && [[NSDate date] timeIntervalSinceDate:modDate] > 2.0) {
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
    seenFiles = [[NSMutableSet alloc] init];
    
    // Initial scan to ignore existing files
    NSArray *dirs = @[ 
        NSTemporaryDirectory(), 
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject],
        [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject],
        [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject]
    ];
    for (NSString *dir in dirs) {
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:dir];
        for (NSString *file in enumerator) {
            if ([file.lowercaseString hasSuffix:@".mp4"] || [file.lowercaseString hasSuffix:@".mov"]) {
                [seenFiles addObject:[dir stringByAppendingPathComponent:file]];
            }
        }
    }
    
    // Start background timer
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), 2.0 * NSEC_PER_SEC, 0.5 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        checkNewVideos();
    });
    dispatch_resume(timer);
}
