//
//  LGTraceRoute.h
//  LG
//
//  Created by apple on 2023/3/7.
//  Copyright © 2023年 GG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LGNetServerProtocol.h"


@interface LGTraceroute : NSObject<LGNetServerProtocol>

+ (instancetype)sharedInstance;

+ (instancetype)instance;

+ (void)setupTraceroute:(LGTraceroute *)traceRoute;

- (instancetype)init NS_UNAVAILABLE;

//- (instancetype)initWithHostName:(NSString *)hostName NS_DESIGNATED_INITIALIZER;

- (void)setupHostName:(NSString *)hostName;

- (void)startNetServerAndCallback:(NetCallback)callback;

- (void)stopTraceroute;

@end
