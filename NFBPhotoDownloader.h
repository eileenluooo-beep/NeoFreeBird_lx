#import <UIKit/UIKit.h>

@interface NFBPhotoDownloader : NSObject
+ (void)handlePhotoTapWithMediaEntities:(NSArray*)entities
                            sourceView:(UIView*)sourceView
                          videoHandler:(void (^)(void))videoHandler;
@end
