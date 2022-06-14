//
//  HPImageNode.m
//  HiPDA
//
//  Created by Jiangfan on 2017/6/11.
//  Copyright © 2017年 wujichao. All rights reserved.
//

#import "HPImageNode.h"
#import <BlocksKit/NSArray+BlocksKit.h>
#import "HPSetting.h"

@interface HPImageNode()

@property (nonatomic, strong) NSString *prefix;
@property (nonatomic, strong) NSString *id;
@property (nonatomic, strong) NSString *extension;
@property (nonatomic, strong) NSString *url;

@end

@implementation HPImageNode

- (instancetype)initWithURL:(NSString *)url
{
    self = [super init];
    if (self) {
        NSParameterAssert(url.length);
        _url = [url copy];
        
        NSRange r1 = [url rangeOfString:@"attachments/"];
        if (r1.location != NSNotFound) {
            _prefix = [url substringWithRange:NSMakeRange(0, r1.location)];
            
            NSUInteger s = r1.location + r1.length;
            NSRange r2 = [url rangeOfString:@"." options:0 range:NSMakeRange(s, url.length - s)];
            NSParameterAssert(r2.location != NSNotFound);
            if (r2.location != NSNotFound) {
                
                NSUInteger s2 = r2.location + r2.length;
                NSRange r3 = [url rangeOfString:@"." options:0 range:NSMakeRange(s2, url.length - s2)];
                if (r3.location != NSNotFound) {
                    _extension = [url substringWithRange:NSMakeRange(s2, r3.location - s2)];
                } else {
                    _extension = [url substringFromIndex:s2];
                }
                
                _id = [url substringWithRange:NSMakeRange(s, r2.location - s)];
            }
        }
    }
    return self;
}

- (BOOL)isEqual:(id)object
{
    if (!object) {
        return NO;
    }
    
    if (self == object) {
        return YES;
    }
    
    if (![object isKindOfClass:[HPImageNode class]]) {
        return NO;
    }
    
    HPImageNode *other = (HPImageNode *)object;
    
    return [self.id isEqualToString:other.id];
}

- (NSString *)hp_thumbnailURL
{
    NSString *s = [[self hp_URL] stringByAppendingString:HP_THUMB_URL_SUFFIX];
    return s;
}

- (NSString *)hp_URL
{
    NSString *s = [NSString stringWithFormat:@"%@attachments/%@.%@", self.prefix, self.id, self.extension];
    return s;
}

@end

@implementation NSArray (HPImageNode)

- (NSArray<NSString *> *)hp_imageThumbnailURLs;
{
    return [self bk_map:^NSString *(HPImageNode *n) {
        NSParameterAssert([n isKindOfClass:HPImageNode.class]);
        return n.hp_thumbnailURL;
    }];
}

- (NSArray<NSString *> *)hp_imageURLs;
{
    return [self bk_map:^NSString *(HPImageNode *n) {
        NSParameterAssert([n isKindOfClass:HPImageNode.class]);
        return n.hp_URL;
    }];
}

@end

