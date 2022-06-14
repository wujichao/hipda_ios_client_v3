//
//  NSString+CDN.m
//  HiPDA
//
//  Created by Jiangfan on 16/6/9.
//  Copyright © 2016年 wujichao. All rights reserved.
//

#import "NSString+CDN.h"
#import "HPSetting.h"

@implementation NSString (CDN)

- (NSString *)hp_thumbnailURL
{
    NSParameterAssert([self rangeOfString:HP_IMG_BASE_HOST].location != NSNotFound);
    NSParameterAssert([self rangeOfString:HP_CDN_URL_SUFFIX].location == NSNotFound);
    
    NSString *src = [self stringByReplacingOccurrencesOfString:HP_IMG_BASE_HOST withString:HP_CDN_BASE_HOST];
    src = [src stringByAppendingString:HP_CDN_URL_SUFFIX];
    return src;
}

- (NSString *)hp_originalURL
{
    NSParameterAssert([self rangeOfString:HP_CDN_BASE_HOST].location != NSNotFound);
    NSParameterAssert([self rangeOfString:HP_CDN_URL_SUFFIX].location != NSNotFound);
    
    NSString *src = [self stringByReplacingOccurrencesOfString:HP_CDN_BASE_HOST withString:HP_IMG_BASE_HOST];
    src = [src stringByReplacingOccurrencesOfString:HP_CDN_URL_SUFFIX withString:@""];
    return src;
}

@end
