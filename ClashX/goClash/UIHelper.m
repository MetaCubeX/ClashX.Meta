#import "UIHelper.h"
NStringCallback logCallback;
IntCallback     trafficCallback;
void clash_setLogBlock(NStringCallback block) {
	logCallback = [block copy];
}

void clash_setTrafficBlock(IntCallback block) {
    trafficCallback = [block copy];
}