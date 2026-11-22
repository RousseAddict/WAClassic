// WA Classic by aronsz26, https://github.com/aronsz26/WAClassic. GPLv3 with attribution terms, see LICENSE and NOTICE.

#import <UIKit/UIKit.h>

// 2.10 SinglePersonPicker, used for "New Message"
@interface WAPersonPicker : UITableViewController <UISearchBarDelegate>
@property (nonatomic, copy) void (^onPick)(NSDictionary *contact);
@end
