//
//  HPJSON.m
//  HiPDA
//
//  Created by Jiangfan on 2018/8/12.
//  Copyright © 2018年 wujichao. All rights reserved.
//

#import "HPJSON.h"

@implementation HPJSON

+ (NSDictionary *)fromJSON:(NSString *)jsonString
{
    NSError *jsonError;
    NSData *objectData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:objectData
                                                         options:NSJSONReadingMutableContainers
                                                           error:&jsonError];
    if (jsonError) {
        DDLogError(@"fromJSON error: %@, %@", jsonString, jsonError);
        return nil;
    }
    
    return json;
}

+ (NSString *)toJSON:(NSDictionary *)dic
{
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dic
                                                       options:0
                                                         error:&error];
    
    if (error) {
        DDLogError(@"toJSON error: %@, %@", dic, error);
        return nil;
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

+ (MTLModel<MTLJSONSerializing> *)mtl_fromJSON:(NSString *)jsonString
                                         class:(Class)clazz
{
    if (!jsonString.length) {
        return nil;
    }
    
    NSDictionary *json = [HPJSON fromJSON:jsonString];
    if (!json) {
        return nil;
    }
    NSError *jsonError;
    id object = [MTLJSONAdapter modelOfClass:clazz
                          fromJSONDictionary:json
                                       error:&jsonError];
    if (jsonError) {
        DDLogError(@"加载失败 %@", json);
        return nil;
    }
    return object;
}

+ (NSString *)mtl_toJSON:(MTLModel<MTLJSONSerializing> *)object
{
    NSDictionary *json = [MTLJSONAdapter JSONDictionaryFromModel:object];
    return [HPJSON toJSON:json];
}

@end
