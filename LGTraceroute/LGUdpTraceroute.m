//
//  LGUdpTraceroute.m
//  LGTraceroute
//
//  Created by admin on 2023/5/19.
//

#import "LGUdpTraceroute.h"

#include <AssertMacros.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>

#import <netinet/in.h>
#import <netinet/tcp.h>

#import <sys/select.h>
#import <sys/time.h>

#import "LGTracerouteQueue.h"

NSUInteger const  kUpdTracertSendIcmpPacketTimes = 3;   // 对一个中间节点，发送3个udp包
NSUInteger const  kUdpTracertMaxTTL = 30;               // Max 30 hops（最多30跳）

@interface LGUdpTracerouteDetail: NSObject
@property(readonly) NSUInteger hop;    // 第几跳
@property(nonatomic, copy) NSString *routeIP;    // 中间路由IP
@property(nonatomic) NSTimeInterval *durations;   // 存储时间
@property(readonly) NSUInteger sendTimes;        // 每个路由发几个包
@end

@implementation LGUdpTracerouteDetail

- (instancetype)initWithHop:(NSUInteger)hop
                  sendTimes:(NSUInteger)sendTimes {
    
    if(self = [super init]) {
        _routeIP = nil;
        _hop = hop;
        _durations = (NSTimeInterval *)calloc(sendTimes, sizeof(NSTimeInterval));
        _sendTimes = sendTimes;
    }
    
    return self;
}

- (NSString *)description {
    NSMutableString* routeDetail = [[NSMutableString alloc] initWithCapacity:20];
    [routeDetail appendFormat:@"%ld\t", (long)_hop];
    
    if (_routeIP == nil) {
        [routeDetail appendFormat:@" \t"];
    } else {
        [routeDetail appendFormat:@"%@\t", _routeIP];
    }
    for (int i = 0; i < _sendTimes; i++) {
        if (_durations[i] <= 0) {
            [routeDetail appendFormat:@"*\t"];
        } else {
            [routeDetail appendFormat:@"%.3f ms\t", _durations[i] * 1000];
        }
    }
    
    return routeDetail;
}

- (void)dealloc {
    free(_durations);
}

@end

@interface LGUdpTraceroute()
{
    int socket_send;
    int socket_recv;
    struct sockaddr_in remote_addr;
}

@property(nonatomic, copy) NSString *host;
@property(nonatomic, getter=isStopStatus) BOOL stopStatus;
@property(nonatomic) NSInteger maxTtl;
@property(nonatomic, copy) LGUdpTracerouteHandler complete;
@property(nonatomic, strong) NSMutableString *traceDetails;

@end

@implementation LGUdpTraceroute

- (instancetype)initWithHost:(NSString *_Nonnull)host
                      maxTtl:(NSUInteger)maxTtl
                    complete:(LGUdpTracerouteHandler)complete {
    if(self = [super init]) {
        _host = host;
        _maxTtl = maxTtl;
        _complete = complete;
        _stopStatus = NO;

    }
    
    return self;
}

- (void)setupUHostSocketAddressWithHost:(NSString *)host {
    const char *hostAddr = [host UTF8String];
    memset(&remote_addr, 0, sizeof(remote_addr));
    remote_addr.sin_len = sizeof(remote_addr);
    remote_addr.sin_addr.s_addr = inet_addr(hostAddr);
    remote_addr.sin_family = AF_INET;
    remote_addr.sin_port = htons(30006);
    
    if(remote_addr.sin_addr.s_addr == INADDR_NONE) {
        struct hostent *remoteHost = gethostbyname(hostAddr);
        if(remoteHost == NULL || remoteHost->h_addr == NULL) {
            [_traceDetails appendString:@"access DNS error..\n"];
            _complete(_traceDetails);
            
            return;
        }
        
        remote_addr.sin_addr = *(struct in_addr *)remoteHost->h_addr;
        NSString *remoteIp = [NSString stringWithFormat:@"%s", inet_ntoa(remote_addr.sin_addr)];
        [_traceDetails appendString:[NSString stringWithFormat:@"traceroute to %@ \n", remoteIp]];
    }
    
    socket_recv = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    socket_send = socket(AF_INET, SOCK_DGRAM, 0);
    
}

- (void)sendAndRec {
    _traceDetails = [NSMutableString stringWithString:@"\n"];
    [self setupUHostSocketAddressWithHost:_host];
    
    int ttl = 1;
    in_addr_t ipAddr = 0;
    static NSUInteger conuntinueUnreachableRoutes = 0;
    
    // 如果连续5个路由节点无响应，则终止traceroute
    do {
        int t  = setsockopt(socket_send, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl));
        if (t < 0) {
            NSLog(@"error %s\n",strerror(t));
        }
        LGUdpTracerouteDetail *trace = [self sendData:ttl ip:&ipAddr];
        if (trace.routeIP == nil) {
            conuntinueUnreachableRoutes++;
        }else{
            conuntinueUnreachableRoutes = 0;
        }
        
    } while (++ttl <= _maxTtl && ipAddr != remote_addr.sin_addr.s_addr && !_stopStatus && conuntinueUnreachableRoutes < 5);
    
    close(socket_send);
    close(socket_recv);
    if(!_stopStatus) {
        _stopStatus = YES;
    }
    
    [_traceDetails appendString:@"udp traceroute complete ... \n"];
    _complete(_traceDetails);
}

- (LGUdpTracerouteDetail *)sendData:(int)ttl ip:(in_addr_t *)ipOut {
    
    int err = 0;
    struct sockaddr_in storageAddr;
    socklen_t n = sizeof(struct sockaddr);
    static char msg[24] = {0};
    char buff[100];
    
    LGUdpTracerouteDetail *trace = [[LGUdpTracerouteDetail alloc] initWithHop:ttl sendTimes:kUpdTracertSendIcmpPacketTimes];
    
    for (int i = 0; i < 3; i++) {
        NSDate* startTime = [NSDate date];
        ssize_t sent = sendto(socket_send, msg, sizeof(msg), 0, (struct sockaddr*)&remote_addr, sizeof(struct sockaddr));
        if (sent != sizeof(msg)) {
            NSLog(@"error %s",strerror(err));
            break;
        }
        
        struct timeval tv;
        tv.tv_sec = 3;
        tv.tv_usec = 0;
        
        fd_set readfds;
        FD_ZERO(&readfds);  // 初始化套接字集合（清空套接字集合） ,将readfds清零使集合中不含任何fd
        FD_SET(socket_recv,&readfds); // 将readfds加入set集合
        
        /*
         https://zhidao.baidu.com/question/315963155.html
         在编程的过程中，经常会遇到许多阻塞的函数，好像read和网络编程时使用的recv, recvfrom函数都是阻塞的函数，当函数不能成功执行的时候，程序就会一直阻塞在这里，无法执行下面的代码。这是就需要用到非阻塞的编程方式，使用selcet函数就可以实现非阻塞编程。
         selcet函数是一个轮循函数，即当循环询问文件节点，可设置超时时间，超时时间到了就跳过代码继续往下执行。
         Select的函数格式：
         int select(int maxfdp,fd_set *readfds,fd_set *writefds,fd_set *errorfds,struct timeval*timeout);
         select函数有5个参数
         第一个是所有文件节点的最大值加1,如果我有三个文件节点1、4、6,那第一个参数就为7（6+1）
         第二个是可读文件节点集，类型为fd_set。通过FD_ZERO(&readfd);初始化节点集；然后通过FD_SET(fd, &readfd);把需要监听是否可读的节点加入节点集
         第三个是可写文件节点集中，类型为fd_set。操作方法和第二个参数一样。
         第四个参数是检查节点错误集。
         第五个参数是超时参数，类型为struct timeval，然后可以设置超时时间，分别可设置秒timeout.tv_sec和微秒timeout.tv_usec。
         */
        select(socket_recv + 1, &readfds, NULL, NULL,&tv);
        
        if (FD_ISSET(socket_recv,&readfds) > 0) {
            NSLog(@"traceRoute start recv data from route");
            ssize_t res = recvfrom(socket_recv, buff, sizeof(buff), 0, (struct sockaddr*)&storageAddr, &n);
            if (res < 0) {
                err = errno;
                NSLog(@"recv error %s\n",strerror(err));
                break;
            } else {
                NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
                char ipAddr[16] = {0}; // 存放ip地址
                inet_ntop(AF_INET, &storageAddr.sin_addr.s_addr, ipAddr, sizeof(ipAddr));
                *ipOut = storageAddr.sin_addr.s_addr;
                NSString *routeIP = [NSString stringWithFormat:@"%s",ipAddr];
                NSLog(@"traceRoute routeIP:%@ remoteAddr:%s", routeIP, inet_ntoa(remote_addr.sin_addr));
                trace.routeIP = routeIP;
                trace.durations[i] = duration;
            }
        }

    }
//    NSLog(@"%@",trace);
    
    [_traceDetails appendString:trace.description];
    [_traceDetails appendString:@"\n"];
    _complete(_traceDetails);
    
    return trace;
}

+ (instancetype)startWithHost:(NSString *_Nonnull)host
                     complete:(LGUdpTracerouteHandler _Nonnull)complete {
    LGUdpTraceroute *udpTraceroute = [[LGUdpTraceroute alloc] initWithHost:host maxTtl:kUdpTracertMaxTTL complete:complete];
    
    [LGTracerouteQueue LGNetAsync:^{
        [udpTraceroute sendAndRec];
    }];
    
    return udpTraceroute;
}

+ (instancetype)startWithHost:(NSString *_Nonnull)host
                       maxTtl:(NSUInteger)maxTtl
                     complete:(LGUdpTracerouteHandler _Nonnull)complete {
    LGUdpTraceroute *udpTraceroute = [[LGUdpTraceroute alloc] initWithHost:host maxTtl:maxTtl complete:complete];
    [LGTracerouteQueue LGNetAsync:^{
        [udpTraceroute sendAndRec];
    }];
    
    return udpTraceroute;
}

- (BOOL)isDoingUdpTraceroute {
    return !_stopStatus;
}

- (void)stopUdpTraceroute {
    _stopStatus = YES;
}

@end
