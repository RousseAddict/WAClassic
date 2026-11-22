// WA Classic by aronsz26, https://github.com/aronsz26/WAClassic. GPLv3 with attribution terms, see LICENSE and NOTICE.

#import <UIKit/UIKit.h>

// own call screen in ios 6 phone style (used without the tweak)
@interface WACallViewController : UIViewController
+ (void)showIfNeededInWindow:(UIWindow *)window;
+ (BOOL)showing;
@end
