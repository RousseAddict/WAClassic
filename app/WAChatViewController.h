// WA Classic by aronsz26, https://github.com/aronsz26/WAClassic. GPLv3 with attribution terms, see LICENSE and NOTICE.

#import <UIKit/UIKit.h>

@interface WAChatViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate,
	UIActionSheetDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate>
- (instancetype)initWithChat:(NSDictionary *)chat;
@property (nonatomic, readonly) NSString *jid;
@end
