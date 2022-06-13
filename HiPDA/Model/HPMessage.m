//
//  HPMessage.m
//  HiPDA
//
//  Created by wujichao on 13-11-24.
//  Copyright (c) 2013年 wujichao. All rights reserved.
//

#import "HPMessage.h"
#import "HPUser.h"
#import "HPHttpClient.h"
#import "EGOCache.h"
#import "HPSetting.h"
#import "HPSendPost.h"


#import <AFHTTPRequestOperation.h>
#import "NSString+Additions.h"
#import "NSRegularExpression+HP.h"

#import "NSString+HTML.h"
#import <NSString+Emoji/NSString+Emoji.h>

#define kHPMyMessageList @"myMessageList"

#define DEBUG_Message 0
#define DEBUG_Load_Message 0
#define DEBUG_Load_Detail 0

@implementation HPMessage

+ (HPMessage *)sharedMessage {
    
    static HPMessage *sharedMessage = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMessage = [[HPMessage alloc] init];
        
        if ([[EGOCache globalCache] hasCacheForKey:kHPMyMessageList]) {
            sharedMessage.message_list = (NSArray *)[[EGOCache globalCache] objectForKey:kHPMyMessageList];
        } else {
            sharedMessage.message_list = [NSArray array];
        }
    });
    return sharedMessage;
}

- (void)cacheMyMessages:(NSArray *)list {
    _message_list = list;
    [[EGOCache globalCache] setObject:_message_list forKey:kHPMyMessageList];
}


+ (void)loadMessageListWithBlock:(void (^)(NSArray *lists, NSError *error))block page:(NSInteger)page
{
    
    NSString *path = [NSString stringWithFormat:@"forum/pm.php?filter=privatepm&page=%i", page];
    if(DEBUG_Load_Message) NSLog(@"path %@", path);
    
    [[HPHttpClient sharedClient] getPathContent:path parameters:nil success:^(AFHTTPRequestOperation *operation, NSString *html)
     {
         
        if(DEBUG_Load_Message) NSLog(@" html %@", html);
         
         //uc_server/([^\"]+)\".*?
         NSString *pattern = @"uid=(\\d+)\" target=\"_blank\">(.*?)</a></cite>(.*?)</p>.*?summary\">\r\n(.*?)</div>";
         
         NSRegularExpression *reg =
         [[NSRegularExpression alloc] initWithPattern:pattern
                                              options:NSRegularExpressionDotMatchesLineSeparators
                                                error:nil];
         
         NSArray *matches = [reg matchesInString:html
                                         options:0
                                           range:NSMakeRange(0, [html length])];
         
         NSMutableArray *lists = [NSMutableArray arrayWithCapacity:[matches count]];
         
         if(DEBUG_Load_Message)  NSLog(@"lists matches count %ld", [matches count]);
         
         
         for (NSTextCheckingResult *result in matches) {
             
             if ([result numberOfRanges] == 5) {
                 
                 /*
                  NSRange avatarRange = NSMakeRange([result rangeAtIndex:1].location, [result rangeAtIndex:1].length);
                  NSString *avatar = [html substringWithRange:avatarRange];
                  */
                 NSRange uidRange = NSMakeRange([result rangeAtIndex:1].location, [result rangeAtIndex:1].length);
                 NSString *uidString = [html substringWithRange:uidRange];
                 
                 NSRange nameRange = NSMakeRange([result rangeAtIndex:2].location, [result rangeAtIndex:2].length);
                 NSString *username = [html substringWithRange:nameRange];
                 
                 NSRange dateRange = NSMakeRange([result rangeAtIndex:3].location, [result rangeAtIndex:3].length);
                 NSString *dateString = [html substringWithRange:dateRange];
                 
                 NSRange summaryRange = NSMakeRange([result rangeAtIndex:4].location, [result rangeAtIndex:4].length);
                 NSString *summary = [html substringWithRange:summaryRange];
                 
                 NSDictionary *userinfo = @{
                                            @"uid":uidString,
                                            @"username":username
                                            };
                 HPUser *user = [[HPUser alloc] initWithAttributes:userinfo];
                 
                 BOOL isUnread = NO;
                 if ([dateString indexOf:@"NEW"] != -1) {
                     NSRange r = [dateString rangeOfString:@"&nbsp;"];
                     if (r.location != NSNotFound) {
                         dateString = [dateString substringToIndex:r.location];
                     }
                     isUnread = YES;
                 }
                 
                 
                 NSDictionary *info = @{
                                        @"user":user,
                                        @"summary": summary,
                                        @"dateString":dateString,
                                        @"isUnread":(isUnread) ? @YES:@NO
                                        };
                 
                 if(DEBUG_Load_Message) NSLog(@" uid %@ name %@  date %@, summary %@ isUnread %ld", uidString, username,dateString, summary, isUnread);
                 
                 [lists addObject:info];
                 
             } else {
                 NSLog(@"error %@ %ld", result, [result numberOfRanges]);
             }
             
         }
         
         //NSLog(@"lists %@", lists);
         
         if (block) {
             block(lists, nil);
         }
         
     } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
         if (block) {
             block([NSArray array], error);
         }
     }];
    
}


+ (void)loadMessageDetailWithUid:(NSInteger)uid
                       daterange:(HPMessageRange)range
                           block:(void (^)(NSArray *lists, NSError *error))block
{
    
    NSString *path = [NSString stringWithFormat:@"forum/pm.php?uid=%ld&filter=privatepm&daterange=%ld#new", uid, range];
    
    NSLog(@"load message path %@", path);
    
    [[HPHttpClient sharedClient] getPathContent:path parameters:nil success:^(AFHTTPRequestOperation *operation, NSString *html)
    {
         
         //if(DEBUG_Load_Detail) NSLog(@" html %@", html);
        /*
         <cite>geka</cite>
         2012-1-22 15:58</p>
         <div class="summary">雪姨<br />
         求ban一个月<br />
         高三苦逼<br />
         谢谢</div>
         */
        NSString *mineUid = [RX(@"discuz_uid = (\\d+)") firstMatchValue:html];
        NSString *hisUid = @(uid).stringValue;
        
        
        NSString *pattern = @"<cite>([^<]+)</cite>\r\n(.*?)</p>\r\n<div class=\"summary\">(.*?)</div>";
        
        NSRegularExpression *reg =
        [[NSRegularExpression alloc] initWithPattern:pattern
                                             options:NSRegularExpressionDotMatchesLineSeparators
                                               error:nil];
        
        NSArray *matches = [reg matchesInString:html
                                        options:0
                                          range:NSMakeRange(0, [html length])];
        
        NSMutableArray *lists = [NSMutableArray arrayWithCapacity:[matches count]];
        
        if(DEBUG_Load_Detail)  NSLog(@"details matches count %ld", [matches count]);
        
        
        for (NSTextCheckingResult *result in matches) {
            
            if ([result numberOfRanges] == 4) {
                
                NSRange nameRange = NSMakeRange([result rangeAtIndex:1].location, [result rangeAtIndex:1].length);
                NSString *username = [html substringWithRange:nameRange];
                
                NSRange dateRange = NSMakeRange([result rangeAtIndex:2].location, [result rangeAtIndex:2].length);
                NSString *dateString = [html substringWithRange:dateRange];
                
                NSRange summaryRange = NSMakeRange([result rangeAtIndex:3].location, [result rangeAtIndex:3].length);
                NSString *summary = [html substringWithRange:summaryRange];
                
                // message
                if ([summary indexOf:@"images/smilies"] != -1) {
                    // <img src=\"http://www.hi-pda.com/forum/images/smilies/grapeman/19.gif\" border=\"0\" alt=\"\" />
                    // NEW_DOMAIN
                    summary = [summary replaceWithPattern:@"<img[^>]+src=\"https?://.*?/forum/images/smilies/([a-z0-9/]+)\\.gif.*?>" template:@"{表情($1)}" isdot:NO];
                }
                //summary = [summary stringByReplacingOccurrencesOfString:@"<br />" withString:@"\n"];
                //<a href="http://www.hi-pda.com/forum/pm.php?uid=682029&amp;filter=privatepm&amp;daterange=5#new" target="_blank">http://www.hi-pda.com/forum/pm.p ... amp;daterange=5#new</a>
                summary = [RX(@"<a href=\"(.*?)\" target=\"_blank\">.*?</a>") replace:summary withDetailsBlock:^NSString *(RxMatch *match) {
                    
                    RxMatchGroup *m1 = [match.groups objectAtIndex:1];
                    return [NSString stringWithFormat:@"<a href=\"%@\" target=\"_blank\">%@</a>", m1.value, m1.value];
                    
                }];
                summary = [summary stringByConvertingHTMLToPlainText];
                
                // date
                BOOL isUnread = NO;
                if ([dateString indexOf:@"NEW"] != -1) {
                    NSRange r = [dateString rangeOfString:@"&nbsp;"];
                    if (r.location != NSNotFound) {
                        dateString = [dateString substringToIndex:r.location];
                    }
                    isUnread = YES;
                }
                static NSDateFormatter *dateFormatter;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    dateFormatter = [[NSDateFormatter alloc] init];
                    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];
                });
                NSDate *date = [dateFormatter dateFromString:dateString];
                
                NSDictionary *message_info = @{
                                               @"username":username?:@"",
                                               @"date":date?:[NSDate date],
                                               /*@"dateString":dateString,*/
                                               @"message":summary?:@"",
                                               @"isUnread":(isUnread) ? @YES:@NO,
                                               @"hisUid": hisUid?:@"",
                                               @"mineUid": mineUid?:@"",
                                               };
                
                if(DEBUG_Load_Detail) NSLog(@"%@", message_info);
                
                [lists addObject:message_info];
                
            } else {
                NSLog(@"error %@ %ld", result, [result numberOfRanges]);
            }
            
        }
        
        //NSLog(@"lists %@", lists);
        if (block) {
            block(lists, nil);
        }
        
     } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
         if (block) {
             block([NSArray array], error);
         }
     }];
    
}

+ (void)ignoreMessage {
    [HPMessage loadMessageListWithBlock:^(NSArray *info, NSError *error) {
        
        if (!error) {
            [HPMessage ingnoreMessageDetailWithList:info];
        }
        
        if (error && error.code == NSURLErrorUserAuthenticationRequired) {
            NSLog(@"ignoreMessage need login");
            
            // 仅重试一次
            NSTimeInterval delay = 3.f;
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
            dispatch_after(popTime, dispatch_get_main_queue(), ^{
                [HPMessage loadMessageListWithBlock:^(NSArray *info, NSError *error) {
                    NSLog(@"ignoreMessage try again %@", error);
                    if (!error) {
                        [HPMessage ingnoreMessageDetailWithList:info];
                    }
                } page:1];
            });
        }
    } page:1];
}

+ (void)ingnoreMessageDetailWithList:(NSArray *)lists {
    [lists enumerateObjectsUsingBlock:^(NSDictionary *i, NSUInteger idx, BOOL *stop) {
        
        if ([[i objectForKey:@"isUnread"] boolValue]) {
            
            HPUser *user = [i objectForKey:@"user"];
            [HPMessage loadMessageDetailWithUid:user.uid
                                      daterange:5
                                          block:^(NSArray *lists, NSError *error)
             {
                 [Setting saveInteger:0 forKey:HPPMCount];
             }];
        }
    }];
}


+ (void)sendMessageWithUsername:(NSString *)username
                        message:(NSString *)message
                          block:(void (^)(NSError *error))block
{
    // emoji
    message = [message stringByReplacingEmojiUnicodeWithCheatCodes];
    
    [HPSendPost loadFormHashWithBlock:^(NSString *formhash, NSError *error) {

        if (error) {
            if (block) {
                block(error);
            }
            return;
        }
        
        NSString *path = @"forum/pm.php?action=send&pmsubmit=yes&infloat=yes&sendnew=yes";
        NSDictionary *parameters = @{@"formhash": formhash,
                                     @"message": message,
                                     @"msgto": username,
                                     @"pmsubmit": @"true"};
        
        if (DEBUG_Message) NSLog(@"send message path %@ %@", path, parameters);
        
        [[HPHttpClient sharedClient] postPath:path parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
            
            NSString *html = [HPHttpClient GBKresponse2String:responseObject];
            if (DEBUG_Message) NSLog(@"%@", html);
            
            /*<div id="wrap" class="wrap s_clear"><div class="main"><div class="content nofloat">
             <div class="fcontent alert_win">
             <h3 class="float_ctrl"><em>Hi!PDA 提示信息</em></h3>
             <hr class="shadowline" />
             <div class="postbox"><div class="alert_info">
             <p>短消息发送成功。</p>
             </div></div>
             </div>
             </div></div></div>
             */
            
            if (block) {
                if ([html indexOf:@"短消息发送成功"] != -1) {
                    block(nil);
                } else {
                    NSString *alert = [html stringBetweenString:@"<div class=\"alert_" andString:@"</div>"];
                    NSDictionary *details = [NSDictionary dictionaryWithObject:alert?:(html?:@"未知错误") forKey:NSLocalizedDescriptionKey];
                    block([NSError errorWithDomain:@"world" code:200 userInfo:details]);
                }
            }
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            if (block) {
                block(error);
            }
        }];
    }];
}


/*
+ (void)checkPMWithBlock:(void (^)(int pmCount, NSError *error))block {
    int rand = (arc4random() % 1000) + 1000;
    NSString *randomPath = [NSString stringWithFormat:@"forum/pm.php?checknewpm=%ld&inajax=1&ajaxtarget=myprompt_check", rand];
    [[HPHttpClient sharedClient] getPathContent:randomPath parameters:nil success:^(AFHTTPRequestOperation *operation, NSString *html) {
        
        if (block) {
            
            NSLog(@"post html %@", html);
            
            NSString *pm_count_string = [html stringBetweenString:@"私人消息 (" andString:@")"];
            NSInteger pm_count = 0;
            
            if (pm_count_string) {
                pm_count = [pm_count_string integerValue];
                if (pm_count > 0) {
                    [NSStandardUserDefaults setInteger:pm_count forKey:kHPMessageCount];
                }
            }
            block(pm_count, nil);
        }
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"checknewpm error %@", [error localizedDescription]);
        if (block) {
            block(0, error);
        }
    }];
}
 */

// 举报
+ (void)report:(NSString *)username
       message:(NSString *)message
         block:(void (^)(NSError *error))block
{
    NSTimeInterval delay = 0.7f;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^{
         block(nil);
    });
}


@end
