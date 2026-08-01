#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

static AVAudioPlayer *audioPlayer = nil;
static UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;
static NSTimer *progressTimer = nil;
static __weak UIViewController *currentExportVC = nil;

static NSData* createSilentWAVData() {
    unsigned char wavHeader[] = {
        'R', 'I', 'F', 'F', 0x24, 0x1F, 0x00, 0x00, 'W', 'A', 'V', 'E',
        'f', 'm', 't', ' ', 0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
        0x40, 0x1F, 0x00, 0x00, 0x40, 0x1F, 0x00, 0x00, 0x01, 0x00, 0x08, 0x00,
        'd', 'a', 't', 'a', 0x00, 0x1F, 0x00, 0x00
    };
    NSMutableData *data = [NSMutableData dataWithBytes:wavHeader length:sizeof(wavHeader)];
    [data increaseLengthBy:8000];
    return data;
}

static void startBackgroundExecution() {
    if (bgTask == UIBackgroundTaskInvalid) {
        bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            if (bgTask != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                bgTask = UIBackgroundTaskInvalid;
            }
        }];
    }
    
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    [session setActive:YES error:&error];
    
    if (!audioPlayer) {
        NSData *wav = createSilentWAVData();
        audioPlayer = [[AVAudioPlayer alloc] initWithData:wav error:nil];
        audioPlayer.numberOfLoops = -1;
    }
    [audioPlayer play];
}

static void stopBackgroundExecution() {
    if (audioPlayer) {
        [audioPlayer stop];
        audioPlayer = nil;
    }
    if (bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }
}

static void updateProgressNotification(NSString *rateText, NSString *timeText) {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Alight Motion - Đang xuất video ngầm...";
    
    NSString *body = @"Đang tiến hành render...";
    if (rateText.length > 0 && timeText.length > 0) {
        body = [NSString stringWithFormat:@"Tiến độ: %@ (%@)", rateText, timeText];
    } else if (rateText.length > 0) {
        body = [NSString stringWithFormat:@"Tiến độ: %@", rateText];
    }
    content.body = body;
    content.sound = nil;
    
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"AlightMotionExportProgress" content:content trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

static void sendCompletionNotification() {
    [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[@"AlightMotionExportProgress"]];
    [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[@"AlightMotionExportProgress"]];
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Alight Motion MOD";
    content.body = @"Xuất video 100% hoàn tất! Đã tự động lưu vào Camera Roll.";
    content.sound = [UNNotificationSound defaultSound];
    
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:content trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

static void checkExportProgress() {
    if (!currentExportVC) return;
    
    NSString *rateText = @"";
    NSString *timeText = @"";
    
    if ([currentExportVC respondsToSelector:@selector(progressRateLabel)]) {
        IMP imp = [currentExportVC methodForSelector:@selector(progressRateLabel)];
        UILabel *(*func)(id, SEL) = (void *)imp;
        UILabel *lbl = func(currentExportVC, @selector(progressRateLabel));
        if ([lbl isKindOfClass:[UILabel class]]) {
            rateText = lbl.text ?: @"";
        }
    }
    
    if ([currentExportVC respondsToSelector:@selector(progressTimeLabel)]) {
        IMP imp = [currentExportVC methodForSelector:@selector(progressTimeLabel)];
        UILabel *(*func)(id, SEL) = (void *)imp;
        UILabel *lbl = func(currentExportVC, @selector(progressTimeLabel));
        if ([lbl isKindOfClass:[UILabel class]]) {
            timeText = lbl.text ?: @"";
        }
    }
    
    updateProgressNotification(rateText, timeText);
}

// Hook UIViewController viewDidAppear
static void (*orig_viewDidAppear)(UIViewController *, SEL, BOOL);
static void hook_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    
    NSString *className = NSStringFromClass([self class]);
    
    // 1. Export in progress (ExportVC)
    if ([className containsString:@"ExportVC"] && ![className containsString:@"ExportPreviewVC"]) {
        currentExportVC = self;
        startBackgroundExecution();
        
        [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge) completionHandler:^(BOOL granted, NSError * _Nullable error) {}];
        
        if (!progressTimer) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progressTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull t) {
                    checkExportProgress();
                }];
            });
        }
    }
    
    // 2. Export completed (ExportPreviewVC)
    if ([className containsString:@"ExportPreviewVC"]) {
        currentExportVC = nil;
        if (progressTimer) {
            [progressTimer invalidate];
            progressTimer = nil;
        }
        stopBackgroundExecution();
        sendCompletionNotification();
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self respondsToSelector:@selector(storeButton)]) {
                IMP imp = [self methodForSelector:@selector(storeButton)];
                UIButton *(*func)(id, SEL) = (void *)imp;
                UIButton *btn = func(self, @selector(storeButton));
                if ([btn isKindOfClass:[UIButton class]]) {
                    [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                }
            }
        });
    }
}

__attribute__((constructor)) static void initHooks() {
    Class vcClass = objc_getClass("UIViewController");
    Method m = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    orig_viewDidAppear = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_viewDidAppear);
}
