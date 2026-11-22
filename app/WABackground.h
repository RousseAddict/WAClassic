// WA Classic by aronsz26, https://github.com/aronsz26/WAClassic. GPLv3 with attribution terms, see LICENSE and NOTICE.

#import <UIKit/UIKit.h>

// keeps a voip socket to the bridge in bg (/api/updates?only=incoming, 15 min wait).
// ios wakes us on data, we post local notifications
@interface WABackground : NSObject <NSStreamDelegate>
+ (WABackground *)shared;
- (void)start;
- (void)stop;
@end

// "Name: text" / "Sender @ Group: text"
NSString *WANotificationText(NSDictionary *message);
