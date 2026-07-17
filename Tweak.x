#import <UIKit/UIKit.h>
#import <substrate.h>

@interface CrunchyrollForceUpgradeViewController: UIViewController
@end

%hook VSSubscriptionRegistrationCenter
    // When the app was sideloaded without the correct entitlements,
    // this might crash the app
    - (void) registerSubscription:(id)subscription { }
%end

%ctor {
    NSLog(@"[Crunchyrold] Loaded - Network Interception Mode");
    
    %init(CrunchyrollForceUpgradeViewController=objc_getClass("Crunchyroll.ForceUpgradeViewController"));
}
