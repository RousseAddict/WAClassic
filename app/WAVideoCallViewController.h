// WA Classic by aronsz26, https://github.com/aronsz26/WAClassic. GPLv3 with attribution terms, see LICENSE and NOTICE.

#import <UIKit/UIKit.h>

// video call ui, facetime style
@interface WAVideoCallViewController : UIViewController
+ (void)showIfNeededInWindow:(UIWindow *)window;
+ (BOOL)wanted;
@end
