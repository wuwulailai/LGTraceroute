//
//  ViewController.m
//  LGTraceroute
//
//  Created by admin on 2023/5/17.
//

#import "ViewController.h"
#import "traceroute.h"

#import "LGUdpTraceroute.h"
#import "LGTraceroute.h"

@interface ViewController ()
@property(nonatomic, strong) LGUdpTraceroute *traceRoute;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    CGFloat buttonWidth = 100;
    CGFloat buttonHeight = 50;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame =  CGRectMake(self.view.frame.size.width/2 - buttonWidth * 3 / 2 , self.view.frame.size.height/2 - buttonHeight/2, buttonWidth, buttonHeight);
    [button addTarget:self action:@selector(buttonTap) forControlEvents:UIControlEventTouchUpInside];
    [button setTitle:@"UDP路由" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [button setBackgroundColor:[UIColor lightGrayColor]];
    
    [self.view addSubview:button];
    
    UIButton *buttonStop = [UIButton buttonWithType:UIButtonTypeSystem];
    buttonStop.frame =  CGRectMake(self.view.frame.size.width/2 - buttonWidth * 3 / 2 , self.view.frame.size.height/2 + buttonHeight, buttonWidth, buttonHeight);
    [buttonStop addTarget:self action:@selector(buttonStopTap) forControlEvents:UIControlEventTouchUpInside];
    [buttonStop setTitle:@"停止UDP路由" forState:UIControlStateNormal];
    [buttonStop setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [buttonStop setBackgroundColor:[UIColor lightGrayColor]];
    
    [self.view addSubview:buttonStop];
    
    UIButton *icmpButton = [UIButton buttonWithType:UIButtonTypeSystem];
    icmpButton.frame =  CGRectMake(self.view.frame.size.width/2 + buttonWidth/2 , self.view.frame.size.height/2 - buttonHeight/2, buttonWidth, buttonHeight);
    [icmpButton addTarget:self action:@selector(icmpButtonTap) forControlEvents:UIControlEventTouchUpInside];
    [icmpButton setTitle:@"ICMP路由" forState:UIControlStateNormal];
    [icmpButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [icmpButton setBackgroundColor:[UIColor lightGrayColor]];
    [self.view addSubview:icmpButton];
    
    UIButton *icmpButtonStop = [UIButton buttonWithType:UIButtonTypeSystem];
    icmpButtonStop.frame =  CGRectMake(self.view.frame.size.width/2 + buttonWidth/2 , self.view.frame.size.height/2 + buttonHeight, buttonWidth, buttonHeight);
    [icmpButtonStop addTarget:self action:@selector(icmpButtonStopTap) forControlEvents:UIControlEventTouchUpInside];
    [icmpButtonStop setTitle:@"停止ICMP路由" forState:UIControlStateNormal];
    [icmpButtonStop setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [icmpButtonStop setBackgroundColor:[UIColor lightGrayColor]];
    
    [self.view addSubview:icmpButtonStop];
}

- (void)buttonTap {
    NSLog(@"traceRoute call by UDP");
//    char *argv[3] = {0};
//    argv[0] = (char *)malloc(11);
//    argv[1] = (char *)malloc(14);
//    strcpy(argv[0], "traceroute");
//    strcpy(argv[1], "www.baidu.com");
//    traceroute(2, argv);
    self.traceRoute = [LGUdpTraceroute startWithHost:@"www.baidu.com" complete:^(NSString * _Nonnull traceRoute) {
        NSLog(@"traceRoute:%@", traceRoute);
    }];
}

- (void)icmpButtonTap {
    NSLog(@"traceRoute call by icmp");
//    char *argv[3] = {0};
//    argv[0] = (char *)malloc(11);
//    argv[1] = (char *)malloc(14);
//    strcpy(argv[0], "traceroute");
//    strcpy(argv[1], "www.baidu.com");
//    traceroute(2, argv);
//    [LGUdpTraceroute startWithHost:@"www.baidu.com" complete:^(NSString * _Nonnull traceRoute) {
//        NSLog(@"traceRoute:%@", traceRoute);
//    }];
    
    [[LGTraceroute sharedInstance] setupHostName:@"www.baidu.com"];
    [[LGTraceroute sharedInstance] startNetServerAndCallback:^(NSString *info, NSInteger flag) {
        NSLog(@"traceRoute info:%@, flag:%ld", info, (long)flag);
    }];
}


- (void)buttonStopTap {
    NSLog(@"traceRoute call by UDP");
    [self.traceRoute stopUdpTraceroute];
}

- (void)icmpButtonStopTap {
    [[LGTraceroute sharedInstance] stopTraceroute];
}

@end
