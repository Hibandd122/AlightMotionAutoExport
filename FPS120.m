#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

// This file adds a separate 120 FPS choice to the new-project screen.
// The app's Swift source is unavailable, so the setter bridge intentionally
// tries the public/KVC-visible names exposed by the inspected binary.

static char AMFPS120TargetKey;
static char AMFPS120SelectedKey;
static const NSInteger AMFPS120ButtonTag = 120120;

@interface AMFPS120Target : NSObject
@property(nonatomic, weak) id controller;
- (void)select120:(UIButton *)sender;
@end

static void AMSetValueIfPossible(id object, NSString *key, NSNumber *value) {
    if (!object || !key) return;

    NSString *first = [[[key substringToIndex:1] uppercaseString] copy];
    NSString *setterName = [first stringByAppendingString:[key substringFromIndex:1]];
    SEL setter = NSSelectorFromString([NSString stringWithFormat:@"set%@:", setterName]);
    if ([object respondsToSelector:setter]) {
        ((void (*)(id, SEL, id))objc_msgSend)(object, setter, value);
        return;
    }

    @try {
        [object setValue:value forKey:key];
    } @catch (__unused NSException *exception) {
        // Swift-only/private properties may not be KVC-visible.
    }
}

static void AMApply120FPS(id controller) {
    if (!controller) return;

    NSNumber *fps = @120;
    // Names found in the app binary and export/project metadata.
    for (NSString *key in @[@"frameRate", @"fps", @"exportFPS", @"newScenePresetFPS", @"new_scene_preset_fps"]) {
        AMSetValueIfPossible(controller, key, fps);
    }

    // Keep a tweak-local marker so the create hook can re-apply the value just
    // before the original project creation flow runs.
    objc_setAssociatedObject(controller, AMFPS120SelectedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL AMIs120FPSSelected(id controller) {
    return [objc_getAssociatedObject(controller, AMFPS120SelectedKey) boolValue];
}

static void AMInstall120Button(UIViewController *controller) {
    if (![controller isKindOfClass:[UIViewController class]]) return;
    if (objc_getAssociatedObject(controller, AMFPS120TargetKey)) return;

    UIView *root = controller.view;
    if (!root) return;

    id valueButton = nil;
    @try {
        valueButton = [controller valueForKey:@"valueFrameRateButton"];
    } @catch (__unused NSException *exception) {}

    UIView *anchor = [valueButton isKindOfClass:[UIView class]] ? valueButton : nil;
    UIView *parent = anchor.superview ?: root;

    AMFPS120Target *target = [AMFPS120Target new];
    target.controller = controller;
    objc_setAssociatedObject(controller, AMFPS120TargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = AMFPS120ButtonTag;
    button.accessibilityIdentifier = @"alightmotion.fps.120";
    [button setTitle:@"120 FPS" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    button.layer.cornerRadius = 8.0;
    button.layer.masksToBounds = YES;
    button.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button addTarget:target action:@selector(select120:) forControlEvents:UIControlEventTouchUpInside];

    CGRect frame = anchor ? anchor.frame : CGRectMake(20.0, 120.0, 120.0, 40.0);
    frame.origin.y += frame.size.height + 8.0;
    frame.size.width = MAX(frame.size.width, 110.0);
    frame.size.height = 38.0;
    button.frame = frame;
    button.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    [parent addSubview:button];
}

@implementation AMFPS120Target

- (void)select120:(UIButton *)sender {
    id controller = self.controller;
    AMApply120FPS(controller);
    sender.backgroundColor = [UIColor colorWithRed:0.10 green:0.45 blue:0.95 alpha:1.0];
    [sender setTitle:@"120 FPS (selected)" forState:UIControlStateNormal];
}

@end

static void (*AMOriginalCreate)(id, SEL, id);

static void AMHookCreate(id self, SEL _cmd, id sender) {
    if (AMIs120FPSSelected(self)) {
        AMApply120FPS(self);
    }
    if (AMOriginalCreate) {
        AMOriginalCreate(self, _cmd, sender);
    }
}

static void AMSwizzleCreateVC(Class createClass) {
    static BOOL done = NO;
    if (done || !createClass) return;
    done = YES;

    SEL selector = NSSelectorFromString(@"onTapCreate:");
    Method method = class_getInstanceMethod(createClass, selector);
    if (!method) return;

    AMOriginalCreate = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)AMHookCreate);
}

void AMInstallFPS120ForController(UIViewController *controller) {
    NSString *name = NSStringFromClass(controller.class);
    if ([name isEqualToString:@"CreateVC"] || [name isEqualToString:@"_TtC12AlightMotion8CreateVC"]) {
        AMSwizzleCreateVC(controller.class);
        AMInstall120Button(controller);
    }
}
