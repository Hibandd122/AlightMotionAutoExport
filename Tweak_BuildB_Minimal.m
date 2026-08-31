#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - =========================================================
#pragma mark BUILD B: MINIMAL DIAGNOSTIC TWEAK (DYLIB LOAD ONLY)
#pragma mark =========================================================
// Zero hooks, zero swizzling, zero Metal allocation, zero permission requests, zero XML parsing.
// Purpose: Isolate whether LC_LOAD_DYLIB and dyld image loading itself succeeds on the physical device.

__attribute__((constructor)) static void initUltraMotionMinimalDiag() {
    NSLog(@"============================================================");
    NSLog(@"[UltraMotion-Diag] 🟢 BUILD B: DYLIB LOADED SUCCESSFULLY!");
    NSLog(@"[UltraMotion-Diag] Process Name: %@", [[NSProcessInfo processInfo] processName]);
    NSLog(@"[UltraMotion-Diag] Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    NSLog(@"[UltraMotion-Diag] Running in pure passive diagnostic mode (0 hooks).");
    NSLog(@"============================================================");
}
