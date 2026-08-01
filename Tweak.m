#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Hook UIViewController viewDidAppear to auto-tap the storeButton on ExportPreviewVC
static void (*orig_viewDidAppear)(UIViewController *, SEL, BOOL);
static void hook_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"ExportPreviewVC"] || [className containsString:@"ExportVC"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // 1. Target storeButton (the "Save to Gallery" button in Alight Motion's ExportPreviewVC)
            if ([self respondsToSelector:@selector(storeButton)]) {
                IMP imp = [self methodForSelector:@selector(storeButton)];
                UIButton *(*func)(id, SEL) = (void *)imp;
                UIButton *btn = func(self, @selector(storeButton));
                if ([btn isKindOfClass:[UIButton class]]) {
                    [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                }
            }
            
            // 2. Also try selector invocation fallback
            if ([self respondsToSelector:@selector(didTapSave:)]) {
                [self performSelector:@selector(didTapSave:) withObject:nil];
            } else if ([self respondsToSelector:@selector(didTapSave)]) {
                [self performSelector:@selector(didTapSave)];
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
