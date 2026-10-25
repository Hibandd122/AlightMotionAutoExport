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
        if ([defaultName isEqualToString:@"Forced Subscription status"] ||
            [defaultName isEqualToString:@"subscription_status"] ||
            [defaultName isEqualToString:@"subscriptionStatus"]) {
            return @"active";
        }
        if ([defaultName isEqualToString:@"AM_ActiveProductID"] ||
            [defaultName isEqualToString:@"activeProductID"] ||
            [defaultName isEqualToString:@"productId"]) {
            return @"alightcreative.motion.1y_t80";
        }
        if ([defaultName isEqualToString:@"active_subscriptions"] ||
            [defaultName isEqualToString:@"activeSubscriptions"]) {
            return @{
                @"alightcreative.motion.1y_t80": @{
                    @"product_id": @"alightcreative.motion.1y_t80",
                    @"status": @"active",
                    @"expires_date_ms": @"4102444800000",
                    @"is_trial_period": @NO,
                    @"auto_renew_status": @YES
                }
            };
        }
        if ([defaultName isEqualToString:@"UnlockAllProFeatures"] ||
            [defaultName isEqualToString:@"isSubscribedToUltra"] ||
            [defaultName isEqualToString:@"isPremium"] ||
            [defaultName isEqualToString:@"hasMembership"] ||
            [defaultName isEqualToString:@"benefit_remove_watermark"] ||
            [defaultName isEqualToString:@"remove_watermark"] ||
            [defaultName isEqualToString:@"has_active_subscriptions"] ||
            [defaultName isEqualToString:@"isSubscribed"] ||
            [defaultName isEqualToString:@"is_subscribed"] ||
            [defaultName isEqualToString:@"isPremiumUser"] ||
            [defaultName isEqualToString:@"watermark_removed"]) {
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
            [defaultName isEqualToString:@"has_active_subscriptions"] ||
            [defaultName isEqualToString:@"isSubscribed"] ||
            [defaultName isEqualToString:@"is_subscribed"] ||
            [defaultName isEqualToString:@"isPremiumUser"] ||
            [defaultName isEqualToString:@"watermark_removed"]) {
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
    [ud setObject:@YES forKey:@"isSubscribed"];
    [ud setObject:@YES forKey:@"is_subscribed"];
    [ud setObject:@YES forKey:@"isPremiumUser"];
    [ud setObject:@YES forKey:@"watermark_removed"];
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

#pragma mark - =========================================================
#pragma mark UI Helpers: Spring Micro-Animation & Apple SF Symbols
#pragma mark - =========================================================

static void AMApplySpringTouchAnimation(UIButton *btn) {
    if (!btn) return;
    [btn addTarget:btn action:@selector(_am_onTouchDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:btn action:@selector(_am_onTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
}

@interface UIButton (AMSpringAnimation)
- (void)_am_onTouchDown:(UIButton *)sender;
- (void)_am_onTouchUp:(UIButton *)sender;
@end

@implementation UIButton (AMSpringAnimation)
- (void)_am_onTouchDown:(UIButton *)sender {
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        sender.transform = CGAffineTransformMakeScale(0.92, 0.92);
        sender.alpha = 0.82;
    } completion:nil];
}

- (void)_am_onTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:3.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        sender.transform = CGAffineTransformIdentity;
        sender.alpha = 1.0;
    } completion:nil];
}
@end

static UIImage *AMGetSystemIcon(NSString *symbolName, NSString *fallbackText, CGFloat pointSize, UIFontWeight weight) {
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
        UIImage *img = [UIImage systemImageNamed:symbolName withConfiguration:config];
        if (img) return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return nil;
}

#pragma mark - =========================================================
#pragma mark Batch Lyrics Modal (Apple Modern Sheet UI + Glassmorphism)
#pragma mark - =========================================================

@interface AMBatchLyricsViewController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UIView *sheetContainer;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *statsPillLabel;
@property (nonatomic, strong) UIButton *pasteButton;
@property (nonatomic, strong) UIButton *clearQueueButton;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, copy) void (^onLyricsLoaded)(void);
@end

@implementation AMBatchLyricsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:1.0]; // #0A0D12 Deep OLED

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];

    [self setupCardUI];

    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];
    if (mgr.lyricsLines.count > 0) {
        self.textView.text = [mgr.lyricsLines componentsJoinedByString:@"\n"];
        self.placeholderLabel.hidden = YES;
    }
    [self updateLineCount];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupCardUI {
    CGFloat viewW = self.view.bounds.size.width;
    CGFloat viewH = self.view.bounds.size.height;

    // 1. Drag / Pull Indicator Pill
    UIView *grabber = [[UIView alloc] initWithFrame:CGRectMake((viewW - 40.0) / 2.0, 10.0, 40.0, 5.0)];
    grabber.backgroundColor = [UIColor colorWithWhite:0.32 alpha:1.0];
    grabber.layer.cornerRadius = 2.5;
    grabber.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:grabber];

    // 2. Close Button Top-Right [✕]
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(viewW - 46.0, 16.0, 32.0, 32.0);
    UIImage *closeIcon = AMGetSystemIcon(@"xmark.circle.fill", @"✕", 20.0, UIFontWeightBold);
    if (closeIcon) {
        [self.closeButton setImage:closeIcon forState:UIControlStateNormal];
        self.closeButton.tintColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    } else {
        [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
        [self.closeButton setTitleColor:[UIColor colorWithWhite:0.65 alpha:1.0] forState:UIControlStateNormal];
        self.closeButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    }
    [self.closeButton addTarget:self action:@selector(dismissModal) forControlEvents:UIControlEventTouchUpInside];
    AMApplySpringTouchAnimation(self.closeButton);
    self.closeButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:self.closeButton];

    // 3. Header Titles
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 26.0, viewW - 75.0, 26.0)];
    self.titleLabel.text = @"📝 Quản Lý Lời Bài Hát";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightBold];
    self.titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 52.0, viewW - 40.0, 18.0)];
    self.subtitleLabel.text = @"Tự động nhận diện câu & làm sạch timestamp LRC.";
    self.subtitleLabel.textColor = [UIColor colorWithRed:0.62 green:0.65 blue:0.75 alpha:1.0];
    self.subtitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    self.subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.subtitleLabel];

    // 4. Stats Pill Label (Mini Badge)
    self.statsPillLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 76.0, viewW - 40.0, 24.0)];
    self.statsPillLabel.textColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:1.0]; // #00FFA8
    self.statsPillLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    self.statsPillLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.statsPillLabel];

    // 5. Input TextView with Glass Frame
    CGFloat textY = 108.0;
    CGFloat bottomMargin = 120.0;
    CGFloat textH = viewH - textY - bottomMargin;
    if (textH < 150.0) textH = 150.0;

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(16.0, textY, viewW - 32.0, textH)];
    self.textView.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.15 alpha:0.95]; // #141A26
    self.textView.textColor = [UIColor whiteColor];
    self.textView.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium];
    self.textView.layer.cornerRadius = 14.0;
    self.textView.layer.borderWidth = 1.0;
    self.textView.layer.borderColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:0.35].CGColor;
    self.textView.textContainerInset = UIEdgeInsetsMake(12.0, 10.0, 12.0, 10.0);
    self.textView.delegate = self;
    self.textView.keyboardAppearance = UIKeyboardAppearanceDark;
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.textView];

    // Placeholder inside textview
    self.placeholderLabel = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 12.0, self.textView.bounds.size.width - 32.0, 60.0)];
    self.placeholderLabel.text = @"Dán lời bài hát vào đây (mỗi dòng 1 câu)...\nVí dụ:\n[00:12.30] Câu hát thứ nhất\n[00:15.80] Câu hát thứ hai";
    self.placeholderLabel.textColor = [UIColor colorWithWhite:0.42 alpha:1.0];
    self.placeholderLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightRegular];
    self.placeholderLabel.numberOfLines = 4;
    self.placeholderLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.textView addSubview:self.placeholderLabel];

    // 6. Bottom Floating Action Dock
    CGFloat btnY = viewH - 62.0;
    CGFloat gap = 10.0;

    // Paste Button [📋 Dán]
    self.pasteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.pasteButton.frame = CGRectMake(16.0, btnY, 82.0, 44.0);
    [self.pasteButton setTitle:@"📋 Dán" forState:UIControlStateNormal];
    [self.pasteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pasteButton.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    self.pasteButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.18 blue:0.25 alpha:1.0];
    self.pasteButton.layer.cornerRadius = 12.0;
    self.pasteButton.layer.borderWidth = 0.8;
    self.pasteButton.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    [self.pasteButton addTarget:self action:@selector(pasteFromClipboard) forControlEvents:UIControlEventTouchUpInside];
    AMApplySpringTouchAnimation(self.pasteButton);
    self.pasteButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.pasteButton];

    // Clear Button [🗑️ Xóa]
    self.clearQueueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearQueueButton.frame = CGRectMake(16.0 + 82.0 + gap, btnY, 78.0, 44.0);
    [self.clearQueueButton setTitle:@"🗑️ Xóa" forState:UIControlStateNormal];
    [self.clearQueueButton setTitleColor:[UIColor colorWithRed:1.00 green:0.45 blue:0.45 alpha:1.0] forState:UIControlStateNormal];
    self.clearQueueButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.clearQueueButton.backgroundColor = [UIColor colorWithRed:0.28 green:0.10 blue:0.12 alpha:0.85];
    self.clearQueueButton.layer.cornerRadius = 12.0;
    self.clearQueueButton.layer.borderWidth = 0.8;
    self.clearQueueButton.layer.borderColor = [UIColor colorWithRed:1.00 green:0.40 blue:0.40 alpha:0.3].CGColor;
    [self.clearQueueButton addTarget:self action:@selector(clearQueue) forControlEvents:UIControlEventTouchUpInside];
    AMApplySpringTouchAnimation(self.clearQueueButton);
    self.clearQueueButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.clearQueueButton];

    // Save & Apply Button [⚡ Lưu Hàng Đợi]
    CGFloat applyX = 16.0 + 82.0 + gap + 78.0 + gap;
    CGFloat applyW = viewW - applyX - 16.0;
    self.applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.applyButton.frame = CGRectMake(applyX, btnY, applyW, 44.0);
    [self.applyButton setTitle:@"⚡ Lưu & Sử Dụng" forState:UIControlStateNormal];
    [self.applyButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.applyButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    self.applyButton.backgroundColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:1.0]; // #00FFA8
    self.applyButton.layer.cornerRadius = 12.0;
    [self.applyButton addTarget:self action:@selector(applyLyricsToQueue) forControlEvents:UIControlEventTouchUpInside];
    AMApplySpringTouchAnimation(self.applyButton);
    self.applyButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.applyButton];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)clearQueue {
    self.textView.text = @"";
    self.placeholderLabel.hidden = NO;
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
        frame.size.height = self.view.bounds.size.height - 108.0 - keyboardHeight - 10.0;
        if (frame.size.height < 100.0) frame.size.height = 100.0;
        self.textView.frame = frame;
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    [UIView animateWithDuration:duration animations:^{
        CGRect frame = self.textView.frame;
        frame.size.height = self.view.bounds.size.height - 108.0 - 120.0;
        self.textView.frame = frame;
    }];
}

- (void)textViewDidChange:(UITextView *)textView {
    self.placeholderLabel.hidden = (textView.text.length > 0);
    [self updateLineCount];
}

- (void)updateLineCount {
    NSArray *lines = [self extractValidLines:self.textView.text];
    NSUInteger totalWords = 0;
    for (NSString *s in lines) {
        NSArray *words = [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        for (NSString *w in words) {
            if (w.length > 0) totalWords++;
        }
    }
    self.statsPillLabel.text = [NSString stringWithFormat:@"📊 %lu câu hát • %lu từ • Sẵn sàng nạp", (unsigned long)lines.count, (unsigned long)totalWords];
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
        self.placeholderLabel.hidden = YES;
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
                                                                       message:@"Vui lòng nhập hoặc dán ít nhất 1 câu hát trước khi lưu."
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


#pragma mark - =========================================================
#pragma mark Minimal Lyrics Bar (Frosted Glass Capsule + SF Symbols)
#pragma mark - =========================================================

@interface AMMinimalLyricsBar : UIView
@property (nonatomic, weak) UIViewController *targetVC;
@property (nonatomic, strong) UIVisualEffectView *blurView;
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
    AMMinimalLyricsBar *bar = [[self alloc] initWithFrame:CGRectMake(0, 0, screenW, 44.0)];
    bar.targetVC = vc;
    bar.backgroundColor = [UIColor clearColor];

    // 1. Frosted Glass Capsule Container
    UIView *capsule = [[UIView alloc] initWithFrame:CGRectMake(8.0, 3.0, screenW - 16.0, 38.0)];
    capsule.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.12 alpha:0.92];
    capsule.layer.cornerRadius = 19.0;
    capsule.layer.borderWidth = 1.0;
    capsule.layer.borderColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:0.35].CGColor; // #00FFA8
    capsule.clipsToBounds = YES;
    [bar addSubview:capsule];
    bar.capsule = capsule;

    // Blur Background
    UIBlurEffect *blurEffect = nil;
    if (@available(iOS 13.0, *)) {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    } else {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    }
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blur.frame = capsule.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [capsule addSubview:blur];
    bar.blurView = blur;

    // 2. Prev Button [‹ / chevron.left]
    UIButton *prev = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *prevImg = AMGetSystemIcon(@"chevron.left", @"‹", 15.0, UIFontWeightBold);
    if (prevImg) {
        [prev setImage:prevImg forState:UIControlStateNormal];
        prev.tintColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:1.0];
    } else {
        [prev setTitle:@"‹" forState:UIControlStateNormal];
        [prev setTitleColor:[UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:1.0] forState:UIControlStateNormal];
        prev.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    }
    prev.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.8];
    prev.layer.cornerRadius = 15.0;
    [prev addTarget:bar action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];
    AMApplySpringTouchAnimation(prev);
    [capsule addSubview:prev];
    bar.prevBtn = prev;

    // 3. Next Button [› / chevron.right]
    UIButton *next = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *nextImg = AMGetSystemIcon(@"chevron.right", @"›", 15.0, UIFontWeightBold);
    if (nextImg) {
        [next setImage:nextImg forState:UIControlStateNormal];
        next.tintColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:1.0];
    } else {
        [next setTitle:@"›" forState:UIControlStateNormal];
        [next setTitleColor:[UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:1.0] forState:UIControlStateNormal];
        next.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    }
    next.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.8];
    next.layer.cornerRadius = 15.0;
    [next addTarget:bar action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    AMApplySpringTouchAnimation(next);
    [capsule addSubview:next];
    bar.nextBtn = next;

    // 4. Close Button [✕ / keyboard.chevron.compact.down]
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *closeImg = AMGetSystemIcon(@"keyboard.chevron.compact.down", @"✕", 15.0, UIFontWeightSemibold);
    if (closeImg) {
        [close setImage:closeImg forState:UIControlStateNormal];
        close.tintColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    } else {
        [close setTitle:@"✕" forState:UIControlStateNormal];
        [close setTitleColor:[UIColor colorWithWhite:0.85 alpha:1.0] forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    }
    close.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.8];
    close.layer.cornerRadius = 15.0;
    [close addTarget:bar action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    AMApplySpringTouchAnimation(close);
    [capsule addSubview:close];
    bar.closeBtn = close;

    // 5. Menu Button [slider.horizontal.3 / 📋]
    UIButton *menu = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *menuImg = AMGetSystemIcon(@"slider.horizontal.3", @"📋", 14.0, UIFontWeightMedium);
    if (menuImg) {
        [menu setImage:menuImg forState:UIControlStateNormal];
        menu.tintColor = [UIColor colorWithWhite:0.90 alpha:1.0];
    } else {
        [menu setTitle:@"📋" forState:UIControlStateNormal];
        menu.titleLabel.font = [UIFont systemFontOfSize:14];
    }
    menu.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.8];
    menu.layer.cornerRadius = 15.0;
    [menu addTarget:bar action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    AMApplySpringTouchAnimation(menu);
    [capsule addSubview:menu];
    bar.menuBtn = menu;

    // 6. Verse Pill Center Button [⚡ #1/N: "Câu hát..."]
    UIButton *verse = [UIButton buttonWithType:UIButtonTypeSystem];
    verse.backgroundColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:0.16]; // Emerald Glow
    verse.layer.cornerRadius = 15.0;
    verse.layer.borderWidth = 0.8;
    verse.layer.borderColor = [UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:0.45].CGColor;
    [verse setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    verse.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    verse.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    verse.contentEdgeInsets = UIEdgeInsetsMake(0, 10.0, 0, 10.0);
    [verse addTarget:bar action:@selector(verseTapped) forControlEvents:UIControlEventTouchUpInside];
    AMApplySpringTouchAnimation(verse);
    [capsule addSubview:verse];
    bar.versePillBtn = verse;

    [bar setNeedsLayout];
    [bar refreshDisplay];
    return bar;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 44.0);
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, 44.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets insets = self.safeAreaInsets;
    CGFloat w = self.bounds.size.width;
    CGFloat padLeft = MAX(8.0, insets.left);
    CGFloat padRight = MAX(8.0, insets.right);

    CGFloat capW = w - padLeft - padRight;
    if (capW < 100.0) capW = [UIScreen mainScreen].bounds.size.width - 16.0;

    self.capsule.frame = CGRectMake(padLeft, 3.0, capW, 38.0);

    CGFloat btnH = 30.0;
    CGFloat btnY = 4.0;

    self.prevBtn.frame = CGRectMake(4.0, btnY, 30.0, btnH);
    self.nextBtn.frame = CGRectMake(38.0, btnY, 30.0, btnH);

    self.closeBtn.frame = CGRectMake(capW - 34.0, btnY, 30.0, btnH);
    self.menuBtn.frame = CGRectMake(capW - 68.0, btnY, 30.0, btnH);

    CGFloat centerStartX = 72.0;
    CGFloat centerW = capW - 72.0 - 72.0;
    if (centerW < 60.0) centerW = 60.0;
    self.versePillBtn.frame = CGRectMake(centerStartX, btnY, centerW, btnH);
}

- (void)refreshDisplay {
    AMLyricsQueueManager *mgr = [AMLyricsQueueManager sharedManager];

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
        [self.versePillBtn setTitle:@"✨ Chạm để nạp lời bài hát..." forState:UIControlStateNormal];
        [self.versePillBtn setTitleColor:[UIColor colorWithRed:0.00 green:1.00 blue:0.66 alpha:1.0] forState:UIControlStateNormal];
    } else {
        self.prevBtn.enabled = (mgr.currentIndex > 0);
        self.prevBtn.alpha = (mgr.currentIndex > 0) ? 1.0 : 0.4;

        self.nextBtn.enabled = (mgr.currentIndex + 1 < mgr.lyricsLines.count);
        self.nextBtn.alpha = (mgr.currentIndex + 1 < mgr.lyricsLines.count) ? 1.0 : 0.4;

        NSUInteger cur = mgr.currentIndex + 1;
        NSString *line = [mgr currentLineText] ?: @"";
        NSString *title = [NSString stringWithFormat:@"⚡ #%lu/%lu: \"%@\"", (unsigned long)cur, (unsigned long)mgr.lyricsLines.count, line];
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
    modal.modalPresentationStyle = UIModalPresentationPageSheet;
    __weak typeof(self) weakSelf = self;
    modal.onLyricsLoaded = ^{
        [weakSelf refreshDisplay];
    };
    [self.targetVC presentViewController:modal animated:YES completion:nil];
}

@end


#pragma mark - Universal Haptic Silencer (Triệt tiêu 100% mọi nguồn phát rung)

static void noop_haptic_void(id self, SEL _cmd, ...) {
    // 100% Im lặng - không rung
}

static BOOL noop_haptic_false(id self, SEL _cmd, ...) {
    return NO;
}

static id noop_haptic_nil(id self, SEL _cmd, ...) {
    return nil;
}

static void hook_CHHapticEngine_startWithCompletionHandler(id self, SEL _cmd, void (^handler)(NSError *)) {
    if (handler) {
        NSError *err = [NSError errorWithDomain:@"CHHapticErrorDomain" code:-4805 userInfo:@{NSLocalizedDescriptionKey: @"Haptics disabled"}];
        handler(err);
    }
}

static long long hook_UIDevice_feedbackSupportLevel(id self, SEL _cmd) {
    // 0 = Hardware có 0 haptic engine (tương đương iPad/iPod), UIKit tự động tắt vĩnh viễn toàn bộ haptics
    return 0;
}

// Fishhook hooks for AudioServices (Chặn đứng mọi system sound clicks & motor vibrations)
static void (*orig_AudioServicesPlaySystemSound)(SystemSoundID);
static void hook_AudioServicesPlaySystemSound(SystemSoundID soundID) {
    // Block 100% mọi system sound & haptic
    return;
}

static void (*orig_AudioServicesPlaySystemSoundWithCompletion)(SystemSoundID, void (^)(void));
static void hook_AudioServicesPlaySystemSoundWithCompletion(SystemSoundID soundID, void (^block)(void)) {
    if (block) block();
    return;
}

static void (*orig_AudioServicesPlayAlertSound)(SystemSoundID);
static void hook_AudioServicesPlayAlertSound(SystemSoundID soundID) {
    return;
}

static void (*orig_AudioServicesPlayAlertSoundWithCompletion)(SystemSoundID, void (^)(void));
static void hook_AudioServicesPlayAlertSoundWithCompletion(SystemSoundID soundID, void (^block)(void)) {
    if (block) block();
    return;
}

static void AMNeutralizeAllHaptics(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1. Tắt cấp độ phần cứng haptic trên UIDevice (Master Switch của UIKit)
        Class devCls = [UIDevice class];
        if (devCls) {
            Method mF1 = class_getInstanceMethod(devCls, @selector(_feedbackSupportLevel));
            if (mF1) method_setImplementation(mF1, (IMP)hook_UIDevice_feedbackSupportLevel);
            else class_addMethod(devCls, @selector(_feedbackSupportLevel), (IMP)hook_UIDevice_feedbackSupportLevel, "q@:");

            Method mF2 = class_getInstanceMethod(devCls, @selector(feedbackSupportLevel));
            if (mF2) method_setImplementation(mF2, (IMP)hook_UIDevice_feedbackSupportLevel);
            else class_addMethod(devCls, @selector(feedbackSupportLevel), (IMP)hook_UIDevice_feedbackSupportLevel, "q@:");

            Class metaDev = object_getClass((id)devCls);
            if (metaDev) {
                Method mF3 = class_getInstanceMethod(metaDev, @selector(_feedbackSupportLevel));
                if (mF3) method_setImplementation(mF3, (IMP)hook_UIDevice_feedbackSupportLevel);
                else class_addMethod(metaDev, @selector(_feedbackSupportLevel), (IMP)hook_UIDevice_feedbackSupportLevel, "q@:");
            }
        }

        // 2. Tắt master switch trên UIFeedbackGenerator
        Class fbCls = objc_getClass("UIFeedbackGenerator");
        if (fbCls) {
            Class metaFb = object_getClass((id)fbCls);
            if (metaFb) {
                Method mMeta = class_getInstanceMethod(metaFb, @selector(_feedbackSupportLevel));
                if (mMeta) method_setImplementation(mMeta, (IMP)hook_UIDevice_feedbackSupportLevel);
                else class_addMethod(metaFb, @selector(_feedbackSupportLevel), (IMP)hook_UIDevice_feedbackSupportLevel, "q@:");
            }
        }

        // 3. Triệt tiêu các phương thức thực thi rung của UIKit Feedback Generators
        Class selGen = [UISelectionFeedbackGenerator class];
        if (selGen) {
            Method m = class_getInstanceMethod(selGen, @selector(selectionChanged));
            if (m) method_setImplementation(m, (IMP)noop_haptic_void);
            Method mLoc = class_getInstanceMethod(selGen, sel_registerName("selectionChangedAtLocation:"));
            if (mLoc) method_setImplementation(mLoc, (IMP)noop_haptic_void);
        }
        Class impGen = [UIImpactFeedbackGenerator class];
        if (impGen) {
            Method m1 = class_getInstanceMethod(impGen, @selector(impactOccurred));
            if (m1) method_setImplementation(m1, (IMP)noop_haptic_void);
            Method m2 = class_getInstanceMethod(impGen, @selector(impactOccurredWithIntensity:));
            if (m2) method_setImplementation(m2, (IMP)noop_haptic_void);
            Method m3 = class_getInstanceMethod(impGen, sel_registerName("impactOccurredWithIntensity:atLocation:"));
            if (m3) method_setImplementation(m3, (IMP)noop_haptic_void);
            Method m4 = class_getInstanceMethod(impGen, sel_registerName("impactOccurredAtLocation:"));
            if (m4) method_setImplementation(m4, (IMP)noop_haptic_void);
        }
        Class notGen = [UINotificationFeedbackGenerator class];
        if (notGen) {
            Method m = class_getInstanceMethod(notGen, @selector(notificationOccurred:));
            if (m) method_setImplementation(m, (IMP)noop_haptic_void);
            Method mLoc = class_getInstanceMethod(notGen, sel_registerName("notificationOccurred:atLocation:"));
            if (mLoc) method_setImplementation(mLoc, (IMP)noop_haptic_void);
        }
        Class baseGen = [UIFeedbackGenerator class];
        if (baseGen) {
            Method mPrep = class_getInstanceMethod(baseGen, @selector(prepare));
            if (mPrep) method_setImplementation(mPrep, (IMP)noop_haptic_void);
            Method mAct = class_getInstanceMethod(baseGen, sel_registerName("activateWithCompletionBlock:"));
            if (mAct) method_setImplementation(mAct, (IMP)noop_haptic_void);
            Method mPlay = class_getInstanceMethod(baseGen, sel_registerName("_playFeedback:withTimestamp:"));
            if (mPlay) method_setImplementation(mPlay, (IMP)noop_haptic_void);
            Method mUpd = class_getInstanceMethod(baseGen, sel_registerName("_clientDidUpdateFeedback:"));
            if (mUpd) method_setImplementation(mUpd, (IMP)noop_haptic_void);
        }


        // 4. Triệt tiêu CoreHaptics an toàn (Trả về NO/nil cho hardware capability)
        Class chEngineCls = objc_getClass("CHHapticEngine");
        if (chEngineCls) {
            Class metaCh = object_getClass((id)chEngineCls);
            if (metaCh) {
                Method m1 = class_getInstanceMethod(metaCh, @selector(capabilitiesForHardware));
                if (m1) method_setImplementation(m1, (IMP)noop_haptic_false);
                Method m2 = class_getInstanceMethod(metaCh, @selector(supportsHaptics));
                if (m2) method_setImplementation(m2, (IMP)noop_haptic_false);
            }
            Method mStart = class_getInstanceMethod(chEngineCls, sel_registerName("startAndReturnError:"));
            if (mStart) method_setImplementation(mStart, (IMP)noop_haptic_false);
            Method mCreate = class_getInstanceMethod(chEngineCls, sel_registerName("createPlayerWithPattern:error:"));
            if (mCreate) method_setImplementation(mCreate, (IMP)noop_haptic_nil);
            Method mCreateAdv = class_getInstanceMethod(chEngineCls, sel_registerName("createAdvancedPlayerWithPattern:error:"));
            if (mCreateAdv) method_setImplementation(mCreateAdv, (IMP)noop_haptic_nil);
            Method mStartComp = class_getInstanceMethod(chEngineCls, sel_registerName("startWithCompletionHandler:"));
            if (mStartComp) method_setImplementation(mStartComp, (IMP)hook_CHHapticEngine_startWithCompletionHandler);
        }

        NSLog(@"[AlightMotionUltra] Successfully neutralized haptics cleanly with 100%% stability!");
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
#pragma mark 7. Export Pipeline & Auto-Save Lifecycle
#pragma mark - =========================================================

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
    AMNeutralizeAllHaptics();
    AMApplyProSettings();
    AMInitSmoothnessAndPerformanceEngine();
    AMUnlockProjectPackageLimit();

    // 1. Rebind Keychain, Photos & AudioServices functions using Fishhook
    rebind_symbols((struct rebinding[9]){
        {"SecItemAdd", (void *)hook_SecItemAdd, (void **)&orig_SecItemAdd},
        {"SecItemCopyMatching", (void *)hook_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
        {"SecItemUpdate", (void *)hook_SecItemUpdate, (void **)&orig_SecItemUpdate},
        {"SecItemDelete", (void *)hook_SecItemDelete, (void **)&orig_SecItemDelete},
        {"UISaveVideoAtPathToSavedPhotosAlbum", (void *)hook_UISaveVideoAtPathToSavedPhotosAlbum, (void **)&orig_UISaveVideoAtPathToSavedPhotosAlbum},
        {"AudioServicesPlaySystemSound", (void *)hook_AudioServicesPlaySystemSound, (void **)&orig_AudioServicesPlaySystemSound},
        {"AudioServicesPlaySystemSoundWithCompletion", (void *)hook_AudioServicesPlaySystemSoundWithCompletion, (void **)&orig_AudioServicesPlaySystemSoundWithCompletion},
        {"AudioServicesPlayAlertSound", (void *)hook_AudioServicesPlayAlertSound, (void **)&orig_AudioServicesPlayAlertSound},
        {"AudioServicesPlayAlertSoundWithCompletion", (void *)hook_AudioServicesPlayAlertSoundWithCompletion, (void **)&orig_AudioServicesPlayAlertSoundWithCompletion}
    }, 9);

    dispatch_async(dispatch_get_main_queue(), ^{
        // 2. Apply Pro Monetization state immediately and on launch notification
        AMApplyProSettings();
        AMNeutralizeAdNetworks();
        AMNeutralizeAllHaptics();
        AMInitSmoothnessAndPerformanceEngine();
        AMUnlockProjectPackageLimit();
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            AMApplyProSettings();
            AMNeutralizeAdNetworks();
            AMNeutralizeAllHaptics();
            AMInitSmoothnessAndPerformanceEngine();
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


