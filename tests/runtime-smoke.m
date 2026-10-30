#import <Foundation/Foundation.h>
#import "../NFBMethodLookup.h"
#include <stdio.h>

static unsigned int NFBInitializations;
static unsigned int NFBResolutions;

@interface NFBRuntimeProbe : NSObject
- (NSString*)existingItem;
+ (NSString*)existingGlyph;
@end

@implementation NFBRuntimeProbe
+ (void)initialize { NFBInitializations++; }
+ (BOOL)resolveInstanceMethod:(SEL)selector { NFBResolutions++; return NO; }
+ (BOOL)resolveClassMethod:(SEL)selector { NFBResolutions++; return NO; }
- (NSString*)existingItem { return @"original instance"; }
+ (NSString*)existingGlyph { return @"original class"; }
@end

@interface NFBRuntimeProbeIntermediate : NFBRuntimeProbe
@end
@implementation NFBRuntimeProbeIntermediate
@end

static id NFBReplacementItem(id self, SEL command) { return @"replacement instance"; }
static id NFBReplacementGlyph(id self, SEL command) { return @"replacement class"; }

static void NFBRequire(BOOL condition, const char* message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        Class parent = objc_getClass("NFBRuntimeProbeIntermediate");
        SEL missing = sel_registerName("nfbMissingPrivateHostAPI");
        NFBRequire(NFBFindMethodWithoutResolving(Nil, missing) == NULL, "missing class");
        NFBRequire(NFBFindMethodWithoutResolving(parent, NULL) == NULL, "missing selector");
        NFBRequire(NFBFindMethodWithoutResolving(parent, missing) == NULL, "missing instance API");
        NFBRequire(NFBFindMethodWithoutResolving(object_getClass(parent), missing) == NULL,
                   "missing class API");
        NFBRequire(NFBFindMethodWithoutResolving(parent, @selector(existingItem)) != NULL,
                   "inherited instance API");
        NFBRequire(NFBFindMethodWithoutResolving(object_getClass(parent), @selector(existingGlyph)) != NULL,
                   "inherited class API");

        Class child = objc_allocateClassPair(parent, "NFBRuntimeProbeChild", 0);
        NFBRequire(child != Nil, "allocate subclass");
        NFBRequire(NFBAddInheritedOverride(child, parent, NO, @selector(existingItem),
                                          (IMP)NFBReplacementItem), "instance override");
        NFBRequire(NFBAddInheritedOverride(child, parent, YES, @selector(existingGlyph),
                                          (IMP)NFBReplacementGlyph), "class override");
        NFBRequire(!NFBAddInheritedOverride(child, parent, YES, missing,
                                           (IMP)NFBReplacementGlyph), "reject missing class override");
        NFBRequire(NFBInitializations == 0, "metadata lookup must not initialize host classes");
        NFBRequire(NFBResolutions == 0, "metadata lookup must not invoke method resolution");
        objc_registerClassPair(child);

        id instance = [child new];
        NFBRequire([[instance existingItem] isEqualToString:@"replacement instance"],
                   "registered instance dispatch");
        NFBRequire([[child existingGlyph] isEqualToString:@"replacement class"],
                   "registered class dispatch");
        [instance release];

        // The required-API failure path must also safely dispose of its class.
        Class rejected = objc_allocateClassPair(parent, "NFBRuntimeProbeRejected", 0);
        NFBRequire(rejected != Nil, "allocate rejected subclass");
        NFBRequire(!NFBAddInheritedOverride(rejected, parent, YES, missing,
                                           (IMP)NFBReplacementGlyph), "reject missing required API");
        objc_disposeClassPair(rejected);
        NFBRequire(objc_getClass("NFBRuntimeProbeRejected") == Nil, "rejected subclass remains unregistered");
        NFBRequire(NFBResolutions == 0, "no resolver calls during registration or disposal");
        puts("Runtime metadata checks: PASS");
    }
    return 0;
}
