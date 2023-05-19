//
//  LGTraceRoute.m
//  LG
//
//  Created by apple on 2023/3/7.
//  Copyright © 2023年 GG. All rights reserved.
//

#import "LGTraceroute.h"
#import "LGSimplePing.h"

//#define kHopsMax  64
#define kHopsMax  30
#define kTracerouteTimeout 3

@interface LGTraceroute()<LGSimplePingDelegate>

@property (nonatomic, strong) NSDate *startDate;
@property (nonatomic, assign) NSInteger hopNum;
@property (nonatomic, copy) NSString *nodeIp;
@property (nonatomic, assign) NSInteger sendIndex;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSTimer *timeoutTimer;
@property (nonatomic, strong) LGSimplePing *tracerouter;

@property (nonatomic, copy) NSString *info;
@property (nonatomic, copy) NetCallback callback;

@property(nonatomic, copy) NSString *hostName;

@property (nonatomic, copy) NSString *currentNodeIp;

@end

LGTraceroute *globalInstance = nil;

@implementation LGTraceroute
+ (instancetype)sharedInstance {
    static id instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    
    return instance;
}

+ (instancetype)instance {
    if(globalInstance) {
        return globalInstance;
    }
    
    return [self sharedInstance];
}

+ (void)setupTraceroute:(LGTraceroute *)traceRoute {
    globalInstance = traceRoute;
}

//- (instancetype)initWithHostName:(NSString *)hostName {
//    self = [super init];
//    if (self) {
//        self.hostName = hostName;
//    }
//    return self;
//}

- (void)setupHostName:(NSString *)hostName {
    [self stopTraceroute];
    self.hostName = hostName;
}

- (void)startNetServerAndCallback:(NetCallback) callback {
    self.callback = callback;
    self.tracerouter = [[LGSimplePing alloc] initWithHostName:self.hostName];
    self.tracerouter.delegate = self;
    [self.tracerouter start];
}

- (void)checkTimeout {
    if (self.sendIndex == 0) {
        self.info = [NSString stringWithFormat:@"%ld * * *" , (long)self.hopNum];
    } else if (self.sendIndex == 1){
        self.info = [NSString stringWithFormat:@"%@ * *" , self.info];
    } else if (self.sendIndex == 2) {
        self.info = [NSString stringWithFormat:@"%@ * " , self.info];
    }
    
    if(self.sendIndex == 3) {
        self.info = [NSString stringWithFormat:@"%@ %@",self.info, self.currentNodeIp];
        self.currentNodeIp = @"";
    }
    
    self.callback(self.info, InfoFlagOn);
    [self.timeoutTimer invalidate];
    self.timeoutTimer = nil;
    
    [self traceroute];
}
- (void)traceroute {
    if (self.hopNum == kHopsMax) {
        [self stopTraceroute];
        return ;
    }
    self.info = @"";
    self.sendIndex = 0;
    self.hopNum += 1;
    [self.tracerouter setTTL:(int)self.hopNum timeout:kTracerouteTimeout];
    [self.tracerouter traceroute];
    self.startDate = [NSDate date];
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kTracerouteTimeout target:self selector:@selector(checkTimeout) userInfo:nil repeats:YES];
}
- (void)stopTraceroute {
    [self.tracerouter stop];
    self.tracerouter = nil;
    
    [self.timeoutTimer invalidate];
    self.timeoutTimer = nil;
    
    
    self.callback = nil;
}


#pragma mark -- simplePing delegate
- (void)simplePing:(LGSimplePing *)pinger didStartWithAddress:(NSData *)address {
    [self traceroute];
    NSString *info = @"";
    if(pinger && address) {
        info = [pinger displayAddressForAddress:address];
    }
    self.callback(info, InfoFlagBegin);

}

- (void)simplePing:(LGSimplePing *)pinger didFailWithError:(NSError *)error {
    NSString *errorInfo = [NSString stringWithFormat:@"error: %@",error.description];
    self.callback(errorInfo, InfoFlagEnd);
    [self stopTraceroute];
}

- (void)simplePing:(LGSimplePing *)pinger didReceivePingResponsePacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber srcAddr:(NSString *)srcAddr {
    NSTimeInterval diffTime = [[NSDate date] timeIntervalSinceDate:self.startDate] * 1000;
    NSString *info = [NSString stringWithFormat:@"%ld %0.0lfms %@", (long)self.hopNum, diffTime, srcAddr];
    self.callback(info, InfoFlagEnd);
    
    [self stopTraceroute];
}

- (void)simplePing:(LGSimplePing *)pinger didReceiveUnexpectedPacket:(NSData *)packet {
    NSTimeInterval diffTime = [[NSDate date] timeIntervalSinceDate:self.startDate] * 1000;
    
    NSString *nodeIp = [self.tracerouter srcAddrInIPv4Packet:packet];
    if (self.sendIndex == 0) {
        self.info = [NSString stringWithFormat:@"%ld  %0.0lfms", (long)self.hopNum, diffTime];
        self.currentNodeIp = nodeIp;
    } else {
        self.info = [NSString stringWithFormat:@"%@  %0.0lfms",self.info, diffTime];
    }
    
    if (self.sendIndex == 3) {
        self.info = [NSString stringWithFormat:@"%@ %@",self.info, self.currentNodeIp];
        self.currentNodeIp = @"";
        self.callback(self.info, InfoFlagOn);
        [self.timeoutTimer invalidate];
        self.timeoutTimer = nil;
        
        [self traceroute];
    } else {
        self.sendIndex += 1;
    }
}
@end
