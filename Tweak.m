#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

#define AUTO_TEXT_BUTTON_TAG 998877

static NSMutableArray<NSString *> *pendingTextLines = nil;
static NSInteger currentLineIndex = 0;
static UIButton *globalAutoTextBtn = nil;
static BOOL isProcessingAutoBatch = NO;

// TimelineCell.onTapCellWithGesture: ignores a recognizer unless its state is
// Ended.  A real cell recognizer is still Possible when called from the batch,
// so use a harmless recognizer subclass that reports the completed state
// without mutating UIKit's private gesture state.
@interface AutoTextFinishedGesture : UITapGestureRecognizer
@property (nonatomic, weak) UIView *autoTextView;
@end

@implementation AutoTextFinishedGesture
- (UIGestureRecognizerState)state {
    return UIGestureRecognizerStateEnded;
}

- (UIView *)view {
    return self.autoTextView;
}

- (CGPoint)locationInView:(UIView *)view {
    UIView *target = self.autoTextView;
    if (!target) return CGPointZero;
    return [target convertPoint:CGPointMake(CGRectGetMidX(target.bounds), CGRectGetMidY(target.bounds)) toView:view];
}
@end

static void sendCompletionNotification() {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Alight Motion MOD";
    content.body = @"Xuất video hoàn tất! Đã tự động lưu vào Cuộn Camera.";
    content.sound = [UNNotificationSound defaultSound];
    
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:content trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

static UIViewController *getTopViewController() {
    UIViewController *top = nil;
    NSArray *windows = [UIApplication sharedApplication].windows;
    for (UIWindow *win in windows) {
        if (win.isKeyWindow) {
            top = win.rootViewController;
            break;
        }
    }
    if (!top && windows.count > 0) {
        UIWindow *firstWin = (UIWindow *)windows.firstObject;
        top = firstWin.rootViewController;
    }
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    return top;
}

static BOOL isViewCurrentlyVisible(UIView *view) {
    return view && view.window && !view.hidden && view.alpha > 0.01;
}

static UIViewController *findViewControllerOfClass(UIViewController *root, NSString *targetClassName) {
    if (!root) return nil;

    NSString *clsName = NSStringFromClass([root class]);
    if ([clsName containsString:targetClassName] && root.isViewLoaded && isViewCurrentlyVisible(root.view)) {
        return root;
    }

    for (UIViewController *child in [root.childViewControllers reverseObjectEnumerator]) {
        UIViewController *found = findViewControllerOfClass(child, targetClassName);
        if (found) return found;
    }
    return nil;
}

static void showHUDLog(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = getTopViewController();
        if (!topVC) return;
        
        UILabel *hud = [topVC.view viewWithTag:997766];
        if (!hud) {
            hud = [[UILabel alloc] init];
            hud.tag = 997766;
            hud.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.92];
            hud.textColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:1.0];
            hud.font = [UIFont boldSystemFontOfSize:11.0];
            hud.numberOfLines = 0;
            hud.textAlignment = NSTextAlignmentCenter;
            hud.layer.cornerRadius = 10.0;
            hud.layer.masksToBounds = YES;
            hud.layer.borderWidth = 1.0;
            hud.layer.borderColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:0.5].CGColor;
            
            CGFloat w = topVC.view.bounds.size.width - 40.0;
            hud.frame = CGRectMake(20.0, topVC.view.bounds.size.height - 110.0, w, 44.0);
            hud.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
            [topVC.view addSubview:hud];
        }
        
        hud.text = [NSString stringWithFormat:@"⚡ AUTO KEYFRAME:\n%@", msg];
        [topVC.view bringSubviewToFront:hud];
        
        [NSObject cancelPreviousPerformRequestsWithTarget:hud selector:@selector(removeFromSuperview) object:nil];
        [hud performSelector:@selector(removeFromSuperview) withObject:nil afterDelay:3.5];
    });
}

static UIView *findTargetInputView(UIView *view) {
    if (!view) return nil;
    if (([view isKindOfClass:[UITextView class]] || [view isKindOfClass:[UITextField class]]) &&
        view.tag != 8899 && isViewCurrentlyVisible(view) && view.userInteractionEnabled) {
        BOOL usable = [view isKindOfClass:[UITextView class]]
            ? [(UITextView *)view isEditable]
            : [(UITextField *)view isEnabled];
        if (usable) return view;
    }
    for (UIView *sub in view.subviews) {
        UIView *res = findTargetInputView(sub);
        if (res) return res;
    }
    return nil;
}

static UIView *findTextInputViewInController(UIViewController *root) {
    if (!root) return nil;

    NSString *className = NSStringFromClass([root class]);
    if ([className containsString:@"TextInputVC"] && root.isViewLoaded && isViewCurrentlyVisible(root.view)) {
        @try {
            id input = [root valueForKey:@"inputTextView"];
            if ([input isKindOfClass:[UITextView class]]) return (UIView *)input;
        } @catch (NSException *exception) {
            (void)exception;
            // Fall back to hierarchy traversal for a class without KVC exposure.
        }
    }

    // The text editor is a child of EditTextInspectorVC/EditTextPanelVC.  Walk
    // the newest child first so a stale, still-retained TextInputVC cannot win
    // over the input belonging to the layer that was just selected.
    for (UIViewController *child in [root.childViewControllers reverseObjectEnumerator]) {
        UIView *input = findTextInputViewInController(child);
        if (input) return input;
    }
    return nil;
}

static BOOL callSelectorOnTarget(id target, SEL sel) {
    if (!target) return NO;
    if ([target respondsToSelector:sel]) {
        IMP imp = [target methodForSelector:sel];
        Method m = class_getInstanceMethod([target class], sel);
        int args = m ? method_getNumberOfArguments(m) : 2;
        if (args > 2) {
            void (*func)(id, SEL, id) = (void *)imp;
            func(target, sel, nil);
        } else {
            void (*func)(id, SEL) = (void *)imp;
            func(target, sel);
        }
        return YES;
    }
    return NO;
}

static BOOL callSelectorOnTargetWithObject(id target, SEL sel, id object) {
    if (!target || ![target respondsToSelector:sel]) return NO;
    IMP imp = [target methodForSelector:sel];
    Method method = class_getInstanceMethod([target class], sel);
    int args = method ? method_getNumberOfArguments(method) : 2;
    if (args > 2) {
        void (*func)(id, SEL, id) = (void *)imp;
        func(target, sel, object);
    } else {
        void (*func)(id, SEL) = (void *)imp;
        func(target, sel);
    }
    return YES;
}

static BOOL sendExactActionToButton(UIView *view, NSString *actionName) {
    if (!view) return NO;
    if ([view isKindOfClass:[UIButton class]] && isViewCurrentlyVisible(view)) {
        UIButton *button = (UIButton *)view;
        for (id target in button.allTargets) {
            for (NSString *action in [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside]) {
                if ([action isEqualToString:actionName]) {
                    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
                    return YES;
                }
            }
        }
    }
    for (UIView *child in view.subviews) {
        if (sendExactActionToButton(child, actionName)) return YES;
    }
    return NO;
}

static UICollectionView *findSelectedTimelineCollectionView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UICollectionView class]]) {
        UICollectionView *collectionView = (UICollectionView *)view;
        if (collectionView.indexPathsForSelectedItems.count > 0) return collectionView;
    }
    for (UIView *child in view.subviews) {
        UICollectionView *found = findSelectedTimelineCollectionView(child);
        if (found) return found;
    }
    return nil;
}

static id valueForKeySafely(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (NSException *exception) {
        (void)exception;
        return nil;
    }
}

static UICollectionView *timelineCollectionViewForController(UIViewController *timelineVC) {
    // IPA evidence: TimelineViewController has an actual `timelineView`
    // outlet. Prefer it over recursively picking an arbitrary collection view.
    id timelineView = valueForKeySafely(timelineVC, @"timelineView");
    if ([timelineView isKindOfClass:[UICollectionView class]]) {
        return (UICollectionView *)timelineView;
    }
    return findSelectedTimelineCollectionView(timelineVC.view);
}

static NSIndexPath *selectedTimelineIndexPath(UIViewController *timelineVC, UICollectionView *collectionView) {
    NSIndexPath *selected = collectionView.indexPathsForSelectedItems.firstObject;
    if (selected) return selected;

    // TimelineLayout keeps the app's selected index path separately from
    // UICollectionView's visual selection state.
    id layout = valueForKeySafely(timelineVC, @"timelineLayout");
    id layoutSelection = valueForKeySafely(layout, @"selectedIndexPath");
    if ([layoutSelection isKindOfClass:[NSIndexPath class]]) return layoutSelection;
    return nil;
}

static BOOL selectNextTimelineLayer() {
    UIViewController *topVC = getTopViewController();
    UIWindow *keyWin = nil;
    NSArray *wins = [UIApplication sharedApplication].windows;
    if (wins.count > 0) keyWin = (UIWindow *)wins.firstObject;
    UIViewController *winRoot = keyWin ? keyWin.rootViewController : nil;

    UIViewController *timelineVC = findViewControllerOfClass(topVC, @"TimelineViewController");
    if (!timelineVC && winRoot) timelineVC = findViewControllerOfClass(winRoot, @"TimelineViewController");
    if (!timelineVC) return NO;

    UICollectionView *collectionView = timelineCollectionViewForController(timelineVC);
    if (!collectionView) {
        showHUDLog(@"Khong tim thay TimelineView cua app");
        return NO;
    }

    NSIndexPath *selected = selectedTimelineIndexPath(timelineVC, collectionView);
    if (!selected) {
        showHUDLog(@"Timeline chua co layer dang chon");
        return NO;
    }

    NSInteger nextItem = selected.item + 1;
    if (nextItem >= [collectionView numberOfItemsInSection:selected.section]) return NO;

    NSIndexPath *next = [NSIndexPath indexPathForItem:nextItem inSection:selected.section];
    [collectionView layoutIfNeeded];
    [collectionView selectItemAtIndexPath:next animated:NO scrollPosition:UICollectionViewScrollPositionNone];

    UICollectionViewCell *nextCell = [collectionView cellForItemAtIndexPath:next];
    if (!nextCell) {
        showHUDLog([NSString stringWithFormat:@"Layer %ld chua hien cell tren Timeline", (long)next.item + 1]);
        return NO;
    }

    AutoTextFinishedGesture *finishedGesture = [[AutoTextFinishedGesture alloc] init];
    finishedGesture.autoTextView = nextCell;
    BOOL didTapCell = NO;
    if ([nextCell respondsToSelector:@selector(onTapCellWithGesture:)]) {
        [nextCell performSelector:@selector(onTapCellWithGesture:) withObject:finishedGesture];
        didTapCell = YES;
    }

    showHUDLog([NSString stringWithFormat:@"Mo layer %ld -> %ld (%@%@)",
                (long)selected.item + 1,
                (long)next.item + 1,
                didTapCell ? @"tap" : @"select",
                didTapCell ? @" + app" : @""]);
    return didTapCell;
}

static BOOL triggerAutoSplitLayer() {
    UIViewController *topVC = getTopViewController();
    UIWindow *keyWin = nil;
    NSArray *wins = [UIApplication sharedApplication].windows;
    if (wins.count > 0) keyWin = (UIWindow *)wins.firstObject;
    UIViewController *winRoot = keyWin ? keyWin.rootViewController : nil;

    // IPA mapping: EditingPanelVC -> splitButton -> onTapSplit:.
    UIViewController *editingPanelVC = findViewControllerOfClass(topVC, @"EditingPanelVC");
    if (!editingPanelVC && winRoot) editingPanelVC = findViewControllerOfClass(winRoot, @"EditingPanelVC");
    if (editingPanelVC && sendExactActionToButton(editingPanelVC.view, @"onTapSplit:")) return YES;
    if (editingPanelVC && callSelectorOnTarget(editingPanelVC, @selector(onTapSplit:))) return YES;

    // EditTimingVC uses the same split action on its own splitButton.
    UIViewController *editTimingVC = findViewControllerOfClass(topVC, @"EditTimingVC");
    if (!editTimingVC && winRoot) editTimingVC = findViewControllerOfClass(winRoot, @"EditTimingVC");
    if (editTimingVC && sendExactActionToButton(editTimingVC.view, @"onTapSplit:")) return YES;
    if (editTimingVC && callSelectorOnTarget(editTimingVC, @selector(onTapSplit:))) return YES;

    // Some multi-select screens expose the equivalent action on MultiSelectorNavVC.
    UIViewController *multiSelectorVC = findViewControllerOfClass(topVC, @"MultiSelectorNavVC");
    if (!multiSelectorVC && winRoot) multiSelectorVC = findViewControllerOfClass(winRoot, @"MultiSelectorNavVC");
    if (multiSelectorVC && sendExactActionToButton(multiSelectorVC.view, @"onTapSplitTimeline:")) return YES;
    if (multiSelectorVC && callSelectorOnTarget(multiSelectorVC, @selector(onTapSplitTimeline:))) return YES;

    // Last fallback: the exact action may be hosted by a container view.
    if (topVC && sendExactActionToButton(topVC.view, @"onTapSplit:")) return YES;
    if (winRoot && winRoot != topVC && sendExactActionToButton(winRoot.view, @"onTapSplit:")) return YES;

    return NO;
}

static BOOL jumpToNextMarkerOrKeyframe() {
    UIViewController *topVC = getTopViewController();
    UIWindow *keyWin = nil;
    NSArray *wins = [UIApplication sharedApplication].windows;
    if (wins.count > 0) keyWin = (UIWindow *)wins.firstObject;
    UIViewController *winRoot = keyWin ? keyWin.rootViewController : nil;
    
    UIViewController *previewVC = findViewControllerOfClass(topVC, @"PreviewControlBarVC");
    if (!previewVC && winRoot) previewVC = findViewControllerOfClass(winRoot, @"PreviewControlBarVC");
    
    // IPA mapping: PreviewControlBarVC -> mvNextButton -> onTapMoveNext:.
    if (previewVC && sendExactActionToButton(previewVC.view, @"onTapMoveNext:")) return YES;
    if (previewVC && callSelectorOnTarget(previewVC, @selector(onTapMoveNext:))) return YES;

    return NO;
}

static void updateButtonState() {
    if (!globalAutoTextBtn) return;
    if (pendingTextLines && pendingTextLines.count > 0 && currentLineIndex < pendingTextLines.count) {
        NSString *title = [NSString stringWithFormat:@"⚡ NẠP TEXT (%ld/%lu)", (long)(currentLineIndex + 1), (unsigned long)pendingTextLines.count];
        [globalAutoTextBtn setTitle:title forState:UIControlStateNormal];
        globalAutoTextBtn.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.95];
    } else {
        [globalAutoTextBtn setTitle:@"⚡ AUTO TEXT" forState:UIControlStateNormal];
        globalAutoTextBtn.backgroundColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:0.95];
    }
}

static void applyTextToInputDirectly(UIViewController *parentVC, NSString *line) {
    if (!line || line.length == 0) return;

    [UIPasteboard generalPasteboard].string = line;

    UIView *inputView = findTextInputViewInController(parentVC);
    if (!inputView) inputView = findTargetInputView(parentVC.view);
    if (!inputView && parentVC.parentViewController) {
        inputView = findTextInputViewInController(parentVC.parentViewController);
        if (!inputView) inputView = findTargetInputView(parentVC.parentViewController.view);
    }
    if (!inputView) {
        UIViewController *top = getTopViewController();
        if (top) {
            inputView = findTextInputViewInController(top);
            if (!inputView) inputView = findTargetInputView(top.view);
        }
    }
    
    if ([inputView isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)inputView;
        [tv becomeFirstResponder];
        tv.text = line;
        if ([tv.delegate respondsToSelector:@selector(textViewDidChange:)]) {
            [tv.delegate textViewDidChange:tv];
        }
    } else if ([inputView isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)inputView;
        tf.text = line;
        [tf sendActionsForControlEvents:UIControlEventEditingChanged];
    }
}

static void finishAutoTextBatch(NSString *message) {
    pendingTextLines = nil;
    currentLineIndex = 0;
    isProcessingAutoBatch = NO;
    updateButtonState();
    showHUDLog(message);
}

static void processPrecutTextAtIndex(NSInteger index);

static void writePrecutTextAtIndex(NSInteger index) {
    if (!isProcessingAutoBatch || !pendingTextLines || index >= pendingTextLines.count) return;

    UIViewController *top = getTopViewController();
    NSString *line = pendingTextLines[index];
    applyTextToInputDirectly(top, line);
    showHUDLog([NSString stringWithFormat:@"Nap Text Layer %ld/%lu: %@", (long)(index + 1), (unsigned long)pendingTextLines.count, line]);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        processPrecutTextAtIndex(index + 1);
    });
}

static void processPrecutTextAtIndex(NSInteger index) {
    if (!isProcessingAutoBatch || !pendingTextLines || index >= pendingTextLines.count) {
        finishAutoTextBatch(@"Da nap xong tat ca Text Layer!");
        return;
    }

    currentLineIndex = index;
    updateButtonState();

    if (index == 0) {
        writePrecutTextAtIndex(index);
        return;
    }

    // Commit Text 1 and release the editor before changing the selected layer.
    UIViewController *top = getTopViewController();
    UIView *activeInput = findTextInputViewInController(top);
    if (!activeInput) activeInput = findTargetInputView(top.view);
    [activeInput resignFirstResponder];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!isProcessingAutoBatch || !pendingTextLines || index >= pendingTextLines.count) return;
        if (!selectNextTimelineLayer()) {
            finishAutoTextBatch(@"Khong tim thay Text Layer tiep theo trong Timeline:");
            return;
        }

        // Selection updates the Swift editor asynchronously. Wait for the new
        // TextInputVC before touching its text view.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            writePrecutTextAtIndex(index);
        });
    });
}

static void processLineAtIndex(NSInteger index) {
    processPrecutTextAtIndex(index);
    return;

    if (!isProcessingAutoBatch || !pendingTextLines || index >= pendingTextLines.count) {
        pendingTextLines = nil;
        currentLineIndex = 0;
        isProcessingAutoBatch = NO;
        updateButtonState();
        showHUDLog(@"✅ Tách & Nạp Text Hoàn Tất!");
        return;
    }
    
    currentLineIndex = index;
    updateButtonState();
    
    if (index == 0) {
        UIViewController *top = getTopViewController();
        applyTextToInputDirectly(top, pendingTextLines[0]);
        showHUDLog([NSString stringWithFormat:@"📝 Nạp dòng 1/%lu: %@", (unsigned long)pendingTextLines.count, pendingTextLines[0]]);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            processLineAtIndex(index + 1);
        });
    } else {
        showHUDLog([NSString stringWithFormat:@"⏩ Nhảy mốc Marker dòng %ld/%lu...", (long)(index + 1), (unsigned long)pendingTextLines.count]);
        BOOL didMove = jumpToNextMarkerOrKeyframe();
        if (!didMove) {
            pendingTextLines = nil;
            currentLineIndex = 0;
            isProcessingAutoBatch = NO;
            updateButtonState();
            showHUDLog(@"Khong tim thay PreviewControlBarVC.onTapMoveNext:");
            return;
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                showHUDLog([NSString stringWithFormat:@"✂️ Cắt Layer dòng %ld/%lu...", (long)(index + 1), (unsigned long)pendingTextLines.count]);
                BOOL didSplit = triggerAutoSplitLayer();
                if (!didSplit) {
                    pendingTextLines = nil;
                    currentLineIndex = 0;
                    isProcessingAutoBatch = NO;
                    updateButtonState();
                    showHUDLog(@"Khong tim thay Action: onTapSplit:");
                    return;
                }
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.40 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    BOOL didSelectNextLayer = selectNextTimelineLayer();
                    if (!didSelectNextLayer) {
                        pendingTextLines = nil;
                        currentLineIndex = 0;
                        isProcessingAutoBatch = NO;
                        updateButtonState();
                        showHUDLog(@"Khong tim thay layer moi sau khi split:");
                        return;
                    }

                    UIViewController *top = getTopViewController();
                    applyTextToInputDirectly(top, pendingTextLines[index]);
                    showHUDLog([NSString stringWithFormat:@"📝 Nạp dòng %ld/%lu: %@", (long)(index + 1), (unsigned long)pendingTextLines.count, pendingTextLines[index]]);
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        processLineAtIndex(index + 1);
                    });
                });

        });
    }
}

static void startSequentialTextProcess(UIViewController *parentVC, NSString *rawText, BOOL autoBatch) {
    if (rawText.length == 0) return;
    
    NSArray<NSString *> *lines = [rawText componentsSeparatedByString:@"\n"];
    pendingTextLines = [NSMutableArray array];
    for (NSString *l in lines) {
        NSString *trimmed = [l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [pendingTextLines addObject:trimmed];
        }
    }
    currentLineIndex = 0;
    
    if (pendingTextLines.count == 0) {
        updateButtonState();
        return;
    }
    
    if (autoBatch) {
        isProcessingAutoBatch = autoBatch;
        if (autoBatch) processLineAtIndex(0);
    } else {
        updateButtonState();
    }
}

static void presentAutoTextModal(UIViewController *parentVC) {
    if (!parentVC) return;
    
    UIViewController *modalVC = [[UIViewController alloc] init];
    modalVC.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    modalVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    modalVC.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.14 alpha:1.0];
    card.layer.cornerRadius = 18.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithRed:0.20 green:0.20 blue:0.25 alpha:1.0].CGColor;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [modalVC.view addSubview:card];
    
    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.text = @"⚡ Auto Keyframe Text";
    titleLbl.textColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:1.0];
    titleLbl.font = [UIFont boldSystemFontOfSize:18.0];
    titleLbl.textAlignment = NSTextAlignmentCenter;
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:titleLbl];
    
    UILabel *subLbl = [[UILabel alloc] init];
    subLbl.text = @"Nạp lần lượt nội dung vào các Text Layer đã được cắt sẵn trên Timeline:";
    subLbl.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    subLbl.font = [UIFont systemFontOfSize:13.0];
    subLbl.numberOfLines = 0;
    subLbl.textAlignment = NSTextAlignmentCenter;
    subLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:subLbl];
    
    UITextView *textView = [[UITextView alloc] init];
    textView.tag = 8899;
    textView.backgroundColor = [UIColor colorWithRed:0.14 green:0.14 blue:0.18 alpha:1.0];
    textView.textColor = [UIColor whiteColor];
    textView.font = [UIFont systemFontOfSize:15.0];
    textView.layer.cornerRadius = 10.0;
    textView.layer.borderWidth = 1.0;
    textView.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:1.0].CGColor;
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.text = @"Text 1\nText 2\nText 3";
    [card addSubview:textView];
    
    UIButton *btnTestSplit = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnTestSplit setTitle:@"✂️ TÁCH LAYER NGAY" forState:UIControlStateNormal];
    [btnTestSplit setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btnTestSplit.backgroundColor = [UIColor colorWithRed:0.90 green:0.20 blue:0.20 alpha:1.0];
    btnTestSplit.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    btnTestSplit.layer.cornerRadius = 10.0;
    btnTestSplit.translatesAutoresizingMaskIntoConstraints = NO;
    btnTestSplit.hidden = YES;
    [card addSubview:btnTestSplit];
    
    UIButton *btnAutoAll = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnAutoAll setTitle:@"⚡ NẠP TEXT THEO LAYER" forState:UIControlStateNormal];
    [btnAutoAll setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    btnAutoAll.backgroundColor = [UIColor colorWithRed:0.00 green:0.90 blue:0.46 alpha:1.0];
    btnAutoAll.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    btnAutoAll.layer.cornerRadius = 10.0;
    btnAutoAll.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:btnAutoAll];
    
    UIButton *btnCancel = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnCancel setTitle:@"HỦY" forState:UIControlStateNormal];
    [btnCancel setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
    btnCancel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    btnCancel.titleLabel.font = [UIFont systemFontOfSize:13.0];
    btnCancel.layer.cornerRadius = 10.0;
    btnCancel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:btnCancel];
    
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:modalVC.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:modalVC.view.centerYAnchor constant:-30],
        [card.widthAnchor constraintEqualToConstant:330],
        [card.heightAnchor constraintEqualToConstant:320],
        
        [titleLbl.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [titleLbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [titleLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        
        [subLbl.topAnchor constraintEqualToAnchor:titleLbl.bottomAnchor constant:6],
        [subLbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [subLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        
        [textView.topAnchor constraintEqualToAnchor:subLbl.bottomAnchor constant:12],
        [textView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [textView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [textView.heightAnchor constraintEqualToConstant:110],
        
        [btnTestSplit.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [btnTestSplit.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [btnTestSplit.widthAnchor constraintEqualToConstant:130],
        [btnTestSplit.heightAnchor constraintEqualToConstant:40],
        
        [btnAutoAll.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [btnAutoAll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [btnAutoAll.widthAnchor constraintEqualToConstant:306],
        [btnAutoAll.heightAnchor constraintEqualToConstant:40],
        
        [btnCancel.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [btnCancel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [btnCancel.widthAnchor constraintEqualToConstant:50],
        [btnCancel.heightAnchor constraintEqualToConstant:30]
    ]];
    
    [btnCancel addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [modalVC dismissViewControllerAnimated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [btnTestSplit addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        BOOL ok = triggerAutoSplitLayer();
        if (ok) {
            sendCompletionNotification();
        }
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [btnAutoAll addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        NSString *raw = textView.text;
        [modalVC dismissViewControllerAnimated:YES completion:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                startSequentialTextProcess(parentVC, raw, YES);
            });
        }];
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [parentVC presentViewController:modalVC animated:YES completion:nil];
}

@interface AutoTextButtonHandler : NSObject
+ (instancetype)sharedInstance;
- (void)buttonTapped:(UIButton *)sender;
- (void)handlePan:(UIPanGestureRecognizer *)pan;
@end

@implementation AutoTextButtonHandler
static CGPoint panStartPoint;

+ (instancetype)sharedInstance {
    static AutoTextButtonHandler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AutoTextButtonHandler alloc] init];
    });
    return instance;
}

- (void)buttonTapped:(UIButton *)sender {
    UIViewController *top = getTopViewController();
    if (isProcessingAutoBatch) return;
    if (pendingTextLines && pendingTextLines.count > 0 && currentLineIndex < pendingTextLines.count) {
        isProcessingAutoBatch = YES;
        processLineAtIndex(currentLineIndex);
        return;
    } else {
        presentAutoTextModal(top);
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    if (pan.state == UIGestureRecognizerStateBegan) {
        panStartPoint = btn.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:btn.superview];
        btn.center = CGPointMake(panStartPoint.x + translation.x, panStartPoint.y + translation.y);
    }
}
@end

static void (*orig_viewDidAppear)(UIViewController *, SEL, BOOL);
static void hook_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    
    NSString *className = NSStringFromClass([self class]);
    
    // 1. Auto-save export completion (ExportPreviewVC)
    if ([className containsString:@"ExportPreviewVC"] || [className containsString:@"ExportVC"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self respondsToSelector:@selector(storeButton)]) {
                IMP imp = [self methodForSelector:@selector(storeButton)];
                UIButton *(*func)(id, SEL) = (void *)imp;
                UIButton *btn = func(self, @selector(storeButton));
                if ([btn isKindOfClass:[UIButton class]]) {
                    [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                    sendCompletionNotification();
                }
            }
        });
    }
    
    // 2. Add DRAGGABLE AUTOMATIC MARKER SPLIT "⚡ AUTO TEXT" button
    if ([className containsString:@"EditTextInspectorVC"] || [className containsString:@"EditTextPanelVC"] || [className containsString:@"MainEditor"] || [className containsString:@"ProjectEditor"]) {
        if (![self.view viewWithTag:AUTO_TEXT_BUTTON_TAG]) {
            UIButton *autoTextBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            autoTextBtn.tag = AUTO_TEXT_BUTTON_TAG;
            globalAutoTextBtn = autoTextBtn;
            
            [autoTextBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            autoTextBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
            autoTextBtn.layer.cornerRadius = 14.0;
            autoTextBtn.layer.shadowColor = [UIColor blackColor].CGColor;
            autoTextBtn.layer.shadowOffset = CGSizeMake(0, 2);
            autoTextBtn.layer.shadowOpacity = 0.4;
            autoTextBtn.layer.shadowRadius = 4.0;
            autoTextBtn.userInteractionEnabled = YES;
            
            CGFloat screenWidth = self.view.bounds.size.width;
            autoTextBtn.frame = CGRectMake(screenWidth - 115.0, 85.0, 100.0, 32.0);
            
            updateButtonState();
            
            [autoTextBtn addTarget:[AutoTextButtonHandler sharedInstance] action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
            
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[AutoTextButtonHandler sharedInstance] action:@selector(handlePan:)];
            pan.cancelsTouchesInView = NO;
            pan.delaysTouchesBegan = NO;
            [autoTextBtn addGestureRecognizer:pan];
            
            [self.view addSubview:autoTextBtn];
            [self.view bringSubviewToFront:autoTextBtn];
        }
    }
}

__attribute__((constructor)) static void initHooks() {
    // Hook UIViewController viewDidAppear
    Class vcClass = objc_getClass("UIViewController");
    Method m = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    orig_viewDidAppear = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_viewDidAppear);
}
