#import <Foundation/Foundation.h>
#import "../NFBPhotoSupport.h"
#include <stdio.h>
#include <stdlib.h>

@interface NFBPhotoFixture : NSObject <NFBMediaEntity>
@property(nonatomic) NSInteger mediaType;
@property(nonatomic, strong) id mediaURL;
@end
@implementation NFBPhotoFixture
@end

static void Require(BOOL condition, const char* message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

static NFBPhotoFixture* Media(NSInteger type, id url) {
    NFBPhotoFixture* media = [NFBPhotoFixture new];
    media.mediaType = type;
    media.mediaURL = url;
    return media;
}

static NSString* Query(NSURL* url, NSString* name) {
    for (NSURLQueryItem* item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if ([item.name isEqualToString:name]) return item.value;
    }
    return nil;
}

int main(void) {
    @autoreleasepool {
        NSArray* candidates = NFBPhotoURLCandidates(@"https://pbs.twimg.com/media/one.jpg");
        Require(candidates.count == 2, "original plus fallback");
        Require([Query(candidates[0], @"name") isEqualToString:@"orig"], "request original size");
        Require([Query(candidates[0], @"format") isEqualToString:@"jpg"], "preserve JPEG format");
        Require([[candidates[1] absoluteString] isEqualToString:@"https://pbs.twimg.com/media/one.jpg"], "keep exact fallback");
        candidates = NFBPhotoURLCandidates(@"http://pbs.twimg.com/media/two.png:large");
        Require([[candidates[0] scheme] isEqualToString:@"https"], "upgrade legacy Twitter HTTP");
        Require([[candidates[0] path] isEqualToString:@"/media/two"], "strip legacy size suffix");
        Require([Query(candidates[0], @"format") isEqualToString:@"png"], "preserve PNG format");
        candidates = NFBPhotoURLCandidates(@"https://pbs.twimg.com/media/three?format=jpg&name=small&tag=keep");
        Require([Query(candidates[0], @"tag") isEqualToString:@"keep"], "preserve unrelated query items");
        Require([Query(candidates[0], @"name") isEqualToString:@"orig"], "replace thumbnail size");
        NSURL* original = [NSURL URLWithString:@"https://pbs.twimg.com/media/four?format=jpg&name=orig"];
        Require(NFBPhotoURLCandidates(original).count == 1, "deduplicate identical fallback");
        NSString* external = @"https://images.example.test/image.png?name=small";
        candidates = NFBPhotoURLCandidates(external);
        Require(candidates.count == 1 && [[candidates[0] absoluteString] isEqualToString:external], "leave other HTTPS hosts unchanged");
        Require(NFBPhotoURLCandidates(@"https://pbs.twimg.com/media/no-known-format").count == 1, "do not guess missing formats");
        Require(NFBPhotoURLCandidates(nil).count == 0, "nil URL");
        Require(NFBPhotoURLCandidates(@42).count == 0, "non-string URL");
        Require(NFBPhotoURLCandidates(@"file:///tmp/image.jpg").count == 0, "reject file URL");
        Require(NFBPhotoURLCandidates(@"https://").count == 0, "reject missing host");

        NFBPhotoFixture* first = Media(1, @"https://pbs.twimg.com/media/a.jpg");
        NFBPhotoFixture* missing = Media(1, nil);
        NFBPhotoFixture* last = Media(1, @"https://pbs.twimg.com/media/b.png");
        NSArray* mixed = @[first, Media(2, nil), missing, Media(3, nil), last, [NSObject new]];
        NSArray<NSArray<NSURL*>*>* groups = NFBPhotoURLGroups(mixed);
        Require(groups.count == 3 && groups[1].count == 0, "count invalid photos instead of silently dropping them");
        Require([groups[0][0].path isEqualToString:@"/media/a"] &&
                [groups[2][0].path isEqualToString:@"/media/b"], "preserve photo attachment order");
        first.mediaURL = @"https://pbs.twimg.com/media/reused-cell.jpg";
        Require([groups[0][0].path isEqualToString:@"/media/a"], "snapshot URLs before cell reuse");
        Require(NFBHasDownloadableMedia(@[Media(1, nil)]), "show button for ordinary photos");
        Require(NFBHasDownloadableMedia(@[Media(2, nil)]) && NFBHasDownloadableMedia(@[Media(3, nil)]), "retain GIF/video support");
        Require(!NFBHasDownloadableMedia(@[]) && !NFBHasDownloadableMedia(@[[NSObject new], Media(4, nil)]), "ignore text and unsupported entities");
        Require(NFBPhotoURLGroups(@[last, last]).count == 2, "retain each attached photo, even repeated images");
        puts("Photo URL, ordering, routing and reuse checks: PASS");
    }
    return 0;
}
