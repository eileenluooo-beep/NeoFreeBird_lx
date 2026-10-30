#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
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

typedef CGFloat (^NFBRuntimeCalculator)(id);

@interface NFBRuntimeLayoutProbe : NSObject
- (BOOL)isNarrowButton:(id)button;
- (void)layoutAtOrigin:(CGPoint)origin
         contentWidth:(CGFloat)width contentHeight:(CGFloat)height
      widthCalculator:(NFBRuntimeCalculator)widthCalculator
  alignmentCalculator:(NFBRuntimeCalculator)alignmentCalculator
       minimumSpacing:(CGFloat)minimum maximumSpacing:(CGFloat)maximum
     rightSidePadding:(BOOL)padding;
@end

@implementation NFBRuntimeLayoutProbe
- (BOOL)isNarrowButton:(id)button { return NO; }
- (void)layoutAtOrigin:(CGPoint)origin
         contentWidth:(CGFloat)width contentHeight:(CGFloat)height
      widthCalculator:(NFBRuntimeCalculator)widthCalculator
  alignmentCalculator:(NFBRuntimeCalculator)alignmentCalculator
       minimumSpacing:(CGFloat)minimum maximumSpacing:(CGFloat)maximum
     rightSidePadding:(BOOL)padding {}
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
        Class layoutProbe = objc_getClass("NFBRuntimeLayoutProbe");
        Method layout = NFBFindMethodWithoutResolving(layoutProbe,
            @selector(layoutAtOrigin:contentWidth:contentHeight:widthCalculator:alignmentCalculator:minimumSpacing:maximumSpacing:rightSidePadding:));
        const char* layoutArguments[] = {"@", ":", @encode(CGPoint), @encode(CGFloat),
            @encode(CGFloat), "@?", "@?", @encode(CGFloat), @encode(CGFloat), @encode(BOOL)};
        NFBRequire(NFBMethodHasSignature(layout, "v", 10, layoutArguments),
                   "accept compatible layout hook ABI");
        NFBRequire(!NFBMethodHasSignature(layout, "v", 9, layoutArguments),
                   "reject changed argument count");
        NFBRequire(!NFBMethodHasSignature(layout, "@", 10, layoutArguments),
                   "reject changed return type");
        layoutArguments[2] = @encode(CGFloat);
        NFBRequire(!NFBMethodHasSignature(layout, "v", 10, layoutArguments),
                   "reject CGPoint replaced by scalar");
        layoutArguments[2] = @encode(CGPoint);
        layoutArguments[5] = "@";
        NFBRequire(!NFBMethodHasSignature(layout, "v", 10, layoutArguments),
                   "reject block treated as ordinary object");
        Method narrow = NFBFindMethodWithoutResolving(layoutProbe, @selector(isNarrowButton:));
        const char* narrowArguments[] = {"@", ":", "@"};
        NFBRequire(NFBMethodHasSignature(narrow, @encode(BOOL), 3, narrowArguments),
                   "accept compatible narrow-button hook ABI");
        NFBRequire(!NFBMethodHasSignature(NULL, "v", 10, layoutArguments),
                   "reject missing private method");
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
