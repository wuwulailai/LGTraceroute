//
//  LGUdpTraceroute.h
//  LGTraceroute
//
//  Created by admin on 2023/5/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LGUdpTracerouteHandler)(NSString *);

@interface LGUdpTraceroute : NSObject

+ (instancetype)startWithHost:(NSString *_Nonnull)host
                     complete:(LGUdpTracerouteHandler _Nonnull)complete;

+ (instancetype)startWithHost:(NSString *_Nonnull)host
                       maxTtl:(NSUInteger)maxTtl
                     complete:(LGUdpTracerouteHandler _Nonnull)complete;

- (BOOL)isDoingUdpTraceroute;


- (void)stopUdpTraceroute;

@end

NS_ASSUME_NONNULL_END
