// WA Classic by aronsz26, https://github.com/aronsz26/WAClassic. GPLv3 with attribution terms, see LICENSE and NOTICE.

#import "WADiag.h"
#import "WAClient.h"
#import "WACall.h"
#import "WAAssets.h"
#import "WAUtil.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <unistd.h>

NSString *const WAPrefDiagnostics = @"diagOn";
static NSString *const kSend = @"http://update.waclassic.com/t";
static NSString *const kForget = @"http://update.waclassic.com/t/delete";
static NSString *const kCrashDir = @"/var/mobile/Library/Logs/CrashReporter";
static const NSTimeInterval kEvery = 24 * 3600;
// list version: 1 = 1.0.2 list, 2 = 1.0.3 list, 3 = 1.0.5 list (see WADiag.h). 1.0.2 yeses count as 2
static NSString *const kConsent = @"diagConsent";
static const NSInteger kConsentNow = 3;

@interface WADiag () <UIAlertViewDelegate>
@end

@implementation WADiag {
	BOOL _sending, _launchNoted, _askingMore;
}

+ (instancetype)shared {
	static WADiag *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [[WADiag alloc] init];
		[[NSNotificationCenter defaultCenter] addObserver:shared selector:@selector(memoryWarning)
			name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
	});
	return shared;
}

- (NSUserDefaults *)d { return [NSUserDefaults standardUserDefaults]; }
- (BOOL)on { return [self.d boolForKey:WAPrefDiagnostics]; }
// who said yes in 1.0.2 sends the 1.0.3 list too, without asking again (Aron's call, privacy policy says so)
- (NSInteger)consent { return [self.d objectForKey:kConsent] ? [self.d integerForKey:kConsent] : (self.on ? 2 : 0); }
- (BOOL)extended { return self.on && self.consent >= 2; }
- (BOOL)usage { return self.on && self.consent >= 3; }

#pragma mark - Asking

// also in the settings footer, keep both the same
NSString *const WADiagWhat = @"Once a day: iPhone model, iOS and app version, bridge version and system, language, crash reports, error codes (also from your bridge), how late notifications arrive and how often the connection drops (in rough steps), upload sizes in steps, memory warnings, start time, whether known TLS or App Store tweaks are installed, how far setup got, which features get used and whether sending works (counts per day).";

- (void)askIfNeeded {
	if (_asking || ![WAClient shared].configured || [WACall shared].live) return;
	// said yes before 1.0.5: the new counts need their own yes, asked once
	if (self.extended && !self.usage && ![self.d boolForKey:@"diagAsked3"]) {
		_asking = YES;
		_askingMore = YES;
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:WAL(@"Diagnostics")
			message:WAL(@"WA Classic can also count how far setup got, which features get used and whether sending works, once a day. Never what you write or to whom.")
			delegate:self cancelButtonTitle:WAL(@"Don't Send") otherButtonTitles:WAL(@"Send"), nil];
		[alert show];
		return;
	}
	// 1.0.2 yeses carry over without asking again, see -consent
	if ([self.d boolForKey:@"diagAsked"]) return;
	_asking = YES;
	NSString *never = WAL(@"\n\nNever messages, contacts, numbers, names, your IP or location. You can change this in Settings › Chat Settings › Advanced.");
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:WAL(@"Help Improve WA Classic?")
		message:[[WAL(@"Send anonymous diagnostics. ") stringByAppendingString:WAL(WADiagWhat)] stringByAppendingString:never]
		delegate:self cancelButtonTitle:WAL(@"Don't Send") otherButtonTitles:WAL(@"Send"), nil];
	[alert show];
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
	_asking = NO;
	BOOL yes = index != alert.cancelButtonIndex;
	[self.d setBool:YES forKey:@"diagAsked3"];
	if (_askingMore) {
		_askingMore = NO;
		if (yes) [self.d setInteger:kConsentNow forKey:kConsent];
		WALog(@"diagnostics: 1.0.5 list %@", yes ? @"yes" : @"no");
		return;
	}
	[self.d setBool:YES forKey:@"diagAsked"];
	[self.d setBool:yes forKey:WAPrefDiagnostics];
	[self.d setInteger:yes ? kConsentNow : 0 forKey:kConsent];
	WALog(@"diagnostics: %@", yes ? @"yes" : @"no");
	if (yes) {
		// crashes from before the yes stay on the phone
		[self.d setDouble:[[NSDate date] timeIntervalSince1970] forKey:@"diagCrashSeen"];
		[self sendIfDue];
	}
}

#pragma mark - Collecting

- (NSString *)installID {
	NSString *uuid = [self.d stringForKey:@"diagID"];
	if (!uuid) {
		CFUUIDRef ref = CFUUIDCreate(NULL);
		uuid = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, ref);
		CFRelease(ref);
		[self.d setObject:uuid forKey:@"diagID"];
	}
	return uuid;
}

// sha256 of our own executable. the server knows the hashes of the released debs,
// so rebuilt or patched copies of the app show up as modified instead of mixing into our numbers
static NSString *BinaryHash(void) {
	static NSString *hash;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSData *bin = [NSData dataWithContentsOfFile:[NSBundle mainBundle].executablePath options:NSDataReadingMappedIfSafe error:NULL];
		if (!bin.length) return;
		unsigned char md[CC_SHA256_DIGEST_LENGTH];
		CC_SHA256(bin.bytes, (CC_LONG)bin.length, md);
		NSMutableString *hex = [NSMutableString stringWithCapacity:64];
		for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", md[i]];
		hash = hex;
	});
	return hash ?: @"";
}

static NSString *Machine(void) {
	size_t size = 0;
	sysctlbyname("hw.machine", NULL, &size, NULL, 0);
	char *buf = malloc(size + 1);
	if (!buf) return @"";
	sysctlbyname("hw.machine", buf, &size, NULL, 0);
	buf[size] = 0;
	NSString *out = [NSString stringWithUTF8String:buf] ?: @"";
	free(buf);
	return out;
}

static NSString *Today(void) {
	static NSDateFormatter *f;
	if (!f) {
		f = [[NSDateFormatter alloc] init];
		f.dateFormat = @"yyyy-MM-dd";
		f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
	}
	return [f stringFromDate:[NSDate date]];
}

- (void)noteBridge:(NSDictionary *)status {
	if (![status isKindOfClass:[NSDictionary class]]) return;
	NSMutableDictionary *bridge = [NSMutableDictionary dictionary];
	for (NSString *key in @[@"version", @"platform", @"arch", @"kernel", @"docker"]) {
		if (status[key]) bridge[key] = status[key];
	}
	if (bridge.count) [self.d setObject:bridge forKey:@"diagBridge"];
}

- (void)record:(NSString *)code {
	[self record:code times:1];
}

- (void)count:(NSString *)code {
	if (self.extended) [self record:code times:1];
}

// 1.0.5 list: "setup ...", "use ...", "send ..."
- (void)countUsage:(NSString *)code {
	if (self.usage) [self record:code times:1];
}

// each setup step once per install, a funnel of who got how far
- (void)setupStep:(NSString *)step {
	if (!self.usage) return;
	NSString *key = [@"diagStep " stringByAppendingString:step];
	if ([self.d boolForKey:key]) return;
	[self.d setBool:YES forKey:key];
	[self record:[@"setup " stringByAppendingString:step] times:1];
}

// what the app asks the bridge to do. posts only, never who or what
- (void)noteRequest:(NSURLRequest *)req ok:(BOOL)ok {
	if (!self.usage || ![req.HTTPMethod isEqualToString:@"POST"]) return;
	static NSDictionary *sends, *uses;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		sends = @{@"send": @"text", @"sendimage": @"photo", @"sendvideo": @"video", @"sendvoice": @"voice",
			@"broadcast/send": @"broadcast", @"broadcast/resend": @"broadcast", @"react": @"reaction"};
		uses = @{@"group/create": @"new group", @"call/start": @"call", @"call/answer": @"answer call",
			@"chat/delete": @"delete chat", @"mute": @"mute", @"blocklist": @"block", @"group/subject": @"group subject",
			@"group/photo": @"group photo", @"group/leave": @"leave group", @"group/participants": @"group members",
			@"me": @"profile", @"me/photo": @"profile photo", @"me/lastseen": @"last seen"};
	});
	NSString *path = [req.URL.path stringByReplacingOccurrencesOfString:@"/api/" withString:@""];
	// params are in the query or, for small posts, the body. media bodies are never read
	NSString *body = req.HTTPBody.length < 4096 ? [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding] : nil;
	NSString *params = [NSString stringWithFormat:@"&%@&%@&", req.URL.query ?: @"", body ?: @""];
	NSString *kind = sends[path];
	if (kind) {
		if ([params rangeOfString:@"&quote="].location != NSNotFound) kind = [kind stringByAppendingString:@" reply"];
		[self record:[NSString stringWithFormat:@"send %@ %@", ok ? @"ok" : @"failed", kind] times:1];
		return;
	}
	NSString *what = uses[path];
	if (!what) return;
	if ([path isEqualToString:@"call/start"] && [params rangeOfString:@"&video=1&"].location != NSNotFound) what = @"video call";
	if (ok) [self record:[@"use " stringByAppendingString:what] times:1];
}

static NSString *Step(NSTimeInterval s, const double *limits, NSArray *names) {
	for (NSUInteger i = 0; i < names.count - 1; i++) if (s < limits[i]) return names[i];
	return names.lastObject;
}

- (void)noteDelay:(NSTimeInterval)secs of:(NSString *)what {
	static const double limits[] = {10, 60, 300, 900};
	[self count:[NSString stringWithFormat:@"%@ %@", what, Step(MAX(secs, 0), limits, @[@"<10s", @"<1m", @"<5m", @"<15m", @"15m+"])]];
}

- (void)memoryWarning {
	[self count:@"memory warning"];
}

static NSTimeInterval ProcessAge(void) {
	struct kinfo_proc info;
	size_t size = sizeof(info);
	int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
	if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) return -1;
	struct timeval start = info.kp_proc.p_starttime, now;
	gettimeofday(&now, NULL);
	return (now.tv_sec - start.tv_sec) + (now.tv_usec - start.tv_usec) / 1e6;
}

// first time active after the process started; background launches (voip) don't count
- (void)noteLaunched {
	if (_launchNoted) return;
	_launchNoted = YES;
	NSTimeInterval age = ProcessAge();
	if (age < 0 || age > 60) return;
	static const double limits[] = {1, 2, 5};
	[self count:[@"start " stringByAppendingString:Step(age, limits, @[@"<1s", @"<2s", @"<5s", @"5s+"])]];
}

- (void)record:(NSString *)code times:(NSInteger)times {
	if (!self.on || !code.length || times <= 0) return;
	if (code.length > 80) code = [code substringToIndex:80];
	NSMutableDictionary *days = [[self.d dictionaryForKey:@"diagErrors"] mutableCopy] ?: [NSMutableDictionary dictionary];
	NSString *today = Today();
	NSMutableDictionary *counts = [days[today] mutableCopy] ?: [NSMutableDictionary dictionary];
	if (counts.count >= 120 && !counts[code]) return;
	counts[code] = @([counts[code] integerValue] + times);
	days[today] = counts;
	// two weeks at most if sending keeps failing
	for (NSString *day in [days.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		if (days.count <= 14) break;
		[days removeObjectForKey:day];
	}
	[self.d setObject:days forKey:@"diagErrors"];
}

// the useful parts of a crash log only: exception, crashed thread, last exception backtrace, our binary images.
// no incident id or crashreporter key, those identify the phone
static NSString *ShortCrash(NSString *text) {
	NSMutableArray *out = [NSMutableArray array];
	NSArray *lines = [text componentsSeparatedByString:@"\n"];
	BOOL inBlock = NO, inImages = NO;
	NSUInteger blockLines = 0;
	for (NSString *line in lines) {
		if ([line hasPrefix:@"Exception Type"] || [line hasPrefix:@"Exception Codes"] || [line hasPrefix:@"Crashed Thread"] ||
			[line hasPrefix:@"OS Version"] || [line hasPrefix:@"Version:"]) {
			[out addObject:line];
			continue;
		}
		if (([line hasPrefix:@"Thread "] && [line hasSuffix:@"Crashed:"]) || [line hasPrefix:@"Last Exception Backtrace"]) {
			inBlock = YES;
			blockLines = 0;
			[out addObject:line];
			continue;
		}
		if ([line hasPrefix:@"Binary Images"]) {
			inImages = YES;
			[out addObject:line];
			continue;
		}
		if (inBlock) {
			if (!line.length || blockLines++ > 30) { inBlock = NO; continue; }
			[out addObject:line];
		} else if (inImages && ([line rangeOfString:@"WA4S"].location != NSNotFound || [line rangeOfString:@"WACallScreen"].location != NSNotFound)) {
			[out addObject:line];
		}
	}
	NSString *joined = [out componentsJoinedByString:@"\n"];
	return joined.length > 7500 ? [joined substringToIndex:7500] : joined;
}

// the tweak is loaded in every springboard, so its name is in every springboard crash.
// ours only if an address of the crashed thread or the exception backtrace lies inside it (pass ShortCrash text,
// the full log has registers and other threads)
static BOOL CrashedInCallScreen(NSString *text) {
	NSRange images = [text rangeOfString:@"Binary Images"];
	if (images.location == NSNotFound) return NO;
	unsigned long long lo = 0, hi = 0;
	for (NSString *line in [[text substringFromIndex:images.location] componentsSeparatedByString:@"\n"]) {
		if ([line rangeOfString:@"WACallScreen"].location == NSNotFound) continue;
		NSScanner *s = [NSScanner scannerWithString:line];
		[s scanHexLongLong:&lo];
		[s scanUpToString:@"0x" intoString:NULL];
		[s scanHexLongLong:&hi];
		break;
	}
	if (!lo || hi <= lo) return NO;
	NSScanner *s = [NSScanner scannerWithString:[text substringToIndex:images.location]];
	while (![s isAtEnd]) {
		[s scanUpToString:@"0x" intoString:NULL];
		unsigned long long a = 0;
		if (![s scanHexLongLong:&a]) break;
		if (a >= lo && a <= hi) return YES;
	}
	return NO;
}

- (NSArray *)newCrashes:(NSTimeInterval *)newest {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSTimeInterval seen = [self.d doubleForKey:@"diagCrashSeen"];
	*newest = seen;
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *name in [fm contentsOfDirectoryAtPath:kCrashDir error:NULL]) {
		BOOL app = [name hasPrefix:@"WA4S_"], sb = [name hasPrefix:@"SpringBoard_"];
		if ((!app && !sb) || ![name hasSuffix:@".plist"] || out.count >= 5) continue;
		NSString *path = [kCrashDir stringByAppendingPathComponent:name];
		NSTimeInterval ts = [[fm attributesOfItemAtPath:path error:NULL].fileModificationDate timeIntervalSince1970];
		if (ts <= seen) continue;
		NSString *text = [NSDictionary dictionaryWithContentsOfFile:path][@"description"];
		if (![text isKindOfClass:[NSString class]]) continue;
		if (sb && !CrashedInCallScreen(ShortCrash(text))) continue; // springboard crashes that aren't ours
		[out addObject:@{@"ts": @((long long)ts), @"kind": sb ? @"springboard" : @"app", @"text": ShortCrash(text)}];
		*newest = MAX(*newest, ts);
	}
	return out;
}

#pragma mark - Sending

// only packages whose id says tls/ssl/cert/store/gsa, never the whole list
static NSArray *KnownTweaks(void) {
	NSMutableArray *out = [NSMutableArray array];
	NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"tls|ssl|cert|appstore|storefix|gsa|itunesstore"
		options:NSRegularExpressionCaseInsensitive error:NULL];
	for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/var/lib/dpkg/info" error:NULL]) {
		if (![name hasSuffix:@".list"] || out.count >= 15) continue;
		NSString *pkg = [name stringByDeletingPathExtension];
		if (pkg.length <= 60 && [re numberOfMatchesInString:pkg options:0 range:NSMakeRange(0, pkg.length)]) [out addObject:pkg];
	}
	return [out sortedArrayUsingSelector:@selector(compare:)];
}

- (void)sendIfDue {
	if (!self.on || _sending) return;
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	if (now - [self.d doubleForKey:@"diagSent"] < kEvery) return;
	if (!self.extended || ![WAClient shared].configured) {
		[self sendNow:now];
		return;
	}
	// fresh bridge version and the bridge's error counts first. old bridges have no /api/diag, that's fine
	_sending = YES;
	WAClient *c = [WAClient shared];
	[c load:[c requestFor:@"/api/status" params:nil] completion:^(NSData *data, NSInteger status, NSError *error) {
		id json = status == 200 && data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
		if ([json isKindOfClass:[NSDictionary class]]) [self noteBridge:json];
		[c load:[c requestFor:@"/api/diag" params:nil] completion:^(NSData *data, NSInteger status, NSError *error) {
			id json = status == 200 && data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
			NSDictionary *counts = [json isKindOfClass:[NSDictionary class]] ? json[@"counts"] : nil;
			if ([counts isKindOfClass:[NSDictionary class]]) {
				for (NSString *code in counts) {
					if ([code isKindOfClass:[NSString class]]) [self record:[@"bridge " stringByAppendingString:code] times:[counts[code] integerValue]];
				}
			}
			self->_sending = NO;
			[self sendNow:now];
		}];
	}];
}

- (void)sendNow:(NSTimeInterval)now {
	if (!self.on || _sending) return;
	NSTimeInterval newest = 0;
	NSArray *crashes = [self newCrashes:&newest];
	NSDictionary *days = [self.d dictionaryForKey:@"diagErrors"];
	NSMutableArray *errors = [NSMutableArray array];
	for (NSString *day in days) {
		for (NSString *code in days[day]) [errors addObject:@{@"day": day, @"code": code, @"n": days[day][code]}];
	}
	NSDictionary *bridge = [self.d dictionaryForKey:@"diagBridge"];
	WAClient *c = [WAClient shared];
#ifdef WA_IOS4
	NSString *pkg = @"ios4";
#else
	NSString *pkg = @"ios6";
#endif
	NSDictionary *report = @{
		@"id": [self installID], @"device": Machine(), @"ios": [UIDevice currentDevice].systemVersion ?: @"",
		@"app": [NSBundle mainBundle].infoDictionary[@"CFBundleVersion"] ?: @"", @"pkg": pkg,
		@"bundle": [NSBundle mainBundle].bundleIdentifier ?: @"", @"bin": BinaryHash(),
		@"bridge": bridge[@"version"] ?: @"", @"platform": bridge[@"platform"] ?: @"", @"arch": bridge[@"arch"] ?: @"",
		@"kernel": bridge[@"kernel"] ?: @"", @"docker": @([bridge[@"docker"] boolValue]),
		@"away": @(c.awayURL.length > 0), @"look": @([[NSFileManager defaultManager] fileExistsAtPath:WAAssetPath(@"Tri-tone.caf")]),
		@"lang": [NSLocale preferredLanguages].firstObject ?: @"", @"crashes": crashes, @"errors": errors,
		@"consent": @(self.usage ? 3 : self.extended ? 2 : 1), @"tweaks": self.extended ? KnownTweaks() : @[],
	};
	NSData *body = [NSJSONSerialization dataWithJSONObject:report options:0 error:NULL];
	if (!body) return;
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kSend]
		cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
	req.HTTPMethod = @"POST";
	[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	req.HTTPBody = body;
	_sending = YES;
	[c load:req completion:^(NSData *data, NSInteger status, NSError *error) {
		self->_sending = NO;
		if (error || status != 200) {
			WALog(@"diagnostics: send failed %ld %@", (long)status, error.localizedDescription);
			return;
		}
		[self.d setDouble:now forKey:@"diagSent"];
		[self.d removeObjectForKey:@"diagErrors"];
		if (newest > [self.d doubleForKey:@"diagCrashSeen"]) [self.d setDouble:newest forKey:@"diagCrashSeen"];
		WALog(@"diagnostics: sent (%lu crashes, %lu error codes)", (unsigned long)crashes.count, (unsigned long)errors.count);
	}];
}

- (void)turnedOn {
	[self.d setBool:YES forKey:@"diagAsked"];
	[self.d setBool:YES forKey:@"diagAsked3"];
	[self.d setBool:YES forKey:WAPrefDiagnostics];
	[self.d setInteger:kConsentNow forKey:kConsent];
	[self.d setDouble:[[NSDate date] timeIntervalSince1970] forKey:@"diagCrashSeen"];
	[self sendIfDue];
}

- (void)chosenInSetup:(BOOL)send {
	[self.d setBool:YES forKey:@"diagAsked"];
	[self.d setBool:YES forKey:@"diagAsked3"];
	// crashes from before the yes stay on the phone
	if (send && !self.on) [self.d setDouble:[[NSDate date] timeIntervalSince1970] forKey:@"diagCrashSeen"];
	[self.d setBool:send forKey:WAPrefDiagnostics];
	[self.d setInteger:send ? kConsentNow : 0 forKey:kConsent];
	WALog(@"diagnostics: %@ (setup)", send ? @"yes" : @"no");
}

- (void)turnedOff {
	[self.d setInteger:0 forKey:kConsent];
	NSString *uuid = [self.d stringForKey:@"diagID"];
	[self.d removeObjectForKey:@"diagErrors"];
	[self.d removeObjectForKey:@"diagSent"];
	if (!uuid) return;
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kForget]
		cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
	req.HTTPMethod = @"POST";
	[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"id": uuid} options:0 error:NULL];
	[[WAClient shared] load:req completion:^(NSData *data, NSInteger status, NSError *error) {
		WALog(@"diagnostics: delete %ld", (long)status);
		// new id next time, so old and new can't be linked
		if (!error && status == 200) [self.d removeObjectForKey:@"diagID"];
	}];
}

@end
