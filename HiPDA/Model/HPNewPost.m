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

#import "HPHttpClient.h"
#import <AFHTTPRequestOperation.h>

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

             forceRefresh:(BOOL)forceRefresh // 强制刷新
                printable:(BOOL)printable // 加载打印版网页

                 authorid:(NSInteger)authorid // 只看某人
          redirectFromPid:(NSInteger)redirectFromPid //在搜索全文结果, 跳转等, 只能拿到pid

                    block:(void (^)(NSArray *posts, NSDictionary *parameters, NSError *error))block
{
    // return cache
    //
    NSArray *cachedThread = [[HPCache sharedCache] loadThread:tid page:page];
    NSDictionary *cachedInfo = [[HPCache sharedCache] loadThreadInfo:tid page:page];
    
    if (!forceRefresh && cachedThread && redirectFromPid != 0) {
        if (block) {
            block(cachedThread, cachedInfo, nil);
        }
        NSLog(@"return cache");
        return;
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
        
        // cache
        if (tid == 0 || page == 0) {
            
            //todo
            
        } else {
            [[HPCache sharedCache] cacheThread:[NSArray arrayWithArray:posts] info:parameters tid:tid page:page];
        }
        
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
                           refresh:(BOOL)refresh
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
        html = [RX(@"&nbsp; &nbsp; <b>标题: </b>(.*?)<br /><br />") replace:html withDetailsBlock:^(RxMatch* match){
            
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
            NSMutableArray *b = [NSMutableArray arrayWithCapacity:posts.count - 50];
            for (int i = 50; i < a.count; i++) {
                HPNewPost *p = a[i];
                [b addObject:p];
            }
            [a removeObjectsInRange:NSMakeRange(50, posts.count - 50)];
            
            posts = [NSArray arrayWithArray:a];
            [[HPCache sharedCache] cacheThread:[NSArray arrayWithArray:b] info:parameters tid:tid page:2];
        }
        
        
        
        [[HPCache sharedCache] cacheThread:[NSArray arrayWithArray:posts] info:parameters tid:tid page:1];
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
    [[HPDatabase sharedDb] open];
    
    [postsArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        
        HPNewPost *post = (HPNewPost *)obj;
        
        post.floor = idx+1;
        
        NSInteger uid = [[[HPDatabase sharedDb] db] intForQuery:@"SELECT uid FROM user WHERE username = ?", post.user.username];
        post.user.uid = uid;
        post.user.avatarImageURL = [HPUser avatarStringWithUid:uid];
        
        
        // process content
        [post processContentHTML];
    
    }];
    
    [[HPDatabase sharedDb] close];
    
    // fix
    HPNewPost *last = [postsArray lastObject];
    last.body_html = [last.body_html stringByReplacingOccurrencesOfString:@"<br /><br /><br /><br />" withString:@""];
    
    return postsArray;
}

- (void)processContentHTML {
    
    // 回复
    _body_html = [RX(@"<a href=\"http://www\\.hi-pda\\.com/forum/redirect\\.php\\?goto=findpost&amp;pid=(\\d+)&amp;ptid=\\d+\" target=\"_blank\">(\\d+)#</a>") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
        
        RxMatchGroup *m1 = [match.groups objectAtIndex:1];
        RxMatchGroup *m2 = [match.groups objectAtIndex:2];
        
        //NSLog(@"%@ %@", m1.value, m2.value);
        
        return [NSString stringWithFormat:@"<a href=\"gotofloor://%ld_%ld\" >%ld#</a>", [m2.value integerValue], [m1.value integerValue], [m2.value integerValue]];
    }];
    
    // 引用
    _body_html = [RX(@"<a href=\"http://www\\.hi-pda\\.com/forum/redirect\\.php\\?goto=findpost&amp;pid=(\\d+)&amp;ptid=\\d+\" target=\"_blank\">") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
        
        RxMatchGroup *m1 = [match.groups objectAtIndex:1];
        return [NSString stringWithFormat:@"<a href=\"gotofloor://0_%ld\" >", [m1.value integerValue]];
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
        
        // remove extra
        _body_html = [RX(@"<span style=\"position: absolute; display: none\" id=\"attach_.*?</span>\r\n") replace:_body_html with:@""];
        NSRegularExpression *rx = [NSRegularExpression rx:@"<div class=\"t_attach\" id=\"aimg_.*?\r\n</div>" options:NSRegularExpressionDotMatchesLineSeparators];
        _body_html = [rx replace:_body_html with:@""];
        
        
        __block NSMutableArray *imgsArray = [NSMutableArray arrayWithCapacity:5];
        NSString *imageElement = @"<img class=\"attach_image\" src=\"%@\" />";
        
        // 帖子内部 image
        _body_html = [RX(@"<img src=\"images/common/none\\.gif\" file=\"(.*?)\".*?/>") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
            
            RxMatchGroup *m1 = [match.groups objectAtIndex:1];
            //NSLog(@"%@", m1.value);
            NSString *src = [NSString stringWithFormat:@"http://www.hi-pda.com/forum/%@", m1.value];
            
            [imgsArray addObject:src];
            
            return [NSString stringWithFormat:imageElement, m1.value];
        }];
        
        
        // 帖子底部 image
        _body_html = [RX(@"<br /><br /><img src=\"images/attachicons.*?src=\"(.*?)\".*?/>") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
            
            RxMatchGroup *m1 = [match.groups objectAtIndex:1];
            NSString *src = [NSString stringWithFormat:@"http://www.hi-pda.com/forum/%@", m1.value];
            
            if ([imgsArray indexOfObject:src] == NSNotFound) {
                [imgsArray addObject:src];
                return [NSString stringWithFormat:imageElement, m1.value];
            } else {
                return @"";
            }
        }];
        
        
        // todo
        // 网络图片 也要加进来

        
        // 恢复正序 (正则提取时是倒序提取)
        NSArray *reversedArray = [[imgsArray reverseObjectEnumerator] allObjects];
        self.images = reversedArray;
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
         
         [post processFuckContentHTML];
          
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
    
    if (debugContent) assert(a.groups.count == 3);
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
    self.user.avatarImageURL = [HPUser avatarStringWithUid:uid];
    
    
    // date
    //
    NSString *dateString = nil;
    RxMatch *b = [RX(@"<em id=\"authorposton\\d+\">发表于 ([^<]+)</em>") firstMatchWithDetails:html];
    if (debugContent) assert(b.groups.count == 2);
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
    if (debugContent) assert(c.groups.count == 2);
    if (c && c.groups.count == 2) {
        RxMatchGroup *c1 = [c.groups objectAtIndex:1];
        self.floor = [c1.value integerValue];
    } else {
        self.floor = 0;
    }
    if (debugContent) NSLog(@"floor %ld", self.floor);
    
    // content
    //
    Rx *rx = [Rx rx:@"<td class=\"t_msgfont\" id=\"postmessage_\\d+\">(.*?)</td></tr></table>" options:NSRegularExpressionDotMatchesLineSeparators];
    RxMatch *d = [rx firstMatchWithDetails:html];
    //assert(d.groups.count == 2);
    if (d && d.groups.count == 2) {
        
        RxMatchGroup *d1 = [d.groups objectAtIndex:1];
        self.body_html = d1.value;
        
    } else {
        
        self.body_html = @"提示: <em>作者被禁止或删除 内容自动屏蔽</em>";
    }
    
    if (debugContent) NSLog(@"content %@", self.body_html);
    
    
    // attach
    //
    NSRange range = [html rangeOfString:@"<div class=\"postattachlist\">"];
    if ( range.length > 0 ) {
        [html substringFromIndex:range.location];
        
        NSMutableArray *images = [NSMutableArray arrayWithCapacity:5];
        NSArray *imageMatchs = [RX(@"file=\"([^\"]+)\"") matchesWithDetails:html];
        for (RxMatch *i in imageMatchs) {
            RxMatchGroup *ii = [i.groups objectAtIndex:1];
            NSLog(@"src %@", ii.value);
            [images addObject:[NSString stringWithFormat:@"http://www.hi-pda.com/forum/%@", ii.value]];
        }
        
        self.images = [NSArray arrayWithArray:images];
    }
    
    
    _body_html = [RX(@"<a href=\"http://www\\.hi-pda\\.com/forum/redirect\\.php\\?goto=findpost&amp;pid=(\\d+)&amp;ptid=\\d+\" target=\"_blank\">(\\d+)#</a>") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
        
        RxMatchGroup *m1 = [match.groups objectAtIndex:1];
        RxMatchGroup *m2 = [match.groups objectAtIndex:2];
        
        //NSLog(@"%@ %@", m1.value, m2.value);
        
        return [NSString stringWithFormat:@"<a href=\"gotofloor://%ld_%ld\" >%ld#</a>", [m2.value integerValue], [m1.value integerValue], [m2.value integerValue]];
    }];
    
    _body_html = [RX(@"<a href=\"http://www\\.hi-pda\\.com/forum/redirect\\.php\\?goto=findpost&amp;pid=(\\d+)&amp;ptid=\\d+\" target=\"_blank\">(\\d+)#</a>") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
        
        RxMatchGroup *m1 = [match.groups objectAtIndex:1];
        RxMatchGroup *m2 = [match.groups objectAtIndex:2];
        
        NSLog(@"%@ %@", m1.value, m2.value);
        
        return [NSString stringWithFormat:@"<a href=\"gotofloor://%ld_%ld\" >%ld#</a>", [m2.value integerValue], [m1.value integerValue], [m2.value integerValue]];
    }];
    
    _body_html = [RX(@"<a href=\"http://www\\.hi-pda\\.com/forum/redirect\\.php\\?goto=findpost&amp;pid=(\\d+)&amp;ptid=\\d+\" target=\"_blank\">") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
        
        RxMatchGroup *m1 = [match.groups objectAtIndex:1];
        
        return [NSString stringWithFormat:@"<a href=\"gotofloor://0_%ld\" >", [m1.value integerValue]];
    }];
}

- (void)processFuckContentHTML {
    
    // add attach images to body_html
    if (_images) {
        NSMutableString *img_html = [NSMutableString stringWithCapacity:_images.count];
        [_images enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [img_html appendFormat:@"<img class=\"attach_image\" src=\"%@\" />", obj];
        }];
        _body_html = [_body_html stringByAppendingString:img_html];
    }
    
    if ([_body_html indexOf:@"attachments/day_"] != -1 ) {
        
        /*
         * 注意 此处 和 processContentHTML 一样
         */
        // remove extra
        _body_html = [RX(@"<span style=\"position: absolute; display: none\" id=\"attach_.*?</span>\r\n") replace:_body_html with:@""];
        NSRegularExpression *rx = [NSRegularExpression rx:@"<div class=\"t_attach\" id=\"aimg_.*?\r\n</div>" options:NSRegularExpressionDotMatchesLineSeparators];
        _body_html = [rx replace:_body_html with:@""];
        
        
        __block NSMutableArray *imgsArray = [NSMutableArray arrayWithCapacity:5];
        NSString *imageElement = @"<img class=\"attach_image\" src=\"%@\" />";
        
        // 帖子内部 image
        _body_html = [RX(@"<img src=\"images/common/none\\.gif\" file=\"(.*?)\".*?/>") replace:_body_html withDetailsBlock:^NSString *(RxMatch *match) {
            
            RxMatchGroup *m1 = [match.groups objectAtIndex:1];
            //NSLog(@"%@", m1.value);
            NSString *src = [NSString stringWithFormat:@"http://www.hi-pda.com/forum/%@", m1.value];
            
            [imgsArray addObject:src];
            
            return [NSString stringWithFormat:imageElement, m1.value];
        }];
        
        
        if (!_images) {
            
            _images = [NSArray arrayWithArray:imgsArray];
            
        } else {
            
            _images = [_images arrayByAddingObjectsFromArray:imgsArray];
            
        }
        
        // 恢复正序 (正则提取时是倒序提取)
        NSArray *reversedArray = [[_images reverseObjectEnumerator] allObjects];
        self.images = reversedArray;
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
    
    
    RxMatch *page_match = [RX(@"<strong>(\\d+)</strong>") firstMatchWithDetails:html];
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
    
    AFNetworkReachabilityStatus status = [NSStandardUserDefaults integerForKey:kHPNetworkStatus];
    HPImageDisplayStyle style = HPImageDisplayStyleFull;
    
    if (status == AFNetworkReachabilityStatusReachableViaWWAN) {
        style = [Setting integerForKey:HPSettingImageWWAN];
    } else if (status == AFNetworkReachabilityStatusReachableViaWiFi) {
        style = [Setting integerForKey:HPSettingImageWifi];
    } else {
        NSLog(@"other status %d", status);
    }
    //NSLog(@"style %d", style);
    if (style != HPImageDisplayStyleFull) {
        
        __block int i = 0;
        NSArray *matches = [RX(@"<img class=\"attach_image\" src=\"(.*?)\" />") matches:string];

        final = [RX(@"<img class=\"attach_image\" src=\"(.*?)\" />") replace:string withDetailsBlock:^NSString *(RxMatch *match) {
            
            i++;
            
            if (i == matches.count && style == HPImageDisplayStyleOne) {
                
                //NSLog(@"one %@", match.value);
                return match.value;
                
            } else {
                
                RxMatchGroup *m1 = [match.groups objectAtIndex:1];
                //NSLog(@"%@", m1.value);
                return S(@"<div class='img_placeholder' onclick='img_click(\"http://www.hi-pda.com/forum/%@\")'>点击查看图片</div>",m1.value);
            }
    
        }];
    }
    
    return final;
}


+ (NSString *)dateString:(NSDate *)date {
    
    // todo timeago
    
    NSTimeInterval interval = [date timeIntervalSinceNow];
    float dayInterval = (-interval) / 86400;
    
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
    
    if (dayInterval < 1) {
        dateString = [formatter_s stringFromDate:date];
    } else if (dayInterval < 365) {
        dateString = [formatter_m stringFromDate:date];
    } else {
        dateString = [formatter_l stringFromDate:date];
    }
    
    return dateString;
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
