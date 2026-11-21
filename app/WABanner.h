// WA Classic by aronsz26, https://github.com/aronsz26/WAClassic. GPLv3 with attribution terms, see LICENSE and NOTICE.

#import <UIKit/UIKit.h>

// in-app banner for other chats (2.10 NotificationBg), tap opens the chat
@interface WABanner : NSObject
+ (void)showText:(NSString *)text inWindow:(UIWindow *)window onTap:(void (^)(void))tap;
@end
