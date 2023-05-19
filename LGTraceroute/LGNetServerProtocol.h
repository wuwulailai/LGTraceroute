//
//  LGNetServerProtocol.h
//  Pods
//
//  Created by apple on 2018/9/17.
//
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, InfoFlag) {
    InfoFlagBegin,
    InfoFlagOn,
    InfoFlagEnd
};

typedef void(^NetCallback)(NSString *info, NSInteger flag);

@protocol LGNetServerProtocol<NSObject>

- (void)startNetServerAndCallback:(NetCallback) callback;
@optional
- (instancetype)initWithHostName:(NSString *)hostName;


@end
