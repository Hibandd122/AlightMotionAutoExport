#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static char AMShareLinkTargetKey;
static const NSInteger AMShareLinkButtonTag = 120121;

@interface AMShareLinkTarget : NSObject
@property(nonatomic, weak) UIViewController *controller;
@property(nonatomic, strong) UIButton *button;
@property(nonatomic, strong) UIView *progressPanel;
@property(nonatomic, strong) UILabel *progressLabel;
- (void)openShareLink:(UIButton *)sender;
@end

static UIWindow *AMKeyWindow(void) {
    for (UIWindow *candidate in [UIApplication sharedApplication].windows) {
        if (candidate.isKeyWindow) return candidate;
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

static UIViewController *AMTopViewController(void) {
    UIWindow *window = AMKeyWindow();
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

static void AMShowProgress(AMShareLinkTarget *target, NSString *status) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = AMKeyWindow();
        UIView *host = window ?: target.controller.view;
        if (!host) return;

        if (!target.progressPanel) {
            CGFloat width = MIN(host.bounds.size.width - 32.0, 360.0);
            UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((host.bounds.size.width - width) / 2.0,
                                                                       host.safeAreaInsets.top + 62.0,
                                                                       width,
                                                                       66.0)];
            panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.97];
            panel.layer.cornerRadius = 14.0;
            panel.layer.borderWidth = 1.0;
            panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
            panel.layer.shadowColor = [UIColor blackColor].CGColor;
            panel.layer.shadowOpacity = 0.35;
            panel.layer.shadowRadius = 10.0;
            panel.layer.zPosition = 3000.0;

            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            spinner.frame = CGRectMake(16.0, 16.0, 34.0, 34.0);
            [spinner startAnimating];
            [panel addSubview:spinner];

            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(58.0, 11.0, width - 72.0, 44.0)];
            label.textColor = [UIColor whiteColor];
            label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
            label.numberOfLines = 2;
            target.progressLabel = label;
            [panel addSubview:label];
            target.progressPanel = panel;
            [host addSubview:panel];
        }

        target.progressLabel.text = status;
        [target.progressPanel.superview bringSubviewToFront:target.progressPanel];
    });
}

static void AMHideProgress(AMShareLinkTarget *target) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [target.progressPanel removeFromSuperview];
        target.progressPanel = nil;
        target.progressLabel = nil;
    });
}

static BOOL AMLooksLikeShareLink(NSString *value) {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *url = [NSURL URLWithString:trimmed];
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path.lowercaseString;
    return url && [url.scheme.lowercaseString isEqualToString:@"https"] &&
           [host isEqualToString:@"alightcreative.com"] &&
           [path containsString:@"/am/share/"];
}

static BOOL AMDispatchURLToApp(NSURL *url) {
    if (!url) return NO;
    UIApplication *application = [UIApplication sharedApplication];
    id delegate = application.delegate;
    NSDictionary *options = @{};

    SEL modern = @selector(application:openURL:options:);
    if ([delegate respondsToSelector:modern]) {
        BOOL (*call)(id, SEL, UIApplication *, NSURL *, NSDictionary *) = (void *)objc_msgSend;
        if (call(delegate, modern, application, url, options)) return YES;
    }

    SEL legacy = @selector(application:openURL:sourceApplication:annotation:);
    if ([delegate respondsToSelector:legacy]) {
        BOOL (*call)(id, SEL, UIApplication *, NSURL *, NSString *, id) = (void *)objc_msgSend;
        if (call(delegate, legacy, application, url, nil, nil)) return YES;
    }

    SEL handle = NSSelectorFromString(@"handleOpenURL:");
    if ([delegate respondsToSelector:handle]) {
        BOOL (*call)(id, SEL, NSURL *) = (void *)objc_msgSend;
        if (call(delegate, handle, url)) return YES;
    }
    return NO;
}

static NSURL *AMBuildAppShareURL(NSString *shareLink) {
    NSURLComponents *source = [NSURLComponents componentsWithString:shareLink];
    if (!source) return nil;
    source.scheme = @"com.alightcreative.motion";
    source.query = nil;
    return source.URL;
}

static void AMOpenAppShareURL(NSURL *url) {
    if (!url) {
        AMShowMessage(@"Import failed", @"Could not create the Alight Motion project link.");
        return;
    }

    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [application openURL:url options:@{} completionHandler:^(BOOL success) {
            if (success) return;
            if (!AMDispatchURLToApp(url)) {
                AMShowMessage(@"Import failed", @"Alight Motion did not open the project package.");
            }
        }];
        return;
    }

    if (!AMDispatchURLToApp(url)) {
        AMShowMessage(@"Import failed", @"Alight Motion did not open the project package.");
    }
}

static void AMOpenPackageURL(NSURL *fileURL, NSString *shareLink) {
    if (!fileURL && !shareLink.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (AMDispatchURLToApp(fileURL)) return;

        // Alight Motion's own project-package flow is registered on this
        // internal scheme. The file URL is attempted first; the share-link
        // fallback reaches the app's package importer when it rejects a
        // locally-created ZIP URL.
        NSURL *appShareURL = AMBuildAppShareURL(shareLink);
        AMOpenAppShareURL(appShareURL);
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
        AMShowMessage(@"Invalid link", @"Could not create the download request.");
        return;
    }

    UIButton *button = target.button;
    button.enabled = NO;
    [button setTitle:@"Loading..." forState:UIControlStateNormal];
    AMShowProgress(target, @"Downloading project package...");

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            button.enabled = YES;
            [button setTitle:@"Import share link" forState:UIControlStateNormal];
        });

        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        NSString *contentType = [http.allHeaderFields[@"Content-Type"] lowercaseString];
        BOOL looksLikeZip = data.length >= 4 && ((const unsigned char *)data.bytes)[0] == 'P' &&
                             ((const unsigned char *)data.bytes)[1] == 'K';
        if (error || !data.length || (http.statusCode >= 400) ||
            ![contentType containsString:@"application/zip"] || !looksLikeZip) {
            AMHideProgress(target);
            AMShowMessage(@"Download failed", error.localizedDescription ?: @"The API did not return a valid project ZIP.");
            return;
        }

        NSString *name = [NSString stringWithFormat:@"alightmotion_share_%@.zip", [NSUUID UUID].UUIDString];
        NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
        if (![data writeToURL:fileURL atomically:YES]) {
            AMHideProgress(target);
            AMShowMessage(@"Save failed", @"Could not save the project package.");
            return;
        }

        AMShowProgress(target, @"Opening project in Alight Motion...");
        AMOpenPackageURL(fileURL, link);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            AMHideProgress(target);
        });
    }];
    [task resume];
}

@implementation AMShareLinkTarget

- (void)openShareLink:(UIButton *)sender {
    UIViewController *presenter = self.controller ?: AMTopViewController();
    if (!presenter) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import share link"
                                                                     message:@"Paste an Alight Motion share link to import the project and its media."
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"https://alightcreative.com/am/share/u/...";
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak AMShareLinkTarget *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *link = alert.textFields.firstObject.text ?: @"";
        if (!AMLooksLikeShareLink(link)) {
            AMShowMessage(@"Invalid link", @"Use an https://alightcreative.com/am/share/... link.");
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
    UIWindow *window = AMKeyWindow();
    UIView *host = window ?: root;

    AMShareLinkTarget *target = [AMShareLinkTarget new];
    target.controller = controller;
    objc_setAssociatedObject(controller, &AMShareLinkTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    target.button = button;
    button.tag = AMShareLinkButtonTag;
    button.accessibilityIdentifier = @"alightmotion.import.share.link";
    [button setTitle:@"Import share link" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithRed:0.05 green:0.45 blue:1.0 alpha:1.0];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 12.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOpacity = 0.35;
    button.layer.shadowRadius = 8.0;

    CGFloat width = MIN(host.bounds.size.width - 32.0, 190.0);
    button.frame = CGRectMake(host.bounds.size.width - width - 16.0,
                              host.safeAreaInsets.top + 10.0,
                              width,
                              46.0);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    button.layer.zPosition = 2500.0;
    [button addTarget:target action:@selector(openShareLink:) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:button];
    [host bringSubviewToFront:button];
}
