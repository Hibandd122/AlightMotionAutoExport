#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreImage/CoreImage.h>
#import <VideoToolbox/VideoToolbox.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <objc/runtime.h>

#pragma mark - =========================================================
#pragma mark 1. UMThemeManager: Centralized Full Dark Mode OLED (#07080B)
#pragma mark - =========================================================

@interface UMThemeManager : NSObject
@property (nonatomic, assign) BOOL isOLEDDarkEnabled;
+ (instancetype)sharedManager;
- (UIColor *)oledBackgroundColor;
- (UIColor *)elevatedPanelColor;
- (UIColor *)secondaryCardColor;
- (UIColor *)accentGreenColor;
- (UIColor *)primaryTextColor;
- (UIColor *)secondaryTextColor;
- (UIColor *)separatorLineColor;
- (void)applyThemeToView:(UIView *)view;
@end

@implementation UMThemeManager

+ (instancetype)sharedManager {
    static UMThemeManager *mgr = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mgr = [[self alloc] init];
        mgr.isOLEDDarkEnabled = YES;
    });
    return mgr;
}

- (UIColor *)oledBackgroundColor {
    return [UIColor colorWithRed:0.03 green:0.03 blue:0.04 alpha:1.0]; // #08080A
}

- (UIColor *)elevatedPanelColor {
    return [UIColor colorWithRed:0.07 green:0.08 blue:0.11 alpha:0.98]; // #12141C
}

- (UIColor *)secondaryCardColor {
    return [UIColor colorWithRed:0.11 green:0.12 blue:0.16 alpha:1.0]; // #1C1F29
}

- (UIColor *)accentGreenColor {
    return [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:1.0]; // Ultra Green #00E676
}

- (UIColor *)primaryTextColor {
    return [UIColor colorWithWhite:0.96 alpha:1.0];
}

- (UIColor *)secondaryTextColor {
    return [UIColor colorWithWhite:0.65 alpha:1.0];
}

- (UIColor *)separatorLineColor {
    return [UIColor colorWithWhite:0.18 alpha:0.6];
}

- (void)applyThemeToView:(UIView *)view {
    if (!view || !self.isOLEDDarkEnabled) return;
    
    NSString *clsName = NSStringFromClass([view class]);
    if ([clsName containsString:@"Keyboard"] || [clsName containsString:@"TextEffects"]) {
        return;
    }
    
    if ([clsName containsString:@"Background"] || [clsName containsString:@"Container"] || [clsName containsString:@"Home"] || [clsName containsString:@"Project"]) {
        view.backgroundColor = [self oledBackgroundColor];
    }
}

@end

#pragma mark - =========================================================
#pragma mark 2. UMEffectRegistry & UMEffectSearchEngine (Lazy & Safe Loaded)
#pragma mark - =========================================================

@interface UMEffectItem : NSObject
@property (nonatomic, copy) NSString *effectId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *desc;
@property (nonatomic, copy) NSString *tags;
@property (nonatomic, copy) NSString *xmlFileName;
@property (nonatomic, assign) BOOL isSupportedOnMetal;
@end

@implementation UMEffectItem
@end

@interface UMEffectRegistry : NSObject
@property (nonatomic, strong) NSMutableArray<UMEffectItem *> *effects;
@property (nonatomic, strong) NSArray<NSString *> *categories;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<UMEffectItem *> *> *categorizedEffects;
@property (nonatomic, assign) BOOL isLoaded;
+ (instancetype)sharedRegistry;
- (void)loadAllUltraEffects;
- (NSArray<UMEffectItem *> *)searchEffectsWithQuery:(NSString *)query;
- (UMEffectItem *)effectById:(NSString *)effectId;
@end

@implementation UMEffectRegistry

+ (instancetype)sharedRegistry {
    static UMEffectRegistry *reg = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        reg = [[self alloc] init];
        reg.effects = [NSMutableArray array];
        reg.categories = @[
            @"ultra-blur", @"ultra-light", @"ultra-distortion", @"ultra-color",
            @"ultra-stylize", @"ultra-particles", @"ultra-elements", @"ultra-nature",
            @"ultra-strokes", @"ultra-ink", @"ultra-glitch", @"ultra-depth",
            @"ultra-retro", @"ultra-looks", @"ultra-props", @"ultra-textures",
            @"ultra-transform", @"ultra-water", @"drawing", @"matte",
            @"opacity", @"repeat", @"text", @"other"
        ];
        reg.isLoaded = NO;
    });
    return reg;
}

- (void)loadAllUltraEffects {
    @synchronized (self) {
        if (self.isLoaded) return;
        
        NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
        NSString *builtinDir = [bundlePath stringByAppendingPathComponent:@"BuiltinEffects"];
        
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:builtinDir]) {
            self.isLoaded = YES;
            return;
        }
        
        NSArray *files = [fm contentsOfDirectoryAtPath:builtinDir error:nil];
        NSMutableDictionary *catDict = [NSMutableDictionary dictionary];
        for (NSString *cat in self.categories) {
            catDict[cat] = [NSMutableArray array];
        }
        
        for (NSString *file in files) {
            if (![file.pathExtension.lowercaseString isEqualToString:@"xml"]) continue;
            
            NSString *fullPath = [builtinDir stringByAppendingPathComponent:file];
            NSString *content = [NSString stringWithContentsOfFile:fullPath encoding:NSUTF8StringEncoding error:nil];
            if (!content || content.length == 0) continue;
            
            UMEffectItem *item = [[UMEffectItem alloc] init];
            item.xmlFileName = file;
            
            NSRegularExpression *idRegex = [NSRegularExpression regularExpressionWithPattern:@"id=[\"']([^\"']+)[\"']" options:0 error:nil];
            NSTextCheckingResult *idMatch = [idRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
            item.effectId = idMatch ? [content substringWithRange:[idMatch rangeAtIndex:1]] : file.stringByDeletingPathExtension;
            
            NSRegularExpression *nameRegex = [NSRegularExpression regularExpressionWithPattern:@"name=[\"']([^\"']+)[\"']" options:0 error:nil];
            NSTextCheckingResult *nameMatch = [nameRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
            item.name = nameMatch ? [content substringWithRange:[nameMatch rangeAtIndex:1]] : file.stringByDeletingPathExtension;
            
            NSRegularExpression *catRegex = [NSRegularExpression regularExpressionWithPattern:@"category=[\"']([^\"']+)[\"']" options:0 error:nil];
            NSTextCheckingResult *catMatch = [catRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
            item.category = catMatch ? [content substringWithRange:[catMatch rangeAtIndex:1]] : @"other";
            
            NSRegularExpression *tagRegex = [NSRegularExpression regularExpressionWithPattern:@"tags=[\"']([^\"']+)[\"']" options:0 error:nil];
            NSTextCheckingResult *tagMatch = [tagRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
            item.tags = tagMatch ? [content substringWithRange:[tagMatch rangeAtIndex:1]] : @"";
            
            item.isSupportedOnMetal = YES;
            [self.effects addObject:item];
            
            NSMutableArray *arr = catDict[item.category];
            if (!arr) {
                arr = [NSMutableArray array];
                catDict[item.category] = arr;
            }
            [arr addObject:item];
        }
        
        self.categorizedEffects = catDict;
        self.isLoaded = YES;
    }
}

- (NSArray<UMEffectItem *> *)searchEffectsWithQuery:(NSString *)query {
    if (!self.isLoaded) [self loadAllUltraEffects];
    if (!query || query.length == 0) return self.effects;
    
    NSString *clean = query.lowercaseString;
    NSMutableArray *results = [NSMutableArray array];
    for (UMEffectItem *item in self.effects) {
        if ([item.name.lowercaseString containsString:clean] ||
            [item.category.lowercaseString containsString:clean] ||
            [item.tags.lowercaseString containsString:clean] ||
            [item.effectId.lowercaseString containsString:clean]) {
            [results addObject:item];
        }
    }
    return results;
}

- (UMEffectItem *)effectById:(NSString *)effectId {
    if (!self.isLoaded) [self loadAllUltraEffects];
    if (!effectId) return nil;
    for (UMEffectItem *it in self.effects) {
        if ([it.effectId isEqualToString:effectId]) return it;
    }
    return nil;
}

@end

#pragma mark - =========================================================
#pragma mark 3. UMAudioSyncEngine & UMWaveformGenerator
#pragma mark - =========================================================

@interface UMAudioSyncEngine : NSObject
@property (nonatomic, assign) CMTime masterTime;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, weak) id currentSceneComp;
+ (instancetype)sharedEngine;
- (void)synchronizePlayheadWithCMTime:(CMTime)time;
- (void)handleSeekToSeconds:(double)seconds;
@end

@implementation UMAudioSyncEngine

+ (instancetype)sharedEngine {
    static UMAudioSyncEngine *engine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engine = [[self alloc] init];
        engine.masterTime = kCMTimeZero;
    });
    return engine;
}

- (void)synchronizePlayheadWithCMTime:(CMTime)time {
    self.masterTime = time;
}

- (void)handleSeekToSeconds:(double)seconds {
    self.masterTime = CMTimeMakeWithSeconds(seconds, 600);
}

@end

@interface UMWaveformGenerator : NSObject
@property (nonatomic, strong) NSCache<NSString *, NSArray<NSNumber *> *> *waveformCache;
+ (instancetype)sharedGenerator;
- (void)generateWaveformForAudioURL:(NSURL *)url samplesCount:(NSUInteger)samplesCount completion:(void (^)(NSArray<NSNumber *> *samples))completion;
@end

@implementation UMWaveformGenerator

+ (instancetype)sharedGenerator {
    static UMWaveformGenerator *gen = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gen = [[self alloc] init];
        gen.waveformCache = [[NSCache alloc] init];
        gen.waveformCache.countLimit = 100;
    });
    return gen;
}

- (void)generateWaveformForAudioURL:(NSURL *)url samplesCount:(NSUInteger)samplesCount completion:(void (^)(NSArray<NSNumber *> *samples))completion {
    if (!url) {
        if (completion) completion(@[]);
        return;
    }
    
    NSString *cacheKey = [NSString stringWithFormat:@"%@_%lu", url.path, (unsigned long)samplesCount];
    NSArray<NSNumber *> *cached = [self.waveformCache objectForKey:cacheKey];
    if (cached) {
        if (completion) completion(cached);
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        NSError *error = nil;
        AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
        if (error || !reader) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(@[]); });
            return;
        }
        
        NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeAudio];
        if (tracks.count == 0) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(@[]); });
            return;
        }
        
        NSDictionary *outputSettings = @{
            AVFormatIDKey: @(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: @16,
            AVLinearPCMIsBigEndianKey: @NO,
            AVLinearPCMIsFloatKey: @NO,
            AVLinearPCMIsNonInterleaved: @NO
        };
        
        AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:tracks.firstObject outputSettings:outputSettings];
        [reader addOutput:output];
        [reader startReading];
        
        NSMutableArray<NSNumber *> *resultSamples = [NSMutableArray arrayWithCapacity:samplesCount];
        NSMutableData *fullAudioData = [NSMutableData data];
        
        while (reader.status == AVAssetReaderStatusReading) {
            CMSampleBufferRef sampleBuffer = [output copyNextSampleBuffer];
            if (sampleBuffer) {
                CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
                size_t length = CMBlockBufferGetDataLength(blockBuffer);
                NSMutableData *data = [NSMutableData dataWithLength:length];
                CMBlockBufferCopyDataBytes(blockBuffer, 0, length, data.mutableBytes);
                [fullAudioData appendData:data];
                CMSampleBufferInvalidate(sampleBuffer);
                CFRelease(sampleBuffer);
            }
        }
        
        NSUInteger totalSamples = fullAudioData.length / sizeof(int16_t);
        if (totalSamples == 0) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(@[]); });
            return;
        }
        
        const int16_t *bytes = (const int16_t *)fullAudioData.bytes;
        NSUInteger step = MAX(1, totalSamples / samplesCount);
        
        for (NSUInteger i = 0; i < samplesCount; i++) {
            NSUInteger start = i * step;
            if (start >= totalSamples) break;
            
            int16_t maxVal = 0;
            for (NSUInteger j = 0; j < step && (start + j) < totalSamples; j++) {
                int16_t val = abs(bytes[start + j]);
                if (val > maxVal) maxVal = val;
            }
            float normalized = (float)maxVal / 32767.0f;
            [resultSamples addObject:@(normalized)];
        }
        
        [self.waveformCache setObject:resultSamples forKey:cacheKey];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(resultSamples);
            });
        }
    });
}

@end

#pragma mark - =========================================================
#pragma mark 4. Safe Auto-Save & Lyrics Capsule Bar
#pragma mark - =========================================================

static void AMNotifyUser(NSString *title, NSString *body) {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title ?: @"Ultra Motion Pro";
    content.body = body ?: @"Xuất video hoàn tất! Đã tự động lưu vào Cuộn Camera.";
    content.sound = [UNNotificationSound defaultSound];

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
                                                                            content:content
                                                                            trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                                  withCompletionHandler:nil];
}

static BOOL AMIsAutoSaveEnabled(void) {
    NSNumber *val = [[NSUserDefaults standardUserDefaults] objectForKey:@"AM_AutoSaveToPhotos"];
    if (val == nil) return YES;
    return [val boolValue];
}

static void AMSetAutoSaveEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"AM_AutoSaveToPhotos"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL hasSavedRecentVideo = NO;

static void AMAutoSaveVideoAtPath(NSString *filePath) {
    if (!AMIsAutoSaveEnabled()) return;
    if (!filePath || filePath.length == 0) return;
    if (hasSavedRecentVideo) return;

    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) return;
    if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(filePath)) return;

    hasSavedRecentVideo = YES;
    UISaveVideoAtPathToSavedPhotosAlbum(filePath, nil, NULL, NULL);
    AMNotifyUser(@"Ultra Motion Pro", @"Video đã được tự động lưu vào Cuộn Camera thành công!");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        hasSavedRecentVideo = NO;
    });
}

@interface AMLyricsEngine : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *lyricsLines;
@property (nonatomic, assign) NSUInteger currentIndex;
+ (instancetype)sharedEngine;
- (void)loadRawLyrics:(NSString *)rawText;
- (NSString *)currentLyric;
- (NSString *)advanceLyric;
- (NSString *)previousLyric;
- (void)clear;
@end

@implementation AMLyricsEngine

+ (instancetype)sharedEngine {
    static AMLyricsEngine *engine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engine = [[self alloc] init];
        engine.lyricsLines = [NSMutableArray array];
        engine.currentIndex = 0;
    });
    return engine;
}

- (void)loadRawLyrics:(NSString *)rawText {
    [self.lyricsLines removeAllObjects];
    self.currentIndex = 0;
    if (!rawText || rawText.length == 0) return;

    NSArray *lines = [rawText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [self.lyricsLines addObject:trimmed];
        }
    }
}

- (NSString *)currentLyric {
    if (self.lyricsLines.count == 0 || self.currentIndex >= self.lyricsLines.count) return @"";
    return self.lyricsLines[self.currentIndex];
}

- (NSString *)advanceLyric {
    if (self.lyricsLines.count == 0) return @"";
    if (self.currentIndex + 1 < self.lyricsLines.count) {
        self.currentIndex++;
    }
    return [self currentLyric];
}

- (NSString *)previousLyric {
    if (self.lyricsLines.count == 0) return @"";
    if (self.currentIndex > 0) {
        self.currentIndex--;
    }
    return [self currentLyric];
}

- (void)clear {
    [self.lyricsLines removeAllObjects];
    self.currentIndex = 0;
}

@end

#pragma mark - =========================================================
#pragma mark 5. Defensive Anti-Crack & Ad Shields (Safe Swizzling)
#pragma mark - =========================================================

static BOOL AMIsForbiddenString(NSString *str) {
    if (!str || str.length == 0) return NO;
    NSString *low = str.lowercaseString;
    return [low containsString:@"telegram"] ||
           [low containsString:@"t.me"] ||
           [low containsString:@"tg://"] ||
           [low containsString:@"blatant"] ||
           [low containsString:@"fastdecrypt"] ||
           [low containsString:@"crack"] ||
           [low containsString:@"unlocked by"];
}

// Swizzle UIViewController presentViewController safely
@interface UIViewController (UMSafePresent)
- (void)um_presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion;
@end

@implementation UIViewController (UMSafePresent)

- (void)um_presentViewController:(UIViewController *)vc animated:(BOOL)flag completion:(void (^)(void))completion {
    if (vc) {
        NSString *className = NSStringFromClass([vc class]);

        if ([vc isKindOfClass:[UIAlertController class]]) {
            UIAlertController *alert = (UIAlertController *)vc;
            NSString *title = alert.title ?: @"";
            NSString *message = alert.message ?: @"";
            NSString *combined = [NSString stringWithFormat:@"%@ %@", title, message];

            if (AMIsForbiddenString(combined)) {
                if (completion) completion();
                return;
            }
        }

        if ([className containsString:@"GAD"] || 
            [className containsString:@"IronSource"] || 
            [className containsString:@"Vungle"] || 
            [className containsString:@"StoreSubscription"] || 
            [className containsString:@"StorePromo"] || 
            [className containsString:@"StoreAnnualSale"] || 
            [className containsString:@"StoreTrial"] || 
            [className containsString:@"TrialEndSoon"] || 
            [className containsString:@"WatermarkPopup"] ||
            [className containsString:@"SKStoreProductViewController"]) {
            if (completion) completion();
            return;
        }
    }
    [self um_presentViewController:vc animated:flag completion:completion];
}

@end

// Swizzle UIApplication openURL safely
@interface UIApplication (UMSafeOpenURL)
- (BOOL)um_openURL:(NSURL *)url;
- (void)um_openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey,id> *)options completionHandler:(void (^)(BOOL))completion;
@end

@implementation UIApplication (UMSafeOpenURL)

- (BOOL)um_openURL:(NSURL *)url {
    if (url && AMIsForbiddenString(url.absoluteString)) return NO;
    return [self um_openURL:url];
}

- (void)um_openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey,id> *)options completionHandler:(void (^)(BOOL))completion {
    if (url && AMIsForbiddenString(url.absoluteString)) {
        if (completion) completion(NO);
        return;
    }
    [self um_openURL:url options:options completionHandler:completion];
}

@end

#pragma mark - =========================================================
#pragma mark 6. Safe Startup Constructor (No PAC / No Early XPC / No Early UI)
#pragma mark - =========================================================

static void safeSwizzle(Class cls, SEL origSel, SEL swizzledSel) {
    if (!cls) return;
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method swizzledMethod = class_getInstanceMethod(cls, swizzledSel);
    if (!origMethod || !swizzledMethod) return;

    BOOL didAdd = class_addMethod(cls, origSel, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
    if (didAdd) {
        class_replaceMethod(cls, swizzledSel, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, swizzledMethod);
    }
}

__attribute__((constructor)) static void initUltraMotionMod() {
    // 1. Safe Method Swizzling for Ads/Popups
    Class vcClass = [UIViewController class];
    safeSwizzle(vcClass, @selector(presentViewController:animated:completion:), @selector(um_presentViewController:animated:completion:));

    Class appClass = [UIApplication class];
    safeSwizzle(appClass, @selector(openURL:), @selector(um_openURL:));
    safeSwizzle(appClass, @selector(openURL:options:completionHandler:), @selector(um_openURL:options:completionHandler:));

    // 2. Defer heavy services until application finishes launching
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        // Pre-load effect registry in background thread
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            [[UMEffectRegistry sharedRegistry] loadAllUltraEffects];
        });
        
        NSLog(@"[UltraMotion] 🚀 ULTRA MOTION iOS 6.0.3 READY & RUNNING STABLY!");
    }];
}
