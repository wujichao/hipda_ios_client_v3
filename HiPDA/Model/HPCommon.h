//
//  HPCommon.h
//  HiPDA
//
//  Created by wujichao on 13-11-12.
//  Copyright (c) 2013年 wujichao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NSUserDefaults+Convenience.h"
#import "UIDevice+iPhoneX.h"

//helper
//
#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

#define IOS7_OR_LATER (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
#define IOS8_OR_LATER (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"8.0"))
#define IOS9_OR_LATER (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"9.0"))
#define IOS9_2_OR_LATER (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"9.2"))
#define IOS10_OR_LATER (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"10.0"))
#define IOS11_OR_LATER (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"11.0"))

#define IS_IPAD ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)

#define NSStandardUserDefaults [NSUserDefaults standardUserDefaults]

#define HP_SCREEN_WIDTH (CGRectGetWidth([[UIScreen mainScreen] bounds]))
#define HP_SCREEN_HEIGHT (CGRectGetHeight([[UIScreen mainScreen] bounds]))
#define HP_CONVERT_WIDTH(a) (ceilf((a)*kScreenWidth/320.f))
#define HP_CONVERT_HEIGHT(a) (ceilf((a)*kScreenHeight/568.f))

#define HP_1PX (1.0f / [UIScreen mainScreen].scale)

#define HP_NAVBAR_HEIGHT ([UIDevice hp_isiPhoneX] ? 88.f : 64.f)

// Copy from Tweet4China
// Created by Jason Hsu

#define kTabBarHeight 44
#define kIPadTabBarWidth 84
#define kIPADMainViewWidth 626


#define GCDBackgroundThread dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
#define GCDMainThread dispatch_get_main_queue()

#define dp(filename) [([NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0]) stringByAppendingPathComponent:filename]

#define tp(filename) [([NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0])stringByAppendingPathComponent:filename]

#define ccr(x, y, w, h) CGRectMake(floorf(x), floorf(y), floorf(w), floorf(h))
#define ccp(x, y) CGPointMake(floorf(x), floorf(y))
#define ccs(w, h) CGSizeMake(floorf(w), floorf(h))
#define edi(top, left, bottom, right) UIEdgeInsetsMake(floorf(top), floorf(left), floorf(bottom), floorf(right))
#define cgrgba(r, g, b, a) [[UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:a] CGColor]
#define cgrgb(r, g, b) [[UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:1] CGColor]
#define rgba(r, g, b, a) [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:a]
#define rgb(r, g, b) [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:1]

#define bw(w) [UIColor colorWithWhite:w/255.0f alpha:1]
#define bwa(w, a) [UIColor colorWithWhite:w/255.0f alpha:a]
#define L(s) NSLog(@"%@", s);
#define LR(rect) NSLog(@"%@", NSStringFromCGRect(rect));
#define LF(f,...) NSLog(f,##__VA_ARGS__);
#define S(f,...) [NSString stringWithFormat:f,##__VA_ARGS__]

#define kBlackColor [UIColor blackColor]
#define kWhiteColor [UIColor whiteColor]
#define kClearColor [UIColor clearColor]
#define kGrayColor [UIColor grayColor]
#define kLightBlueColor rgb(141, 157, 168)

#define kWinWidth [HSUCommonTools winWidth]
#define kWinHeight [HSUCommonTools winHeight]

#define TWENGINE [HSUTwitterAPI shared]

#define iOS_Ver MIN([[UIDevice currentDevice].systemVersion floatValue], __IPHONE_OS_VERSION_MAX_ALLOWED/10000.0)

#define IPAD [HSUCommonTools isIPad]
#define IPHONE [HSUCommonTools isIPhone]

#define kNamedImageView(s) [[UIImageView alloc] initWithImage:[UIImage imageNamed:s]]

#define GRAY_INDICATOR [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray]

#define MyScreenName [TWENGINE myScreenName]

#define DEF_NavitationController_Light [[HSUNavigationController alloc] initWithNavigationBarClass:[HSUNavigationBarLight class] toolbarClass:nil]

#define kScreenHeight [UIScreen mainScreen].bounds.size.height
#define kScreenWidth [UIScreen mainScreen].bounds.size.width


#import "UIImage+Color.h"
#import "UIColor+iOS7Colors.h"

// const
//
#define kHPAccountUID @"HPAccountUID"
#define kHPAccountUserName @"HPAccountUserName"
#define kHPAskNotificationPermission @"kHPAskNotificationPermission"

/*
#define kHPLittleTail @"HPLittleTail"
#define kHPLittleTailThreadId @"HPLittleTailThreadId"
#define kHPisShowAvatar @"HPisShowAvatar"

#define kHPFontSize @"HPFontSize1"
#define kHPLineHeightMultiple @"HPLineHeightMultiple1"
#define kHPisUseSystemFont @"HPisUseSystemFontItem"

#define kHPForumsID @"HPForumsID"
#define kHPForumsTitle @"HPForumsTitle"
#define kHPisOrderByDateline @"HPisOrderByDateline"
#define kHPisNightMode @"kHPisNightMode"
#define kHPisAutoRefresh @"HPisAutoRefresh"
#define kHPisLazyLoad @"HPisLazyLoad"
*/
 
#define TAG_NightModeView 149410

#define HP_QCLOUD_PREFIX (@"http://hpimg-1252000006.cos.ap-shanghai.myqcloud.com/")
#define HP_MESSAGE_CELL_TAP_IMAGE @"HP_MESSAGE_CELL_TAP_IMAGE"

#define HPSettingBaseURL @"HPSettingBaseURL"
#define HPSettingForceDNS @"HPSettingForceDNS"
#define HP_BASE_HOST ([Setting objectForKey:HPSettingBaseURL])
#define HP_URL_FORMAT ([Setting boolForKey:HPSettingEnableHTTPS] ? @"https://%@" : @"http://%@")
#define HP_BASE_URL ([NSString stringWithFormat:HP_URL_FORMAT, HP_BASE_HOST])
#define HP_WWW_BASE_HOST @"www.4d4y.com"
#define HP_IMG_BASE_HOST ([HP_BASE_HOST stringByReplacingOccurrencesOfString:@"www." withString:@"img02."])
#define HP_IMG_BASE_URL ([NSString stringWithFormat:HP_URL_FORMAT, HP_IMG_BASE_HOST])
#define HP_CDN_BASE_HOST @"7xq2vp.com1.z0.glb.clouddn.com"
#define HP_CDN_URL_SUFFIX (@"-w600")
#define HP_THUMB_URL_SUFFIX (@".thumb.jpg")
extern NSString *HP_WWW_BASE_IP;
extern NSString *HP_CNC_BASE_IP;


#define HPSettingDic @"HPSettingDic"

#define HPSettingTail @"HPSettingTail"
#define HPSettingFavForums @"HPSettingFavForums"
#define HPSettingFavForumsTitle @"HPSettingFavForumsTitle"

#define HPSettingShowAvatar @"HPSettingShowAvatar"
#define HPSettingBSForumOrderByDate @"HPSettingBSForumOrderByDate"

#define HPSettingApiEnv @"HPSettingApiEnv"

#define HPSettingNightMode @"HPSettingNightMode"
#define HPSettingRegularFontMode @"HPSettingRegularFontMode"

#define HPSettingFontSize @"HPSettingFontSize"
#define HPSettingFontSizeAdjust @"HPSettingFontSizeAdjust"
#define HPSettingLineHeight @"HPSettingLineHeight"
#define HPSettingLineHeightAdjust @"HPSettingLineHeightAdjust"
#define HPSettingTextFont @"HPSettingTextFont"
#define HPSettingImageWifi @"HPSettingImageWifi"
#define HPSettingImageWWAN @"HPSettingImageWWAN"

#define HPSettingBgFetchNotice @"HPSettingBgFetchNoticeV2"

#define HPSettingPreferNotice @"HPSettingPreferNotice"

#define HPSettingIsPullReply @"HPSettingIsPullReply"

#define HPSettingStupidBarDisable @"HPSettingStupidBarDisable"
#define HPSettingStupidBarHide @"HPSettingStupidBarHide"
#define HPSettingStupidBarLeftAction @"HPSettingStupidBarLeftAction"
#define HPSettingStupidBarCenterAction @"HPSettingStupidBarCenterAction"
#define HPSettingStupidBarRightAction @"HPSettingStupidBarRightAction"
#define HPSettingBlockList @"HPSettingBlockList" //to remove
#define HPSettingAfterSendShowConfirm @"HPSettingAfterSendShowConfirm"
#define HPSettingAfterSendJump @"HPSettingAfterSendJump"
#define HPSettingDataTrackEnable @"HPSettingDataTrackEnable"
#define HPSettingForceLogin @"HPSettingForceLogin"
#define HPSettingPrintPagePost @"HPSettingPrintPagePost"
#define HPSettingEnableHTTPS @"HPSettingEnableHTTPS"
#define HPSettingEnableWKWebview @"HPSettingEnableWKWebview"

#define HPSettingLabUserInfo @"HPSettingLabUserInfo"
#define HPSettingLabCookiesPermission @"HPSettingLabCookiesPermission"
#define HPSettingLabEnablePush @"HPSettingLabEnablePush"

// image
typedef NS_ENUM(NSUInteger, HPImageAutoLoadMode) {
    HPImageAutoLoadModePerferOriginal = 0,
    HPImageAutoLoadModePerferThumb = 1,
    HPImageAutoLoadModePerferAuto = 2,
};

// 移动网络
#define HPSettingImageAutoLoadEnableWWAN @"HPSettingImageAutoLoadEnableWWAN"
#define HPSettingImageAutoLoadModeWWAN @"HPSettingImageAutoLoadModeWWAN"
#define HPSettingImageAutoLoadModeAutoThresholdWWAN @"HPSettingImageAutoLoadModeAutoThresholdWWAN"

// WIFI
#define HPSettingImageAutoLoadEnableWifi @"HPSettingImageAutoLoadEnableWifi"
#define HPSettingImageAutoLoadModeWifi @"HPSettingImageAutoLoadModeWifi"
#define HPSettingImageAutoLoadModeAutoThresholdWifi @"HPSettingImageAutoLoadModeAutoThresholdWifi"

// Umeng Settings
//#define HPOnlineConfigEnableHTTPSSetting @"enableHTTPSSetting"
#define HPOnlineWKWebviewEnable @"enableWKWebview"

#define HPDraft @"HPDraft"

#define HPBgFetchInterval @"HPBgFetchInterval"
#define HPPMCount @"HPPMCount"
#define HPNoticeCount @"HPNoticeCount"
#define HPCheckDisable @"HPCheckDisable"

#define HP_SHOW_MESSAGE_IMAGE_NOTICE @"HP_SHOW_MESSAGE_IMAGE_NOTICE"

//#define kHPImageDisplayViaWWAN @"HPImageDisplayViaWWAN"
//#define kHPImageDisplayViaWifi @"HPImageDisplayViaWifi"
//#define kHPScreenBrightness @"HPScreenBrightness"

// notiy
#define kHPUserLoginSuccess @"HPUserLoginSuccess"
#define kHPUserLoginError @"HPUserLoginError"
#define kHPUserLogout @"kHPUserLogout"
#define kHPThemeDidChanged @"HPThemeDidChanged"
#define kHPBlockListDidChange @"kHPBlockListDidChange"
#define kHPThreadListDidChange @"kHPThreadListDidChange"
#define HPLoadThreadListSuccess @"HPLoadThreadListSuccess"



#define kHPPOSTFormHash @"HPPOSTFormHash"



// tip
#define kHPBgVCTip @"kHPBgVCTip"
#define kHPPhotoBrowserTip @"kHPPhotoBrowserTip"
#define kHPNightModeTip @"HPNightModeTip"

//
#define kHPNoAccountCode 9567

extern Class PostViewControllerClass();

// image
enum {
    HPImageDisplayStyleFull  = 0,
    HPImageDisplayStyleOne = 1,
    HPImageDisplayStyleNone = 2
} ;
typedef NSInteger HPImageDisplayStyle;



@interface HPCommon : NSObject

+ (NSTimeInterval)timeIntervalSince1970WithString:(NSString *)string;
+ (UINavigationController *)NVCWithRootVC:(UIViewController *)rootVC;
+ (UINavigationController *)swipeableNVCWithRootVC:(UIViewController *)rootVC;

@end
