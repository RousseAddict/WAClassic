// WA Classic by aronsz26, https://github.com/aronsz26/WAClassic. GPLv3 with attribution terms, see LICENSE and NOTICE.

#import <UIKit/UIKit.h>

// call changed, see [WACall shared].info
extern NSString *const WACallChangedNotification;

// one call at a time. bridge does the whatsapp side (meowcaller),
// we just send/receive 16khz ulaw over /api/call/audio. VoiceProcessingIO for echo cancel
@interface WACall : NSObject

+ (WACall *)shared;

// id, peer, name, incoming, state, reason
@property (nonatomic, readonly) NSDictionary *info;
@property (nonatomic, readonly) NSString *state;
@property (nonatomic, readonly) BOOL live; // ringing/calling/connecting/active
@property (nonatomic, readonly) NSDate *activeSince;
@property (nonatomic) BOOL muted, speaker;
// video state + peer orientation (quarter turns cw)
@property (nonatomic, readonly) BOOL video, peerVideo;
@property (nonatomic, readonly) int orientation;

- (void)callJID:(NSString *)jid name:(NSString *)name;
- (void)callJID:(NSString *)jid name:(NSString *)name video:(BOOL)video;
// camera on in a voice call = ask for video
- (void)setCameraOn:(BOOL)on;
- (void)answer;
- (void)hangup;

- (void)updateWithInfo:(NSDictionary *)info;
- (void)refresh;

// bg notifications (ringing / missed)
- (void)notifyRinging:(NSDictionary *)info;

// WACallScreen tweak installed?
+ (BOOL)systemCallScreen;
- (void)tellCallScreen;
#ifdef WA_DEV
- (void)devLatencyTest; // in an active echo call, logs "dev: audio round trip"
#endif
@end
