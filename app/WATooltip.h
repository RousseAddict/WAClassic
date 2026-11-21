// WA Classic by aronsz26, https://github.com/aronsz26/WAClassic. GPLv3 with attribution terms, see LICENSE and NOTICE.

#import <UIKit/UIKit.h>

// 2.10 tooltip box with arrow + close button
@interface WATooltip : UIView
// arrow tip at point
+ (WATooltip *)showText:(NSString *)text pointingAt:(CGPoint)point inView:(UIView *)view;
- (void)dismiss;
@property (nonatomic, copy) void (^onClose)(void);
@end
