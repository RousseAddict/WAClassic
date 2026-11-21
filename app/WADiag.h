// WA Classic by aronsz26, https://github.com/aronsz26/WAClassic. GPLv3 with attribution terms, see LICENSE and NOTICE.

#import <UIKit/UIKit.h>

// diagnostics, only after the user said yes (asked once). once a day to update.waclassic.com/t:
// iphone model, ios, app and bridge version, bridge platform, language, setup bits, crash reports, error codes.
// since 1.0.3 also: notification delay and connection counts in steps, upload size steps,
// memory warnings, start time, known tls/store tweaks, the bridge's error counts.
// since 1.0.5 (consent 3): how far setup got, which features get used, whether sending works, as counts per day.
// never messages, contacts, numbers or names
extern NSString *const WAPrefDiagnostics;
extern NSString *const WADiagWhat; // what gets sent, for the alert and settings

@interface WADiag : NSObject
@property (nonatomic, readonly) BOOL asking;
+ (instancetype)shared;
- (void)askIfNeeded;
- (void)sendIfDue;
- (void)noteBridge:(NSDictionary *)status;
- (void)record:(NSString *)code;
@property (nonatomic, readonly) BOOL extended; // sends the 1.0.3 list (every yes, 1.0.2 ones too)
- (void)count:(NSString *)code; // only with consent 2
@property (nonatomic, readonly) BOOL usage; // sends the 1.0.5 list too
- (void)countUsage:(NSString *)code; // only with consent 3
- (void)setupStep:(NSString *)step; // "setup <step>", once per install
- (void)noteRequest:(NSURLRequest *)req ok:(BOOL)ok; // "send ok text", "use new group"
- (void)noteDelay:(NSTimeInterval)secs of:(NSString *)what; // "notify <1m" etc.
- (void)noteLaunched;
- (void)turnedOff; // removes what was sent
- (void)turnedOn; // from settings, agrees to the current list
- (void)chosenInSetup:(BOOL)send; // new installs, nothing is sent before the bridge is there
@end
