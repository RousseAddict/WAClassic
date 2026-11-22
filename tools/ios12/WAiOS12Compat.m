// Based on WA Classic by aronsz26, https://github.com/aronsz26/WAClassic. GPLv3 with attribution terms, see LICENSE and NOTICE.
//
// Added by the iOS 12 build (tools/ios12), not part of WA Classic.
//
// iOS 8+ only shows local notifications (alerts, sounds, badges) after the app has
// asked once with registerUserNotificationSettings:. WA Classic targets iOS 4-6, where
// that call doesn't exist, so its incoming-call and message notifications would stay
// silent on iOS 12. This asks right after launch, without touching WA Classic's code.
#import <UIKit/UIKit.h>

__attribute__((constructor)) static void WAiOS12AskForNotifications(void) {
	[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
		object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		UIUserNotificationType types = UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge;
		[[UIApplication sharedApplication] registerUserNotificationSettings:
			[UIUserNotificationSettings settingsForTypes:types categories:nil]];
	}];
}
