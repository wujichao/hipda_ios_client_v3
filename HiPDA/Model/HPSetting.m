//
//  HPSetting.m
//  HiPDA
//
//  Created by wujichao on 14-3-13.
//  Copyright (c) 2014年 wujichao. All rights reserved.
//

#import "HPSetting.h"
#import "HPForum.h"
#import <BlocksKit/NSArray+BlocksKit.h>
#import "NSString+Additions.h"
#import "NSUserDefaults+Convenience.h"
#import "HPOnceRunService.h"

#define DEBUG_SETTING 0

@interface HPSetting()

@property (nonatomic, strong) NSMutableDictionary *globalSettings;

@end



@implementation HPSetting


+ (HPSetting*)sharedSetting {
    
    static dispatch_once_t once;
    static HPSetting *sharedSetting;
    dispatch_once(&once, ^ {
        sharedSetting = [[self alloc] init];
    });
    return sharedSetting;
}

+ (NSString *)keyForSetting
{
    NSString *username = [NSStandardUserDefaults stringForKey:kHPAccountUserName or:@""];
    
    return [NSString stringWithFormat:@"%@_for_%@", HPSettingDic, username];
}

+ (NSString *)keyForOnce:(NSString *)key
{
    NSString *username = [NSStandardUserDefaults stringForKey:kHPAccountUserName or:@""];
    return [NSString stringWithFormat:@"%@_for_%@", key, username];
}

- (void)loadSetting {
    
    //_globalSettings = [NSStandardUserDefaults objectForKey:HPSettingDic];
    NSDictionary *savedSettings = [NSStandardUserDefaults objectForKey:[self.class keyForSetting]];
    if (!savedSettings) {
        // 兼容老版本
        savedSettings = [NSStandardUserDefaults objectForKey:HPSettingDic];
        [self save];
    }
    
    DDLogInfo(@"savedSettings %@", savedSettings);
    
    ///////////
    // app update setting
    if (savedSettings) {
        _globalSettings = [NSMutableDictionary dictionaryWithDictionary:savedSettings];
        
        NSMutableSet *keysInA = [NSMutableSet setWithArray:[[HPSetting defualts] allKeys]];
        NSSet *keysInB = [NSSet setWithArray:[_globalSettings allKeys]];
        [keysInA minusSet:keysInB];
    
        NSLog(@"keys in A that are not in B: %@", keysInA);
        
        for (NSString *key in keysInA) {
            id value = [[HPSetting defualts] objectForKey:key];
            [_globalSettings setObject:value forKey:key];
        }
    }
    //////////
    
    if (!savedSettings) {
        [self loadDefaults];
    }
    
    [HPOnceRunService onceName:@"enableHTTPS" runBlcok:^{
        // 之前默认的https设置是NO, 现在改成默认YES, 老版本ye
        [self saveBool:YES forKey:HPSettingEnableHTTPS];
        
        // 由于上了https, 所以不再允许设置httpdns
        [self saveObject:HP_WWW_BASE_HOST forKey:HPSettingBaseURL];
        [self saveBool:NO forKey:HPSettingForceDNS];
    } skipBlock:nil];
    
    [HPOnceRunService onceName:@"deleteEink" runBlcok:^{
        NSArray *fids = [Setting objectForKey:HPSettingFavForums];
        NSArray *fids_title = [Setting objectForKey:HPSettingFavForumsTitle];

        NSSet *black_fid_set = [NSSet setWithArray:@[@59, @57]];
        NSSet *black_title_set = [NSSet setWithArray:@[@"E-INK", @"疑似机器人"]];
        
        fids = [fids bk_select:^BOOL(id obj) {
            return ![black_fid_set containsObject:obj];
        }];
        fids_title = [fids_title bk_select:^BOOL(id obj) {
            return ![black_title_set containsObject:obj];
        }];
      
        [Setting saveObject:fids forKey:HPSettingFavForums];
        [Setting saveObject:fids_title forKey:HPSettingFavForumsTitle];
    } skipBlock:nil];
    
    [HPOnceRunService onceName:[self.class keyForOnce:@"updateDomain"] runBlcok:^{
        [self saveObject:@"www.4d4y.com" forKey:HPSettingBaseURL];
    } skipBlock:nil];
    
    if (DEBUG_SETTING) NSLog(@"load  _globalSettings %@", _globalSettings);
}

- (void)loadDefaults {
    
    NSDictionary *defaults = [HPSetting defualts];
    
    // todo 加key 升级 后检测
    
    _globalSettings = [NSMutableDictionary dictionaryWithDictionary:defaults];
    if (DEBUG_SETTING) NSLog(@"load  loadDefaults %@", _globalSettings);
    [self save];
}

+ (NSDictionary *)defualts {
    NSDictionary *defaults = @{HPSettingTail:@"iOS fly ~",
                               HPSettingBaseURL:HP_WWW_BASE_HOST,
                               HPSettingForceDNS:@NO,
                               HPSettingFavForums:@[@2, @6],
                               HPSettingFavForumsTitle:@[@"Discovery", @"Buy & Sell"],
                               HPSettingShowAvatar:@YES,
                               HPSettingNightMode:@NO,
                               HPSettingFontSize:@16.f,
                               HPSettingFontSizeAdjust:IS_IPAD?@130:@110,
                               HPSettingLineHeight:@1.5,
                               HPSettingLineHeightAdjust:@160,
                               HPSettingTextFont:@"STHeitiSC-Light",
                               HPSettingImageWifi:@0,
                               HPSettingImageWWAN:@0,
                               HPPMCount:@0,
                               HPNoticeCount:@0,
                               HPSettingBgFetchNotice:@YES,
                               HPSettingIsPullReply:@NO,
                               HPSettingStupidBarDisable:@NO,
                               HPSettingStupidBarHide:@YES,
                               HPSettingStupidBarLeftAction:@(HPStupidBarActionFavorite),
                               HPSettingStupidBarCenterAction:@(HPStupidBarActionScrollBottom),
                               HPSettingStupidBarRightAction:@(HPStupidBarActionReply),
                               HPSettingBlockList:@[],
                               HPSettingAfterSendShowConfirm:@NO,
                               HPSettingAfterSendJump:@YES,
                               HPSettingDataTrackEnable:@YES,
                               HPSettingBSForumOrderByDate:@NO,
                               HPSettingForceLogin:@NO,
                               HPBgFetchInterval:@(60),
                               HP_SHOW_MESSAGE_IMAGE_NOTICE:@(NO),
                               
                               HPSettingImageAutoLoadEnableWWAN:@YES,
                               HPSettingImageAutoLoadModeWWAN: @(HPImageAutoLoadModePerferThumb),
                               HPSettingImageAutoLoadModeAutoThresholdWWAN: @(512),
                               
                               HPSettingImageAutoLoadEnableWifi:@YES,
                               HPSettingImageAutoLoadModeWifi: @(HPImageAutoLoadModePerferAuto),
                               HPSettingImageAutoLoadModeAutoThresholdWifi: @(1024),
                               
                               HPSettingPrintPagePost:@YES,
                               HPSettingEnableHTTPS:@YES,
                               
                               HPSettingRegularFontMode:@YES,
                               
                               HPSettingEnableWKWebview:@NO,
                               
                               HPSettingApiEnv:@YES,
                               HPSettingLabUserInfo: @"",
                               HPSettingLabCookiesPermission: @NO,
                               HPSettingLabEnablePush: @NO,
                               };
    return defaults;
}

- (void)save {
    [NSStandardUserDefaults saveObject:_globalSettings forKey:[self.class keyForSetting]];
    if (DEBUG_SETTING) NSLog(@"save  _globalSettings %@", _globalSettings);
}

#pragma mark -

- (id)objectForKey:(NSString *)key {
    if (DEBUG_SETTING) NSLog(@"objectForKey %@: %@", key, [_globalSettings objectForKey:key]);
    if (!key) {
        NSLog(@"ERROR: objectForKey %@", key);
        return nil;
    }
    return [_globalSettings objectForKey:key];
}

- (BOOL)boolForKey:(NSString *)key {
    return [[self objectForKey:key] boolValue];
}

- (NSInteger)integerForKey:(NSString *)key {
    return [[self objectForKey:key] integerValue];
}

- (CGFloat)floatForKey:(NSString *)key {
    return [[self objectForKey:key] floatValue];
}

#pragma mark - 

- (void)saveObject:(id)value forKey:(NSString *)key {
    if (DEBUG_SETTING) NSLog(@"saveObject %@: %@", key, value);
    
    if (!key || !value) {
        NSLog(@"ERROR: saveObject %@: %@", key, value);
        return;
    }
    [_globalSettings setObject:value forKey:key];
    [self save];
}

- (void)saveInteger:(NSInteger)value forKey:(NSString *)key {
    [self saveObject:[NSNumber numberWithInteger:value] forKey:key];
}

- (void)saveBool:(BOOL)value forKey:(NSString *)key {
    [self saveObject:[NSNumber numberWithBool:value] forKey:key];
}

- (void)saveFloat:(float)value forKey:(NSString *)key {
    [self saveObject:[NSNumber numberWithFloat:value] forKey:key];
}


#pragma mark - post tail
// return @"" or @"[size=1]%@[/size]"
- (NSString *)postTail {
    NSString *tail = [self objectForKey:HPSettingTail];
    if (!tail || [tail isEqualToString:@""]) {
        return @"";
    } else {
        return [NSString stringWithFormat:@"[size=1]%@[/size]", tail];;
    }
}

- (void)setPostTail:(NSString *)postTail {
    if (!postTail) postTail = @"";
    [self saveObject:postTail forKey:HPSettingTail];
}

- (NSString *)isPostTailAllow:(NSString *)postTail {
    //
    if ([postTail indexOf:@"["] != -1 ||
        [postTail indexOf:@"]"] != -1) {
        return @"不允许使用标签";
    }
    //
    NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    NSUInteger length = [postTail lengthOfBytesUsingEncoding:encoding];
    if (length > 16) {
        // 改成八字
        return @"中文七字以内, 英文十四字以内";
    }
    return nil;
}

@end
