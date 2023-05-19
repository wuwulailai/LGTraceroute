//
//  LGTracerouteQueue.m
//  LGTraceroute
//
//  Created by admin on 2023/5/19.
//

#import "LGTracerouteQueue.h"

@interface LGTracerouteQueue()
+ (instancetype)shareInstance;

@property (nonatomic) dispatch_queue_t pingQueue;
@property (nonatomic) dispatch_queue_t quickPingQueue;
@property (nonatomic) dispatch_queue_t traceQueue;
@property (nonatomic) dispatch_queue_t asyncQueue;

@end

@implementation LGTracerouteQueue

+ (instancetype)shareInstance {
    static LGTracerouteQueue *unetQueue = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        unetQueue = [[self alloc] init];
    });
    
    return unetQueue;
}

- (instancetype)init
{
    if (self = [super init]) {
        _pingQueue = dispatch_queue_create("com.ping.queue", DISPATCH_QUEUE_SERIAL);
        _quickPingQueue = dispatch_queue_create("com.qping.queue", DISPATCH_QUEUE_SERIAL);
        _traceQueue = dispatch_queue_create("com.trace.queue", DISPATCH_QUEUE_SERIAL);
        _asyncQueue = dispatch_queue_create("com.async.queue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (void)LGNetPingAsync:(dispatch_block_t)block {
    dispatch_async([LGTracerouteQueue shareInstance].pingQueue, ^{
        block();
    });
}

+ (void)LGNetQuickPingAsync:(dispatch_block_t)block {
    dispatch_async([LGTracerouteQueue shareInstance].quickPingQueue, ^{
        block();
    });
}

+ (void)LGNetTraceAsync:(dispatch_block_t)block {
    dispatch_async([LGTracerouteQueue shareInstance].traceQueue, ^{
        block();
    });
}

+ (void)LGNetAsync:(dispatch_block_t)block {
    dispatch_async([LGTracerouteQueue shareInstance].asyncQueue, ^{
        block();
    });
}

@end
