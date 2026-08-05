#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static char AMShareLinkTargetKey;
static const NSInteger AMShareLinkButtonTag = 120121;

@interface AMShareLinkTarget : NSObject
@property(nonatomic, weak) UIViewController *controller;
@property(nonatomic, weak) UIButton *button;
- (void)openShareLink:(UIButton *)sender;
@end

static UIViewController *AMTopViewController(void) {
    UIWindow *window = nil;
    for (UIWindow *candidate in [UIApplication sharedApplication].windows) {
        if (candidate.isKeyWindow) { window = candidate; break; }
    }
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    if ([controller isKindOfClass:[UINavigationController class]]) {
        controller = [(UINavigationController *)controller visibleViewController];
    } else if ([controller isKindOfClass:[UITabBarController class]]) {
        controller = [(UITabBarController *)controller selectedViewController];
    }
    return controller;
}

static void AMShowMessage(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = AMTopViewController();
        if (!presenter) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                         message:message
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

static BOOL AMLooksLikeShareLink(NSString *value) {
    NSURL *url = [NSURL URLWithString:[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path.lowercaseString;
    return url && (url.scheme.lowercaseString.length > 0) &&
           [host isEqualToString:@"alightcreative.com"] &&
           [path containsString:@"/am/share/"];
}

static void AMOpenPackageURL(NSURL *fileURL) {
    if (!fileURL) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *application = [UIApplication sharedApplication];
        id delegate = application.delegate;
        NSDictionary *options = @{};

        // The app registers these handlers for project-package links/files.
        SEL modern = @selector(application:openURL:options:);
        if ([delegate respondsToSelector:modern]) {
            BOOL (*call)(id, SEL, UIApplication *, NSURL *, NSDictionary *) = (void *)objc_msgSend;
            if (call(delegate, modern, application, fileURL, options)) return;
        }

        SEL legacy = @selector(application:openURL:sourceApplication:annotation:);
        if ([delegate respondsToSelector:legacy]) {
            BOOL (*call)(id, SEL, UIApplication *, NSURL *, NSString *, id) = (void *)objc_msgSend;
            if (call(delegate, legacy, application, fileURL, nil, nil)) return;
        }

        SEL handle = NSSelectorFromString(@"handleOpenURL:");
        if ([delegate respondsToSelector:handle]) {
            BOOL (*call)(id, SEL, NSURL *) = (void *)objc_msgSend;
            if (call(delegate, handle, fileURL)) return;
        }

        AMShowMessage(@"Không thể nhập project", @"Alight Motion không nhận file project package ở phiên bản này.");
    });
}

static void AMDownloadSharePackage(AMShareLinkTarget *target, NSString *link) {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://am-share-extractor.vercel.app/extract"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"mode" value:@"full"],
        [NSURLQueryItem queryItemWithName:@"url" value:link]
    ];
    NSURL *url = components.URL;
    if (!url) {
        AMShowMessage(@"Link không hợp lệ", @"Không thể tạo yêu cầu tải project.");
        return;
    }

    UIButton *button = target.button;
    button.enabled = NO;
    [button setTitle:@"Đang tải project…" forState:UIControlStateNormal];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            button.enabled = YES;
            [button setTitle:@"Nhập từ link share" forState:UIControlStateNormal];
        });

        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        NSString *contentType = [http.allHeaderFields[@"Content-Type"] lowercaseString];
        BOOL looksLikeZip = data.length >= 4 && ((const unsigned char *)data.bytes)[0] == 'P' &&
                             ((const unsigned char *)data.bytes)[1] == 'K';
        if (error || !data.length || (http.statusCode >= 400) ||
            ![contentType containsString:@"application/zip"] || !looksLikeZip) {
            AMShowMessage(@"Tải project thất bại", error.localizedDescription ?: @"Link hết hạn hoặc API không trả về project package.");
            return;
        }

        NSString *name = [NSString stringWithFormat:@"alightmotion_share_%@.zip", [NSUUID UUID].UUIDString];
        NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
        if (![data writeToURL:fileURL atomically:YES]) {
            AMShowMessage(@"Lưu project thất bại", @"Không thể lưu project package vào bộ nhớ tạm.");
            return;
        }
        AMOpenPackageURL(fileURL);
    }];
    [task resume];
}

@implementation AMShareLinkTarget

- (void)openShareLink:(UIButton *)sender {
    UIViewController *presenter = self.controller ?: AMTopViewController();
    if (!presenter) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Nhập link share"
                                                                     message:@"Dán link Alight Motion share để nhập project kèm toàn bộ media."
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"https://alightcreative.com/am/share/u/...";
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak AMShareLinkTarget *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Nhập" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *link = alert.textFields.firstObject.text ?: @"";
        if (!AMLooksLikeShareLink(link)) {
            AMShowMessage(@"Link không hợp lệ", @"Hãy dùng link dạng alightcreative.com/am/share/…");
            return;
        }
        AMDownloadSharePackage(weakSelf, link);
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end

static BOOL AMIsProjectListController(UIViewController *controller) {
    NSString *name = NSStringFromClass(controller.class);
    return [name containsString:@"ProjectsListVC"] ||
           [name containsString:@"ProjectsVC"] ||
           [name containsString:@"HomepageVC"];
}

void AMInstallShareLinkImportForController(UIViewController *controller) {
    if (!controller || !AMIsProjectListController(controller)) return;
    if (objc_getAssociatedObject(controller, &AMShareLinkTargetKey)) return;

    UIView *root = controller.view;
    if (!root) return;

    AMShareLinkTarget *target = [AMShareLinkTarget new];
    target.controller = controller;
    objc_setAssociatedObject(controller, &AMShareLinkTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    target.button = button;
    button.tag = AMShareLinkButtonTag;
    button.accessibilityIdentifier = @"alightmotion.import.share.link";
    [button setTitle:@"Nhập từ link share" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithRed:0.10 green:0.45 blue:0.95 alpha:1.0];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 10.0;
    button.frame = CGRectMake(20.0, MAX(70.0, root.bounds.size.height - 120.0), root.bounds.size.width - 40.0, 46.0);
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [button addTarget:target action:@selector(openShareLink:) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:button];
}
