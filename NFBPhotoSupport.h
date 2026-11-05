#import <Foundation/Foundation.h>

@protocol NFBMediaEntity <NSObject>
- (NSInteger)mediaType;
@optional
- (id)mediaURL;
@end

BOOL NFBHasDownloadableMedia(NSArray* entities);
NSArray<NSURL*>* NFBPhotoURLCandidates(id rawURL);
// One group per photo, in attachment order. An empty group is a failed lookup,
// not a silently omitted attachment. Returned URLs snapshot the current post.
NSArray<NSArray<NSURL*>*>* NFBPhotoURLGroups(NSArray* entities);
NSString* NFBPhotoText(NSString* chinese, NSString* english);
