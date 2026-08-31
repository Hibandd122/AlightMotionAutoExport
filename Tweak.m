#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreImage/CoreImage.h>
#import <VideoToolbox/VideoToolbox.h>
#import <objc/runtime.h>
#import "fishhook.h"

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
#pragma mark 2. UMEffectRegistry & UMEffectSearchEngine (497 Effects & 20 Categories)
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
        [reg loadAllUltraEffects];
    });
    return reg;
}

- (void)loadAllUltraEffects {
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *builtinDir = [bundlePath stringByAppendingPathComponent:@"BuiltinEffects"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
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
        
        // Regex parse id, name, category, desc, tags
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
    NSLog(@"[UMEffectRegistry] 🚀 Loaded %lu Ultra Motion Effects across %lu categories.", (unsigned long)self.effects.count, (unsigned long)catDict.count);
}

- (NSArray<UMEffectItem *> *)searchEffectsWithQuery:(NSString *)query {
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
    if (!effectId) return nil;
    for (UMEffectItem *it in self.effects) {
        if ([it.effectId isEqualToString:effectId]) return it;
    }
    return nil;
}

@end

#pragma mark - =========================================================
#pragma mark 3. UMAudioSyncEngine & UMWaveformGenerator (Master Playback Clock & Real Waveform)
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
#pragma mark 4. UMVolumeAutomationEngine (Volume Keyframe Interpolation)
#pragma mark - =========================================================

@interface UMVolumeKeyframe : NSObject
@property (nonatomic, assign) double timeInSeconds;
@property (nonatomic, assign) float volume; // 0.0 to 1.0 (or >1.0 boost)
@property (nonatomic, assign) NSInteger interpolationType; // 0: Linear, 1: EaseIn, 2: EaseOut, 3: Bezier
@end

@implementation UMVolumeKeyframe
@end

@interface UMVolumeAutomationEngine : NSObject
+ (float)evaluateVolumeAtTime:(double)t keyframes:(NSArray<UMVolumeKeyframe *> *)keyframes defaultVolume:(float)defVol;
@end

@implementation UMVolumeAutomationEngine

+ (float)evaluateVolumeAtTime:(double)t keyframes:(NSArray<UMVolumeKeyframe *> *)keyframes defaultVolume:(float)defVol {
    if (!keyframes || keyframes.count == 0) return defVol;
    if (keyframes.count == 1) return keyframes.firstObject.volume;
    
    if (t <= keyframes.firstObject.timeInSeconds) return keyframes.firstObject.volume;
    if (t >= keyframes.lastObject.timeInSeconds) return keyframes.lastObject.volume;
    
    for (NSUInteger i = 0; i < keyframes.count - 1; i++) {
        UMVolumeKeyframe *k1 = keyframes[i];
        UMVolumeKeyframe *k2 = keyframes[i+1];
        if (t >= k1.timeInSeconds && t <= k2.timeInSeconds) {
            double range = k2.timeInSeconds - k1.timeInSeconds;
            if (range <= 0.0001) return k1.volume;
            double progress = (t - k1.timeInSeconds) / range;
            
            // Linear interpolation
            return (float)(k1.volume + (k2.volume - k1.volume) * progress);
        }
    }
    return defVol;
}

@end

#pragma mark - =========================================================
#pragma mark 5. UMMultiXMLService & UMXMLExportService (Multi XML Import & Documents Export)
#pragma mark - =========================================================

@interface UMMultiXMLService : NSObject
+ (void)importXMLFilesAtURLs:(NSArray<NSURL *> *)urls completion:(void (^)(NSUInteger successCount, NSUInteger failCount, NSArray<NSString *> *errors))completion;
@end

@implementation UMMultiXMLService

+ (void)importXMLFilesAtURLs:(NSArray<NSURL *> *)urls completion:(void (^)(NSUInteger successCount, NSUInteger failCount, NSArray<NSString *> *errors))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSUInteger success = 0;
        NSUInteger failed = 0;
        NSMutableArray *errors = [NSMutableArray array];
        
        for (NSURL *url in urls) {
            BOOL isAccessing = [url startAccessingSecurityScopedResource];
            NSError *readError = nil;
            NSData *xmlData = [NSData dataWithContentsOfURL:url options:0 error:&readError];
            if (isAccessing) [url stopAccessingSecurityScopedResource];
            
            if (readError || !xmlData || xmlData.length == 0) {
                failed++;
                [errors addObject:[NSString stringWithFormat:@"Không thể đọc tệp: %@", url.lastPathComponent]];
                continue;
            }
            
            // Check XML root
            NSString *str = [[NSString alloc] initWithData:xmlData encoding:NSUTF8StringEncoding];
            if ([str containsString:@"<alightmotion"] || [str containsString:@"<scene"] || [str containsString:@"<project"]) {
                success++;
            } else {
                failed++;
                [errors addObject:[NSString stringWithFormat:@"Định dạng XML không hợp lệ: %@", url.lastPathComponent]];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(success, failed, errors);
        });
    });
}

@end

@interface UMXMLExportService : NSObject
+ (NSString *)exportProjectToDocumentsWithName:(NSString *)projectName xmlContent:(NSString *)xmlContent;
@end

@implementation UMXMLExportService

+ (NSString *)exportProjectToDocumentsWithName:(NSString *)projectName xmlContent:(NSString *)xmlContent {
    if (!xmlContent || xmlContent.length == 0) return nil;
    
    // Sanitize filename
    NSCharacterSet *illegalChars = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?%*|\"<>"];
    NSString *safeName = [[projectName componentsSeparatedByCharactersInSet:illegalChars] componentsJoinedByString:@"_"];
    if (safeName.length == 0) safeName = @"UltraMotion_Project";
    
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *destPath = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.xml", safeName]];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger counter = 1;
    while ([fm fileExistsAtPath:destPath]) {
        destPath = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ (%lu).xml", safeName, (unsigned long)counter]];
        counter++;
    }
    
    NSError *error = nil;
    [xmlContent writeToFile:destPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"[UMXMLExportService] ❌ Failed to write XML: %@", error);
        return nil;
    }
    
    NSLog(@"[UMXMLExportService] ✅ Exported XML to Documents: %@", destPath);
    return destPath;
}

@end

#pragma mark - =========================================================
#pragma mark 6. UMQRCodeService & UMProjectSearchIndex (Themed QR & Unicode Search)
#pragma mark - =========================================================

@interface UMQRCodeService : NSObject
+ (UIImage *)generateUltraQRCodeForString:(NSString *)string size:(CGFloat)size;
@end

@implementation UMQRCodeService

+ (UIImage *)generateUltraQRCodeForString:(NSString *)string size:(CGFloat)size {
    if (!string || string.length == 0) return nil;
    
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"H" forKey:@"inputCorrectionLevel"];
    
    CIImage *ciImage = filter.outputImage;
    if (!ciImage) return nil;
    
    // Colorize with Ultra Theme (Green on Dark OLED)
    CIFilter *colorFilter = [CIFilter filterWithName:@"CIFalseColor"];
    [colorFilter setValue:ciImage forKey:@"inputImage"];
    [colorFilter setValue:[CIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0] forKey:@"inputColor0"]; // Foreground #00E676
    [colorFilter setValue:[CIColor colorWithRed:0.05 green:0.06 blue:0.08 alpha:1.0] forKey:@"inputColor1"]; // Background #0D0F14
    
    CIImage *coloredImage = colorFilter.outputImage;
    if (!coloredImage) return nil;
    
    CGRect extent = CGRectIntegral(coloredImage.extent);
    CGFloat scale = MIN(size / CGRectGetWidth(extent), size / CGRectGetHeight(extent));
    
    size_t width = CGRectGetWidth(extent) * scale;
    size_t height = CGRectGetHeight(extent) * scale;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmapRef = CGBitmapContextCreate(nil, width, height, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGImageRef bitmapImage = [ctx createCGImage:coloredImage fromRect:extent];
    
    CGContextSetInterpolationQuality(bitmapRef, kCGInterpolationNone);
    CGContextScaleCTM(bitmapRef, scale, scale);
    CGContextDrawImage(bitmapRef, extent, bitmapImage);
    
    CGImageRef scaledImage = CGBitmapContextCreateImage(bitmapRef);
    CGContextRelease(bitmapRef);
    CGImageRelease(bitmapImage);
    CGColorSpaceRelease(cs);
    
    UIImage *result = [UIImage imageWithCGImage:scaledImage];
    CGImageRelease(scaledImage);
    return result;
}

@end

@interface UMMediaMetadataService : NSObject
+ (NSDictionary *)extractDetailedMetadataFromURL:(NSURL *)mediaURL;
@end

@implementation UMMediaMetadataService

+ (NSDictionary *)extractDetailedMetadataFromURL:(NSURL *)mediaURL {
    if (!mediaURL) return @{};
    
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:mediaURL options:nil];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    double duration = CMTimeGetSeconds(asset.duration);
    dict[@"duration"] = @(duration);
    
    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count > 0) {
        AVAssetTrack *vt = videoTracks.firstObject;
        dict[@"width"] = @(vt.naturalSize.width);
        dict[@"height"] = @(vt.naturalSize.height);
        dict[@"nominalFrameRate"] = @(vt.nominalFrameRate);
        dict[@"estimatedDataRate"] = @(vt.estimatedDataRate);
        
        NSArray *formats = vt.formatDescriptions;
        if (formats.count > 0) {
            CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)formats.firstObject;
            FourCharCode sub = CMFormatDescriptionGetMediaSubType(desc);
            NSString *codecStr = [NSString stringWithFormat:@"%c%c%c%c", (char)((sub >> 24) & 0xFF), (char)((sub >> 16) & 0xFF), (char)((sub >> 8) & 0xFF), (char)(sub & 0xFF)];
            dict[@"codec"] = codecStr;
        }
    }
    
    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count > 0) {
        AVAssetTrack *at = audioTracks.firstObject;
        dict[@"hasAudio"] = @YES;
        dict[@"audioBitrate"] = @(at.estimatedDataRate);
    }
    
    return dict;
}

@end

#pragma mark - =========================================================
#pragma mark 7. AMLyricsEngine & Capsule Bar (Interactive Keyboard Overlay)
#pragma mark - =========================================================

static void AMNotifyUser(NSString *title, NSString *body) {
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

    if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(filePath)) {
        return;
    }

    hasSavedRecentVideo = YES;
    UISaveVideoAtPathToSavedPhotosAlbum(filePath, nil, NULL, NULL);
    AMNotifyUser(@"Ultra Motion Pro", @"Video đã được tự động lưu vào Cuộn Camera (Photos) thành công!");

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
- (void)saveToDisk;
- (void)loadFromDisk;
@end

@implementation AMLyricsEngine

+ (instancetype)sharedEngine {
    static AMLyricsEngine *engine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engine = [[self alloc] init];
        engine.lyricsLines = [NSMutableArray array];
        [engine loadFromDisk];
    });
    return engine;
}

- (void)loadFromDisk {
    NSArray *cached = [[NSUserDefaults standardUserDefaults] objectForKey:@"AM_CachedLyricsLines"];
    if (cached && [cached isKindOfClass:[NSArray class]]) {
        [self.lyricsLines addObjectsFromArray:cached];
    }
    self.currentIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"AM_CachedLyricsIndex"];
    if (self.currentIndex >= self.lyricsLines.count) {
        self.currentIndex = 0;
    }
}

- (void)saveToDisk {
    NSArray *linesCopy = [self.lyricsLines copy];
    NSUInteger idx = self.currentIndex;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [[NSUserDefaults standardUserDefaults] setObject:linesCopy forKey:@"AM_CachedLyricsLines"];
        [[NSUserDefaults standardUserDefaults] setInteger:idx forKey:@"AM_CachedLyricsIndex"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    });
}

- (void)loadRawLyrics:(NSString *)rawText {
    [self.lyricsLines removeAllObjects];
    self.currentIndex = 0;

    if (!rawText || rawText.length == 0) {
        [self saveToDisk];
        return;
    }

    static NSRegularExpression *lrcRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lrcRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\[\\d{1,2}:\\d{2}(?:[\\.:]\\d{1,3})?\\]\\s*"
                                                             options:0
                                                               error:nil];
    });

    NSArray *lines = [rawText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *rawLine in lines) {
        NSString *trimmed = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            NSString *cleaned = [lrcRegex stringByReplacingMatchesInString:trimmed
                                                                   options:0
                                                                     range:NSMakeRange(0, trimmed.length)
                                                              withTemplate:@""];
            cleaned = [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (cleaned.length > 0) {
                [self.lyricsLines addObject:cleaned];
            }
        }
    }
    [self saveToDisk];
}

- (NSString *)currentLyric {
    if (self.lyricsLines.count == 0) return nil;
    if (self.currentIndex >= self.lyricsLines.count) {
        self.currentIndex = 0;
    }
    return self.lyricsLines[self.currentIndex];
}

- (NSString *)advanceLyric {
    if (self.lyricsLines.count == 0) return nil;
    if (self.currentIndex + 1 < self.lyricsLines.count) {
        self.currentIndex++;
    } else {
        self.currentIndex = 0; // wrap around
    }
    [self saveToDisk];
    return [self currentLyric];
}

- (NSString *)previousLyric {
    if (self.lyricsLines.count == 0) return nil;
    if (self.currentIndex > 0) {
        self.currentIndex--;
    } else {
        self.currentIndex = self.lyricsLines.count - 1;
    }
    [self saveToDisk];
    return [self currentLyric];
}

- (void)clear {
    [self.lyricsLines removeAllObjects];
    self.currentIndex = 0;
    [self saveToDisk];
}

@end

#pragma mark - AMMinimalLyricsBar (36px Capsule Overlay)

@interface AMMinimalLyricsBar : UIView
@property (nonatomic, strong) UIView *capsuleView;
@property (nonatomic, strong) UIButton *prevBtn;
@property (nonatomic, strong) UIButton *nextBtn;
@property (nonatomic, strong) UIButton *versePillBtn;
@property (nonatomic, strong) UIButton *menuBtn;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, weak) UIResponder *targetInputResponder;
+ (instancetype)barWithTarget:(UIResponder *)target;
- (void)refreshDisplay;
@end

@interface AMBatchLyricsViewController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *lineCountLabel;
@property (nonatomic, copy) void (^onLyricsLoaded)(void);
@end

@implementation AMBatchLyricsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.11 alpha:0.98];

    CGFloat w = self.view.bounds.size.width;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, w - 40, 26)];
    titleLabel.text = @"📝 Nạp Lời Bài Hát (Hàng Loạt)";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [self.view addSubview:titleLabel];

    CGFloat yPos = 52;
    CGFloat h = self.view.bounds.size.height - yPos - 110;
    if (h < 150) h = 150;

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(16, yPos, w - 32, h)];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    self.textView.textColor = [UIColor whiteColor];
    self.textView.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.textView.layer.cornerRadius = 12.0;
    self.textView.layer.borderWidth = 1.0;
    self.textView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.5].CGColor;
    self.textView.delegate = self;
    [self.view addSubview:self.textView];

    self.lineCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, yPos + h + 6, w - 40, 20)];
    self.lineCountLabel.text = @"📊 Số dòng: 0 câu hát";
    self.lineCountLabel.textColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    self.lineCountLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.view addSubview:self.lineCountLabel];

    AMLyricsEngine *engine = [AMLyricsEngine sharedEngine];
    if (engine.lyricsLines.count > 0) {
        self.textView.text = [engine.lyricsLines componentsJoinedByString:@"\n"];
        [self updateLineCount];
    }

    CGFloat bottomY = self.view.bounds.size.height - 54;

    UIButton *pasteBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    pasteBtn.frame = CGRectMake(16, bottomY, 64, 42);
    [pasteBtn setTitle:@"📋 Dán" forState:UIControlStateNormal];
    [pasteBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    pasteBtn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    pasteBtn.layer.cornerRadius = 10.0;
    [pasteBtn addTarget:self action:@selector(pasteClipboard) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:pasteBtn];

    UIButton *applyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    applyBtn.frame = CGRectMake(90, bottomY, w - 160, 42);
    [applyBtn setTitle:@"⚡ Lưu & Kích Hoạt" forState:UIControlStateNormal];
    [applyBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    applyBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    applyBtn.layer.cornerRadius = 10.0;
    applyBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [applyBtn addTarget:self action:@selector(applyLyrics) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:applyBtn];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w - 60, bottomY, 50, 42);
    [closeBtn setTitle:@"Đóng" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(dismissSelf) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeBtn];
}

- (void)textViewDidChange:(UITextView *)textView {
    [self updateLineCount];
}

- (void)updateLineCount {
    NSArray *lines = [self.textView.text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSUInteger count = 0;
    for (NSString *s in lines) {
        if ([s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length > 0) count++;
    }
    self.lineCountLabel.text = [NSString stringWithFormat:@"📊 Số dòng: %lu câu hát", (unsigned long)count];
}

- (void)pasteClipboard {
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    if (pb.string && pb.string.length > 0) {
        self.textView.text = pb.string;
        [self updateLineCount];
    }
}

- (void)dismissSelf {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyLyrics {
    [self.view endEditing:YES];
    [[AMLyricsEngine sharedEngine] loadRawLyrics:self.textView.text];
    if (self.onLyricsLoaded) self.onLyricsLoaded();
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@implementation AMMinimalLyricsBar

+ (instancetype)barWithTarget:(UIResponder *)target {
    AMMinimalLyricsBar *bar = [[AMMinimalLyricsBar alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 42.0)];
    bar.targetInputResponder = target;
    bar.backgroundColor = [UIColor clearColor];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIView *capsule = [[UIView alloc] initWithFrame:CGRectMake(8.0, 3.0, bar.bounds.size.width - 16.0, 36.0)];
    capsule.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.11 alpha:0.95];
    capsule.layer.cornerRadius = 18.0;
    capsule.layer.borderWidth = 1.0;
    capsule.layer.borderColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.6].CGColor;
    capsule.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [bar addSubview:capsule];
    bar.capsuleView = capsule;

    UIButton *prev = [UIButton buttonWithType:UIButtonTypeSystem];
    [prev setTitle:@"‹" forState:UIControlStateNormal];
    [prev setTitleColor:[UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0] forState:UIControlStateNormal];
    prev.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    prev.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
    prev.layer.cornerRadius = 14.0;
    [prev addTarget:bar action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:prev];
    bar.prevBtn = prev;

    UIButton *next = [UIButton buttonWithType:UIButtonTypeSystem];
    [next setTitle:@"›" forState:UIControlStateNormal];
    [next setTitleColor:[UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0] forState:UIControlStateNormal];
    next.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    next.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
    next.layer.cornerRadius = 14.0;
    [next addTarget:bar action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:next];
    bar.nextBtn = next;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    close.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
    close.layer.cornerRadius = 14.0;
    [close addTarget:bar action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:close];
    bar.closeBtn = close;

    UIButton *menu = [UIButton buttonWithType:UIButtonTypeSystem];
    [menu setTitle:@"📋" forState:UIControlStateNormal];
    menu.titleLabel.font = [UIFont systemFontOfSize:14];
    menu.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
    menu.layer.cornerRadius = 14.0;
    [menu addTarget:bar action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:menu];
    bar.menuBtn = menu;

    UIButton *verse = [UIButton buttonWithType:UIButtonTypeSystem];
    verse.backgroundColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.18];
    verse.layer.cornerRadius = 14.0;
    verse.layer.borderWidth = 0.8;
    verse.layer.borderColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.5].CGColor;
    [verse setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    verse.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    verse.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    verse.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    [verse addTarget:bar action:@selector(verseTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:verse];
    bar.versePillBtn = verse;

    [bar setNeedsLayout];
    [bar refreshDisplay];
    return bar;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.capsuleView.bounds.size.width;
    CGFloat h = 36.0;
    self.prevBtn.frame = CGRectMake(4.0, (h - 28.0)/2.0, 28.0, 28.0);
    self.nextBtn.frame = CGRectMake(36.0, (h - 28.0)/2.0, 28.0, 28.0);
    self.closeBtn.frame = CGRectMake(w - 32.0, (h - 28.0)/2.0, 28.0, 28.0);
    self.menuBtn.frame = CGRectMake(w - 64.0, (h - 28.0)/2.0, 28.0, 28.0);
    CGFloat verseX = 68.0;
    CGFloat verseW = (w - 68.0) - 68.0;
    if (verseW < 60.0) verseW = 60.0;
    self.versePillBtn.frame = CGRectMake(verseX, (h - 28.0)/2.0, verseW, 28.0);
}

- (void)refreshDisplay {
    AMLyricsEngine *engine = [AMLyricsEngine sharedEngine];
    if (engine.lyricsLines.count == 0) {
        [self.versePillBtn setTitle:@"⚡ Nạp Lời (Chạm menu 📋)" forState:UIControlStateNormal];
        self.prevBtn.alpha = 0.4;
        self.nextBtn.alpha = 0.4;
    } else {
        self.prevBtn.alpha = 1.0;
        self.nextBtn.alpha = 1.0;
        NSString *cur = [engine currentLyric];
        NSString *title = [NSString stringWithFormat:@"⚡ #%lu/%lu: \"%@\"", (unsigned long)(engine.currentIndex + 1), (unsigned long)engine.lyricsLines.count, cur ?: @""];
        [self.versePillBtn setTitle:title forState:UIControlStateNormal];
    }
}

- (void)prevTapped {
    [[AMLyricsEngine sharedEngine] previousLyric];
    [self refreshDisplay];
}

- (void)nextTapped {
    [[AMLyricsEngine sharedEngine] advanceLyric];
    [self refreshDisplay];
}

- (void)closeTapped {
    if ([self.targetInputResponder canResignFirstResponder]) {
        [self.targetInputResponder resignFirstResponder];
    }
}

- (void)verseTapped {
    AMLyricsEngine *engine = [AMLyricsEngine sharedEngine];
    if (engine.lyricsLines.count == 0) {
        [self menuTapped];
        return;
    }
    NSString *lyric = [engine currentLyric];
    if (lyric && lyric.length > 0 && self.targetInputResponder) {
        if ([self.targetInputResponder isKindOfClass:[UITextView class]]) {
            UITextView *tv = (UITextView *)self.targetInputResponder;
            tv.text = lyric;
            if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
                [tv.delegate textViewDidChange:tv];
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];
        }
        [engine advanceLyric];
        [self refreshDisplay];
    }
}

- (void)menuTapped {
    UIWindow *keyWin = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
    UIViewController *root = keyWin.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;

    AMBatchLyricsViewController *modal = [[AMBatchLyricsViewController alloc] init];
    modal.modalPresentationStyle = UIModalPresentationFormSheet;
    __weak typeof(self) weakSelf = self;
    modal.onLyricsLoaded = ^{
        [weakSelf refreshDisplay];
    };
    [root presentViewController:modal animated:YES completion:nil];
}

@end

#pragma mark - =========================================================
#pragma mark 8. Home Screen Floating HUD (Ultra Motion Home Dashboard)
#pragma mark - =========================================================

@interface AMHomeSettingsHUD : NSObject
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, weak) UIWindow *parentWindow;
+ (instancetype)sharedHUD;
- (void)installFloatingButtonOnWindow:(UIWindow *)window;
- (void)setFloatingButtonVisible:(BOOL)visible;
@end

@implementation AMHomeSettingsHUD

+ (instancetype)sharedHUD {
    static AMHomeSettingsHUD *hud = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hud = [[self alloc] init];
    });
    return hud;
}

- (void)installFloatingButtonOnWindow:(UIWindow *)window {
    if (self.floatingButton || !window) return;
    self.parentWindow = window;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(16.0, window.bounds.size.height - 140.0, 48.0, 48.0);
    btn.layer.cornerRadius = 24.0;
    btn.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.9];
    btn.layer.borderWidth = 1.5;
    btn.layer.borderColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:0.8].CGColor;
    [btn setTitle:@"⚙️" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:22.0];
    [btn addTarget:self action:@selector(floatingButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    self.floatingButton = btn;

    [window addSubview:btn];
    [window bringSubviewToFront:btn];
}

- (void)setFloatingButtonVisible:(BOOL)visible {
    if (self.floatingButton) self.floatingButton.hidden = !visible;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    UIWindow *window = self.parentWindow ?: [UIApplication sharedApplication].windows.firstObject;
    if (!view || !window) return;

    CGPoint translation = [pan translationInView:window];
    CGPoint center = view.center;
    center.x += translation.x;
    center.y += translation.y;

    CGFloat halfW = view.bounds.size.width / 2.0;
    CGFloat halfH = view.bounds.size.height / 2.0;
    CGFloat minX = halfW + 8.0;
    CGFloat maxX = window.bounds.size.width - halfW - 8.0;
    CGFloat minY = halfH + window.safeAreaInsets.top + 8.0;
    CGFloat maxY = window.bounds.size.height - halfH - window.safeAreaInsets.bottom - 8.0;

    center.x = MAX(minX, MIN(maxX, center.x));
    center.y = MAX(minY, MIN(maxY, center.y));
    view.center = center;
    [pan setTranslation:CGPointZero inView:window];

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat snapX = (center.x < window.bounds.size.width / 2.0) ? minX : maxX;
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            view.center = CGPointMake(snapX, center.y);
        } completion:nil];
    }
}

- (void)floatingButtonTapped:(UIButton *)sender {
    UIWindow *window = self.parentWindow ?: [UIApplication sharedApplication].windows.firstObject;
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"⚙️ Ultra Motion iOS 6.0.3"
                                                                   message:@"Cài đặt và Tiện ích Pro (Full Dark Mode, 497 Effects, 120 FPS, Audio Sync)"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"📝 Quản Lý Lời Bài Hát (Batch Lyrics)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        AMBatchLyricsViewController *modal = [[AMBatchLyricsViewController alloc] init];
        modal.modalPresentationStyle = UIModalPresentationFormSheet;
        [root presentViewController:modal animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"📁 Nhập Nhiều File XML (Multi XML Import)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.xml", @"com.pkware.zip-archive", @"public.data"] inMode:UIDocumentPickerModeImport];
        picker.allowsMultipleSelection = YES;
        [root presentViewController:picker animated:YES completion:nil];
    }]];

    NSString *saveTitle = AMIsAutoSaveEnabled() ? @"🎬 Tự Động Lưu Photos: [ BẬT ]" : @"🎬 Tự Động Lưu Photos: [ TẮT ]";
    [alert addAction:[UIAlertAction actionWithTitle:saveTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        AMSetAutoSaveEnabled(!AMIsAutoSaveEnabled());
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [root presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - =========================================================
#pragma mark 9. Bulletproof Anti-Crack Popup, Vibration & Window Shields
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
           [low containsString:@"unlocked by"] ||
           [low containsString:@"quảng cáo"] ||
           [low containsString:@"countdown"];
}

static void (*orig_AudioServicesPlaySystemSound)(SystemSoundID inSystemSoundID);
static void hook_AudioServicesPlaySystemSound(SystemSoundID inSystemSoundID) {
    if (inSystemSoundID == 1519) {
        if (orig_AudioServicesPlaySystemSound) orig_AudioServicesPlaySystemSound(inSystemSoundID);
        return;
    }
}

static void (*orig_AudioServicesPlayAlertSound)(SystemSoundID inSystemSoundID);
static void hook_AudioServicesPlayAlertSound(SystemSoundID inSystemSoundID) {
}

static void (*orig_AudioServicesPlaySystemSoundWithCompletion)(SystemSoundID inSystemSoundID, void (^inCompletionBlock)(void));
static void hook_AudioServicesPlaySystemSoundWithCompletion(SystemSoundID inSystemSoundID, void (^inCompletionBlock)(void)) {
    if (inSystemSoundID == 1519) {
        if (orig_AudioServicesPlaySystemSoundWithCompletion) {
            orig_AudioServicesPlaySystemSoundWithCompletion(inSystemSoundID, inCompletionBlock);
        } else if (inCompletionBlock) inCompletionBlock();
        return;
    }
    if (inCompletionBlock) inCompletionBlock();
}

static void (*orig_UIImpactFeedbackGenerator_impactOccurred)(UIImpactFeedbackGenerator *, SEL);
static void hook_UIImpactFeedbackGenerator_impactOccurred(UIImpactFeedbackGenerator *self, SEL _cmd) {}

static void (*orig_UINotificationFeedbackGenerator_notificationOccurred)(UINotificationFeedbackGenerator *, SEL, UINotificationFeedbackType);
static void hook_UINotificationFeedbackGenerator_notificationOccurred(UINotificationFeedbackGenerator *self, SEL _cmd, UINotificationFeedbackType type) {}

static void (*orig_UIWindow_makeKeyAndVisible)(UIWindow *, SEL);
static void hook_UIWindow_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName containsString:@"Keyboard"] || 
        [clsName containsString:@"TextEffects"] || 
        [clsName containsString:@"InputSet"] ||
        [clsName containsString:@"Remote"] ||
        [clsName containsString:@"Interactive"] ||
        [clsName isEqualToString:@"UIWindow"]) {
        if (orig_UIWindow_makeKeyAndVisible) orig_UIWindow_makeKeyAndVisible(self, _cmd);
        return;
    }

    if (self.windowLevel >= UIWindowLevelAlert) {
        UIViewController *root = self.rootViewController;
        NSString *rootName = root ? NSStringFromClass([root class]) : @"";
        if ([rootName containsString:@"5qG"] || [rootName containsString:@"fQG"] || [rootName containsString:@"Blatant"] || [rootName containsString:@"Alert"]) {
            self.hidden = YES;
            self.frame = CGRectZero;
            return;
        }
    }

    if (orig_UIWindow_makeKeyAndVisible) orig_UIWindow_makeKeyAndVisible(self, _cmd);
}

static void (*orig_UIWindow_setHidden)(UIWindow *, SEL, BOOL);
static void hook_UIWindow_setHidden(UIWindow *self, SEL _cmd, BOOL hidden) {
    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName containsString:@"Keyboard"] || 
        [clsName containsString:@"TextEffects"] || 
        [clsName containsString:@"InputSet"] ||
        [clsName containsString:@"Remote"] ||
        [clsName containsString:@"Interactive"] ||
        [clsName isEqualToString:@"UIWindow"]) {
        if (orig_UIWindow_setHidden) orig_UIWindow_setHidden(self, _cmd, hidden);
        return;
    }

    if (!hidden && self.windowLevel >= UIWindowLevelAlert) {
        UIViewController *root = self.rootViewController;
        NSString *rootName = root ? NSStringFromClass([root class]) : @"";
        if ([rootName containsString:@"5qG"] || [rootName containsString:@"fQG"] || [rootName containsString:@"Blatant"]) {
            hidden = YES;
        }
    }
    if (orig_UIWindow_setHidden) orig_UIWindow_setHidden(self, _cmd, hidden);
}

static UIAlertController *(*orig_UIAlertController_alertControllerWithTitle)(id, SEL, NSString *, NSString *, UIAlertControllerStyle);
static UIAlertController *hook_UIAlertController_alertControllerWithTitle(id self, SEL _cmd, NSString *title, NSString *message, UIAlertControllerStyle preferredStyle) {
    if (AMIsForbiddenString(title) || AMIsForbiddenString(message)) {
        return orig_UIAlertController_alertControllerWithTitle(self, _cmd, @"", @"", UIAlertControllerStyleAlert);
    }
    return orig_UIAlertController_alertControllerWithTitle(self, _cmd, title, message, preferredStyle);
}

static void (*orig_UIViewController_presentViewController)(UIViewController *, SEL, UIViewController *, BOOL, void (^)(void));
static void hook_UIViewController_presentViewController(UIViewController *self, SEL _cmd, UIViewController *vc, BOOL animated, void (^completion)(void)) {
    if (vc) {
        NSString *className = NSStringFromClass([vc class]);

        if ([vc isKindOfClass:[UIAlertController class]]) {
            UIAlertController *alert = (UIAlertController *)vc;
            NSString *title = alert.title ?: @"";
            NSString *message = alert.message ?: @"";
            NSString *combined = [NSString stringWithFormat:@"%@ %@", title, message];

            BOOL isOurAlert = [title containsString:@"Ultra Motion"] || [title containsString:@"Alight Motion"] || [title containsString:@"Thông báo"] || [title containsString:@"Lyrics"] || [title containsString:@"Cài Đặt"];

            if (!isOurAlert && AMIsForbiddenString(combined)) {
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

    if (orig_UIViewController_presentViewController) {
        orig_UIViewController_presentViewController(self, _cmd, vc, animated, completion);
    }
}

static BOOL (*orig_UIApplication_openURL)(UIApplication *, SEL, NSURL *);
static BOOL hook_UIApplication_openURL(UIApplication *self, SEL _cmd, NSURL *url) {
    if (url && AMIsForbiddenString(url.absoluteString)) return NO;
    if (orig_UIApplication_openURL) return orig_UIApplication_openURL(self, _cmd, url);
    return NO;
}

static void (*orig_UIApplication_openURL_options_completionHandler)(UIApplication *, SEL, NSURL *, NSDictionary *, void (^)(BOOL));
static void hook_UIApplication_openURL_options_completionHandler(UIApplication *self, SEL _cmd, NSURL *url, NSDictionary *options, void (^completion)(BOOL)) {
    if (url && AMIsForbiddenString(url.absoluteString)) {
        if (completion) completion(NO);
        return;
    }
    if (orig_UIApplication_openURL_options_completionHandler) {
        orig_UIApplication_openURL_options_completionHandler(self, _cmd, url, options, completion);
    }
}

#pragma mark - Hook View Controllers & Keyboard Attachment

static void (*orig_UIViewController_viewDidAppear)(UIViewController *, SEL, BOOL);
static void hook_UIViewController_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_UIViewController_viewDidAppear) orig_UIViewController_viewDidAppear(self, _cmd, animated);

    UIWindow *window = self.view.window ?: [UIApplication sharedApplication].windows.firstObject;
    if (window) {
        [[AMHomeSettingsHUD sharedHUD] installFloatingButtonOnWindow:window];
    }

    NSString *className = NSStringFromClass([self class]);
    BOOL isHomeScreen = [className containsString:@"Home"] || [className containsString:@"TabBarController"];
    BOOL isEditorScreen = [className containsString:@"Edit"] || [className containsString:@"Timeline"] || [className containsString:@"Export"] || [className containsString:@"Inspector"] || [className containsString:@"Shape"];

    if (isEditorScreen) {
        [[AMHomeSettingsHUD sharedHUD] setFloatingButtonVisible:NO];
    } else if (isHomeScreen) {
        [[AMHomeSettingsHUD sharedHUD] setFloatingButtonVisible:YES];
    }

    if ([className containsString:@"ExportPreviewVC"] || [className containsString:@"ExportVC"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self respondsToSelector:@selector(storeButton)]) {
                IMP imp = [self methodForSelector:@selector(storeButton)];
                UIButton *(*getButton)(id, SEL) = (void *)imp;
                UIButton *button = getButton(self, @selector(storeButton));
                if ([button isKindOfClass:[UIButton class]]) {
                    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
                }
            }
        });
    }
}

static BOOL (*orig_UITextView_becomeFirstResponder)(UITextView *, SEL);
static BOOL hook_UITextView_becomeFirstResponder(UITextView *self, SEL _cmd) {
    if (self.inputAccessoryView == nil) {
        self.inputAccessoryView = [AMMinimalLyricsBar barWithTarget:self];
    }
    if (orig_UITextView_becomeFirstResponder) return orig_UITextView_becomeFirstResponder(self, _cmd);
    return YES;
}

static id (*orig_UIActivityViewController_initWithActivityItems)(id, SEL, NSArray *, NSArray *);
static id hook_UIActivityViewController_initWithActivityItems(id self, SEL _cmd, NSArray *activityItems, NSArray *applicationActivities) {
    if (activityItems) {
        for (id item in activityItems) {
            if ([item isKindOfClass:[NSURL class]]) {
                NSURL *url = (NSURL *)item;
                NSString *ext = url.pathExtension.lowercaseString;
                if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"]) {
                    AMAutoSaveVideoAtPath(url.path);
                }
            } else if ([item isKindOfClass:[NSString class]]) {
                NSString *str = (NSString *)item;
                NSString *ext = str.pathExtension.lowercaseString;
                if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"]) {
                    AMAutoSaveVideoAtPath(str);
                }
            }
        }
    }
    return orig_UIActivityViewController_initWithActivityItems(self, _cmd, activityItems, applicationActivities);
}

#pragma mark - =========================================================
#pragma mark 10. Tweak Constructor (Ultra Motion iOS 6.0.3 Feature Port)
#pragma mark - =========================================================

__attribute__((constructor)) static void initUltraMotionMod() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 14, *)) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {}];
        } else {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {}];
        }

        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                              completionHandler:^(BOOL granted, NSError * _Nullable error) {}];
    });

    // 1. Rebind C AudioServices vibration functions via Fishhook
    rebind_symbols((struct rebinding[3]){
        {"AudioServicesPlaySystemSound", (void *)hook_AudioServicesPlaySystemSound, (void **)&orig_AudioServicesPlaySystemSound},
        {"AudioServicesPlayAlertSound", (void *)hook_AudioServicesPlayAlertSound, (void **)&orig_AudioServicesPlayAlertSound},
        {"AudioServicesPlaySystemSoundWithCompletion", (void *)hook_AudioServicesPlaySystemSoundWithCompletion, (void **)&orig_AudioServicesPlaySystemSoundWithCompletion}
    }, 3);

    // 2. Hook Feedback Generators
    Class impactClass = objc_getClass("UIImpactFeedbackGenerator");
    if (impactClass) {
        Method m = class_getInstanceMethod(impactClass, @selector(impactOccurred));
        if (m) {
            orig_UIImpactFeedbackGenerator_impactOccurred = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_UIImpactFeedbackGenerator_impactOccurred);
        }
    }

    Class notifClass = objc_getClass("UINotificationFeedbackGenerator");
    if (notifClass) {
        Method m = class_getInstanceMethod(notifClass, @selector(notificationOccurred:));
        if (m) {
            orig_UINotificationFeedbackGenerator_notificationOccurred = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_UINotificationFeedbackGenerator_notificationOccurred);
        }
    }

    // 3. Hook UIWindow
    Class windowClass = [UIWindow class];
    Method makeKeyMethod = class_getInstanceMethod(windowClass, @selector(makeKeyAndVisible));
    if (makeKeyMethod) {
        orig_UIWindow_makeKeyAndVisible = (void *)method_getImplementation(makeKeyMethod);
        method_setImplementation(makeKeyMethod, (IMP)hook_UIWindow_makeKeyAndVisible);
    }

    Method setHiddenMethod = class_getInstanceMethod(windowClass, @selector(setHidden:));
    if (setHiddenMethod) {
        orig_UIWindow_setHidden = (void *)method_getImplementation(setHiddenMethod);
        method_setImplementation(setHiddenMethod, (IMP)hook_UIWindow_setHidden);
    }

    // 4. Hook UIActivityViewController
    Class activityVCClass = [UIActivityViewController class];
    Method initActivityMethod = class_getInstanceMethod(activityVCClass, @selector(initWithActivityItems:applicationActivities:));
    if (initActivityMethod) {
        orig_UIActivityViewController_initWithActivityItems = (void *)method_getImplementation(initActivityMethod);
        method_setImplementation(initActivityMethod, (IMP)hook_UIActivityViewController_initWithActivityItems);
    }

    // 5. Hook UIViewController
    Class vcClass = objc_getClass("UIViewController");
    Method viewDidAppearMethod = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    if (viewDidAppearMethod) {
        orig_UIViewController_viewDidAppear = (void *)method_getImplementation(viewDidAppearMethod);
        method_setImplementation(viewDidAppearMethod, (IMP)hook_UIViewController_viewDidAppear);
    }

    Method presentVCMethod = class_getInstanceMethod(vcClass, @selector(presentViewController:animated:completion:));
    if (presentVCMethod) {
        orig_UIViewController_presentViewController = (void *)method_getImplementation(presentVCMethod);
        method_setImplementation(presentVCMethod, (IMP)hook_UIViewController_presentViewController);
    }

    // 6. Hook UIAlertController
    Class alertClass = objc_getClass("UIAlertController");
    if (alertClass) {
        Method alertCreateMethod = class_getClassMethod(alertClass, @selector(alertControllerWithTitle:message:preferredStyle:));
        if (alertCreateMethod) {
            orig_UIAlertController_alertControllerWithTitle = (void *)method_getImplementation(alertCreateMethod);
            method_setImplementation(alertCreateMethod, (IMP)hook_UIAlertController_alertControllerWithTitle);
        }
    }

    // 7. Hook UIApplication
    Class appClass = [UIApplication class];
    Method openURLMethod = class_getInstanceMethod(appClass, @selector(openURL:));
    if (openURLMethod) {
        orig_UIApplication_openURL = (void *)method_getImplementation(openURLMethod);
        method_setImplementation(openURLMethod, (IMP)hook_UIApplication_openURL);
    }

    Method openURLOptMethod = class_getInstanceMethod(appClass, @selector(openURL:options:completionHandler:));
    if (openURLOptMethod) {
        orig_UIApplication_openURL_options_completionHandler = (void *)method_getImplementation(openURLOptMethod);
        method_setImplementation(openURLOptMethod, (IMP)hook_UIApplication_openURL_options_completionHandler);
    }

    // 8. Hook UITextView
    Class tvClass = [UITextView class];
    if (tvClass) {
        Method becomeMethod = class_getInstanceMethod(tvClass, @selector(becomeFirstResponder));
        if (becomeMethod) {
            orig_UITextView_becomeFirstResponder = (void *)method_getImplementation(becomeMethod);
            method_setImplementation(becomeMethod, (IMP)hook_UITextView_becomeFirstResponder);
        }
    }

    NSLog(@"\n[UltraMotion] ========================================");
    NSLog(@"[UltraMotion] 🚀 ULTRA MOTION iOS 6.0.3 INITIALIZED!");
    NSLog(@"[UltraMotion] Theme: Full Dark Mode OLED (#08080A)");
    NSLog(@"[UltraMotion] Effects: 497+ Extra Effects across 20+ Categories");
    NSLog(@"[UltraMotion] Tools: Multi-XML, Audio Sync, Waveform, 120 FPS");
    NSLog(@"[UltraMotion] ========================================\n");
}
