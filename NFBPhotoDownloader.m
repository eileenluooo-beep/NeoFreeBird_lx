#import "NFBPhotoDownloader.h"
#import "NFBPhotoSupport.h"
#import <Photos/Photos.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>

static UIWindow* NFBPhotoWindow(UIView* source) {
    if (source.window != nil) return source.window;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return nil;
}

static UIViewController* NFBPhotoController(UIWindow* window) {
    UIViewController* top = window.rootViewController;
    while (top != nil) {
        if (top.presentedViewController != nil && !top.presentedViewController.isBeingDismissed) {
            top = top.presentedViewController;
        } else if ([top isKindOfClass:UINavigationController.class] &&
                   ((UINavigationController*)top).visibleViewController != nil) {
            top = ((UINavigationController*)top).visibleViewController;
        } else if ([top isKindOfClass:UITabBarController.class] &&
                   ((UITabBarController*)top).selectedViewController != nil) {
            top = ((UITabBarController*)top).selectedViewController;
        } else {
            return top;
        }
    }
    return nil;
}

@interface NFBPhotoFeedback : NSObject
@property(nonatomic, strong) UIVisualEffectView* panel;
@property(nonatomic, strong) UILabel* label;
- (instancetype)initWithWindow:(UIWindow*)window;
- (void)setText:(NSString*)text;
- (void)finishWithText:(NSString*)text;
@end

static __weak UIVisualEffectView* NFBLivePhotoPanel;

@implementation NFBPhotoFeedback
- (instancetype)initWithWindow:(UIWindow*)window {
    self = [super init];
    if (self == nil) return nil;
    self.panel = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    self.panel.layer.cornerRadius = 14.0;
    self.panel.clipsToBounds = YES;
    self.panel.userInteractionEnabled = NO;
    self.panel.translatesAutoresizingMaskIntoConstraints = NO;
    self.label = [UILabel new];
    self.label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.label.adjustsFontForContentSizeCategory = YES;
    self.label.textColor = UIColor.labelColor;
    self.label.numberOfLines = 0;
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.panel.contentView addSubview:self.label];
    [NSLayoutConstraint activateConstraints:@[
        [self.label.leadingAnchor constraintEqualToAnchor:self.panel.contentView.leadingAnchor constant:14],
        [self.label.trailingAnchor constraintEqualToAnchor:self.panel.contentView.trailingAnchor constant:-14],
        [self.label.topAnchor constraintEqualToAnchor:self.panel.contentView.topAnchor constant:10],
        [self.label.bottomAnchor constraintEqualToAnchor:self.panel.contentView.bottomAnchor constant:-10]
    ]];
    if (window != nil) {
        [NFBLivePhotoPanel removeFromSuperview];
        NFBLivePhotoPanel = self.panel;
        [window addSubview:self.panel];
        [NSLayoutConstraint activateConstraints:@[
            [self.panel.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
            [self.panel.leadingAnchor constraintGreaterThanOrEqualToAnchor:window.safeAreaLayoutGuide.leadingAnchor constant:20],
            [self.panel.trailingAnchor constraintLessThanOrEqualToAnchor:window.safeAreaLayoutGuide.trailingAnchor constant:-20],
            [self.panel.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-24]
        ]];
    }
    return self;
}
- (void)setText:(NSString*)text { self.label.text = text; }
- (void)finishWithText:(NSString*)text {
    [self setText:text];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, text);
    UIVisualEffectView* panel = self.panel;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ [panel removeFromSuperview]; });
}
@end

@class NFBPhotoBatch;
static NFBPhotoBatch* NFBActivePhotoBatch;

@interface NFBPhotoBatch : NSObject
@property(nonatomic, copy) NSArray<NSArray<NSURL*>*>* groups;
@property(nonatomic, strong) NFBPhotoFeedback* feedback;
@property(nonatomic, strong) NSURLSession* session;
@property(nonatomic, strong) NSURL* directory;
@property(nonatomic) NSUInteger index;
@property(nonatomic) NSUInteger saved;
@property(nonatomic) BOOL finished;
- (void)start;
- (void)beginDownloading;
- (void)downloadNext;
- (void)downloadCandidate:(NSUInteger)candidate;
- (void)saveFile:(NSURL*)file;
- (void)finishWithMessage:(NSString*)message;
@end

// NSURLSession's temporary URL is deleted when its completion handler returns.
// Stage bytes synchronously before passing a file to asynchronous PhotoKit.
static NSURL* NFBStagePhoto(NSURL* temporary, NSURL* directory, NSUInteger index) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)temporary, NULL);
    if (source == NULL) return nil;
    size_t count = CGImageSourceGetCount(source);
    NSString* identifier = [(__bridge NSString*)CGImageSourceGetType(source) copy];
    CFRelease(source);
    if (count == 0 || identifier.length == 0) return nil;
    UTType* type = [UTType typeWithIdentifier:identifier];
    NSString* extension = type.preferredFilenameExtension;
    if (![type conformsToType:UTTypeImage] || extension.length == 0) return nil;
    NSURL* file = [directory URLByAppendingPathComponent:
        [NSString stringWithFormat:@"X-photo-%lu.%@", (unsigned long)(index + 1), extension]];
    if ([[NSFileManager defaultManager] copyItemAtURL:temporary toURL:file error:NULL]) return file;
    [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
    return nil;
}

static BOOL NFBPhotoAuthorized(PHAuthorizationStatus status) {
    return status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited;
}

@implementation NFBPhotoBatch
- (void)start {
    [self.feedback setText:NFBPhotoText(@"准备保存全部图片…", @"Preparing to save all photos…")];
    // A missing privacy-purpose string can terminate a host app. Check the
    // actual host bundle before asking PhotoKit for authorization.
    id addDescription = [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSPhotoLibraryAddUsageDescription"];
    id readDescription = [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSPhotoLibraryUsageDescription"];
    PHAccessLevel level;
    if ([addDescription isKindOfClass:NSString.class] && [addDescription length] > 0) {
        level = PHAccessLevelAddOnly;
    } else if ([readDescription isKindOfClass:NSString.class] && [readDescription length] > 0) {
        // Some host packages declare only their existing read/write Photos use.
        // The implementation still only creates assets; it never reads albums.
        level = PHAccessLevelReadWrite;
    } else {
        [self finishWithMessage:NFBPhotoText(@"当前安装包缺少相册保存配置，无法直接保存图片。",
            @"This app package is missing its Photos permission description.")];
        return;
    }
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:level];
    if (NFBPhotoAuthorized(status)) {
        [self beginDownloading];
    } else if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:level handler:^(PHAuthorizationStatus result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (NFBPhotoAuthorized(result)) [self beginDownloading];
                else [self finishWithMessage:NFBPhotoText(@"请在系统设置中允许 X 保存照片。",
                    @"Allow X to save photos in iOS Settings.")];
            });
        }];
    } else {
        [self finishWithMessage:NFBPhotoText(@"请在系统设置中允许 X 保存照片。",
            @"Allow X to save photos in iOS Settings.")];
    }
}
- (void)beginDownloading {
    self.directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[@"NFBPhotos-" stringByAppendingString:NSUUID.UUID.UUIDString]
        isDirectory:YES];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:self.directory
            withIntermediateDirectories:NO attributes:nil error:NULL]) {
        [self finishWithMessage:NFBPhotoText(@"无法创建图片临时文件，请检查可用空间。",
            @"Unable to create temporary photo files. Check available storage.")];
        return;
    }
    NSURLSessionConfiguration* config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.URLCache = nil;
    config.HTTPCookieStorage = nil;
    config.URLCredentialStorage = nil;
    config.HTTPShouldSetCookies = NO;
    config.timeoutIntervalForRequest = 30;
    config.timeoutIntervalForResource = 90;
    self.session = [NSURLSession sessionWithConfiguration:config];
    [self downloadNext];
}
- (void)downloadNext {
    if (self.index >= self.groups.count) {
        NSString* format = self.saved == self.groups.count
            ? NFBPhotoText(@"已保存 %lu 张图片到相册。", @"Saved %lu photos to Photos.")
            : NFBPhotoText(@"已保存 %lu/%lu 张图片，%lu 张未保存。", @"Saved %lu/%lu photos; %lu failed.");
        [self finishWithMessage:[NSString stringWithFormat:format, (unsigned long)self.saved,
            (unsigned long)self.groups.count, (unsigned long)(self.groups.count - self.saved)]];
        return;
    }
    [self.feedback setText:[NSString stringWithFormat:NFBPhotoText(@"正在保存图片 %lu/%lu…",
        @"Saving photo %lu/%lu…"), (unsigned long)(self.index + 1), (unsigned long)self.groups.count]];
    [self downloadCandidate:0];
}
- (void)downloadCandidate:(NSUInteger)candidate {
    NSArray<NSURL*>* candidates = self.groups[self.index];
    if (candidate >= candidates.count) {
        self.index++;
        [self downloadNext];
        return;
    }
    NSURLRequest* request = [NSURLRequest requestWithURL:candidates[candidate]];
    NSUInteger index = self.index;
    NSURL* directory = self.directory;
    [[self.session downloadTaskWithRequest:request completionHandler:
        ^(NSURL* temporary, NSURLResponse* response, NSError* error) {
            NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class]
                ? ((NSHTTPURLResponse*)response).statusCode : 0;
            NSURL* file = error == nil && temporary != nil && status >= 200 && status < 300
                ? NFBStagePhoto(temporary, directory, index) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (file == nil) [self downloadCandidate:candidate + 1];
                else [self saveFile:file];
            });
        }] resume];
}
- (void)saveFile:(NSURL*)file {
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCreationRequest* creation = [PHAssetCreationRequest creationRequestForAsset];
        PHAssetResourceCreationOptions* options = [PHAssetResourceCreationOptions new];
        options.originalFilename = file.lastPathComponent;
        [creation addResourceWithType:PHAssetResourceTypePhoto fileURL:file options:options];
    } completionHandler:^(BOOL success, NSError* error) {
        // Keep the staged bytes alive until PhotoKit has finished importing.
        [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) self.saved++;
            self.index++;
            [self downloadNext];
        });
    }];
}
- (void)finishWithMessage:(NSString*)message {
    if (self.finished) return;
    self.finished = YES;
    [self.session invalidateAndCancel];
    if (self.directory != nil) [[NSFileManager defaultManager] removeItemAtURL:self.directory error:NULL];
    [self.feedback finishWithText:message];
    if (NFBActivePhotoBatch == self) NFBActivePhotoBatch = nil;
}
@end

@implementation NFBPhotoDownloader
+ (void)startGroups:(NSArray<NSArray<NSURL*>*>*)groups window:(UIWindow*)window {
    // All job state changes run on the main queue. Repeated taps during a batch
    // cannot enqueue the same images again, including after a cell is reused.
    if (NFBActivePhotoBatch != nil || groups.count == 0) return;
    NFBPhotoBatch* batch = [NFBPhotoBatch new];
    batch.groups = groups;
    batch.feedback = [[NFBPhotoFeedback alloc] initWithWindow:window];
    NFBActivePhotoBatch = batch;
    [batch start];
}
+ (void)handlePhotoTapWithMediaEntities:(NSArray*)entities
                            sourceView:(UIView*)sourceView
                          videoHandler:(void (^)(void))videoHandler {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handlePhotoTapWithMediaEntities:entities sourceView:sourceView videoHandler:videoHandler];
        });
        return;
    }
    NSArray<NSArray<NSURL*>*>* groups = NFBPhotoURLGroups(entities);
    UIWindow* window = NFBPhotoWindow(sourceView);
    if (videoHandler == nil) {
        [self startGroups:groups window:window];
        return;
    }
    UIViewController* controller = NFBPhotoController(window);
    if (controller == nil || [controller isKindOfClass:UIAlertController.class]) return;
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:
        NFBPhotoText(@"下载媒体", @"Download media") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak UIAlertController* weakSheet = sheet;
    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:
        NFBPhotoText(@"保存全部图片（%lu 张）", @"Save all photos (%lu)"), (unsigned long)groups.count]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
            [self startGroups:groups window:window];
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NFBPhotoText(@"下载视频 / GIF", @"Download video / GIF")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
            // Present NeoFreeBird's quality picker after this sheet finishes
            // dismissing; an arbitrary one-queue delay may race its animation.
            UIAlertController* closing = weakSheet;
            id<UIViewControllerTransitionCoordinator> transition = closing.transitionCoordinator;
            if (closing.isBeingDismissed && transition != nil &&
                [transition animateAlongsideTransition:nil completion:
                    ^(id<UIViewControllerTransitionCoordinatorContext> context) { videoHandler(); }]) return;
            if (closing.presentingViewController != nil) {
                [closing dismissViewControllerAnimated:YES completion:videoHandler];
            } else {
                videoHandler();
            }
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NFBPhotoText(@"取消", @"Cancel")
        style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sourceView.window ? sourceView : controller.view;
    UIView* anchor = sheet.popoverPresentationController.sourceView;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(anchor.bounds),
        CGRectGetMidY(anchor.bounds), 1, 1);
    [controller presentViewController:sheet animated:YES completion:nil];
}
@end
