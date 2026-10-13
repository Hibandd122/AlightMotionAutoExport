// =====================================================================
// AlightMotionUltra Tweak - Full Standalone Unified Mod
// Features: Full Pro Unlocked, Watermark Removed, Sideload Fix (AppGroup & Keychain),
//           UltraMotion 811+ XML Effects & Metal Shaders, OLED Dark Mode,
//           Batch Lyrics 5-Button Capsule Bar, Auto-Save to Photos (Native 60 FPS)
// =====================================================================

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
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "fishhook.h"
#import <mach-o/dyld.h>
#import <mach/mach.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <limits.h>
#include <stdio.h>

#pragma mark - =========================================================
#pragma mark 1. Sideload Crash Protector (App Group & Keychain Security Fix)
#pragma mark - =========================================================

// Swizzle [NSFileManager containerURLForSecurityApplicationGroupIdentifier:]
static NSURL *(*orig_containerURLForSecurityApplicationGroupIdentifier)(id, SEL, NSString *);

static NSURL *hook_containerURLForSecurityApplicationGroupIdentifier(id self, SEL _cmd, NSString *groupId) {
    NSURL *url = nil;
    if (orig_containerURLForSecurityApplicationGroupIdentifier) {
        url = orig_containerURLForSecurityApplicationGroupIdentifier(self, _cmd, groupId);
    }
    if (url) return url;
    
    // Fallback sandbox directory for sideloading environments
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    if (!appSupport) {
        appSupport = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    }
    NSString *groupPath = [appSupport stringByAppendingPathComponent:[NSString stringWithFormat:@"AppGroup/%@", groupId ?: @"default"]];
    [[NSFileManager defaultManager] createDirectoryAtPath:groupPath withIntermediateDirectories:YES attributes:nil error:nil];
    return [NSURL fileURLWithPath:groupPath isDirectory:YES];
}

// Hook Keychain APIs to strip kSecAttrAccessGroup when sideloaded
static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef);

static OSStatus hook_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (attributes && CFDictionaryContainsKey(attributes, kSecAttrAccessGroup)) {
        CFMutableDictionaryRef mut = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, attributes);
        CFDictionaryRemoveValue(mut, kSecAttrAccessGroup);
        OSStatus st = orig_SecItemAdd ? orig_SecItemAdd(mut, result) : noErr;
        CFRelease(mut);
        return st;
    }
    return orig_SecItemAdd ? orig_SecItemAdd(attributes, result) : noErr;
}

static OSStatus hook_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (query && CFDictionaryContainsKey(query, kSecAttrAccessGroup)) {
        CFMutableDictionaryRef mut = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
        CFDictionaryRemoveValue(mut, kSecAttrAccessGroup);
        OSStatus st = orig_SecItemCopyMatching ? orig_SecItemCopyMatching(mut, result) : noErr;
        CFRelease(mut);
        return st;
    }
    return orig_SecItemCopyMatching ? orig_SecItemCopyMatching(query, result) : noErr;
}

static OSStatus hook_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (query && CFDictionaryContainsKey(query, kSecAttrAccessGroup)) {
        CFMutableDictionaryRef mut = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
        CFDictionaryRemoveValue(mut, kSecAttrAccessGroup);
        OSStatus st = orig_SecItemUpdate ? orig_SecItemUpdate(mut, attributesToUpdate) : noErr;
        CFRelease(mut);
        return st;
    }
    return orig_SecItemUpdate ? orig_SecItemUpdate(query, attributesToUpdate) : noErr;
}

static OSStatus hook_SecItemDelete(CFDictionaryRef query) {
    if (query && CFDictionaryContainsKey(query, kSecAttrAccessGroup)) {
        CFMutableDictionaryRef mut = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
        CFDictionaryRemoveValue(mut, kSecAttrAccessGroup);
        OSStatus st = orig_SecItemDelete ? orig_SecItemDelete(mut) : noErr;
        CFRelease(mut);
        return st;
    }
    return orig_SecItemDelete ? orig_SecItemDelete(query) : noErr;
}

#pragma mark - =========================================================
#pragma mark 2. Native Pro & Watermark Annihilator (Clean & Blatant-Free)
#pragma mark - =========================================================

static id (*orig_NSUserDefaults_objectForKey)(id, SEL, NSString *);
static id hook_NSUserDefaults_objectForKey(id self, SEL _cmd, NSString *defaultName) {
    if (defaultName) {
        if ([defaultName isEqualToString:@"forced_subscription_tier_key"]) return @"cloudSubscriber";
        if ([defaultName isEqualToString:@"activeSubscriptionsOverride"] ||
            [defaultName isEqualToString:@"activeLifetimesOverride"] ||
            [defaultName isEqualToString:@"activeBundleSubscriptionsOverride"] ||
            [defaultName isEqualToString:@"activeExternalSubscriptionsOverride"]) {
            return @[@"alightcreative.motion.1y_t80"];
        }
        if ([defaultName isEqualToString:@"Forced Subscription status"]) return @"active";
        if ([defaultName isEqualToString:@"UnlockAllProFeatures"] ||
            [defaultName isEqualToString:@"isSubscribedToUltra"] ||
            [defaultName isEqualToString:@"isPremium"] ||
            [defaultName isEqualToString:@"hasMembership"] ||
            [defaultName isEqualToString:@"benefit_remove_watermark"] ||
            [defaultName isEqualToString:@"remove_watermark"] ||
            [defaultName isEqualToString:@"has_active_subscriptions"]) {
            return @YES;
        }
        if ([defaultName isEqualToString:@"isFreeUser"]) return @NO;
    }
    return orig_NSUserDefaults_objectForKey ? orig_NSUserDefaults_objectForKey(self, _cmd, defaultName) : nil;
}

static BOOL (*orig_NSUserDefaults_boolForKey)(id, SEL, NSString *);
static BOOL hook_NSUserDefaults_boolForKey(id self, SEL _cmd, NSString *defaultName) {
    if (defaultName) {
        if ([defaultName isEqualToString:@"UnlockAllProFeatures"] ||
            [defaultName isEqualToString:@"isSubscribedToUltra"] ||
            [defaultName isEqualToString:@"isPremium"] ||
            [defaultName isEqualToString:@"hasMembership"] ||
            [defaultName isEqualToString:@"benefit_remove_watermark"] ||
            [defaultName isEqualToString:@"remove_watermark"] ||
            [defaultName isEqualToString:@"has_active_subscriptions"]) {
            return YES;
        }
        if ([defaultName isEqualToString:@"isFreeUser"]) return NO;
    }
    return orig_NSUserDefaults_boolForKey ? orig_NSUserDefaults_boolForKey(self, _cmd, defaultName) : NO;
}

static void AMApplyProSettings(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:@YES forKey:@"UnlockAllProFeatures"];
    [ud setObject:@YES forKey:@"isSubscribedToUltra"];
    [ud setObject:@YES forKey:@"isPremium"];
    [ud setObject:@YES forKey:@"hasMembership"];
    [ud setObject:@NO forKey:@"isFreeUser"];
    [ud setObject:@YES forKey:@"benefit_remove_watermark"];
    [ud setObject:@YES forKey:@"remove_watermark"];
    [ud setObject:@YES forKey:@"has_active_subscriptions"];
    [ud setObject:@"cloudSubscriber" forKey:@"forced_subscription_tier_key"];
    [ud setObject:@"active" forKey:@"Forced Subscription status"];
    [ud setObject:@"alightcreative.motion.1y_t80" forKey:@"AM_ActiveProductID"];
    
    // Alight Motion internal Monetization storage
    NSDictionary *subInfo = @{
        @"alightcreative.motion.1y_t80": @{
            @"product_id": @"alightcreative.motion.1y_t80",
            @"status": @"active",
            @"expires_date_ms": @"4102444800000",
            @"is_trial_period": @NO,
            @"auto_renew_status": @YES
        }
    };
    [ud setObject:subInfo forKey:@"active_subscriptions"];
    [ud setObject:@[@"alightcreative.motion.1y_t80"] forKey:@"activeSubscriptionsOverride"];
    [ud setObject:@[@"alightcreative.motion.1y_t80"] forKey:@"activeLifetimesOverride"];
    [ud setObject:@[@"alightcreative.motion.1y_t80"] forKey:@"activeBundleSubscriptionsOverride"];
    [ud setObject:@[@"alightcreative.motion.1y_t80"] forKey:@"activeExternalSubscriptionsOverride"];
    [ud setBool:NO forKey:@"google_analytics_default_allow_analytics_storage"];
    [ud setBool:NO forKey:@"google_analytics_default_allow_ad_storage"];
    [ud setBool:NO forKey:@"google_analytics_default_allow_ad_user_data"];
    [ud setBool:NO forKey:@"google_analytics_default_allow_ad_personalization_signals"];
    [ud setBool:NO forKey:@"firebase_analytics_collection_enabled"];
    [ud setBool:NO forKey:@"firebase_analytics_collection_deactivated"];
    [ud setBool:NO forKey:@"FIREBASE_ANALYTICS_COLLECTION_ENABLED"];
    [ud synchronize];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class udClass = [NSUserDefaults class];
        Method mObj = class_getInstanceMethod(udClass, @selector(objectForKey:));
        if (mObj) {
            orig_NSUserDefaults_objectForKey = (void *)method_getImplementation(mObj);
            method_setImplementation(mObj, (IMP)hook_NSUserDefaults_objectForKey);
        }
        Method mBool = class_getInstanceMethod(udClass, @selector(boolForKey:));
        if (mBool) {
            orig_NSUserDefaults_boolForKey = (void *)method_getImplementation(mBool);
            method_setImplementation(mBool, (IMP)hook_NSUserDefaults_boolForKey);
        }
    });
}

#pragma mark - =========================================================
#pragma mark 2.5. Ad-Networks & Telemetry Neutralizer Engine (Zero Lag & Pure Speed)
#pragma mark - =========================================================

// Block Google Mobile Ads (GAD)
static void hook_GADMobileAds_startWithCompletionHandler(id self, SEL _cmd, void (^completionHandler)(id status)) {
    NSLog(@"[AlightMotionUltra] Neutralized GADMobileAds startWithCompletionHandler");
    if (completionHandler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(nil);
        });
    }
}

// Block IronSource SDK
static void hook_IronSource_initSDK(id self, SEL _cmd, id config) {
    NSLog(@"[AlightMotionUltra] Neutralized IronSource initSDK");
}

static void hook_IronSourceAdsInternal_initWithRequest(id self, SEL _cmd, id request, void (^completion)(id result, NSError *error)) {
    NSLog(@"[AlightMotionUltra] Neutralized IronSourceAdsInternal initWithRequest");
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, nil);
        });
    }
}

// Block Firebase Analytics Events & Screen Views
static void hook_FIRAnalytics_logEventWithName(id self, SEL _cmd, NSString *name, NSDictionary *params) {
    // Drop all background telemetry silently to save CPU & battery
}

// Block Vungle Ads SDK
static void hook_VungleAds_initWithPlacementId(id self, SEL _cmd, id placementId, id size) {
    NSLog(@"[AlightMotionUltra] Neutralized VungleAds initWithPlacementId");
}

// Block AppLovin SDK (Instant Cold Boot Bypass)
static void hook_ALSdk_initializeSdk(id self, SEL _cmd) {
    NSLog(@"[AlightMotionUltra] Neutralized ALSdk initializeSdk");
}

static void hook_ALSdk_initializeWithConfiguration(id self, SEL _cmd, id config, void (^completionHandler)(id conf)) {
    NSLog(@"[AlightMotionUltra] Neutralized ALSdk initializeWithConfiguration");
    if (completionHandler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(nil);
        });
    }
}

// Block Fyber / IASDKCore (Instant Cold Boot Bypass)
static void hook_IASDKCore_initWithAppID(id self, SEL _cmd, id appId, void (^completionBlock)(BOOL, NSError *), dispatch_queue_t q) {
    NSLog(@"[AlightMotionUltra] Neutralized IASDKCore initWithAppID");
    if (completionBlock) {
        dispatch_async(q ?: dispatch_get_main_queue(), ^{
            completionBlock(YES, nil);
        });
    }
}

// Block Adjust SDK Telemetry
static void hook_Adjust_trackEvent(id self, SEL _cmd, id event) {
    // Drop Adjust tracking silently
}

static void hook_Adjust_appDidLaunch(id self, SEL _cmd, id config) {
    NSLog(@"[AlightMotionUltra] Neutralized Adjust appDidLaunch");
}

// Zero-Overhead Network Ad Sinkhole: Immediately drops requests to ad/tracking networks
static NSURLSessionDataTask *(*orig_NSURLSession_dataTaskWithRequest_completionHandler)(NSURLSession *, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));
static NSURLSessionDataTask *hook_NSURLSession_dataTaskWithRequest_completionHandler(NSURLSession *self, SEL _cmd, NSURLRequest *request, void (^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
    NSString *urlString = request.URL.absoluteString.lowercaseString;
    if (urlString) {
        if ([urlString containsString:@"googleads"] ||
            [urlString containsString:@"doubleclick.net"] ||
            [urlString containsString:@"ironsrc.com"] ||
            [urlString containsString:@"vungle.com"] ||
            [urlString containsString:@"applovin.com"] ||
            [urlString containsString:@"fyber.com"] ||
            [urlString containsString:@"app-measurement.com"] ||
            [urlString containsString:@"crashlytics.com"] ||
            [urlString containsString:@"adjust.com"]) {
            if (completionHandler) {
                NSHTTPURLResponse *fakeResp = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                    completionHandler([NSData data], fakeResp, nil);
                });
            }
            return nil;
        }
    }
    return orig_NSURLSession_dataTaskWithRequest_completionHandler ? orig_NSURLSession_dataTaskWithRequest_completionHandler(self, _cmd, request, completionHandler) : nil;
}

static void AMNeutralizeAdNetworks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1. Google Mobile Ads
        Class gadClass = objc_getClass("GADMobileAds");
        if (gadClass) {
            Method mStart = class_getInstanceMethod(gadClass, @selector(startWithCompletionHandler:));
            if (mStart) {
                method_setImplementation(mStart, (IMP)hook_GADMobileAds_startWithCompletionHandler);
            }
        }

        // 2. IronSource SDK
        Class isAdapterClass = objc_getClass("ISIronSourceAdapter");
        if (isAdapterClass) {
            Method mInit = class_getInstanceMethod(isAdapterClass, @selector(initSDK:));
            if (mInit) {
                method_setImplementation(mInit, (IMP)hook_IronSource_initSDK);
            }
        }
        Class isAdsInternal = objc_getClass("IronSourceAdsInternal");
        if (isAdsInternal) {
            Method mReq = class_getInstanceMethod(isAdsInternal, @selector(initWithRequest:completion:));
            if (mReq) {
                method_setImplementation(mReq, (IMP)hook_IronSourceAdsInternal_initWithRequest);
            }
        }

        // 3. Firebase Analytics
        Class firAnalyticsClass = objc_getClass("FIRAnalytics");
        if (firAnalyticsClass) {
            Method mLog = class_getClassMethod(firAnalyticsClass, @selector(logEventWithName:parameters:));
            if (mLog) {
                method_setImplementation(mLog, (IMP)hook_FIRAnalytics_logEventWithName);
            }
        }

        // 4. Vungle Ads
        Class vungleBanner = objc_getClass("_TtC12VungleAdsSDK12VungleBanner");
        if (vungleBanner) {
            Method mInitVungle = class_getInstanceMethod(vungleBanner, @selector(initWithPlacementId:vungleAdSize:));
            if (mInitVungle) {
                method_setImplementation(mInitVungle, (IMP)hook_VungleAds_initWithPlacementId);
            }
        }

        // 5. AppLovin SDK (Instant cold boot bypass)
        Class alSdkClass = objc_getClass("ALSdk");
        if (alSdkClass) {
            Method mInitSdk = class_getInstanceMethod(alSdkClass, @selector(initializeSdk));
            if (mInitSdk) method_setImplementation(mInitSdk, (IMP)hook_ALSdk_initializeSdk);
            Method mInitConfig = class_getInstanceMethod(alSdkClass, @selector(initializeWithConfiguration:completionHandler:));
            if (mInitConfig) method_setImplementation(mInitConfig, (IMP)hook_ALSdk_initializeWithConfiguration);
        }

        // 6. Fyber IASDKCore
        Class iaSdkClass = objc_getClass("IASDKCore");
        if (iaSdkClass) {
            Method mInitApp = class_getInstanceMethod(iaSdkClass, @selector(initWithAppID:completionBlock:completionQueue:));
            if (mInitApp) method_setImplementation(mInitApp, (IMP)hook_IASDKCore_initWithAppID);
        }

        // 7. Adjust SDK
        Class adjClass = objc_getClass("Adjust");
        if (adjClass) {
            Method mEvent = class_getClassMethod(adjClass, @selector(trackEvent:));
            if (mEvent) method_setImplementation(mEvent, (IMP)hook_Adjust_trackEvent);
            Method mLaunch = class_getClassMethod(adjClass, @selector(appDidLaunch:));
            if (mLaunch) method_setImplementation(mLaunch, (IMP)hook_Adjust_appDidLaunch);
        }

        // 8. Network Level Sinkhole
        Class sessionClass = [NSURLSession class];
        Method mTask = class_getInstanceMethod(sessionClass, @selector(dataTaskWithRequest:completionHandler:));
        if (mTask) {
            orig_NSURLSession_dataTaskWithRequest_completionHandler = (void *)method_getImplementation(mTask);
            method_setImplementation(mTask, (IMP)hook_NSURLSession_dataTaskWithRequest_completionHandler);
        }
    });
}

#pragma mark - =========================================================
#pragma mark 2.6. Group A: Unlimited Project Package Engine (> 5 MB Unlocker)
#pragma mark - =========================================================

static int64_t hook_ProjectPackage_freeUserMaxDownloadSize(id self, SEL _cmd) {
    return 53687091200LL; // 50 GB
}

static void AMUnlockProjectPackageLimit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setDouble:53687091200.0 forKey:@"project_package_freeuser_maxdownloadsize"];
        [ud setDouble:53687091200.0 forKey:@"freeUserMaxDownloadSize"];
        [ud setObject:@YES forKey:@"project_package_sharing"];
        [ud setObject:@YES forKey:@"benefit_project_package_sharing"];
        [ud synchronize];

        // Hook any classes responding to freeUserMaxDownloadSize
        const char *targetClasses[] = {
            "_TtC12AlightMotion15ProjectPackager",
            "_TtC12AlightMotion15PackageImporter",
            "_TtC12AlightMotion21ShareProjectPackageVC",
            "AlightMotion.ProjectPackager",
            "AlightMotion.PackageImporter",
            NULL
        };

        for (int i = 0; targetClasses[i] != NULL; i++) {
            Class cls = objc_getClass(targetClasses[i]);
            if (!cls) continue;

            SEL sel = @selector(freeUserMaxDownloadSize);
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                method_setImplementation(m, (IMP)hook_ProjectPackage_freeUserMaxDownloadSize);
            } else {
                class_addMethod(cls, sel, (IMP)hook_ProjectPackage_freeUserMaxDownloadSize, "q@:");
            }

            SEL selClass = @selector(freeUserMaxDownloadSize);
            Method mClass = class_getClassMethod(cls, selClass);
            if (mClass) {
                method_setImplementation(mClass, (IMP)hook_ProjectPackage_freeUserMaxDownloadSize);
            }
        }
    });
}

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

        // Keep injected XML out of the host app's BuiltinEffects directory:

        // its Singleton Loader validates that directory and aborts on unknown

        // schemas. Only the tweak-owned registry reads this private directory.

        NSString *builtinDir = [bundlePath stringByAppendingPathComponent:@"UltraMotionEffects"];

        

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



#pragma mark - =========================================================
#pragma mark 4. Auto Save To Camera Roll Engine
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

// =====================================================================
// UMV Engine v6.6.6 (Ultra Motion Video Engine - MP4 FastStart & Stream Optimization)
// Relocates 'moov' atom before 'mdat' and recalculates chunk offsets (stco / co64)
// Allows zero-buffering instant streaming on TikTok, Instagram, YouTube Shorts, Discord
// =====================================================================

static uint32_t read_be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static uint64_t read_be64(const uint8_t *p) {
    return ((uint64_t)read_be32(p) << 32) | (uint64_t)read_be32(p + 4);
}

static void write_be32(uint8_t *p, uint32_t val) {
    p[0] = (uint8_t)(val >> 24);
    p[1] = (uint8_t)(val >> 16);
    p[2] = (uint8_t)(val >> 8);
    p[3] = (uint8_t)(val);
}

static void write_be64(uint8_t *p, uint64_t val) {
    write_be32(p, (uint32_t)(val >> 32));
    write_be32(p + 4, (uint32_t)(val & 0xFFFFFFFFULL));
}

static void UMV_PatchChunkOffsets(uint8_t *buf, size_t size, uint64_t shift) {
    if (!buf || size < 8) return;
    size_t i = 0;
    while (i + 8 <= size) {
        uint32_t atom_size = read_be32(buf + i);
        if (atom_size < 8) break;
        if (i + atom_size > size) break;
        
        // Check for 'stco' (32-bit chunk offset box)
        if (memcmp(buf + i + 4, "stco", 4) == 0 && atom_size >= 16) {
            uint32_t count = read_be32(buf + i + 12);
            size_t entry_start = i + 16;
            for (uint32_t c = 0; c < count; c++) {
                size_t offset_pos = entry_start + (c * 4);
                if (offset_pos + 4 > size) break;
                uint32_t old_off = read_be32(buf + offset_pos);
                write_be32(buf + offset_pos, old_off + (uint32_t)shift);
            }
        }
        // Check for 'co64' (64-bit chunk offset box)
        else if (memcmp(buf + i + 4, "co64", 4) == 0 && atom_size >= 16) {
            uint32_t count = read_be32(buf + i + 12);
            size_t entry_start = i + 16;
            for (uint32_t c = 0; c < count; c++) {
                size_t offset_pos = entry_start + (c * 8);
                if (offset_pos + 8 > size) break;
                uint64_t old_off = read_be64(buf + offset_pos);
                write_be64(buf + offset_pos, old_off + shift);
            }
        }
        // Recursively inspect container boxes: 'trak', 'mdia', 'minf', 'stbl'
        else if (memcmp(buf + i + 4, "trak", 4) == 0 ||
                 memcmp(buf + i + 4, "mdia", 4) == 0 ||
                 memcmp(buf + i + 4, "minf", 4) == 0 ||
                 memcmp(buf + i + 4, "stbl", 4) == 0) {
            if (atom_size > 8) {
                UMV_PatchChunkOffsets(buf + i + 8, atom_size - 8, shift);
            }
        }
        i += atom_size;
    }
}

static BOOL UMV_OptimizeMP4(NSString *filePath) {
    if (!filePath || filePath.length == 0) return NO;
    const char *cPath = [filePath UTF8String];
    FILE *in = fopen(cPath, "rb");
    if (!in) return NO;

    fseek(in, 0, SEEK_END);
    long total_size = ftell(in);
    fseek(in, 0, SEEK_SET);

    if (total_size < 32) {
        fclose(in);
        return NO;
    }

    uint32_t ftyp_size = 0;
    long moov_pos = -1;
    uint32_t moov_size = 0;
    long mdat_pos = -1;
    uint32_t mdat_size = 0;

    long cur_pos = 0;
    while (cur_pos < total_size - 8) {
        fseek(in, cur_pos, SEEK_SET);
        uint8_t hdr[8];
        if (fread(hdr, 1, 8, in) != 8) break;
        uint32_t box_sz = read_be32(hdr);
        if (box_sz < 8) break;

        if (memcmp(hdr + 4, "ftyp", 4) == 0) {
            ftyp_size = box_sz;
        } else if (memcmp(hdr + 4, "moov", 4) == 0) {
            moov_pos = cur_pos;
            moov_size = box_sz;
        } else if (memcmp(hdr + 4, "mdat", 4) == 0) {
            mdat_pos = cur_pos;
            mdat_size = box_sz;
        }
        cur_pos += box_sz;
    }

    // If moov is already before mdat or moov not found, no need to relocate
    if (moov_pos < 0 || mdat_pos < 0 || moov_pos < mdat_pos) {
        fclose(in);
        return YES;
    }

    // Read moov atom into memory buffer
    uint8_t *moov_buf = malloc(moov_size);
    if (!moov_buf) {
        fclose(in);
        return NO;
    }
    fseek(in, moov_pos, SEEK_SET);
    if (fread(moov_buf, 1, moov_size, in) != moov_size) {
        free(moov_buf);
        fclose(in);
        return NO;
    }

    // Patch chunk offsets inside moov: offset increases by moov_size
    if (moov_size > 8) {
        UMV_PatchChunkOffsets(moov_buf + 8, moov_size - 8, (uint64_t)moov_size);
    }

    // Write out new file with FastStart structure: [ftyp] -> [moov] -> [mdat...]
    NSString *tmpPath = [filePath stringByAppendingString:@".umv.tmp"];
    FILE *out = fopen([tmpPath UTF8String], "wb");
    if (!out) {
        free(moov_buf);
        fclose(in);
        return NO;
    }

    // 1. Write ftyp
    if (ftyp_size > 0) {
        uint8_t *ftyp_buf = malloc(ftyp_size);
        if (ftyp_buf) {
            fseek(in, 0, SEEK_SET);
            fread(ftyp_buf, 1, ftyp_size, in);
            fwrite(ftyp_buf, 1, ftyp_size, out);
            free(ftyp_buf);
        }
    }

    // 2. Write relocated moov
    fwrite(moov_buf, 1, moov_size, out);
    free(moov_buf);

    // 3. Write mdat and remaining payload (from ftyp_size up to moov_pos)
    fseek(in, ftyp_size, SEEK_SET);
    long remaining = moov_pos - ftyp_size;
    uint8_t stream_chunk[65536];
    while (remaining > 0) {
        size_t to_read = (remaining > sizeof(stream_chunk)) ? sizeof(stream_chunk) : (size_t)remaining;
        size_t n = fread(stream_chunk, 1, to_read, in);
        if (n <= 0) break;
        fwrite(stream_chunk, 1, n, out);
        remaining -= n;
    }

    // 4. Any atoms after original moov
    fseek(in, moov_pos + moov_size, SEEK_SET);
    long tail = total_size - (moov_pos + moov_size);
    while (tail > 0) {
        size_t to_read = (tail > sizeof(stream_chunk)) ? sizeof(stream_chunk) : (size_t)tail;
        size_t n = fread(stream_chunk, 1, to_read, in);
        if (n <= 0) break;
        fwrite(stream_chunk, 1, n, out);
        tail -= n;
    }

    fclose(in);
    fclose(out);

    // Replace original file atomically
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    BOOL ok = [[NSFileManager defaultManager] moveItemAtPath:tmpPath toPath:filePath error:nil];
    NSLog(@"[UMV Engine] Successfully fast-started MP4 video (Moov shifted by +%u bytes). Status: %d", moov_size, ok);
    return ok;
}

static BOOL hasSavedRecentImage = NO;

static void AMAutoSaveImage(UIImage *image) {
    if (!AMIsAutoSaveEnabled()) return;
    if (!image) return;
    if (hasSavedRecentImage) return;

    hasSavedRecentImage = YES;
    UIImageWriteToSavedPhotosAlbum(image, nil, NULL, NULL);
    AMNotifyUser(@"Alight Motion", @"🖼️ Đã tự động lưu khung ảnh vào Cuộn Camera (Photos)!");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        hasSavedRecentImage = NO;
    });
}

static void AMAutoSaveImageAtPath(NSString *filePath) {
    if (!AMIsAutoSaveEnabled()) return;
    if (!filePath || filePath.length == 0) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) return;

    UIImage *img = [UIImage imageWithContentsOfFile:filePath];
    if (img) {
        AMAutoSaveImage(img);
    }
}

static id (*orig_UIActivityViewController_initWithActivityItems)(id, SEL, NSArray *, NSArray *);

static id hook_UIActivityViewController_initWithActivityItems(id self, SEL _cmd, NSArray *activityItems, NSArray *applicationActivities) {
    if (activityItems && AMIsAutoSaveEnabled()) {
        for (id item in activityItems) {
            if ([item isKindOfClass:[UIImage class]]) {
                AMAutoSaveImage((UIImage *)item);
            } else if ([item isKindOfClass:[NSURL class]]) {
                NSURL *url = (NSURL *)item;
                NSString *ext = url.pathExtension.lowercaseString;
                if ([ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] || [ext isEqualToString:@"webp"] || [ext isEqualToString:@"heic"]) {
                    AMAutoSaveImageAtPath(url.path);
                }
            } else if ([item isKindOfClass:[NSString class]]) {
                NSString *str = (NSString *)item;
                NSString *ext = str.pathExtension.lowercaseString;
                if ([ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] || [ext isEqualToString:@"webp"] || [ext isEqualToString:@"heic"]) {
                    AMAutoSaveImageAtPath(str);
                }
            }
        }
    }
    return orig_UIActivityViewController_initWithActivityItems ? orig_UIActivityViewController_initWithActivityItems(self, _cmd, activityItems, applicationActivities) : self;
}

#pragma mark - Lyrics Queue Manager (With Async Non-Blocking Disk Persistence)

@interface AMLyricsQueueManager : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *lyricsLines;
@property (nonatomic, assign) NSUInteger currentIndex;
+ (instancetype)sharedManager;
- (void)loadLyrics:(NSArray<NSString *> *)lines;
- (void)clearLyrics;
- (void)resetToFirstVerse;
- (void)jumpToVerseIndex:(NSUInteger)index;
- (NSString *)currentLineText;
- (NSString *)consumeNextLineText;
- (BOOL)hasNextLine;
@end

@implementation AMLyricsQueueManager

+ (instancetype)sharedManager {
    static AMLyricsQueueManager *mgr = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mgr = [[self alloc] init];
        mgr.lyricsLines = [NSMutableArray array];
        
        NSArray *cached = [[NSUserDefaults standardUserDefaults] objectForKey:@"AM_CachedLyrics"];
        if (cached && [cached isKindOfClass:[NSArray class]]) {
            [mgr.lyricsLines addObjectsFromArray:cached];
        }
        mgr.currentIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"AM_CachedLyricsIndex"];
        if (mgr.currentIndex >= mgr.lyricsLines.count) {
            mgr.currentIndex = 0;
        }
    });
    return mgr;
}

- (void)saveToDisk {
    NSArray *linesCopy = [self.lyricsLines copy];
    NSUInteger indexCopy = self.currentIndex;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [[NSUserDefaults standardUserDefaults] setObject:linesCopy forKey:@"AM_CachedLyrics"];
        [[NSUserDefaults standardUserDefaults] setInteger:indexCopy forKey:@"AM_CachedLyricsIndex"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    });
}

- (void)loadLyrics:(NSArray<NSString *> *)lines {
    [self.lyricsLines removeAllObjects];
    if (lines) {
        [self.lyricsLines addObjectsFromArray:lines];
    }
    self.currentIndex = 0;
    [self saveToDisk];
}

- (void)clearLyrics {
    [self.lyricsLines removeAllObjects];
    self.currentIndex = 0;
    [self saveToDisk];
}

- (void)resetToFirstVerse {
    self.currentIndex = 0;
    [self saveToDisk];
}

- (void)jumpToVerseIndex:(NSUInteger)index {
    if (index < self.lyricsLines.count) {
        self.currentIndex = index;
        [self saveToDisk];
    }
}

- (NSString *)currentLineText {
    if (self.currentIndex < self.lyricsLines.count) {
        return self.lyricsLines[self.currentIndex];
    }
    return nil;
}

- (NSString *)consumeNextLineText {
    if (self.currentIndex < self.lyricsLines.count) {
        NSString *line = self.lyricsLines[self.currentIndex];
        if (self.currentIndex + 1 < self.lyricsLines.count) {
            self.currentIndex++;
            [self saveToDisk];
        }
        return line;
    }
    return nil;
}

- (BOOL)hasNextLine {
    return self.currentIndex < self.lyricsLines.count;
}

@end

#pragma mark - Batch Lyrics Inserter Modal View Controller (With Smart LRC Cleaner)

@interface AMBatchLyricsViewController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *lineCountLabel;
@property (nonatomic, strong) UIButton *pasteButton;
@property (nonatomic, strong) UIButton *clearQueueButton;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, copy) void (^onLyricsLoaded)(void);
@end

@implementation AMBatchLyricsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor]; // #000000 Pure OLED Black

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];

    [self setupHeader];
    [self setupTextView];
    [self setupButtons];

    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count > 0) {
        self.textView.text = [mgr.lyricsLines componentsJoinedByString:@"\n"];
        [self updateLineCount];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupHeader {
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, self.view.bounds.size.width - 40, 28)];
    titleLabel.text = @"📝 Nạp Lời Bài Hát (Lyrics)";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 44, self.view.bounds.size.width - 40, 32)];
    subtitleLabel.text = @"Dán lời bài hát (mỗi dòng 1 câu - tự động lọc sạch timestamp LRC). Lưu hàng đợi hoặc xóa bất cứ lúc nào.";
    subtitleLabel.textColor = [UIColor colorWithRed:0.85 green:0.85 blue:0.85 alpha:1.0]; // #D9D9D9
    subtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:subtitleLabel];
}

- (void)setupTextView {
    CGFloat yPos = 82;
    CGFloat bottomMargin = 110;
    CGFloat h = self.view.bounds.size.height - yPos - bottomMargin;
    if (h < 150) h = 150;

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(16, yPos, self.view.bounds.size.width - 32, h)];
    self.textView.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.13 alpha:1.0]; // #141620
    self.textView.textColor = [UIColor whiteColor];
    self.textView.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.textView.layer.cornerRadius = 12.0;
    self.textView.layer.borderWidth = 1.2;
    self.textView.layer.borderColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:0.6].CGColor; // #00FFA8
    self.textView.delegate = self;
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.textView];

    self.lineCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, yPos + h + 6, self.view.bounds.size.width - 40, 20)];
    self.lineCountLabel.text = @"📊 Số dòng: 0 câu hát đã nhập";
    self.lineCountLabel.textColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:1.0]; // #00FFA8
    self.lineCountLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.lineCountLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.lineCountLabel];
}

- (void)setupButtons {
    CGFloat bottomY = self.view.bounds.size.height - 54;
    CGFloat width = self.view.bounds.size.width;

    // Paste Button
    self.pasteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.pasteButton.frame = CGRectMake(16, bottomY, 64, 42);
    [self.pasteButton setTitle:@"📋 Dán" forState:UIControlStateNormal];
    [self.pasteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pasteButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.16 blue:0.19 alpha:1.0]; // #262831
    self.pasteButton.layer.cornerRadius = 10.0;

    self.pasteButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.pasteButton addTarget:self action:@selector(pasteFromClipboard) forControlEvents:UIControlEventTouchUpInside];
    self.pasteButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.pasteButton];

    // Clear Queue Button
    self.clearQueueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearQueueButton.frame = CGRectMake(86, bottomY, 78, 42);
    [self.clearQueueButton setTitle:@"🗑️ Xóa Hết" forState:UIControlStateNormal];
    [self.clearQueueButton setTitleColor:[UIColor colorWithRed:1.0 green:0.45 blue:0.45 alpha:1.0] forState:UIControlStateNormal];
    self.clearQueueButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.1 blue:0.1 alpha:0.8];
    self.clearQueueButton.layer.cornerRadius = 10.0;
    self.clearQueueButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.clearQueueButton addTarget:self action:@selector(clearQueue) forControlEvents:UIControlEventTouchUpInside];
    self.clearQueueButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.clearQueueButton];

    // Save Queue Button
    CGFloat applyX = 170;
    CGFloat applyW = width - applyX - 60;
    self.applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.applyButton.frame = CGRectMake(applyX, bottomY, applyW, 42);
    [self.applyButton setTitle:@"⚡ Lưu Hàng Đợi Mới" forState:UIControlStateNormal];
    [self.applyButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.applyButton.backgroundColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:1.0]; // #00FFA8
    self.applyButton.layer.cornerRadius = 10.0;

    self.applyButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [self.applyButton addTarget:self action:@selector(applyLyricsToQueue) forControlEvents:UIControlEventTouchUpInside];
    self.applyButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.applyButton];

    // Close Button
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(width - 54, bottomY, 44, 42);
    [self.closeButton setTitle:@"Đóng" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(dismissModal) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:self.closeButton];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)clearQueue {
    self.textView.text = @"";
    [self updateLineCount];
    [[AMLyricsQueueManager sharedManager] clearLyrics];
    if (self.onLyricsLoaded) {
        self.onLyricsLoaded();
    }
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat keyboardHeight = keyboardFrame.size.height;
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    [UIView animateWithDuration:duration animations:^{
        CGRect frame = self.textView.frame;
        frame.size.height = self.view.bounds.size.height - 82 - keyboardHeight - 10;
        if (frame.size.height < 100) frame.size.height = 100;
        self.textView.frame = frame;
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    [UIView animateWithDuration:duration animations:^{
        CGRect frame = self.textView.frame;
        frame.size.height = self.view.bounds.size.height - 82 - 110;
        self.textView.frame = frame;
    }];
}

- (void)textViewDidChange:(UITextView *)textView {
    [self updateLineCount];
}

- (void)updateLineCount {
    NSArray *lines = [self extractValidLines:self.textView.text];
    self.lineCountLabel.text = [NSString stringWithFormat:@"📊 Số dòng: %lu câu hát đã nhập", (unsigned long)lines.count];
}

- (NSArray<NSString *> *)extractValidLines:(NSString *)rawText {
    if (!rawText || rawText.length == 0) return @[];
    NSArray *all = [rawText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *valid = [NSMutableArray array];
    
    static NSRegularExpression *lrcRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lrcRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\[\\d{1,2}:\\d{2}(?:[\\.:]\\d{1,3})?\\]\\s*" options:0 error:nil];
    });

    for (NSString *s in all) {
        NSString *trimmed = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            if (lrcRegex) {
                trimmed = [lrcRegex stringByReplacingMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length) withTemplate:@""];
                trimmed = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            }
            if (trimmed.length > 0) {
                [valid addObject:trimmed];
            }
        }
    }
    return valid;
}

- (void)pasteFromClipboard {
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    if (pb.string && pb.string.length > 0) {
        self.textView.text = pb.string;
        [self updateLineCount];
    }
}

- (void)dismissModal {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyLyricsToQueue {
    [self.view endEditing:YES];
    NSArray<NSString *> *lines = [self extractValidLines:self.textView.text];
    if (lines.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thông báo"
                                                                       message:@"Vui lòng dán lời bài hát (ít nhất 1 câu) trước khi lưu."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    [[AMLyricsQueueManager sharedManager] loadLyrics:lines];

    if (self.onLyricsLoaded) {
        self.onLyricsLoaded();
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Home Settings Dashboard Modal (Mở từ nút nổi ở Trang Chủ)

@interface AMHomeSettingsViewController : UIViewController
@property (nonatomic, strong) UILabel *lyricsStatusLabel;
@end

@implementation AMHomeSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Apple Native iOS 18 Dark Slate Background
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.10 alpha:1.0]; // #12141A Midnight Slate

    CGFloat w = self.view.bounds.size.width;

    // Header with App Title & Subtitle
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(20, 20, w - 40, 50)];
    headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:headerView];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, headerView.bounds.size.width, 26)];
    titleLabel.text = @"Alight Motion Pro";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    [headerView addSubview:titleLabel];

    UILabel *subTitle = [[UILabel alloc] initWithFrame:CGRectMake(0, 26, headerView.bounds.size.width, 18)];
    subTitle.text = @"Bản Dựng Tối Ưu • iOS 18 Native Experience";
    subTitle.textColor = [UIColor colorWithRed:0.58 green:0.62 blue:0.70 alpha:1.0]; // Slate muted
    subTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    [headerView addSubview:subTitle];

    // Card 1: Batch Lyrics Manager (Apple Native Slate Card)
    UIView *card1 = [[UIView alloc] initWithFrame:CGRectMake(16, 80, w - 32, 100)];
    card1.backgroundColor = [UIColor colorWithRed:0.12 green:0.13 blue:0.16 alpha:1.0]; // Apple Secondary Grouped Dark
    card1.layer.cornerRadius = 16.0;
    card1.layer.borderWidth = 1.0;
    card1.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.07].CGColor;
    card1.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:card1];

    UILabel *l1 = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, card1.bounds.size.width - 32, 20)];
    l1.text = @"Hàng Đợi Lời Bài Hát (Smart Lyrics)";
    l1.textColor = [UIColor whiteColor];
    l1.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [card1 addSubview:l1];

    self.lyricsStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 38, card1.bounds.size.width - 195, 50)];
    self.lyricsStatusLabel.textColor = [UIColor colorWithRed:0.20 green:0.80 blue:0.50 alpha:1.0]; // iOS Mint/Green
    self.lyricsStatusLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
    self.lyricsStatusLabel.numberOfLines = 2;
    [card1 addSubview:self.lyricsStatusLabel];
    [self refreshLyricsStatus];

    // Nạp Mới Button (Apple Slate Accent)
    UIButton *loadBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    loadBtn.frame = CGRectMake(card1.bounds.size.width - 180, 46, 85, 34);
    [loadBtn setTitle:@"Nạp Mới" forState:UIControlStateNormal];
    [loadBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    loadBtn.backgroundColor = [UIColor colorWithRed:0.00 green:0.48 blue:1.00 alpha:1.0]; // Apple System Blue
    loadBtn.layer.cornerRadius = 10.0;
    loadBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    loadBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [loadBtn addTarget:self action:@selector(openLyricsModal) forControlEvents:UIControlEventTouchUpInside];
    [card1 addSubview:loadBtn];

    // Xóa Hàng Đợi Button
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(card1.bounds.size.width - 86, 46, 72, 34);
    [clearBtn setTitle:@"Xóa" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.40 blue:0.40 alpha:1.0] forState:UIControlStateNormal];
    clearBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    clearBtn.layer.cornerRadius = 10.0;
    clearBtn.layer.borderWidth = 1.0;
    clearBtn.layer.borderColor = [UIColor colorWithRed:1.0 green:0.40 blue:0.40 alpha:0.2].CGColor;
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    clearBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [clearBtn addTarget:self action:@selector(clearQueueAction) forControlEvents:UIControlEventTouchUpInside];
    [card1 addSubview:clearBtn];

    // Card 2: Auto Save to Camera Roll
    UIView *card2 = [[UIView alloc] initWithFrame:CGRectMake(16, 192, w - 32, 72)];
    card2.backgroundColor = [UIColor colorWithRed:0.12 green:0.13 blue:0.16 alpha:1.0];
    card2.layer.cornerRadius = 16.0;
    card2.layer.borderWidth = 1.0;
    card2.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.07].CGColor;
    card2.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:card2];

    UILabel *l2 = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, card2.bounds.size.width - 100, 20)];
    l2.text = @"Tự Động Lưu Ảnh Vào Photos";
    l2.textColor = [UIColor whiteColor];
    l2.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [card2 addSubview:l2];

    UILabel *l2Sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, card2.bounds.size.width - 100, 20)];
    l2Sub.text = @"Tự động lưu khung hình PNG và ảnh chia sẻ vào Cuộn Camera";
    l2Sub.textColor = [UIColor colorWithRed:0.58 green:0.62 blue:0.70 alpha:1.0];
    l2Sub.font = [UIFont systemFontOfSize:11];
    [card2 addSubview:l2Sub];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(card2.bounds.size.width - 66, 20, 51, 31)];
    sw.onTintColor = [UIColor colorWithRed:0.20 green:0.80 blue:0.50 alpha:1.0]; // Apple Mint
    sw.on = AMIsAutoSaveEnabled();
    sw.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [sw addTarget:self action:@selector(toggleAutoSave:) forControlEvents:UIControlEventValueChanged];
    [card2 addSubview:sw];

    // Card 3: System Performance & Optimization Badges
    UIView *card3 = [[UIView alloc] initWithFrame:CGRectMake(16, 276, w - 32, 115)];
    card3.backgroundColor = [UIColor colorWithRed:0.12 green:0.13 blue:0.16 alpha:1.0];
    card3.layer.cornerRadius = 16.0;
    card3.layer.borderWidth = 1.0;
    card3.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.07].CGColor;
    card3.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:card3];

    UILabel *l3 = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, card3.bounds.size.width - 32, 20)];
    l3.text = @"Động Cơ Hiệu Năng & Trạng Thái";
    l3.textColor = [UIColor whiteColor];
    l3.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [card3 addSubview:l3];

    // 4 Badges layout inside Card 3
    NSArray *badges = @[
        @"✓ Mở Khóa Pro • No Watermark",
        @"✓ ProMotion 120 FPS & Metal 3x",
        @"✓ Anti-Throttling (Chống Tụt FPS)",
        @"✓ Triệt Tiêu 100% Ad & Telemetry"
    ];
    CGFloat badgeW = (card3.bounds.size.width - 40) / 2.0;
    for (int i = 0; i < 4; i++) {
        CGFloat bx = 16 + (i % 2) * (badgeW + 8);
        CGFloat by = 38 + (i / 2) * 34;
        UIView *bView = [[UIView alloc] initWithFrame:CGRectMake(bx, by, badgeW, 28)];
        bView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.04];
        bView.layer.cornerRadius = 8.0;
        bView.layer.borderWidth = 1.0;
        bView.layer.borderColor = [UIColor colorWithRed:0.20 green:0.80 blue:0.50 alpha:0.25].CGColor;
        
        UILabel *bLbl = [[UILabel alloc] initWithFrame:bView.bounds];
        bLbl.text = badges[i];
        bLbl.textColor = [UIColor colorWithRed:0.20 green:0.80 blue:0.50 alpha:1.0];
        bLbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        bLbl.textAlignment = NSTextAlignmentCenter;
        [bView addSubview:bLbl];
        [card3 addSubview:bView];
    }

    // Close Button (Apple Native Subtle Style)
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(16, self.view.bounds.size.height - 56, w - 32, 44);
    [closeBtn setTitle:@"Đóng" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithRed:0.75 green:0.80 blue:0.90 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.07];
    closeBtn.layer.cornerRadius = 14.0;
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    closeBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [closeBtn addTarget:self action:@selector(dismissSelf) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeBtn];
}

- (void)refreshLyricsStatus {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count == 0) {
        self.lyricsStatusLabel.text = @"Trạng thái: Trống (chưa có câu nào).";
        self.lyricsStatusLabel.textColor = [UIColor lightGrayColor];
    } else {
        self.lyricsStatusLabel.text = [NSString stringWithFormat:@"Đang có %lu câu trong hàng đợi.\n(Hiện tại: #%lu/%lu)", (unsigned long)mgr.lyricsLines.count, (unsigned long)(mgr.currentIndex + 1), (unsigned long)mgr.lyricsLines.count];
        self.lyricsStatusLabel.textColor = [UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0];
    }
}

- (void)clearQueueAction {
    [[AMLyricsQueueManager sharedManager] clearLyrics];
    [self refreshLyricsStatus];
}

- (void)toggleAutoSave:(UISwitch *)sw {
    AMSetAutoSaveEnabled(sw.on);
}

- (void)openLyricsModal {
    AMBatchLyricsViewController *modal = [[AMBatchLyricsViewController alloc] init];
    modal.modalPresentationStyle = UIModalPresentationFormSheet;
    __weak typeof(self) weakSelf = self;
    modal.onLyricsLoaded = ^{
        [weakSelf refreshLyricsStatus];
    };
    [self presentViewController:modal animated:YES completion:nil];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Sleek Glassmorphic Minimal Lyrics Accessory Bar (Rock-Solid Pixel-Perfect Layout)

@interface AMMinimalLyricsBar : UIView
@property (nonatomic, weak) UIViewController *targetVC;
@property (nonatomic, strong) UIView *capsule;
@property (nonatomic, strong) UIButton *prevBtn;
@property (nonatomic, strong) UIButton *nextBtn;
@property (nonatomic, strong) UIButton *versePillBtn;
@property (nonatomic, strong) UIButton *menuBtn;
@property (nonatomic, strong) UIButton *closeBtn;
+ (instancetype)barForViewController:(UIViewController *)vc;
- (void)refreshDisplay;
@end

@implementation AMMinimalLyricsBar

+ (instancetype)barForViewController:(UIViewController *)vc {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    AMMinimalLyricsBar *bar = [[self alloc] initWithFrame:CGRectMake(0, 0, screenW, 42.0)];
    bar.targetVC = vc;
    bar.backgroundColor = [UIColor clearColor];

    UIView *capsule = [[UIView alloc] initWithFrame:CGRectMake(8.0, 3.0, screenW - 16.0, 36.0)];
    capsule.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.13 alpha:0.96]; // #141620
    capsule.layer.cornerRadius = 18.0;
    capsule.layer.borderWidth = 1.0;
    capsule.layer.borderColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:0.4].CGColor; // #00FFA8
    capsule.clipsToBounds = YES;
    [bar addSubview:capsule];
    bar.capsule = capsule;

    // 1. Prev Button [‹]
    UIButton *prev = [UIButton buttonWithType:UIButtonTypeSystem];
    [prev setTitle:@"‹" forState:UIControlStateNormal];
    [prev setTitleColor:[UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:1.0] forState:UIControlStateNormal]; // #00FFA8
    prev.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    prev.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.8];
    prev.layer.cornerRadius = 14.0;
    [prev addTarget:bar action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:prev];
    bar.prevBtn = prev;

    // 2. Next Button [›]
    UIButton *next = [UIButton buttonWithType:UIButtonTypeSystem];
    [next setTitle:@"›" forState:UIControlStateNormal];
    [next setTitleColor:[UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:1.0] forState:UIControlStateNormal]; // #00FFA8
    next.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    next.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.8];
    next.layer.cornerRadius = 14.0;
    [next addTarget:bar action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:next];
    bar.nextBtn = next;

    // 3. Close Button [✕]
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithRed:0.85 green:0.85 blue:0.85 alpha:1.0] forState:UIControlStateNormal]; // #D9D9D9
    close.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];

    close.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.8];
    close.layer.cornerRadius = 14.0;
    [close addTarget:bar action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:close];
    bar.closeBtn = close;

    // 4. Menu Button [📋] (Nạp Lời / Chọn Câu / Xóa)
    UIButton *menu = [UIButton buttonWithType:UIButtonTypeSystem];
    [menu setTitle:@"📋" forState:UIControlStateNormal];
    menu.titleLabel.font = [UIFont systemFontOfSize:14];
    menu.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.8];
    menu.layer.cornerRadius = 14.0;
    [menu addTarget:bar action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    [capsule addSubview:menu];
    bar.menuBtn = menu;

    // 5. Verse Pill Button [⚡ #1/N: "Lời câu..."]
    UIButton *verse = [UIButton buttonWithType:UIButtonTypeSystem];
    verse.backgroundColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:0.18]; // #00FFA8
    verse.layer.cornerRadius = 14.0;
    verse.layer.borderWidth = 0.8;
    verse.layer.borderColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:0.5].CGColor; // #00FFA8
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

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 42.0);
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, 42.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets insets = self.safeAreaInsets;
    CGFloat w = self.bounds.size.width;
    CGFloat padLeft = MAX(8.0, insets.left);
    CGFloat padRight = MAX(8.0, insets.right);
    
    CGFloat capW = w - padLeft - padRight;
    if (capW < 100.0) capW = [UIScreen mainScreen].bounds.size.width - 16.0;
    
    self.capsule.frame = CGRectMake(padLeft, 3.0, capW, 36.0);

    CGFloat btnH = 28.0;
    CGFloat btnY = 4.0;

    self.prevBtn.frame = CGRectMake(4.0, btnY, 28.0, btnH);
    self.nextBtn.frame = CGRectMake(36.0, btnY, 28.0, btnH);

    self.closeBtn.frame = CGRectMake(capW - 32.0, btnY, 28.0, btnH);
    self.menuBtn.frame = CGRectMake(capW - 64.0, btnY, 28.0, btnH);

    CGFloat centerStartX = 68.0;
    CGFloat centerW = capW - 68.0 - 68.0;
    if (centerW < 60.0) centerW = 60.0;
    self.versePillBtn.frame = CGRectMake(centerStartX, btnY, centerW, btnH);
}

- (void)refreshDisplay {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    
    // Always keep all buttons visible!
    self.prevBtn.hidden = NO;
    self.nextBtn.hidden = NO;
    self.menuBtn.hidden = NO;
    self.closeBtn.hidden = NO;
    self.versePillBtn.hidden = NO;

    if (mgr.lyricsLines.count == 0) {
        self.prevBtn.enabled = NO;
        self.prevBtn.alpha = 0.35;
        self.nextBtn.enabled = NO;
        self.nextBtn.alpha = 0.35;
        [self.versePillBtn setTitle:@"📋 Chạm để Nạp Lời Bài Hát" forState:UIControlStateNormal];
        [self.versePillBtn setTitleColor:[UIColor colorWithRed:0.0 green:0.90 blue:0.46 alpha:1.0] forState:UIControlStateNormal];
    } else {
        self.prevBtn.enabled = (mgr.currentIndex > 0);
        self.prevBtn.alpha = (mgr.currentIndex > 0) ? 1.0 : 0.4;

        self.nextBtn.enabled = (mgr.currentIndex + 1 < mgr.lyricsLines.count);
        self.nextBtn.alpha = (mgr.currentIndex + 1 < mgr.lyricsLines.count) ? 1.0 : 0.4;

        NSUInteger cur = mgr.currentIndex + 1;
        NSString *line = [mgr currentLineText] ?: @"";
        NSString *title = [NSString stringWithFormat:@"⚡ %lu/%lu: \"%@\"", (unsigned long)cur, (unsigned long)mgr.lyricsLines.count, line];
        [self.versePillBtn setTitle:title forState:UIControlStateNormal];
        [self.versePillBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
}

- (void)verseTapped {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count == 0) {
        [self loadTapped];
        return;
    }

    NSString *line = [mgr currentLineText];
    if (!line) return;

    UITextView *tv = nil;
    if ([self.targetVC respondsToSelector:@selector(inputTextView)]) {
        tv = [self.targetVC valueForKey:@"inputTextView"];
    }
    if (!tv) {
        for (UIView *sub in self.targetVC.view.subviews) {
            if ([sub isKindOfClass:[UITextView class]]) {
                tv = (UITextView *)sub;
                break;
            }
        }
    }

    if (tv) {
        tv.text = line;
        if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
            [tv.delegate textViewDidChange:tv];
        }
        if ([tv.delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
            [tv.delegate textView:tv shouldChangeTextInRange:NSMakeRange(0, tv.text.length) replacementText:line];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];

        @try {
            [self.targetVC setValue:line forKey:@"appearText"];
        } @catch (NSException *e) {}

        [mgr consumeNextLineText];
        [self refreshDisplay];

        AudioServicesPlaySystemSound(1519);
    }
}

- (void)prevTapped {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.currentIndex > 0) {
        mgr.currentIndex--;
        [mgr saveToDisk];
    }
    [self refreshDisplay];
}

- (void)nextTapped {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.currentIndex + 1 < mgr.lyricsLines.count) {
        mgr.currentIndex++;
        [mgr saveToDisk];
    }
    [self refreshDisplay];
}

- (void)closeTapped {
    [self.targetVC.view endEditing:YES];
}

- (void)menuTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Quản Lý Lời Bài Hát"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"📝 Nạp Lời Mới / Chỉnh Sửa" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self loadTapped];
    }]];

    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count > 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"🔄 Bắt Đầu Lại Từ Câu #1" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [mgr resetToFirstVerse];
            [self refreshDisplay];
        }]];

        [sheet addAction:[UIAlertAction actionWithTitle:@"🎯 Chọn Câu Cụ Thể Trong Danh Sách" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self openVersePicker];
        }]];

        [sheet addAction:[UIAlertAction actionWithTitle:@"🗑️ Xóa Sạch Hàng Đợi" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [mgr clearLyrics];
            [self refreshDisplay];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];

    [self.targetVC presentViewController:sheet animated:YES completion:nil];
}

- (void)openVersePicker {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Chọn Câu Hát Bắt Đầu"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSUInteger i = 0; i < mgr.lyricsLines.count && i < 25; i++) {
        NSString *verseTitle = [NSString stringWithFormat:@"#%lu: \"%@\"", (unsigned long)(i + 1), mgr.lyricsLines[i]];
        [picker addAction:[UIAlertAction actionWithTitle:verseTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [mgr jumpToVerseIndex:i];
            [self refreshDisplay];
        }]];
    }

    [picker addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self.targetVC presentViewController:picker animated:YES completion:nil];
}

- (void)loadTapped {
    AMBatchLyricsViewController *modal = [[AMBatchLyricsViewController alloc] init];
    modal.modalPresentationStyle = UIModalPresentationFormSheet;
    __weak typeof(self) weakSelf = self;
    modal.onLyricsLoaded = ^{
        [weakSelf refreshDisplay];
    };
    [self.targetVC presentViewController:modal animated:YES completion:nil];
}

@end

#pragma mark - Home Screen Floating Settings HUD (CHỈ HIỆN Ở TRANG CHỦ)

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
    btn.frame = CGRectMake(16.0, window.bounds.size.height - 140.0, 46.0, 46.0);
    btn.layer.cornerRadius = 23.0;
    // Apple iOS 18 Midnight Slate Glass Surface
    btn.backgroundColor = [UIColor colorWithRed:0.13 green:0.14 blue:0.18 alpha:0.92];
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 4);
    btn.layer.shadowRadius = 10.0;
    btn.layer.shadowOpacity = 0.35;

    // SF Symbol with Slate Tint
    UIImage *symbol = nil;
    if (@available(iOS 13.0, *)) {
        symbol = [UIImage systemImageNamed:@"slider.horizontal.3"];
        if (!symbol) symbol = [UIImage systemImageNamed:@"gearshape.fill"];
    }
    if (symbol) {
        [btn setImage:symbol forState:UIControlStateNormal];
        btn.tintColor = [UIColor colorWithRed:0.80 green:0.85 blue:0.95 alpha:1.0]; // Slate Ice Blue
    } else {
        [btn setTitle:@"⚙️" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:20.0];
    }
    
    [btn addTarget:self action:@selector(floatingButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    self.floatingButton = btn;

    [window addSubview:btn];
    [window bringSubviewToFront:btn];
}

- (void)setFloatingButtonVisible:(BOOL)visible {
    if (self.floatingButton) {
        self.floatingButton.hidden = !visible;
    }
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
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.4 options:UIViewAnimationOptionCurveEaseOut animations:^{
            view.center = CGPointMake(snapX, center.y);
        } completion:nil];
    }
}

- (void)floatingButtonTapped:(UIButton *)sender {
    // Native Haptic Feedback
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [haptic prepare];
        [haptic impactOccurred];
    }

    UIWindow *window = self.parentWindow ?: [UIApplication sharedApplication].windows.firstObject;
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }

    AMHomeSettingsViewController *vc = [[AMHomeSettingsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationFormSheet;
    [root presentViewController:vc animated:YES completion:nil];
}

@end

#pragma mark - =========================================================
#pragma mark 7. Liquid Glass Button & Elastic Motion Engine
#pragma mark - =========================================================

static void (*orig_UIButton_touchesBegan)(UIButton *, SEL, NSSet<UITouch *> *, UIEvent *);
static void hook_UIButton_touchesBegan(UIButton *self, SEL _cmd, NSSet<UITouch *> *touches, UIEvent *event) {
    if (orig_UIButton_touchesBegan) {
        orig_UIButton_touchesBegan(self, _cmd, touches, event);
    }
    // Elastic liquid compression (co dãn giọt nước)
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = CGAffineTransformMakeScale(0.92, 0.92);
        self.alpha = 0.88;
    } completion:nil];
}

static void (*orig_UIButton_touchesEnded)(UIButton *, SEL, NSSet<UITouch *> *, UIEvent *);
static void hook_UIButton_touchesEnded(UIButton *self, SEL _cmd, NSSet<UITouch *> *touches, UIEvent *event) {
    if (orig_UIButton_touchesEnded) {
        orig_UIButton_touchesEnded(self, _cmd, touches, event);
    }
    // Liquid haptic impulse
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [haptic prepare];
        [haptic impactOccurred];
    }
    // Spring liquid rebound (bật nảy lò xo đàn hồi mượt mà)
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.48 initialSpringVelocity:0.8 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1.0;
    } completion:nil];
}

static void (*orig_UIButton_touchesCancelled)(UIButton *, SEL, NSSet<UITouch *> *, UIEvent *);
static void hook_UIButton_touchesCancelled(UIButton *self, SEL _cmd, NSSet<UITouch *> *touches, UIEvent *event) {
    if (orig_UIButton_touchesCancelled) {
        orig_UIButton_touchesCancelled(self, _cmd, touches, event);
    }
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1.0;
    } completion:nil];
}

static void (*orig_UIButton_layoutSubviews)(UIButton *, SEL);
static void hook_UIButton_layoutSubviews(UIButton *self, SEL _cmd) {
    if (orig_UIButton_layoutSubviews) {
        orig_UIButton_layoutSubviews(self, _cmd);
    }
    // Continuous liquid curvature (bo cong liền mạch tự nhiên)
    if (@available(iOS 13.0, *)) {
        if (self.layer.cornerRadius > 4.0) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
    }
}

static void AMInitLiquidGlassButtonEngine(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class btnClass = [UIButton class];
        if (btnClass) {
            Method mBegan = class_getInstanceMethod(btnClass, @selector(touchesBegan:withEvent:));
            if (mBegan) {
                orig_UIButton_touchesBegan = (void *)method_getImplementation(mBegan);
                method_setImplementation(mBegan, (IMP)hook_UIButton_touchesBegan);
            }
            Method mEnded = class_getInstanceMethod(btnClass, @selector(touchesEnded:withEvent:));
            if (mEnded) {
                orig_UIButton_touchesEnded = (void *)method_getImplementation(mEnded);
                method_setImplementation(mEnded, (IMP)hook_UIButton_touchesEnded);
            }
            Method mCancelled = class_getInstanceMethod(btnClass, @selector(touchesCancelled:withEvent:));
            if (mCancelled) {
                orig_UIButton_touchesCancelled = (void *)method_getImplementation(mCancelled);
                method_setImplementation(mCancelled, (IMP)hook_UIButton_touchesCancelled);
            }
            Method mLayout = class_getInstanceMethod(btnClass, @selector(layoutSubviews));
            if (mLayout) {
                orig_UIButton_layoutSubviews = (void *)method_getImplementation(mLayout);
                method_setImplementation(mLayout, (IMP)hook_UIButton_layoutSubviews);
            }
        }
    });
}

#pragma mark - Hook UITextView (Lyrics Accessory Bar)

static BOOL (*orig_UITextView_becomeFirstResponder)(UITextView *, SEL);
static BOOL hook_UITextView_becomeFirstResponder(UITextView *self, SEL _cmd) {
    if (self.inputAccessoryView == nil) {
        UIResponder *responder = self;
        while ((responder = [responder nextResponder])) {
            if ([responder isKindOfClass:[UIViewController class]]) {
                break;
            }
        }
        if (responder) {
            NSString *vcName = NSStringFromClass([responder class]);
            if ([vcName containsString:@"TextInput"] || [vcName containsString:@"Edit"] || [vcName containsString:@"Text"]) {
                AMMinimalLyricsBar *bar = [AMMinimalLyricsBar barForViewController:(UIViewController *)responder];
                self.inputAccessoryView = bar;
            }
        }
        // Force Dark Keyboard Appearance across app
        self.keyboardAppearance = UIKeyboardAppearanceDark;
    }
    if (orig_UITextView_becomeFirstResponder) {
        return orig_UITextView_becomeFirstResponder(self, _cmd);
    }

    return YES;
}

static BOOL (*orig_UITextView_resignFirstResponder)(UITextView *, SEL);
static BOOL hook_UITextView_resignFirstResponder(UITextView *self, SEL _cmd) {
    if (orig_UITextView_resignFirstResponder) {
        return orig_UITextView_resignFirstResponder(self, _cmd);
    }
    return YES;
}




#pragma mark - =========================================================
#pragma mark 7. View Controller Lifecycle & Home Screen Floating HUD
static id getObjcIvar(id obj, const char *name) {
    if (!obj) return nil;
    Class cls = object_getClass(obj);
    while (cls) {
        Ivar iv = class_getInstanceVariable(cls, name);
        if (iv) return object_getIvar(obj, iv);
        cls = class_getSuperclass(cls);
    }
    return nil;
}

// Restored 100% native bitrate and video export quality handling (no custom slider override)

#pragma mark - =========================================================
#pragma mark Export Auto-Save & FastStart Moov Pipeline Hooks
#pragma mark - =========================================================

static void (*orig_UISaveVideoAtPathToSavedPhotosAlbum)(NSString *, id, SEL, void *);
static void hook_UISaveVideoAtPathToSavedPhotosAlbum(NSString *videoPath, id target, SEL action, void *context) {
    if (videoPath && videoPath.length > 0) {
        NSString *ext = videoPath.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"mov"]) {
            UMV_OptimizeMP4(videoPath);
        }
    }
    if (orig_UISaveVideoAtPathToSavedPhotosAlbum) {
        orig_UISaveVideoAtPathToSavedPhotosAlbum(videoPath, target, action, context);
    }
    AMNotifyUser(@"UMV Engine v6.6.6 Pro", @"Video đã được tối ưu hóa FastStart Moov & lưu vào Camera Roll!");
}

static void (*orig_ExportPreviewVC_viewDidAppear)(UIViewController *, SEL, BOOL);
static void hook_ExportPreviewVC_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_ExportPreviewVC_viewDidAppear) {
        orig_ExportPreviewVC_viewDidAppear(self, _cmd, animated);
    }

    if (AMIsAutoSaveEnabled()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                // Only auto-save if this preview is for an IMAGE export (no videoControlView or hidden)
                UIView *videoCtrl = nil;
                @try { videoCtrl = [self valueForKey:@"videoControlView"]; } @catch (NSException *e) {}
                BOOL isVideo = (videoCtrl && !videoCtrl.hidden);

                if (!isVideo) {
                    UIButton *btn = (UIButton *)getObjcIvar(self, "storeButton");
                    if (!btn) {
                        @try { btn = [self valueForKey:@"storeButton"]; } @catch (NSException *e) {}
                    }
                    if ([self respondsToSelector:@selector(onTapSave:)]) {
                        ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(onTapSave:), btn ?: self);
                        AMNotifyUser(@"Alight Motion", @"🖼️ Đã tự động lưu khung ảnh vào Cuộn Camera (Photos)!");
                    } else if (btn && [btn isKindOfClass:[UIButton class]]) {
                        [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                        [btn sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
                        AMNotifyUser(@"Alight Motion", @"🖼️ Đã tự động lưu khung ảnh vào Cuộn Camera (Photos)!");
                    }
                }
            } @catch (NSException *e) {
                NSLog(@"[AlightMotionUltra] Auto-save image error: %@", e);
            }
        });
    }
}

static void (*orig_ExportVC_viewDidAppear)(UIViewController *, SEL, BOOL);
static void hook_ExportVC_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_ExportVC_viewDidAppear) {
        orig_ExportVC_viewDidAppear(self, _cmd, animated);
    }
}

static void AMApplyDefaultWhiteColorPatch(void) {
    uintptr_t slide = (uintptr_t)_dyld_get_image_vmaddr_slide(0);
    uintptr_t colorVecAddr = slide + 0x1025c2c00;

    mach_port_t self_task = mach_task_self();
    vm_address_t page_start = (vm_address_t)(colorVecAddr & ~0xfff);
    kern_return_t kr = vm_protect(self_task, page_start, 0x1000, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr == KERN_SUCCESS) {
        float whiteVec[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
        memcpy((void *)colorVecAddr, whiteVec, sizeof(whiteVec));
        vm_protect(self_task, page_start, 0x1000, FALSE, VM_PROT_READ);
        NSLog(@"[AlightMotionUltra] Successfully patched native default color vector at 0x%lx to pure White (1.0, 1.0, 1.0, 1.0)!", colorVecAddr);
    } else {
        NSLog(@"[AlightMotionUltra] vm_protect failed on default color vector: %d", kr);
    }
}

#pragma mark - =========================================================
#pragma mark Pure OLED Dark Mode Engine (Based on Android APK Reference)
#pragma mark =========================================================

#define COLOR_OLED_BG       [UIColor colorWithRed:0.00 green:0.00 blue:0.00 alpha:1.0] // #000000
#define COLOR_SURFACE_BASE  [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:1.0] // #17181B
#define COLOR_SURFACE_CARD  [UIColor colorWithRed:0.13 green:0.13 blue:0.17 alpha:1.0] // #21222B
#define COLOR_ELEVATED      [UIColor colorWithRed:0.15 green:0.16 blue:0.19 alpha:1.0] // #262831
#define COLOR_PRIMARY_ACC   [UIColor colorWithRed:0.00 green:0.80 blue:0.68 alpha:1.0] // #00CCAD
#define COLOR_SEC_ACC       [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:1.0] // #00E575
#define COLOR_DIVIDER       [UIColor colorWithRed:0.37 green:0.38 blue:0.44 alpha:1.0] // #5F606F
#define COLOR_TEXT_PRI      [UIColor colorWithRed:1.00 green:1.00 blue:1.00 alpha:1.0] // #FFFFFF
#define COLOR_TEXT_SEC      [UIColor colorWithRed:0.85 green:0.85 blue:0.85 alpha:1.0] // #D9D9D9

static void (*orig_UIViewController_viewWillAppear)(UIViewController *, SEL, BOOL);

static void applyDarkThemeRecursive(UIView *view, BOOL isRoot) {
    if (!view) return;
    
    // Do NOT recolor Metal video viewport / Canvas texture layer
    NSString *vClass = NSStringFromClass([view class]);
    if ([vClass containsString:@"MTKView"] || [vClass containsString:@"CAMetalLayer"] || [vClass containsString:@"Canvas"]) {
        return;
    }
    
    // Replace light / white backgrounds with OLED Black or Dark Surface
    if (view.backgroundColor) {
        CGFloat r, g, b, a;
        if ([view.backgroundColor getRed:&r green:&g blue:&b alpha:&a]) {
            if (r > 0.85 && g > 0.85 && b > 0.85 && a > 0.5) {
                view.backgroundColor = isRoot ? COLOR_OLED_BG : COLOR_SURFACE_CARD;
            } else if (r > 0.5 && g > 0.5 && b > 0.5 && a > 0.5) {
                view.backgroundColor = COLOR_ELEVATED;
            }
        }
    }
    
    // TableView & CollectionView styling
    if ([view isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)view;
        tv.backgroundColor = COLOR_OLED_BG;
        tv.backgroundView = nil;
        tv.separatorColor = COLOR_DIVIDER;
    } else if ([view isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)view;
        cv.backgroundColor = COLOR_OLED_BG;
        cv.backgroundView = nil;
    }
    
    // Contrast safeguard: Elevate dark text (< 0.4 brightness) to light text to prevent black-on-black invisibility
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *lbl = (UILabel *)view;
        CGFloat r, g, b, a;
        if ([lbl.textColor getRed:&r green:&g blue:&b alpha:&a]) {
            if (r < 0.40 && g < 0.40 && b < 0.40 && a > 0.5) {
                lbl.textColor = COLOR_TEXT_PRI;
            }
        }
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        tf.keyboardAppearance = UIKeyboardAppearanceDark;
        CGFloat r, g, b, a;
        if ([tf.textColor getRed:&r green:&g blue:&b alpha:&a]) {
            if (r < 0.40 && g < 0.40 && b < 0.40 && a > 0.5) {
                tf.textColor = COLOR_TEXT_PRI;
            }
        }
    } else if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        tv.keyboardAppearance = UIKeyboardAppearanceDark;
        CGFloat r, g, b, a;
        if ([tv.textColor getRed:&r green:&g blue:&b alpha:&a]) {
            if (r < 0.40 && g < 0.40 && b < 0.40 && a > 0.5) {
                tv.textColor = COLOR_TEXT_PRI;
            }
        }
    } else if ([vClass containsString:@"WKWebView"]) {
        view.backgroundColor = COLOR_OLED_BG;
        view.opaque = NO;
        if ([view respondsToSelector:@selector(scrollView)]) {
            UIScrollView *sv = [view performSelector:@selector(scrollView)];
            sv.backgroundColor = COLOR_OLED_BG;
            sv.indicatorStyle = UIScrollViewIndicatorStyleWhite;
        }
    }
    
    for (UIView *sub in view.subviews) {
        applyDarkThemeRecursive(sub, NO);
    }
}

static void hook_UIViewController_viewWillAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_UIViewController_viewWillAppear) {
        orig_UIViewController_viewWillAppear(self, _cmd, animated);
    }
    
    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName containsString:@"AlightMotion"] || [clsName containsString:@"Edit"] || [clsName containsString:@"Home"] || [clsName containsString:@"Project"]) {
        if (self.view) {
            self.view.backgroundColor = COLOR_OLED_BG;
            applyDarkThemeRecursive(self.view, YES);
        }
        
        UINavigationBar *navBar = self.navigationController.navigationBar;
        if (navBar) {
            navBar.barTintColor = COLOR_OLED_BG;
            navBar.backgroundColor = COLOR_OLED_BG;
            navBar.tintColor = COLOR_PRIMARY_ACC;
            navBar.titleTextAttributes = @{NSForegroundColorAttributeName: COLOR_TEXT_PRI};
        }
        
        UITabBar *tabBar = self.tabBarController.tabBar;
        if (tabBar) {
            tabBar.barTintColor = COLOR_OLED_BG;
            tabBar.backgroundColor = COLOR_OLED_BG;
            tabBar.tintColor = COLOR_PRIMARY_ACC;
            tabBar.unselectedItemTintColor = COLOR_TEXT_SEC;
        }
    }
}

#pragma mark - =========================================================
#pragma mark 8. Ultimate Smoothness & 120 FPS Performance Engine
#pragma mark - =========================================================

typedef struct {
    float minimum;
    float maximum;
    float preferred;
} AMFrameRateRange;

// 1. Force 120 FPS ProMotion on all CADisplayLink instances (Timeline, Scrubbing, Animation)
static CADisplayLink *(*orig_CADisplayLink_displayLinkWithTarget_selector)(id, SEL, id, SEL);
static CADisplayLink *hook_CADisplayLink_displayLinkWithTarget_selector(id self, SEL _cmd, id target, SEL sel) {
    CADisplayLink *dl = orig_CADisplayLink_displayLinkWithTarget_selector ? orig_CADisplayLink_displayLinkWithTarget_selector(self, _cmd, target, sel) : nil;
    if (dl) {
        if ([dl respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
            dl.preferredFramesPerSecond = 120;
        }
        if ([dl respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
            AMFrameRateRange range = { 60.0f, 120.0f, 120.0f };
            typedef void (*SetRangeFunc)(id, SEL, AMFrameRateRange);
            ((SetRangeFunc)objc_msgSend)(dl, @selector(setPreferredFrameRateRange:), range);
        }
    }
    return dl;
}

static void (*orig_CADisplayLink_addToRunLoop_forMode)(id, SEL, NSRunLoop *, NSRunLoopMode);
static void hook_CADisplayLink_addToRunLoop_forMode(id self, SEL _cmd, NSRunLoop *runloop, NSRunLoopMode mode) {
    if ([self respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
        ((CADisplayLink *)self).preferredFramesPerSecond = 120;
    }
    if ([self respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
        AMFrameRateRange range = { 60.0f, 120.0f, 120.0f };
        typedef void (*SetRangeFunc)(id, SEL, AMFrameRateRange);
        ((SetRangeFunc)objc_msgSend)(self, @selector(setPreferredFrameRateRange:), range);
    }
    if (orig_CADisplayLink_addToRunLoop_forMode) {
        orig_CADisplayLink_addToRunLoop_forMode(self, _cmd, runloop, mode);
    }
}

// 2. GPU Triple-Buffering for CAMetalLayer (Zero Stutter on Heavy Video & Effects)
static id (*orig_CAMetalLayer_init)(id, SEL);
static id hook_CAMetalLayer_init(id self, SEL _cmd) {
    self = orig_CAMetalLayer_init ? orig_CAMetalLayer_init(self, _cmd) : self;
    if (self) {
        if ([self respondsToSelector:@selector(setMaximumDrawableCount:)]) {
            ((void(*)(id, SEL, NSUInteger))objc_msgSend)(self, @selector(setMaximumDrawableCount:), 3);
        }
        if ([self respondsToSelector:@selector(setPresentsWithTransaction:)]) {
            ((void(*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setPresentsWithTransaction:), NO);
        }
        if ([self respondsToSelector:@selector(setDisplaySyncEnabled:)]) {
            ((void(*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setDisplaySyncEnabled:), YES);
        }
    }
    return self;
}

// 3. Thermal Throttling & Low Power Mode Bypass (Prevents FPS drop when iPhone gets warm)
static NSProcessInfoThermalState hook_NSProcessInfo_thermalState(id self, SEL _cmd) {
    return NSProcessInfoThermalStateNominal; // Always 0 (Cool)
}

static BOOL hook_NSProcessInfo_isLowPowerModeEnabled(id self, SEL _cmd) {
    return NO; // Never throttle CPU/GPU
}

static UIDeviceBatteryState hook_UIDevice_batteryState(id self, SEL _cmd) {
    return UIDeviceBatteryStateCharging; // Always charging for max CPU/GPU clock
}

static float hook_UIDevice_batteryLevel(id self, SEL _cmd) {
    return 1.0f; // 100% full battery
}

static BOOL hook_UIDevice_isBatteryMonitoringEnabled(id self, SEL _cmd) {
    return NO;
}

// 4. Instant Zero-Stall Video Playback (Timeline Preview Starts Immediately)
static void (*orig_AVPlayer_setAutomaticallyWaitsToMinimizeStalling)(id, SEL, BOOL);
static void hook_AVPlayer_setAutomaticallyWaitsToMinimizeStalling(id self, SEL _cmd, BOOL waits) {
    if (orig_AVPlayer_setAutomaticallyWaitsToMinimizeStalling) {
        orig_AVPlayer_setAutomaticallyWaitsToMinimizeStalling(self, _cmd, NO);
    }
}

// 5. Expand Texture Cache & Thumbnail Cache Limits (Prevents reload stutters)
static void AMOptimizeCacheAndMemory(void) {
    NSURLCache *sharedCache = [NSURLCache sharedURLCache];
    if (sharedCache) {
        [sharedCache setMemoryCapacity:128 * 1024 * 1024]; // 128 MB RAM Cache
        [sharedCache setDiskCapacity:512 * 1024 * 1024];   // 512 MB Disk Cache
    }
}

static void AMInitSmoothnessAndPerformanceEngine(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1. Hook CADisplayLink for 120 FPS
        Class dlClass = [CADisplayLink class];
        if (dlClass) {
            Method mCreate = class_getClassMethod(dlClass, @selector(displayLinkWithTarget:selector:));
            if (mCreate) {
                orig_CADisplayLink_displayLinkWithTarget_selector = (void *)method_getImplementation(mCreate);
                method_setImplementation(mCreate, (IMP)hook_CADisplayLink_displayLinkWithTarget_selector);
            }
            Method mAdd = class_getInstanceMethod(dlClass, @selector(addToRunLoop:forMode:));
            if (mAdd) {
                orig_CADisplayLink_addToRunLoop_forMode = (void *)method_getImplementation(mAdd);
                method_setImplementation(mAdd, (IMP)hook_CADisplayLink_addToRunLoop_forMode);
            }
        }

        // 2. Hook CAMetalLayer for Triple Buffering
        Class metalLayerClass = objc_getClass("CAMetalLayer");
        if (metalLayerClass) {
            Method mInit = class_getInstanceMethod(metalLayerClass, @selector(init));
            if (mInit) {
                orig_CAMetalLayer_init = (void *)method_getImplementation(mInit);
                method_setImplementation(mInit, (IMP)hook_CAMetalLayer_init);
            }
        }

        // 3. Hook NSProcessInfo for Thermal & Low Power Throttling Bypass
        Class procClass = [NSProcessInfo class];
        if (procClass) {
            Method mThermal = class_getInstanceMethod(procClass, @selector(thermalState));
            if (mThermal) {
                method_setImplementation(mThermal, (IMP)hook_NSProcessInfo_thermalState);
            }
            Method mLowPower = class_getInstanceMethod(procClass, @selector(isLowPowerModeEnabled));
            if (mLowPower) {
                method_setImplementation(mLowPower, (IMP)hook_NSProcessInfo_isLowPowerModeEnabled);
            }
        }

        // 4. Hook UIDevice to prevent Battery Low Power Clocks
        Class devClass = [UIDevice class];
        if (devClass) {
            Method mBatState = class_getInstanceMethod(devClass, @selector(batteryState));
            if (mBatState) method_setImplementation(mBatState, (IMP)hook_UIDevice_batteryState);
            Method mBatLvl = class_getInstanceMethod(devClass, @selector(batteryLevel));
            if (mBatLvl) method_setImplementation(mBatLvl, (IMP)hook_UIDevice_batteryLevel);
            Method mBatMon = class_getInstanceMethod(devClass, @selector(isBatteryMonitoringEnabled));
            if (mBatMon) method_setImplementation(mBatMon, (IMP)hook_UIDevice_isBatteryMonitoringEnabled);
        }

        // 5. Hook AVPlayer for Zero-Stall Playback
        Class avClass = [AVPlayer class];
        if (avClass) {
            Method mStall = class_getInstanceMethod(avClass, @selector(setAutomaticallyWaitsToMinimizeStalling:));
            if (mStall) {
                orig_AVPlayer_setAutomaticallyWaitsToMinimizeStalling = (void *)method_getImplementation(mStall);
                method_setImplementation(mStall, (IMP)hook_AVPlayer_setAutomaticallyWaitsToMinimizeStalling);
            }
        }

        // 6. Expand Cache
        AMOptimizeCacheAndMemory();
        NSLog(@"[AlightMotionUltra] Successfully initialized 120 FPS ProMotion & Metal Triple-Buffering Engine!");
    });
}

__attribute__((constructor)) static void initAlightMotionUltra() {
    // 0. Instant Cold Boot: Neutralize heavy ad & telemetry SDKs synchronously before UIApplication starts
    AMNeutralizeAdNetworks();
    AMApplyProSettings();
    AMInitSmoothnessAndPerformanceEngine();
    AMInitLiquidGlassButtonEngine();
    AMUnlockProjectPackageLimit();

    // 1. Rebind Keychain & Photos functions using Fishhook
    rebind_symbols((struct rebinding[5]){
        {"SecItemAdd", (void *)hook_SecItemAdd, (void **)&orig_SecItemAdd},
        {"SecItemCopyMatching", (void *)hook_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
        {"SecItemUpdate", (void *)hook_SecItemUpdate, (void **)&orig_SecItemUpdate},
        {"SecItemDelete", (void *)hook_SecItemDelete, (void **)&orig_SecItemDelete},
        {"UISaveVideoAtPathToSavedPhotosAlbum", (void *)hook_UISaveVideoAtPathToSavedPhotosAlbum, (void **)&orig_UISaveVideoAtPathToSavedPhotosAlbum}
    }, 5);

    dispatch_async(dispatch_get_main_queue(), ^{
        // 2. Apply Pro Monetization state immediately and on launch notification
        AMApplyProSettings();
        AMNeutralizeAdNetworks();
        AMInitSmoothnessAndPerformanceEngine();
        AMInitLiquidGlassButtonEngine();
        AMUnlockProjectPackageLimit();
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            AMApplyProSettings();
            AMNeutralizeAdNetworks();
            AMInitSmoothnessAndPerformanceEngine();
            AMInitLiquidGlassButtonEngine();
            AMUnlockProjectPackageLimit();
        }];

        // 3. Swizzle NSFileManager containerURLForSecurityApplicationGroupIdentifier:
        Method mContainer = class_getInstanceMethod([NSFileManager class], @selector(containerURLForSecurityApplicationGroupIdentifier:));
        if (mContainer) {
            orig_containerURLForSecurityApplicationGroupIdentifier = (void *)method_getImplementation(mContainer);
            method_setImplementation(mContainer, (IMP)hook_containerURLForSecurityApplicationGroupIdentifier);
        }

        // 4. Hook UIActivityViewController for UMV Engine FastStart Auto-Save
        Class actClass = [UIActivityViewController class];
        Method mAct = class_getInstanceMethod(actClass, @selector(initWithActivityItems:applicationActivities:));
        if (mAct) {
            orig_UIActivityViewController_initWithActivityItems = (void *)method_getImplementation(mAct);
            method_setImplementation(mAct, (IMP)hook_UIActivityViewController_initWithActivityItems);
        }

        // 5. Hook ExportPreviewVC & ExportVC for Instant Auto-Save
        Class expPrevClass = objc_getClass("_TtC12AlightMotion15ExportPreviewVC");
        if (expPrevClass) {
            Method mAppear = class_getInstanceMethod(expPrevClass, @selector(viewDidAppear:));
            if (mAppear) {
                orig_ExportPreviewVC_viewDidAppear = (void *)method_getImplementation(mAppear);
                method_setImplementation(mAppear, (IMP)hook_ExportPreviewVC_viewDidAppear);
            }
        }
        Class expClass = objc_getClass("_TtC12AlightMotion8ExportVC");
        if (expClass) {
            Method mAppear = class_getInstanceMethod(expClass, @selector(viewDidAppear:));
            if (mAppear) {
                orig_ExportVC_viewDidAppear = (void *)method_getImplementation(mAppear);
                method_setImplementation(mAppear, (IMP)hook_ExportVC_viewDidAppear);
            }
        }

        // 6. Hook UITextView (Font Memory, White Text Color & Lyrics Accessory Bar)
        Class tvClass = [UITextView class];
        if (tvClass) {
            Method becomeMethod = class_getInstanceMethod(tvClass, @selector(becomeFirstResponder));
            if (becomeMethod) {
                orig_UITextView_becomeFirstResponder = (void *)method_getImplementation(becomeMethod);
                method_setImplementation(becomeMethod, (IMP)hook_UITextView_becomeFirstResponder);
            }
            Method resignMethod = class_getInstanceMethod(tvClass, @selector(resignFirstResponder));
            if (resignMethod) {
                orig_UITextView_resignFirstResponder = (void *)method_getImplementation(resignMethod);
                method_setImplementation(resignMethod, (IMP)hook_UITextView_resignFirstResponder);
            }
        }

        // AMApplyDefaultWhiteColorPatch disabled on v6.2.60 to prevent stripping execute permissions from __objc_stubs
        // AMApplyDefaultWhiteColorPatch();

        // 7. Pure Dark Mode Engine removed per user request

        // Native bitrate engine preserved 100% untouched
        NSLog(@"[AlightMotionUltra] Successfully initialized Clean Tweak with 120 FPS ProMotion, Triple Buffering & FastStart Auto-Save!");
    });
}


