//
//  HPNewPost.m
//  HiPDA
//
//  Created by wujichao on 14-2-25.
//  Copyright (c) 2014年 wujichao. All rights reserved.
//

#import "HPNewPost.h"
#import "HPUser.h"
#import "HPDatabase.h"
#import "HPCache.h"
#import "HPSetting.h"

#import "NSString+Additions.h"
#import "NSString+HTML.h"
#import "NSRegularExpression+HP.h"
#import "NSString+HPImageSize.h"

#import "HPHttpClient.h"
#import <AFHTTPRequestOperation.h>
#import <SDWebImage/SDWebImageManager.h>
#import "SDImageCache+URLCache.h"
#import "NSString+CDN.h"

#define debugParameters 0
#define debugContent 0

@implementation HPNewPost

- (id)initWithAttributes:(NSDictionary *)attributes {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _pid = [[attributes valueForKeyPath:@"pid"] integerValue];
    _date = [attributes valueForKeyPath:@"date"];
    _body = [attributes valueForKeyPath:@"body"];
    _body_html = [attributes valueForKeyPath:@"body_html"];
    _floor = [[attributes valueForKeyPath:@"floor"] integerValue];
    _user = [[HPUser alloc] initWithAttributes:[attributes valueForKeyPath:@"user"]];
    
    _images = [attributes valueForKeyPath:@"images"];
    
    return self;
}

- (id)initWithUsername:(NSString *)username
            dateString:(NSString *)dateString
             body_html:(NSString *)body_html {
    
    self = [super init];
    if (!self) {
        return nil;
    }
    
    static NSDateFormatter *post_date_formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        post_date_formatter = [[NSDateFormatter alloc] init];
        [post_date_formatter setDateFormat:@"yyyy-MM-dd HH:mm"];
    });
    
    _pid = 0;
    
    _date = [post_date_formatter dateFromString:dateString];
    
    _body = nil;
    _body_html = body_html;
    
    _floor = 0;
    
    _user = [[HPUser alloc] init]; _user.username = username;
    
    _images = nil;
    
    return self;
}



/*
 
 桌面版网页
 parameters 
    formhash, pagecount, title, fid, tid, pm_count, remind_count
 posts 
    user(name,avatar), pid, date, body_html, floor, images,
 
 打印版网页
 parameters
    ### fid 无法获得, 在readVC中是thread自带, home中获得 ###
    title, author, tid, pageCount=0, postsCount
 posts
    user(name,avatar), pid, date, body_html, floor, images,
 
 */

+ (void)loadThreadWithTid:(NSInteger)tid
                     page:(NSInteger)page // page = 0 last

             forceRefresh:(BOOL)forceRefresh // 强制刷新, #没有用了#
                printable:(BOOL)printable // 加载打印版网页

                 authorid:(NSInteger)authorid // 只看某人
          redirectFromPid:(NSInteger)redirectFromPid //在搜索全文结果, 跳转等, 只能拿到pid

                    block:(void (^)(NSArray *posts, NSDictionary *parameters, NSError *error))block
{
    BOOL enablePrint = [Setting boolForKey:HPSettingPrintPagePost];
    if (!enablePrint) {
        printable = NO;
    }
    
    if (printable && redirectFromPid == 0) {
        [HPNewPost loadPrintableThreadWithTid:tid refresh:forceRefresh block:block];
        return;
    }
    
    //
    //
    NSString *urlString = nil;
    // lastpost & onlylz
    //
    if (page) {
        if (authorid == 0) {
            urlString = [NSString stringWithFormat:@"forum/viewthread.php?tid=%ld&page=%ld", tid, page];
            //urlString = @"http://localhost/viewthread.html";
        } else {
            urlString = [NSString stringWithFormat:@"forum/viewthread.php?tid=%ld&page=%ld&authorid=%ld", tid, page, authorid];
        }
    } else {
        urlString = [NSString stringWithFormat:@"forum/redirect.php?tid=%ld&goto=lastpost", tid];
    }
    
    // handle redirect (pid)
    if (redirectFromPid != 0 ) {
        if (tid != 0) urlString = [NSString stringWithFormat:@"forum/redirect.php?goto=findpost&pid=%ld&ptid=%ld", redirectFromPid, tid];
        else urlString = [NSString stringWithFormat:@"forum/gotopost.php?pid=%ld", redirectFromPid];
    }
    
    NSLog(@"load post %@ forceRefresh %@", urlString, forceRefresh?@"YES":@"NO");
    
    // load
    //
    [[HPHttpClient sharedClient] getPathContent:urlString parameters:nil success:^(AFHTTPRequestOperation *operation, NSString *html) {
        
        NSString *url = [[[operation response] URL] absoluteString];
        
        NSArray *posts = [HPNewPost extractFuckPosts:html];
        NSDictionary *parameters = [HPNewPost findPageInfo:html url:url];
        
        NSLog(@"url %@", url);
        if(1||debugParameters) NSLog(@"parameters %@" , parameters);
        
        if (block) {
            block(posts, parameters, nil);
        }
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (block) {
            block([NSArray array], nil, error);
        }
    }];
}



+ (void)loadPrintableThreadWithTid:(NSInteger)tid
                           refresh:(BOOL)refresh //#没有用了#
                             block:(void (^)(NSArray *posts, NSDictionary *parameters, NSError *error))block
{
    NSString *urlString = [NSString stringWithFormat:@"forum/viewthread.php?action=printable&tid=%ld", tid];
    
    NSLog(@"load Printable thread %@ forceRefresh %@", urlString, refresh?@"YES":@"NO");
    
    //
    [[HPHttpClient sharedClient] getPathContent:urlString parameters:nil success:^(AFHTTPRequestOperation *operation, NSString *html) {
      
        //NSLog(@"post html %@", html);
        
        NSArray *posts = nil;
        NSDictionary *parameters = nil;
        
        
        // get title
        __block NSString *title = nil;
        html = [RX(@"&nbsp; &nbsp; <b>标题: </b>([^<]+)<br /><br />") replace:html withDetailsBlock:^(RxMatch* match){
            
            RxMatchGroup *m1 = [match.groups objectAtIndex:1];
            title = m1.value;
            
            return @"<br /><br />";
        }];
        
        // split post
        posts = [HPNewPost extractPosts:html];
        
        // get author
        HPUser *author = posts.count ? [(HPNewPost *)posts[0] user]:nil;
        
        // parameters
        parameters = @{
                       @"title":title?title:@"",
                       @"author":author?author:[NSNull null],
                       @"tid":[NSNumber numberWithUnsignedInteger:tid],
                       @"pageCount": @0,
                       @"postsCount": [NSNumber numberWithInteger:posts.count]
        };
        
        /*
        // debug
        [posts enumerateObjectsUsingBlock:^(HPNewPost* obj, NSUInteger idx, BOOL *stop) {
            
            NSString *r = [NSString stringWithFormat:
                           @"\nuser: %@, uid: %d, date: %@"
                           @"\nhtml: %@"
                           @"\nfloor: %d",
                           obj.user.username, obj.user.uid, obj.date, obj.body_html, obj.floor];
            
            NSLog(r);
        }];
        */
        
        if (posts.count > 50) {
            NSMutableArray *a = [NSMutableArray arrayWithArray:posts];
            [a removeObjectsInRange:NSMakeRange(50, posts.count - 50)];
            
            posts = [NSArray arrayWithArray:a];
        }
        
        block(posts, parameters, nil);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (block) {
            block([NSArray array], nil, error);
        }
    }];
}

+ (void)cancelRequstOperationWithTid:(NSInteger)tid {
    NSString *urlString = [NSString stringWithFormat:@"forum/viewthread.php?action=printable&tid=%ld", tid];
    [[HPHttpClient sharedClient] cancelAllHTTPOperationsWithMethod:@"GET" path:urlString];
}

+ (NSArray *)extractPosts:(NSString *)string {
    
    /*
     <b>作者: </b>队长，别开枪！&nbsp; &nbsp; <b>时间: </b>2014-2-25 22:10<br /><br />
     这个，强迫症啊，得电。<hr noshade size="2" width="100%" color="#808080">
     */
    
    //NSLog(@"html : \n%@", string);
    
    NSError *error;
    NSRegularExpression *regex = [NSRegularExpression
                                  regularExpressionWithPattern:@"<b>作者: </b>(.*?)&nbsp; &nbsp; <b>时间: </b>([^<]+)<br /><br />\r\n(.*?)<hr noshade size"
                                  options:NSRegularExpressionDotMatchesLineSeparators
                                  error:&error
                                  ];
    
    __block NSMutableArray *postsArray = [NSMutableArray arrayWithCapacity:42];
    
    [regex enumerateMatchesInString:string
                            options:0
                              range:NSMakeRange(0, string.length)
                         usingBlock:
     ^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
         
         NSString *username = [string  substringWithRange:[result rangeAtIndex:1]];
         NSString *dateString = [string  substringWithRange:[result rangeAtIndex:2]];
         NSString *body_html = [string  substringWithRange:[result rangeAtIndex:3]];
         
         //NSLog(@"%@\n%@\n%@\n", username, dateString, body_html);
         
         HPNewPost *post = [
                            [HPNewPost alloc]
                            initWithUsername:username
                            dateString:dateString
                            body_html:body_html
                            ];
         
         [postsArray addObject:post];
     }];
    
    
    // get avator & floor
    [[HPDatabase sharedDb].queue inDatabase:^(FMDatabase *db) {
        [postsArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            
            HPNewPost *post = (HPNewPost *)obj;
            
            post.floor = idx+1;
            
            NSInteger uid = [db intForQuery:@"SELECT uid FROM user WHERE username = ?", post.user.username];
            post.user.uid = uid;
            post.user.avatarImageURL = [HPUser avatarStringWithUid:uid];
            
            
            // process content
            [post processContentHTML];
            
        }];
    }];
    
    // fix
    HPNewPost *last = [postsArray lastObject];
    last.body_html = [last.body_html stringByReplacingOccurrencesOfString:@"<br /><br /><br /><br />" withString:@""];
    
    return postsArray;
}

- (void)processContentHTML {
    
    // 回复 NEW_DOMAIN
    _body_html = [RX(@"<a href=\"https?://.*?/forum/redirect\\.php\\?goto=findpost&amp;pid=(\\d+)&amp;ptid=\\d+\" target=\"_blank\">(\\d+)#</a>") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
        
        RxMatchGroup *m1 = [match.groups objectAtIndex:1];
        RxMatchGroup *m2 = [match.groups objectAtIndex:2];
        
        //NSLog(@"%@ %@", m1.value, m2.value);
        
        return [NSString stringWithFormat:@"<a onclick='gotofloor(\"%ld_%ld\")' >%ld#</a>", [m2.value integerValue], [m1.value integerValue], [m2.value integerValue]];
    }];
    
    // 引用 NEW_DOMAIN
    _body_html = [RX(@"<a href=\"https?://.*?/forum/redirect\\.php\\?goto=findpost&amp;pid=(\\d+)&amp;ptid=\\d+\" target=\"_blank\">") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
        
        RxMatchGroup *m1 = [match.groups objectAtIndex:1];
        return [NSString stringWithFormat:@"<a onclick='gotofloor(\"0_%ld\")' >", [m1.value integerValue]];
    }];
    
    // 视频
    _body_html = [RX(@"\\[(rm|wmv|flash)\\](.*?)\\[/(rm|wmv|flash)\\]") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
        
        RxMatchGroup *m1 = [match.groups objectAtIndex:2];
        NSString *url = [HPNewPost urlForSwfUrl:m1.value];
        if (url) {
            return [NSString stringWithFormat:@"<a style=\"background: #f6f6f6;\" href=\"video://%@\" >%@</a>",url, url];
        }
        return match.value;
    }];
    

    if ([_body_html indexOf:@"attachments/day_"] != -1 ) {
// 改这里记得改 processFuckContentHTML里的 一样
//================================================================
        NSString *html = [self.body_html copy];
        
        // remove extra
        _body_html = [RX(@"<span style=\"position: absolute; display: none\" id=\"attach_.*?</span>\r\n") replace:_body_html with:@""];
        NSRegularExpression *rx = [NSRegularExpression rx:@"<div class=\"t_attach\" id=\"aimg_.*?\r\n</div>" options:NSRegularExpressionDotMatchesLineSeparators];
        _body_html = [rx replace:_body_html with:@""];
        
        
        __block NSMutableArray<HPImageNode *> *imgsArray = [NSMutableArray arrayWithCapacity:5];
        // 用来去重 和 查找imagesize
        __block NSMutableArray *aidArray = [NSMutableArray arrayWithCapacity:5];
        
        NSString *imageElement = @"<img class=\"attach_image\" src=\"%@\" a__i__d=\"%@\" />";
        // 最后会是 <img class="attach_image" src="http://domain.com/xxx.jpg" aid="123456" size="123" />
        // preProcessHTML: 里也要改
        // 这里结构真是太恶心, model层应该返回的数据结构, view层再拼接展示
        // 理想的数据结构应该是 {title:xxx, postInfo:{...} content:[html, imageInfo, html, text, imageInfo, videoInfo, otherType...]}
        
        // 帖子内部 image
        NSString *(^replacer)(RxMatch *match) = ^NSString *(RxMatch *match) {
            RxMatchGroup *m1 = [match.groups objectAtIndex:1];
            RxMatchGroup *m2 = [match.groups objectAtIndex:2];
            NSString *src = m1.value;
            
            // 正则提取是倒序
            [imgsArray insertObject:[[HPImageNode alloc] initWithURL:src] atIndex:0];
            NSString *aid = m2.value;
            if (aid.length) {
                [aidArray addObject:aid];
            }
            
            return [NSString stringWithFormat:imageElement, m1.value, aid];
        };
        
        _body_html = [RX(@"<img src=\"[^\"]*images/common/none\\.gif\" file=\"(.*?)\".*?aimg_(\\d+).*?/>") replace:_body_html withDetailsBlock:replacer];
        _body_html = [RX(@"<a href=\"javascript:;\"><img onclick=.*?src=\"(.*?)\".*?aimg_(\\d+).*?/></a>") replace:_body_html withDetailsBlock:replacer];
//=============================================
        
        // 帖子底部 image
        NSUInteger start_index = imgsArray.count;
        
        _body_html = [RX(@"<br /><br /><img src=\"[^\"]*images/attachicons.*?aid=(\\d+).*?src=\"(.*?)\".*?/>") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
            
            RxMatchGroup *m1 = [match.groups objectAtIndex:1];
            RxMatchGroup *m2 = [match.groups objectAtIndex:2];
            
            NSString *aid = m1.value;
            NSString *src = m2.value;
            
            HPImageNode *n = [[HPImageNode alloc] initWithURL:src];
            if ([imgsArray indexOfObject:n] == NSNotFound) {
                // 正则提取是倒序
                // start_index 原因是 `帖子内部 image` 已经倒插了一批进来
                // 5 4 3 2 1 10 9 8 7 6
                [imgsArray insertObject:n atIndex:start_index];
            }
            if (aid.length && [aidArray indexOfObject:aid] == NSNotFound) {
                [aidArray addObject:aid];
                return [NSString stringWithFormat:imageElement, m2.value, aid];
            } else {
                return @"";
            }
        }];
//=======================================================
        // 图片size
        for (NSString *aid in aidArray) {
            // 找到size
            NSString *sizeInfo = [html getSizeString:aid];
            if (!sizeInfo) continue;
            
            // 填上size
            NSString *sizeString = [NSString stringWithFormat:@"%.2f", [sizeInfo imageSize]];
            NSString *pattern2 = [NSString stringWithFormat:@"a__i__d=\"%@\"", aid];
            self.body_html = [RX(pattern2) replace:self.body_html with:[NSString stringWithFormat:@"aid=\"%@\" size=\"%@\"", aid, sizeString]];
        }
//=======================================================
        // TODO: 网络图片 也要加进来

        self.images = [imgsArray copy];
    }
}


+ (NSArray *)extractFuckPosts:(NSString *)string {
    
    
    //NSLog(@"html : \n%@", string);
    
    NSError *error;
    NSRegularExpression *regex = [NSRegularExpression
                                  regularExpressionWithPattern:@"<table id=\"pid(\\d+)\"[^>]*>[\\s\\n]*(<tr class=\"threadad\">.*?</tr>)?.*?<tr class=\"threadad\">"
                                  options:NSRegularExpressionDotMatchesLineSeparators
                                  error:&error
                                  ];
    
    __block NSMutableArray *postsArray = [NSMutableArray arrayWithCapacity:42];
    
    [regex enumerateMatchesInString:string
                            options:0
                              range:NSMakeRange(0, string.length)
                         usingBlock:
     ^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
         
         NSString *html = [string  substringWithRange:[result rangeAtIndex:0]];
         NSString *pidString = [string  substringWithRange:[result rangeAtIndex:1]];
         
         HPNewPost *post = [HPNewPost new];
         post.pid = [pidString integerValue];
         [post processFuckPostHTML:html];
         
         [post processFuckContentHTML:html];
          
         [postsArray addObject:post];
     }];
    
    return postsArray;
}

- (void)processFuckPostHTML:(NSString *)html {
    
    // pid
    
    // username
    // uid
    //
    NSString *username = nil;
    NSInteger uid = 0;
    
    RxMatch *a = [RX(@"space\\.php\\?uid=(\\d+)\"[^>]+>([^<]+)</a>") firstMatchWithDetails:html];
    
    if (debugContent) NSParameterAssert(a.groups.count == 3);
    if (a && a.groups.count == 3) {
        RxMatchGroup *a1 = [a.groups objectAtIndex:1];
        RxMatchGroup *a2 = [a.groups objectAtIndex:2];
        uid = [a1.value integerValue];
        username = a2.value;
    } else {
        uid = 0;
        username = @"";
    }
    
    if (debugContent) NSLog(@"a %@ %ld", username, uid);
    
    self.user = [HPUser new];
    self.user.username = username;
    self.user.uid = uid;
    self.user.avatarImageURL = [HPUser avatarStringWithUid:uid];
    
    
    // date
    //
    NSString *dateString = nil;
    RxMatch *b = [RX(@"<em id=\"authorposton\\d+\">发表于 ([^<]+)</em>") firstMatchWithDetails:html];
    if (debugContent) NSParameterAssert(b.groups.count == 2);
    if (b && b.groups.count == 2) {
        RxMatchGroup *b1 = [b.groups objectAtIndex:1];
        dateString = b1.value;
    } else {
        dateString = @"";
    }
    
    if (debugContent) NSLog(@"b %@", dateString);
    
    static NSDateFormatter *post_date_formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        post_date_formatter = [[NSDateFormatter alloc] init];
        [post_date_formatter setDateFormat:@"yyyy-MM-dd HH:mm"];
    });
    self.date = [post_date_formatter dateFromString:dateString];
    
    // floor
    //
    RxMatch *c = [RX(@"<em>(\\d+)</em>") firstMatchWithDetails:html];
    if (debugContent) NSParameterAssert(c.groups.count == 2);
    if (c && c.groups.count == 2) {
        RxMatchGroup *c1 = [c.groups objectAtIndex:1];
        self.floor = [c1.value integerValue];
    } else {
        self.floor = 0;
    }
    if (debugContent) NSLog(@"floor %ld", self.floor);
    
    // signature
    //
    NSString *signature = [html stringBetweenString:@"<div class=\"signatures\" style=\"max-height:14px;maxHeightIE:14px;\">" andString:@"</div>"];
    self.signature = signature ?: @"";
    
    // content
    //
    Rx *rx = [Rx rx:@"<td class=\"t_msgfont\" id=\"postmessage_\\d+\">(.*?)</td></tr></table>" options:NSRegularExpressionDotMatchesLineSeparators];
    RxMatch *d = [rx firstMatchWithDetails:html];
    //NSParameterAssert(d.groups.count == 2);
    if (d && d.groups.count == 2) {
        
        RxMatchGroup *d1 = [d.groups objectAtIndex:1];
        self.body_html = d1.value?:@"";
        
    } else {
        
        self.body_html = @"提示: <em>作者被禁止或删除 内容自动屏蔽</em>";
    }
    
    if (debugContent) NSLog(@"content %@", self.body_html);
    // NEW_DOMAIN
    _body_html = [RX(@"<a href=\"https?://.*?/forum/redirect\\.php\\?goto=findpost&amp;pid=(\\d+)&amp;ptid=\\d+\" target=\"_blank\">(\\d+)#</a>") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
        
        RxMatchGroup *m1 = [match.groups objectAtIndex:1];
        RxMatchGroup *m2 = [match.groups objectAtIndex:2];
        
        NSLog(@"%@ %@", m1.value, m2.value);
        
        return [NSString stringWithFormat:@"<a onclick='gotofloor(\"%ld_%ld\")' >%ld#</a>", [m2.value integerValue], [m1.value integerValue], [m2.value integerValue]];
    }];
    // NEW_DOMAIN
    _body_html = [RX(@"<a href=\"https?://.*?/forum/redirect\\.php\\?goto=findpost&amp;pid=(\\d+)&amp;ptid=\\d+\" target=\"_blank\">") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
        
        RxMatchGroup *m1 = [match.groups objectAtIndex:1];
        
        return [NSString stringWithFormat:@"<a onclick='gotofloor(\"0_%ld\")' >", [m1.value integerValue]];
    }];
}

- (void)processFuckContentHTML:(NSString *)html {
    
    if ([_body_html indexOf:@"attachments/day_"] != -1 ||
        [_body_html indexOf:@"attachment.php"] != -1 ||
        [html indexOf:@"<div class=\"postattachlist\">"] != -1) {
        
        /*
         * 注意 此处 和 processContentHTML 一样
         * 201508 有变化 和processContentHTML 可能不同 
         * 论坛普通版的没有_day前缀了 打印版还有
         */
//==============和processContentHTML一样=========================================
        // remove extra
        _body_html = [RX(@"<span style=\"position: absolute; display: none\" id=\"attach_.*?</span>\r\n") replace:_body_html with:@""];
        NSRegularExpression *rx = [NSRegularExpression rx:@"<div class=\"t_attach\" id=\"aimg_.*?\r\n</div>" options:NSRegularExpressionDotMatchesLineSeparators];
        _body_html = [rx replace:_body_html with:@""];
        
        
        __block NSMutableArray<HPImageNode *> *imgsArray = [NSMutableArray arrayWithCapacity:5];
        // 用来去重 和 查找imagesize
        __block NSMutableArray *aidArray = [NSMutableArray arrayWithCapacity:5];
        
        NSString *imageElement = @"<img class=\"attach_image\" src=\"%@\" a__i__d=\"%@\" />";
        // 最后会是 <img class="attach_image" src="http://domain.com/xxx.jpg" aid="123456" size="123" />
        
        // 帖子内部 image
        NSString *(^replacer)(RxMatch *match) = ^NSString *(RxMatch *match) {
            RxMatchGroup *m1 = [match.groups objectAtIndex:1];
            RxMatchGroup *m2 = [match.groups objectAtIndex:2];
            NSString *src = m1.value;
            
            // 正则提取是倒序
            [imgsArray insertObject:[[HPImageNode alloc] initWithURL:src] atIndex:0];
            NSString *aid = m2.value;
            if (aid.length) {
                [aidArray addObject:aid];
            }
            
            return [NSString stringWithFormat:imageElement, m1.value, aid];
        };
        
        _body_html = [RX(@"<img src=\"[^\"]*images/common/none\\.gif\" file=\"(.*?)\".*?aimg_(\\d+).*?/>") replace:_body_html withDetailsBlock:replacer];
        _body_html = [RX(@"<a href=\"javascript:;\"><img onclick=.*?src=\"(.*?)\".*?aimg_(\\d+).*?/></a>") replace:_body_html withDetailsBlock:replacer];
//======================================================
        // attach
        NSRange range = [html rangeOfString:@"<div class=\"postattachlist\">"];
        if (range.length > 0) {
            
            // img_html 最后会附加到 body_html 后面
            NSMutableString *img_html = [NSMutableString stringWithCapacity:5];
            void(^addImageNode)(NSString *src, NSString *aid) = ^(NSString *src, NSString *aid) {
                HPImageNode *n = [[HPImageNode alloc] initWithURL:src];
                if ([imgsArray indexOfObject:n] == NSNotFound) {
                    [imgsArray addObject:n];
                }
                // 去重
                if (aid.length && [aidArray indexOfObject:aid] == NSNotFound) {
                    [aidArray addObject:aid];
                    [img_html appendFormat:imageElement, src, aid];
                }
            };
            
            NSString *listPart = [html substringFromIndex:range.location];
            
            // 20161225前 兼容
            NSArray *imageMatchs = [RX(@"file=\"([^\"]+)\".*?id=\"aimg_(\\d+)\"") matchesWithDetails:listPart];
            for (RxMatch *i in imageMatchs) {
                RxMatchGroup *m1 = [i.groups objectAtIndex:1];
                RxMatchGroup *m2 = [i.groups objectAtIndex:2];
                NSString *src = m1.value;
                NSString *aid = m2.value;
                
                addImageNode(src, aid);
            }
            
            // 20161225后
            //<a href="javascript:;"><img onclick="zoom(this, 'attachments/day_161225/161225103518fdf8f15dc6cb5f.jpg')" src="attachments/day_161225/161225103518fdf8f15dc6cb5f.jpg.thumb.jpg" alt="IMG_20161225_103409.jpg" /></a>
            NSArray *imageMatchs2 = [RX(@"<img onclick=\"[^\"]+\" src=\"([^\"]+)\"") matchesWithDetails:listPart];
            for (RxMatch *i in imageMatchs2) {
                RxMatchGroup *m1 = [i.groups objectAtIndex:1];
                NSString *src = m1.value;
                
                // find aid
                RxMatchGroup *m0 = [i.groups objectAtIndex:0];
                NSString *aid = [listPart getAidString:m0.value];
                
                addImageNode(src, aid);
            }
            
            if (img_html.length) {
                self.body_html = [self.body_html stringByAppendingString:img_html];
            }
        }
//======================================================
        // 图片size
        for (NSString *aid in aidArray) {
            // 找到size
            NSString *sizeInfo = [html getFuckSizeString:aid];
            if (!sizeInfo) continue;
            
            // 填上size
            NSString *sizeString = [NSString stringWithFormat:@"%.2f", [sizeInfo imageSize]];
            NSString *pattern2 = [NSString stringWithFormat:@"a__i__d=\"%@\"", aid];
            self.body_html = [RX(pattern2) replace:self.body_html with:[NSString stringWithFormat:@"aid=\"%@\" size=\"%@\"", aid, sizeString]];
        }
//===========================================================
        
        self.images = [imgsArray copy];
    }
}

+ (NSDictionary *)findPageInfo:(NSString *)html url:(NSString *)url{
    // parameters
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithCapacity:5];
    // title <title>{酝酿改进中} D版 iOS 客户端 - Discovery -  Hi!PDA Hi!PDA </title>
    // fid fid = parseInt('2'), tid = parseInt('1272557')
    // pagecount
    // ~~formhash 暂时不需要
    // ~~user 暂时不需要
    // 提醒
    
    // formhash" value="82a18cad" />
    //
    NSString *formhash = [html stringBetweenString:@"formhash\" value=\"" andString:@"\" />"];
    
    NSLog(@"get form hash %@", formhash);
    NSString *old_formhash = [NSStandardUserDefaults stringForKey:kHPPOSTFormHash or:@""];
    if (old_formhash) {
        if ([old_formhash isEqualToString:formhash]) {
            //NSLog(@"############   formhash SAME   #####################");
        } else {
            NSLog(@"############   formhash NONO   #####################");
            [NSStandardUserDefaults setObject:formhash forKey:kHPPOSTFormHash];
        }
        
    } else {
        [NSStandardUserDefaults setObject:formhash forKey:kHPPOSTFormHash];
    }
    
    // pageCount
    NSInteger pageCount = 0;
    //
    //NSLog(@"post count  %lu", (unsigned long)[mutablePosts count]);
    /*if (page != NSIntegerMax && [mutablePosts count] < 50 && page == 1) {
     pageCount = 1;
     if(debugParameters) NSLog(@"pageCount seems = 1");
     } else {*/
    // 17</a><a href="viewthread.php?tid=923572&amp;extra=page%3D1&amp;page=2" class="next">
    NSArray *tmp = [html matchesWithPattern:@"[^0-9](\\d+)</a><a href=\"viewthread\\.php\\?tid=[^\"]+\" class=\"next\">" isdot:NO];
    
    if (![tmp count]) {
        tmp = [html matchesWithPattern:@"<strong>(\\d+)</strong></div><span class=\"pageback\"" isdot:NO];
    }
    
    if ([tmp count] == 2) {
        pageCount = [[tmp objectAtIndex:1] integerValue];
        if(debugParameters)  NSLog(@"pageCount = %ld", pageCount);
    } else {
        //NSLog(@"error get pageCount %@, %@", tmp, html);
        if(debugParameters) NSLog(@" get pageCount seems 1 %@, %@", tmp, html);
        pageCount = 1;
    }
    
    /*}*/
    
    // title
    // <title>{酝酿改进中} D版 iOS 客户端 - Discovery -  Hi!PDA Hi!PDA </title>
    NSString *title = [html stringBetweenString:@"<title>" andString:@" - "];
    if(debugParameters) NSLog(@"title %@", title);
    
    // fid
    // fid = parseInt('2')
    NSString *fidString = [html stringBetweenString:@"fid = parseInt('" andString:@"')"];
    if(debugParameters) NSLog(@"fidString %@", fidString);
    NSInteger fid = 0;
    if (fidString) {
        fid = [fidString integerValue];
    }
    
    // tid
    // tid = parseInt('1273829')
    NSString *tidString = [html stringBetweenString:@"tid = parseInt('" andString:@"')"];
    if(debugParameters) NSLog(@"tidString %@", tidString);
    NSInteger tid = 0;
    if (tidString) {
        tid = [tidString integerValue];
    }
    
    /*
    // msg
    // <ul class="s_clear"><li><a id="prompt_pm" href="pm.php?filter=newpm" target="_blank">私人消息 (2)</a></li><li style="display:none"><a id="prompt_announcepm" href="pm.php?filter=announcepm" target="_blank">公共消息 (0)</a></li><li style="display:none"><a id="prompt_systempm" href="notice.php?filter=systempm" target="_blank">系统消息 (0)</a></li><li style="display:none"><a id="prompt_friend" href="notice.php?filter=friend" target="_blank">好友消息 (0)</a></li><li><a id="prompt_threads" href="notice.php?filter=threads" target="_blank">帖子消息 (1)</a></li></ul>
    NSString *pm_count_string = [html stringBetweenString:@">私人消息 (" andString:@")<"];
    NSInteger pm_count = 0;
    
    if (pm_count_string) {
        pm_count = [pm_count_string integerValue];
        if (pm_count > 0) {
            [NSStandardUserDefaults setInteger:pm_count forKey:kHPMessageCount];
        }
    }
    
    NSLog(@"pm_count_string %@ %d", pm_count_string, [NSStandardUserDefaults integerForKey:kHPMessageCount or:0]);
    
    NSString *remind_count_string = [html stringBetweenString:@">帖子消息 (" andString:@")<"];
    NSInteger remind_count = 0;
    if(debugParameters) NSLog(@"remind_count_string %@", remind_count_string);
    if (remind_count_string) {
        remind_count = [remind_count_string integerValue];
        if (remind_count > 0) {
            [NSStandardUserDefaults setInteger:remind_count forKey:kHPRemindCount];
        }
    }
    */
    
    // title <title>{酝酿改进中} D版 iOS 客户端 - Discovery -  Hi!PDA Hi!PDA </title>
    // fid fid = parseInt('2'), tid = parseInt('1272557')
    // pagecount
    // new msg
    if (formhash) {
        [parameters setObject:formhash forKey:@"formhash"];
    }
    
    if (pageCount) {
        [parameters setObject:[NSNumber numberWithInteger:pageCount] forKey:@"pageCount"];
    }
    if (title) {
        [parameters setObject:title forKey:@"title"];
    }
    if (fid) {
        [parameters setObject:[NSNumber numberWithInteger:fid] forKey:@"fid"];
    }
    if (tid) {
        [parameters setObject:[NSNumber numberWithInteger:tid] forKey:@"tid"];
    }
    
    /*
    if (pm_count) {
        [parameters setObject:[NSNumber numberWithInteger:pm_count] forKey:@"pm_count"];
    }
    if (remind_count) {
        [parameters setObject:[NSNumber numberWithInteger:remind_count] forKey:@"remind_count"];
    }*/
    
    if (url) {
        //http://www.hi-pda.com/forum/viewthread.php?tid=1365231&rpid=24817242&ordertype=0&page=1#pid24817242
        RxMatch *a = [RX(@"page=(\\d+).*?pid(\\d+)") firstMatchWithDetails:url];
        
        if (a.groups.count == 3) {
            //RxMatchGroup *a1 = [a.groups objectAtIndex:1];
            RxMatchGroup *a2 = [a.groups objectAtIndex:2];
    
            //NSInteger page = [a1.value integerValue];
            NSInteger pid = [a2.value integerValue];
            
            //[parameters setObject:[NSNumber numberWithInteger:page] forKey:@"current_page"];
            [parameters setObject:[NSNumber numberWithInteger:pid] forKey:@"find_pid"];
        }
    }
    
    
    NSString *pageHTML = [html stringBetweenString:@"<div class=\"pages\">" andString:@"</div>"];
    RxMatch *page_match = [RX(@"<strong>(\\d+)</strong>") firstMatchWithDetails:pageHTML ?: @""];
    if (page_match) {
        
        RxMatchGroup *m = [page_match.groups objectAtIndex:1];
        NSInteger page = [m.value integerValue];
        [parameters setObject:[NSNumber numberWithInteger:page] forKey:@"current_page"];
        
    } else {
        [parameters setObject:@1 forKey:@"current_page"];
    }

    return parameters;
}


+ (NSString *)preProcessHTML:(NSMutableString *)string {
    
    if ([Setting boolForKey:HPSettingNightMode]) {
        [string replaceOccurrencesOfString:@"<font color=\"Black\">" withString:@"<font color=\"White\">" options:0 range:NSMakeRange(0, string.length)];
    } else {
        [string replaceOccurrencesOfString:@"<font color=\"White\">" withString:@"<font color=\"Red\">" options:0 range:NSMakeRange(0, string.length)];
    }
    
    NSString *final = (NSString *)string;
    
    // 小尾巴太长
    // <a href="http://www.hi-pda.com/forum/viewthread.php?tid=1579403" target="_blank"><font size="1">HiPDA·NG</font>
    final = [RX(@"<a href=[^>]+><font size=\"1\">([^<]+)</font>") replace:final withDetailsBlock:^NSString *(RxMatch *match) {
        if (match.groups.count != 2) {
            return match.value;
        }

        NSString *content = [(RxMatchGroup *)match.groups[1] value];
        if (content.length > 10) {
            return [match.value stringByReplacingOccurrencesOfString:content withString:[[content substringToIndex:10] stringByAppendingString:@"..."]];
        } else {
            return match.value;
        }
    }];
    
    
    BOOL imageAutoLoadEnable = NO;
    HPImageAutoLoadMode autoLoadMode = 0;
    CGFloat autoLoadThreshold = 0.f;
    
    AFNetworkReachabilityStatus status = [[HPHttpClient sharedClient] networkReachabilityStatus];
    if (status == AFNetworkReachabilityStatusReachableViaWiFi) {
        imageAutoLoadEnable = [Setting boolForKey:HPSettingImageAutoLoadEnableWifi];
        autoLoadMode = [Setting integerForKey:HPSettingImageAutoLoadModeWifi];
        autoLoadThreshold = [Setting floatForKey:HPSettingImageAutoLoadModeAutoThresholdWifi];
    } else {
        imageAutoLoadEnable = [Setting boolForKey:HPSettingImageAutoLoadEnableWWAN];
        autoLoadMode = [Setting integerForKey:HPSettingImageAutoLoadModeWWAN];
        autoLoadThreshold = [Setting floatForKey:HPSettingImageAutoLoadModeAutoThresholdWWAN];
    }
 
/*
 * 加载策略:
 *   1. BOOL imageAutoLoadEnable = NO;
 *   目前只能拿到原图的size 而不是缩略图的size, 所以无法做一个智能模式, 大于xxx不自动加载, 只要关了autoload, 一律手动载入
 *   -> 是否换成placeholder
 *
 *   2. HPImageAutoLoadMode autoLoadMode = 0;
 *      CGFloat autoLoadThreshold = 0.f;
 *   -> 是否替换url
 */
    NSRegularExpression *rx = RX(@"<img class=\"attach_image\" src=\"(.*?)\"(.*?)/>");
    final = [rx replace:final withDetailsBlock:^NSString *(RxMatch *match) {
        
        NSString *imageNode = match.value;
        
        // 缓存里有就不过滤
        {
            NSString *src = [(RxMatchGroup *)match.groups[1] value];
            // 如果没有域名, 只是相对路径, 那么就检测HP_BASE_URL的缓存, 毕竟加载html时, baseurl为HP_BASE_URL
            if ([src rangeOfString:HP_BASE_URL].location == NSNotFound) {
                src = [[HP_BASE_URL stringByAppendingString:@"/forum/"] stringByAppendingString:src];
            }
            NSString *src_original = [src stringByReplacingOccurrencesOfString:HP_THUMB_URL_SUFFIX withString:@""];
            if ([src_original rangeOfString:HP_BASE_URL].location == NSNotFound) {
                src_original = [[HP_BASE_URL stringByAppendingString:@"/forum/"] stringByAppendingString:src_original];
            }
            NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:[NSURL URLWithString:src]];
            NSString *key2 = [[SDWebImageManager sharedManager] cacheKeyForURL:[NSURL URLWithString:src_original]];
            if ([[SDImageCache sharedImageCache] hp_imageDataExistsWithKey:key]) {
                return match.value;
            }
            if ([[SDImageCache sharedImageCache] hp_imageDataExistsWithKey:key2]) {
                return [match.value stringByReplacingOccurrencesOfString:HP_THUMB_URL_SUFFIX withString:@""];
            }
        }
        
        
        NSString *sizeString = [match.value stringBetweenString:@"size=\"" andString:@"\""];
        double imageSize = sizeString.length ? [sizeString doubleValue] : 0.f;
        
        switch (autoLoadMode) {
            case HPImageAutoLoadModePerferAuto:
                if (imageSize <= autoLoadThreshold) {
                    imageNode = [imageNode stringByReplacingOccurrencesOfString:HP_THUMB_URL_SUFFIX withString:@""];
                }
                break;
            case HPImageAutoLoadModePerferThumb:
                // no-op;
                break;
            case HPImageAutoLoadModePerferOriginal:
                imageNode = [imageNode stringByReplacingOccurrencesOfString:HP_THUMB_URL_SUFFIX withString:@""];
                break;
        }
 
        if (!imageAutoLoadEnable) {
            NSString *sizeDisplayString = [sizeString imageSizeString];
            NSParameterAssert(sizeDisplayString.length);
            BOOL isThumbnail = [imageNode rangeOfString:HP_THUMB_URL_SUFFIX].location != NSNotFound;
            NSString *tip = [NSString stringWithFormat:@"点击查看图片%@", sizeDisplayString.length ? [NSString stringWithFormat:@"(%@)", isThumbnail ? @"缩略图" : sizeDisplayString] : @""];
            imageNode = [imageNode stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
            return S(@"<div class='img_placeholder' image='%@' onclick='img_click(this)'>%@</div>", imageNode, sizeDisplayString.length ? tip : @"");
        } else {
            return imageNode;
        }
    }];
    
    return final;
}


+ (NSString *)dateString:(NSDate *)date
{
    NSString *dateString = nil;
    static NSDateFormatter *formatter_l;
    static NSDateFormatter *formatter_m;
    static NSDateFormatter *formatter_s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter_l = [[NSDateFormatter alloc] init];
        [formatter_l setDateFormat:@"yyyy-MM-dd HH:mm"];
        formatter_m = [[NSDateFormatter alloc] init];
        [formatter_m setDateFormat:@"MM-dd HH:mm"];
        formatter_s = [[NSDateFormatter alloc] init];
        [formatter_s setDateFormat:@"HH:mm"];
    });
    
    NSCalendar *calendar = [NSCalendar currentCalendar];
    
    unsigned unitFlags = NSYearCalendarUnit | NSMonthCalendarUnit |  NSDayCalendarUnit;
    NSDateComponents *today_comp = [calendar components:unitFlags fromDate:[NSDate date]];
    NSDateComponents *comp = [calendar components:unitFlags fromDate:date];
    
    if (today_comp.year == comp.year) {
        if (today_comp.month == comp.month && today_comp.day == comp.day) {
            dateString = [formatter_s stringFromDate:date];
        } else {
            dateString = [formatter_m stringFromDate:date];
        }
    } else {
        dateString = [formatter_l stringFromDate:date];
    }
    
    return dateString;
}

+ (NSString *)fullDateString:(NSDate *)date {
    
    static NSDateFormatter *formatter_l;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter_l = [[NSDateFormatter alloc] init];
        [formatter_l setDateFormat:@"yyyy-MM-dd HH:mm"];
    });

    return [formatter_l stringFromDate:date];;
}


/*
- (NSString *)description {
    NSString *r = [NSString stringWithFormat:
        @"\nuser %@, uid %d"
        @"\nhtml %@"
        @"\nfloor %d",
        _user.username, _user.uid, _body_html, _floor];
    
    return r;
}
 */

#pragma mark - NSCoding


- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeInteger:_pid forKey:@"pid"];
    [aCoder encodeObject:_user forKey:@"user"];
    [aCoder encodeObject:_date forKey:@"date"];
    [aCoder encodeInteger:_floor forKey:@"floor"];
    [aCoder encodeObject:_body forKey:@"body"];
    [aCoder encodeObject:_body_html forKey:@"body_html"];
    [aCoder encodeObject:_images forKey:@"images"];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        _pid = [aDecoder decodeIntegerForKey:@"pid"];
        _user = [aDecoder decodeObjectForKey:@"user"];
        _date = [aDecoder decodeObjectForKey:@"date"];
        _floor = [aDecoder decodeIntegerForKey:@"floor"];
        
        _body = [aDecoder decodeObjectForKey:@"body"];
        _body_html = [aDecoder decodeObjectForKey:@"body_html"];
        
        _images = [aDecoder decodeObjectForKey:@"images"];
    }
    return self;
}

+ (NSString *)urlForSwfUrl:(NSString *)link {
    
    NSString *result = nil;
    
    if ([link indexOf:@"http://player.youku.com/player.php/sid/"] != -1) {
        
        NSString *url = [link stringBetweenString:@"http://player.youku.com/player.php/sid/" andString:@"/v.swf"];
        
        if (url) {
            result = [NSString stringWithFormat:@"v.youku.com/v_show/id_%@.html", url];
        }
        
    } else if ([link indexOf:@"http://www.tudou.com/v/"] != -1) {
        
        NSString *url = [link stringBetweenString:@"http://www.tudou.com/v/" andString:@"/&resourceId"];
        
        if (url) {
            result = [NSString stringWithFormat:@"www.tudou.com/programs/view/%@", url];
        }
        
    } else if ([link indexOf:@"http://www.tudou.com/a/"] != -1) {
        
        NSString *url = [link stringBetweenString:@"http://www.tudou.com/a/" andString:@"/&resourceId"];
        
        if (url) {
            result = [NSString stringWithFormat:@"www.tudou.com/albumplay/%@", url];
        }
        
    } else if ([link indexOf:@"http://player.video.qiyi.com/"] != -1) {
        
        NSString *url = [link stringBetweenString:@"v_" andString:@".swf"];
        
        if (url) {
            result = [NSString stringWithFormat:@"www.iqiyi.com/v_%@.html", url];
        }
    } else if ([link indexOf:@"http://player.video.qiyi.com/"] != -1) {
        
        NSString *url = [link stringBetweenString:@"v_" andString:@".swf"];
        
        if (url) {
            result = [NSString stringWithFormat:@"www.iqiyi.com/v_%@.html", url];
        }
    } else if ([link indexOf:@"http://player.56.com/v_"] != -1) {
        
        NSString *url = [link stringBetweenString:@"http://player.56.com/v_" andString:@".swf"];
        
        if (url) {
            result = [NSString stringWithFormat:@"www.56.com/iframe/%@", url];
        }
    } else if ([link indexOf:@"http://player.56.com/cpm_"] != -1) {
        
        NSString *url = [link stringBetweenString:@"http://player.56.com/cpm_" andString:@".swf"];
        
        if (url) {
            result = [NSString stringWithFormat:@"www.56.com/iframe/%@", url];
        }
        
    } else {
        ;
    }
    return result;
}




@end
