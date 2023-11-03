#import <Foundation/Foundation.h>

typedef void (^NStringCallback)(NSString *,NSString *);
typedef void (^IntCallback)(int64_t,int64_t);
extern NStringCallback logCallback;
extern IntCallback     trafficCallback;
void clash_setLogBlock(NStringCallback block);

void clash_setTrafficBlock(IntCallback block);

static inline void sendLogToUI(char *s, char *level) {
	@autoreleasepool {
		if (logCallback) {
			logCallback([NSString stringWithUTF8String:s], [NSString stringWithUTF8String:level]);
		}
	}
}

static inline void sendTrafficToUI(int64_t up, int64_t down) {
	if (trafficCallback) {
		trafficCallback(up, down);
	}
}
