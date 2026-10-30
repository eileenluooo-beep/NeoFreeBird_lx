// Adds a native inline shortcut to NeoFreeBird's existing video/GIF downloader.
// Host API reference: NeoFreeBird/classdump and NeoFreeBird/app v7.3.0.
// Compiled without ARC: initializer IMPs consume self and return +1; other
// object-returning IMPs return borrowed/autoreleased values, as the host expects.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@protocol NFBMediaViewModel <NSObject>
- (NSArray*)representedMediaEntities;
@end

@protocol NFBMediaEntity <NSObject>
- (NSInteger)mediaType;
@end

@protocol NFBInlineAction <NSObject>
- (id)viewModel;
- (id)delegate;
- (instancetype)initWithOptions:(NSUInteger)options overrideSize:(id)size account:(id)account;
- (instancetype)initWithInlineActionType:(NSUInteger)type
                                options:(NSUInteger)options
                           overrideSize:(id)overrideSize
                                account:(id)account;
+ (NSString*)buttonImageNameForUIControlState:(NSUInteger)state viewModel:(id)model
                                    options:(NSUInteger)options account:(id)account;
+ (NSString*)buttonHoverImageNameForUIControlState:(NSUInteger)state viewModel:(id)model
                                         options:(NSUInteger)options account:(id)account;
- (BOOL)shouldShowCount;
- (NSUInteger)visibility;
- (BOOL)enabled;
- (NSString*)actionSheetTitle;
- (void)didTap;
- (void)didLongPressActionButton:(UILongPressGestureRecognizer*)gesture;
- (void)didTriggerAlternateAction;
@end

@protocol NFBDownloadPresenter <NSObject>
- (void)presentDownloadOptionsForMediaEntities:(NSArray*)entities;
@end

@protocol NFBSettingsProvider <NSObject>
+ (BOOL)boolForKey:(NSString*)key;
@end

@protocol NFBBundleProvider <NSObject>
+ (instancetype)sharedBundle;
- (NSString*)localizedStringForKey:(NSString*)key;
@end

typedef NSArray* (*NFBActionClassesIMP)(id, SEL, id, NSUInteger, NSUInteger, id);

static NFBActionClassesIMP NFBOriginalActionClasses;
static Class NFBDownloadButtonClass;
static char NFBDownloadPresenterKey;

static NSString* NFBDownloadTitle(void) {
    Class<NFBBundleProvider> bundleClass = (Class)objc_getClass("BHTBundle");
    if ([bundleClass respondsToSelector:@selector(sharedBundle)]) {
        id<NFBBundleProvider> bundle = [bundleClass sharedBundle];
        if ([bundle respondsToSelector:@selector(localizedStringForKey:)]) {
            NSString* title = [bundle localizedStringForKey:@"DOWNLOAD_VIDEOS_TITLE"];
            if (title.length > 0 && ![title isEqualToString:@"DOWNLOAD_VIDEOS_TITLE"]) {
                return title;
            }
        }
    }
    return @"Download media";
}

static BOOL NFBDownloadsEnabled(void) {
    Class<NFBSettingsProvider> settings = (Class)objc_getClass("BHTSettings");
    Class presenter = objc_getClass("DownloadInlineButton");
    return [settings respondsToSelector:@selector(boolForKey:)] &&
        [settings boolForKey:@"download_videos"] &&
        [presenter instancesRespondToSelector:@selector(presentDownloadOptionsForMediaEntities:)];
}

static NSArray* NFBMediaEntities(id viewModel) {
    if (![viewModel respondsToSelector:@selector(representedMediaEntities)]) {
        return nil;
    }
    id entities = [(id<NFBMediaViewModel>)viewModel representedMediaEntities];
    return [entities isKindOfClass:NSArray.class] ? entities : nil;
}

static BOOL NFBHasVideo(NSArray* entities) {
    for (id<NFBMediaEntity> media in entities) {
        if ([media respondsToSelector:@selector(mediaType)]) {
            NSInteger type = [media mediaType];
            // These are the same media types handled by NeoFreeBird's menu.
            if (type == 2 || type == 3) {
                return YES;
            }
        }
    }
    return NO;
}

static NSArray* NFBCurrentButtonMedia(id<NFBInlineAction> button) {
    // Read at tap time: a timeline cell may have been reused for another post.
    id viewModel = [button viewModel];
    return NFBMediaEntities(viewModel);
}

static id NFBButtonInit(id<NFBInlineAction> self, SEL command, NSUInteger options,
                        id overrideSize, id account) {
    // 131 is the custom download action type used by NeoFreeBird's former
    // inline button. Keep the host's initializer, sizing, tint and animations.
    return [self initWithInlineActionType:131
                                options:options
                           overrideSize:overrideSize
                                account:account];
}

static id NFBButtonImageName(id self, SEL command, NSUInteger state, id viewModel,
                            NSUInteger options, id account) {
    return @"arrow_down_circle_stroke";
}

static BOOL NFBButtonShowsCount(id self, SEL command) {
    return NO;
}

static NSUInteger NFBButtonVisibility(id self, SEL command) {
    return 1;
}

static BOOL NFBButtonEnabled(id self, SEL command) {
    return NFBDownloadsEnabled() && NFBHasVideo(NFBCurrentButtonMedia(self));
}

static id NFBButtonTitle(id self, SEL command) {
    return NFBDownloadTitle();
}

static void NFBButtonTapped(id self, SEL command) {
    if (!NFBDownloadsEnabled()) {
        return;
    }
    NSArray* entities = NFBCurrentButtonMedia(self);
    if (!NFBHasVideo(entities)) {
        return;
    }
    id<NFBDownloadPresenter> presenter = objc_getAssociatedObject(self, &NFBDownloadPresenterKey);
    if (presenter == nil) {
        presenter = [objc_getClass("DownloadInlineButton") new];
        objc_setAssociatedObject(self, &NFBDownloadPresenterKey, presenter,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [(id)presenter release];
    }
    // Reuse the existing quality picker, multi-video menu, saving and progress.
    [presenter presentDownloadOptionsForMediaEntities:entities];
}

static void NFBButtonLongPressed(id self, SEL command, UILongPressGestureRecognizer* gesture) {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        NFBButtonTapped(self, @selector(didTap));
    }
}

static BOOL NFBOverrideInheritedMethod(Class subclass, BOOL isClassMethod, SEL selector,
                                        IMP implementation) {
    Class destination = isClassMethod ? object_getClass(subclass) : subclass;
    Method inherited = class_getInstanceMethod(destination, selector);
    if (inherited == NULL) {
        return NO;
    }
    return class_addMethod(destination, selector, implementation, method_getTypeEncoding(inherited));
}

static Class NFBCreateDownloadButton(void) {
    Class parent = objc_getClass("TTAStatusInlineActionButton");
    if (parent == Nil ||
        ![parent instancesRespondToSelector:@selector(viewModel)] ||
        ![parent instancesRespondToSelector:@selector(initWithInlineActionType:options:overrideSize:account:)]) {
        return Nil;
    }
    Class button = objc_allocateClassPair(parent, "NFBActionBarMediaDownloadButton", 0);
    if (button == Nil) {
        return Nil;
    }
    BOOL ready =
        NFBOverrideInheritedMethod(button, NO, @selector(initWithOptions:overrideSize:account:), (IMP)NFBButtonInit) &&
        NFBOverrideInheritedMethod(button, YES, @selector(buttonImageNameForUIControlState:viewModel:options:account:), (IMP)NFBButtonImageName) &&
        NFBOverrideInheritedMethod(button, NO, @selector(shouldShowCount), (IMP)NFBButtonShowsCount) &&
        NFBOverrideInheritedMethod(button, NO, @selector(visibility), (IMP)NFBButtonVisibility) &&
        NFBOverrideInheritedMethod(button, NO, @selector(enabled), (IMP)NFBButtonEnabled) &&
        NFBOverrideInheritedMethod(button, NO, @selector(actionSheetTitle), (IMP)NFBButtonTitle) &&
        NFBOverrideInheritedMethod(button, NO, @selector(didTap), (IMP)NFBButtonTapped) &&
        NFBOverrideInheritedMethod(button, NO, @selector(didLongPressActionButton:), (IMP)NFBButtonLongPressed) &&
        NFBOverrideInheritedMethod(button, NO, @selector(didTriggerAlternateAction), (IMP)NFBButtonTapped);
    if (!ready) {
        objc_disposeClassPair(button);
        return Nil;
    }
    // UIKit accessibility methods are inherited. Preserve their actual encodings.
    NFBOverrideInheritedMethod(button, NO, @selector(accessibilityLabel), (IMP)NFBButtonTitle);
    NFBOverrideInheritedMethod(button, YES, @selector(buttonHoverImageNameForUIControlState:viewModel:options:account:), (IMP)NFBButtonImageName);
    objc_registerClassPair(button);
    return button;
}

static NSUInteger NFBIndexOfClass(NSArray* classes, const char* name) {
    Class candidate = objc_getClass(name);
    return candidate ? [classes indexOfObject:candidate] : NSNotFound;
}

static NSArray* NFBInlineActionClasses(id self, SEL command, id viewModel,
                                      NSUInteger options, NSUInteger displayType, id account) {
    NSArray* original = NFBOriginalActionClasses(self, command, viewModel, options, displayType, account);
    if (![original isKindOfClass:NSArray.class] || NFBDownloadButtonClass == Nil ||
        !NFBDownloadsEnabled() || !NFBHasVideo(NFBMediaEntities(viewModel)) ||
        [original containsObject:NFBDownloadButtonClass]) {
        return original;
    }
    NSMutableArray* classes = [[original mutableCopy] autorelease];
    // This is a logical position, so native layout also handles RTL and resizing.
    NSUInteger insertion = NFBIndexOfClass(classes, "TTAStatusInlineBookmarkButton");
    if (insertion == NSNotFound) {
        insertion = NFBIndexOfClass(classes, "TTAStatusInlineShareButton");
    }
    if (insertion == NSNotFound) {
        insertion = classes.count;
    }
    [classes insertObject:NFBDownloadButtonClass atIndex:insertion];
    return [[classes copy] autorelease];
}

__attribute__((constructor)) static void NFBInstallActionBarShortcut(void) {
    @autoreleasepool {
        Class actions = objc_getClass("TTAStatusInlineActionsView");
        SEL selector = sel_registerName("_t1_inlineActionViewClassesForViewModel:options:displayType:account:");
        Method method = class_getClassMethod(actions, selector);
        if (method == NULL) {
            NSLog(@"[NFBActionBarDownload] Inline action API unavailable; shortcut not installed.");
            return;
        }
        NFBDownloadButtonClass = NFBCreateDownloadButton();
        if (NFBDownloadButtonClass == Nil) {
            NSLog(@"[NFBActionBarDownload] Native button API unavailable; shortcut not installed.");
            return;
        }
        NFBOriginalActionClasses = (NFBActionClassesIMP)method_getImplementation(method);
        // Add a local override if the class inherited this method; otherwise
        // replace the class's own implementation and keep the existing chain.
        if (!class_addMethod(object_getClass(actions), selector, (IMP)NFBInlineActionClasses,
                             method_getTypeEncoding(method))) {
            NFBOriginalActionClasses = (NFBActionClassesIMP)method_setImplementation(method, (IMP)NFBInlineActionClasses);
        }
    }
}
