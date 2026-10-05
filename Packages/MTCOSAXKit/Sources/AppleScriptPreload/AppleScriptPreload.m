// For tests only: loads AppleScript when a test bundle is loaded, before any test runs.
//
// CommandDispatcher loads AppleScript (for the Apple Event Manager's text-to-number coercions) the first time one is
// made. In a test process, where Swift Testing runs many tests at once, that load sometimes recursed inside the
// Apple Event Manager and AppleScript until the stack ran out (about one AppleEventCoreTests run in ten). The app
// loads it at launch on its main thread, with nothing else running, and never did. Loading it here, while the bundle
// is loaded and no test has started, gives the tests the app's conditions; CommandDispatcher's own load then finds
// AppleScript ready.

#import <Foundation/Foundation.h>
#import "AppleScriptPreload.h"

__attribute__((constructor, used)) static void mtc_preload_applescript(void) {
	@autoreleasepool {
		NSDictionary *error = nil;
		[[[NSAppleScript alloc] initWithSource:@"1"] compileAndReturnError:&error];
	}
}
