#import "NFBPhotoSupport.h"

NSString* NFBPhotoText(NSString* chinese, NSString* english) {
    return [NSLocale.preferredLanguages.firstObject hasPrefix:@"zh"] ? chinese : english;
}

BOOL NFBHasDownloadableMedia(NSArray* entities) {
    for (id<NFBMediaEntity> media in entities) {
        if (![media respondsToSelector:@selector(mediaType)]) continue;
        NSInteger kind = [media mediaType];
        if (kind == 1 || kind == 2 || kind == 3) return YES;
    }
    return NO;
}

NSArray<NSURL*>* NFBPhotoURLCandidates(id rawURL) {
    NSString* string = [rawURL isKindOfClass:NSURL.class] ? [rawURL absoluteString] : rawURL;
    if (![string isKindOfClass:NSString.class] || string.length == 0) return @[];
    NSURLComponents* components = [NSURLComponents componentsWithString:string];
    NSString* scheme = components.scheme.lowercaseString;
    BOOL isTwitterImage = [components.host.lowercaseString isEqualToString:@"pbs.twimg.com"] &&
        [components.path hasPrefix:@"/media/"];
    if (isTwitterImage && [scheme isEqualToString:@"http"]) {
        components.scheme = @"https";
        scheme = @"https";
    }
    if (![scheme isEqualToString:@"https"] || components.host.length == 0 ||
        components.user.length > 0 || components.password.length > 0) return @[];
    components.fragment = nil;
    NSURL* fallback = components.URL;
    if (fallback == nil) return @[];
    if (!isTwitterImage) return @[fallback];

    // Handle both /media/id.jpg:large and /media/id?format=jpg&name=small.
    NSString* path = components.path;
    NSRange colon = [path rangeOfString:@":" options:NSBackwardsSearch];
    if (colon.location != NSNotFound) {
        NSString* suffix = [path substringFromIndex:colon.location + 1];
        if ([@[@"orig", @"small", @"medium", @"large", @"thumb"] containsObject:suffix]) {
            path = [path substringToIndex:colon.location];
        }
    }
    NSString* format = nil;
    NSMutableArray<NSURLQueryItem*>* query = [NSMutableArray array];
    for (NSURLQueryItem* item in components.queryItems) {
        if ([item.name.lowercaseString isEqualToString:@"format"]) {
            if (format.length == 0) format = item.value.lowercaseString;
        } else if (![item.name.lowercaseString isEqualToString:@"name"]) {
            [query addObject:item];
        }
    }
    NSString* extension = path.pathExtension.lowercaseString;
    NSArray* formats = @[@"jpg", @"jpeg", @"png", @"webp", @"heic", @"avif"];
    if (format.length == 0 && [formats containsObject:extension]) format = extension;
    if (format.length == 0 || ![formats containsObject:format]) return @[fallback];
    if ([formats containsObject:extension]) path = path.stringByDeletingPathExtension;
    if ([format isEqualToString:@"jpeg"]) format = @"jpg";
    components.path = path;
    [query addObject:[NSURLQueryItem queryItemWithName:@"format" value:format]];
    [query addObject:[NSURLQueryItem queryItemWithName:@"name" value:@"orig"]];
    components.queryItems = query;
    NSURL* original = components.URL;
    if (original == nil || [original isEqual:fallback]) return @[fallback];
    return @[original, fallback];
}

NSArray<NSArray<NSURL*>*>* NFBPhotoURLGroups(NSArray* entities) {
    NSMutableArray* groups = [NSMutableArray array];
    for (id<NFBMediaEntity> media in entities) {
        if (![media respondsToSelector:@selector(mediaType)] || [media mediaType] != 1) continue;
        id rawURL = [media respondsToSelector:@selector(mediaURL)] ? [media mediaURL] : nil;
        [groups addObject:NFBPhotoURLCandidates(rawURL)];
    }
    return [groups copy];
}
