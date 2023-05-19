//
//  LGTracerouteQueue.h
//  LGTraceroute
//
//  Created by admin on 2023/5/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LGTracerouteQueue : NSObject
+ (void)LGNetPingAsync:(dispatch_block_t)block;
+ (void)LGNetQuickPingAsync:(dispatch_block_t)block;
+ (void)LGNetTraceAsync:(dispatch_block_t)block;
+ (void)LGNetAsync:(dispatch_block_t)block;
@end

NS_ASSUME_NONNULL_END
