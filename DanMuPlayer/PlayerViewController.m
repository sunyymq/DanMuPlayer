//
//  PlayerViewController.m
//  tvosPlayer
//
//  Created by zfu on 2017/4/9.
//  Copyright © 2017年 zfu. All rights reserved.
//

#import "PlayerViewController.h"
#import <SGPlayer/SGPlayer.h>
#import "StrokeUILabel.h"
#import "SiriRemoteGestureRecognizer.h"

@implementation MMVideoSegment
@synthesize url;
@synthesize duration;
-(MMVideoSegment*)init {
    self = [super init];
    self.url = nil;
    self.duration = -1.0f;
    return self;
}
-(MMVideoSegment*)initWithURL:(NSString*)url_ duration:(CGFloat)duration_ {
    self = [super init];
    self.url = url_;
    self.duration = duration_;
    return self;
}
+(MMVideoSegment*)videoSegmentWithURL:(NSString*)url duration:(CGFloat)duration {
    return [[MMVideoSegment alloc] initWithURL:url duration:duration];
}
@end

@implementation MMVideoSources
@synthesize segments = _segments;
@synthesize duration = _duration;
-(id)init {
    self = [super init];
    _segments = [NSMutableArray array];
    return self;
}

-(NSInteger)count {
    return [_segments count];
}
-(void)clear {
    [_segments removeAllObjects];
    [self updateDuration];
}
-(void)addSegmentWithURL: (NSString*)url duration:(CGFloat)duration {
    MMVideoSegment *seg = [MMVideoSegment videoSegmentWithURL:url duration:duration];
    [_segments addObject:seg];
    [self updateDuration];
}
-(void)updateDuration {
    CGFloat duration = 0.0f;
    for (MMVideoSegment *seg in _segments) {
        duration += seg.duration;
    }
    _duration = duration;
}
+(MMVideoSources*)sourceFromURL:(NSString*)url {
    MMVideoSources *source = [[MMVideoSources alloc] init];
    if (url.length>=6 && [[url substringWithRange:NSMakeRange(0, 6)] isEqualToString:@"edl://"]) {
        NSString *content = [url substringWithRange:NSMakeRange(6, url.length-6)];
        NSArray<NSString*> *items = [content componentsSeparatedByString:@";"];
        for (NSString *item in items) {
            NSArray<NSString*> *infos = [item componentsSeparatedByString:@"%"];
            if ([infos count]==3) {
                NSLog(@"duration %@ url %@", [infos objectAtIndex:1], [infos objectAtIndex:2]);
            } else {
                NSLog(@"error parse for %@", item);
            }
        }
    } else {
        [source addSegmentWithURL:url duration:0.0f];
    }
    return source;
}
-(void)dump {
    NSLog(@"----------dump segments--------------");
    NSLog(@"duration    : %.2f", _duration);
    NSLog(@"segment num : %ld", [_segments count]);
    int i=0;
    for (MMVideoSegment *seg in _segments) {
        NSLog(@"segment [%d] duration %.2f url %@", i, seg.duration, seg.url);
        i++;
    }
    NSLog(@"----------dump segments--------------");
}
@end

@interface PlayerViewController ()
{
    UIView *hudLayer;
    //UIVisualEffectView *hudLayerBg;
    UIProgressView *_progress;
    StrokeUILabel *_title;
    StrokeUILabel *_currentTime;
    StrokeUILabel *_leftTime;
    StrokeUILabel *_statLabel;
    StrokeUILabel *_timeLabel;
    UITapGestureRecognizer *playPauseRecognizer;
    UITapGestureRecognizer *menuRecognizer;
    UITapGestureRecognizer *leftArrowRecognizer;
    UITapGestureRecognizer *rightArrowRecognizer;
    UITapGestureRecognizer *upArrowRecognizer;
    UITapGestureRecognizer *downArrowRecognizer;
    SiriRemoteGestureRecognizer *siriRemoteRecognizer;
    UIPanGestureRecognizer *panRecognizer;
    UIGestureRecognizer *touchRecognizer;
    UIActivityIndicatorView *loadingIndicator;
    UIImageView *pointImageView;
    UIImageView *pauseImageView;
    StrokeUILabel *pauseTimeLabel;
    StrokeUILabel *_pointTime;
    BOOL _isPlaying;
    CGPoint indicatorStartPoint;
    CGFloat oldProgress;
    CADisplayLink *displayLink;
    CGRect oriPauseImageRect;
    CGRect oriPauseTimeRect;
    BOOL hudInited;
    CGPoint lastLocation;
    BOOL _hudInHidenProgress;
    CGFloat _resumeTime;
    NSTimer *_hideDelayTimer;
    StrokeUILabel *subTitle;
    MMVideoSources *videoSource;
    DanMuLayer *danmu;
}

@property (nonatomic, readwrite, assign) PlayerState playerState;
@property (nonatomic, readwrite, assign) CGFloat targetProgress;
@property (nonatomic, readwrite, strong) NSSet<UIGestureRecognizer*> *simultaneousGestureRecognizers;
@property (nonatomic, readwrite, assign) BOOL isHudHidden;
@end

@implementation PlayerViewController
@synthesize player = _player;
@synthesize playerState;
@synthesize targetProgress;
@synthesize isHudHidden;

-(id)init {
    self = [super init];
    self.delegate = nil;
    hudInited = NO;
    _hudInHidenProgress = NO;
    lastLocation = CGPointMake(0.0, 0.0);
    _resumeTime = 0.0;
    self.isHudHidden = NO;
    return self;
}

-(void)seekToTime:(CGFloat)time {
    [_player seekToTime:time];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"view did load");
    oldProgress = 0;
    _player = [SGPlayer player];
    [self.player registerPlayerNotificationTarget:self
                                      stateAction:@selector(stateAction:)
                                   progressAction:@selector(progressAction:)
                                   playableAction:@selector(playableAction:)
                                      errorAction:@selector(errorAction:)];
    [self.player setViewTapAction:^(SGPlayer * _Nonnull player, SGPLFView * _Nonnull view) {
        NSLog(@"player display view did click!");
    }];
    [self.view insertSubview:self.player.view atIndex:0];
    
    self.playerState = PS_INIT;
    self.targetProgress = -1;
    displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateProgress)];
    displayLink.paused = YES;
    //[displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

-(void)playVideo:(NSString*)url
       withTitle:(NSString*)title
         withImg:(NSString*)img
  withDesciption:(NSString*)desc
         options:(NSMutableDictionary*)options
             mp4:(BOOL)mp4
  withResumeTime: (CGFloat)resumeTime {
    NSLog(@"playVideo %@ resumeTime %.2f", url, resumeTime);
    videoSource = [MMVideoSources sourceFromURL:url];
    [videoSource dump];
    _title.text = title;
    if (false) {
        static NSURL * normalVideo = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            normalVideo = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"i-see-fire" ofType:@"mp4"]];
        });
        [self.player replaceVideoWithURL:normalVideo options: options mp4: mp4];
    } else {
        _resumeTime = resumeTime;
        NSURL *video = [NSURL URLWithString:url];
        if (mp4) {
            [self.player replaceVideoWithURL:video options:options mp4:mp4];
        } else {
            [self.player replaceVideoWithURL:video options: options mp4:mp4];
        }
    }
}

- (void)updateProgress
{
    [self updatePointTime:self.player.progress];
    [danmu updateFrame];
    if (self.delegate) {
        [self.delegate timeDidChangedHD:self.player.progress];
    }
}

- (void)updatePointTime: (CGFloat)time
{
    //NSLog(@"time %f", time);
    {
        if (pointImageView && self.player.duration !=0) {
            CGFloat x = indicatorStartPoint.x + _progress.frame.size.width * (time/self.player.duration);
            CGRect frame = pointImageView.frame;
            CGRect pauseframe = pauseImageView.frame;
            CGRect pauseTimeFrame = pauseTimeLabel.frame;
            frame.origin.x = x;
            pauseframe.origin.x = x;
            pauseTimeFrame.origin.x = x-78;
            pointImageView.frame = frame;
            pauseImageView.frame = pauseframe;
            pauseTimeLabel.frame = pauseTimeFrame;
            _pointTime.text = [self timeToStr:time];
            if (x > (80+48) && x < (80+_progress.frame.size.width-50)) {
                _pointTime.hidden = NO;
                _currentTime.hidden = YES;
                CGRect pointTimeFrame = _pointTime.frame;
                pointTimeFrame.origin.x = x-77;
                _pointTime.frame = pointTimeFrame;
                //pointImageView.frame = frame;
            }
            if (x < (80+48)) {
                _currentTime.hidden = NO;
                _pointTime.hidden = YES;
            }
            if (x > _progress.frame.size.width+80-180) {
                _leftTime.hidden = YES;
            } else {
                _leftTime.hidden = NO;
            }
        }
    }
}

- (void) startUpdateProgress {
    displayLink.paused = NO;
}

- (void) stopUpdateProgress {
    displayLink.paused = YES;
}

- (void)initHud
{
    NSLog(@"initHud");
    CGSize size = [self.view bounds].size;
    
    danmu = [[DanMuLayer alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:danmu];
    
    subTitle = [[StrokeUILabel alloc] init];
    subTitle.textColor = [UIColor whiteColor];
    subTitle.strokeColor = [UIColor blackColor];
    subTitle.frame = CGRectMake(0, size.height-130, size.width, 80);
    subTitle.font = [UIFont fontWithName:@"Menlo" size:65];
    subTitle.textAlignment = NSTextAlignmentCenter;
    subTitle.text = @"";
    [self.view addSubview:subTitle];
    
    hudLayer = [[UIView alloc] init];
    hudLayer.frame = CGRectMake(0, size.height-200, size.width, 200);
    
    loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    CGSize indicatorSize = loadingIndicator.frame.size;
    loadingIndicator.frame = CGRectMake(size.width/2-indicatorSize.width/2,
                                        size.height/2-indicatorSize.height/2,
                                        indicatorSize.width,
                                        indicatorSize.height);
    [loadingIndicator setHidden:NO];
    [loadingIndicator startAnimating];
    
    _timeLabel = [[StrokeUILabel alloc] initWithFrame:CGRectMake(size.width-300, 80, 200, 40)];
    _timeLabel.text = @"";
    _timeLabel.font = [UIFont fontWithName:@"Menlo" size:50];
    _timeLabel.textColor = [UIColor whiteColor];
    
    [self.view addSubview:hudLayer];
    [self.view addSubview:loadingIndicator];
    [self.view addSubview:_timeLabel];
    
    _progress = [[UIProgressView alloc] init];
    _progress.frame = CGRectMake(80, 110, size.width-160, 10);
    _progress.progress = 0.0f;
    //_progress.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1];
    _progress.tintColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:0.8];
    [hudLayer addSubview:_progress];
    [_progress setProgress:0];
    _title = [[StrokeUILabel alloc] init];
    _title.text = @"";
    _title.frame = CGRectMake(80, 60, size.width-360, 20);
    _title.textColor = [UIColor whiteColor];
    [hudLayer addSubview:_title];
    
    _currentTime = [[StrokeUILabel alloc] init];
    _currentTime.textColor = [UIColor whiteColor];
    _currentTime.frame = CGRectMake(80, 135, 160, 40);
    _currentTime.text = @"";
    _currentTime.font = [UIFont fontWithName:@"Menlo" size:34];
    _currentTime.textAlignment = NSTextAlignmentLeft;
    [hudLayer addSubview:_currentTime];
    
    _pointTime = [[StrokeUILabel alloc] init];
    _pointTime.textColor = [UIColor whiteColor];
    _pointTime.frame = CGRectMake(80, 135, 160, 40);
    _pointTime.text = @"";
    _pointTime.font = [UIFont fontWithName:@"Menlo" size:34];
    _pointTime.textAlignment = NSTextAlignmentCenter;
    _pointTime.hidden = YES;
    [hudLayer addSubview:_pointTime];
    
    _leftTime = [[StrokeUILabel alloc] init];
    _leftTime.textColor = [UIColor whiteColor];
    _leftTime.frame = CGRectMake(size.width-160-80, 135, 160, 40);
    _leftTime.text = @"";
    _leftTime.font = [UIFont fontWithName:@"Menlo" size:34];
    _leftTime.textAlignment = NSTextAlignmentRight;
    [hudLayer addSubview:_leftTime];
    
    pointImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"indicator.png"]];
    pointImageView.frame = CGRectMake(80, 110, 2, 10);
    indicatorStartPoint = pointImageView.frame.origin;
    [hudLayer addSubview:pointImageView];
    
    pauseImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"indicator.png"]];
    pauseImageView.frame = CGRectMake(80, 80, 2, 40);
    indicatorStartPoint = pauseImageView.frame.origin;
    [hudLayer addSubview:pauseImageView];
    pauseImageView.hidden = YES;
    
    pauseTimeLabel = [[StrokeUILabel alloc] init];
    pauseTimeLabel.textColor = [UIColor whiteColor];
    pauseTimeLabel.frame = CGRectMake(80, 42, 160, 40);
    pauseTimeLabel.text = @"";
    pauseTimeLabel.font = [UIFont fontWithName:@"Menlo" size:34];
    pauseTimeLabel.textAlignment = NSTextAlignmentCenter;
    [hudLayer addSubview:pauseTimeLabel];
    pauseTimeLabel.hidden = YES;
    
    [self setupRecognizers];
    
    _isPlaying = NO;
}

- (void) setupRecognizers {
    playPauseRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapPlayPause:)];
    playPauseRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
    [self.view addGestureRecognizer:playPauseRecognizer];
    
    menuRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapMenu:)];
    menuRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];
    [self.view addGestureRecognizer:menuRecognizer];
    
    //leftArrowRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapLeftArrow:)];
    //leftArrowRecognizer.allowedPressTypes = @[@(UIPressTypeLeftArrow)];
    //[self.view addGestureRecognizer:leftArrowRecognizer];
    
    //rightArrowRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapRightArrow:)];
    //rightArrowRecognizer.allowedPressTypes = @[@(UIPressTypeRightArrow)];
    //[self.view addGestureRecognizer:rightArrowRecognizer];
    
    upArrowRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapUpArrow:)];
    upArrowRecognizer.allowedPressTypes = @[@(UIPressTypeUpArrow)];
    [self.view addGestureRecognizer:upArrowRecognizer];
    
    downArrowRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapDownArrow:)];
    downArrowRecognizer.allowedPressTypes = @[@(UIPressTypeDownArrow)];
    [self.view addGestureRecognizer:downArrowRecognizer];
    
    panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self.view addGestureRecognizer:panRecognizer];
    
    siriRemoteRecognizer = [[SiriRemoteGestureRecognizer alloc] initWithTarget:self action:@selector(siriTouch:)];
    siriRemoteRecognizer.delegate = self;
    [self.view addGestureRecognizer:siriRemoteRecognizer];
    
    NSMutableSet<UIGestureRecognizer*> *simultaneousGestureRecognizers = [NSMutableSet set];
    [simultaneousGestureRecognizers addObject:panRecognizer];
    [simultaneousGestureRecognizers addObject:siriRemoteRecognizer];
    self.simultaneousGestureRecognizers = simultaneousGestureRecognizers;
}

#pragma mark - gesture recognizer delegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return [self.simultaneousGestureRecognizers containsObject:gestureRecognizer];
}

- (void)tapPlayPause:(UITapGestureRecognizer*)sender {
    NSLog(@"taped playpause");
    if (_hudInHidenProgress) return;
    if (_isPlaying) {
        _isPlaying=!_isPlaying;
        [self.player pause];
        pauseTimeLabel.text = [self timeToStr: self.player.progress];
        pauseTimeLabel.hidden = NO;
        pauseImageView.hidden = NO;
        _title.hidden = YES;
        _pointTime.textColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0];
    } else {
        if (self.targetProgress != -1) {
            NSLog(@"seek to progress %f", self.targetProgress);
            [self updatePointTime:self.targetProgress];
            [self.player seekToTime:self.targetProgress completeHandler:^(BOOL finished) {
                self.targetProgress = -1;
                [self.player play];
            }];
        } else {
            [self.player play];
        }
        _isPlaying=!_isPlaying;
        pauseTimeLabel.hidden = YES;
        pauseImageView.hidden = YES;
        _title.hidden = NO;
        _pointTime.textColor = UIColor.whiteColor;
    }
}

- (void)tapMenu:(UITapGestureRecognizer*)sender {
    if (_hudInHidenProgress) return;
    NSLog(@"taped Menu key");
    if (self.playerState == PS_PAUSED) {
        _isPlaying=!_isPlaying;
        pauseTimeLabel.hidden = YES;
        pauseImageView.hidden = YES;
        _title.hidden = NO;
        _pointTime.textColor = UIColor.whiteColor;
        [self.player play];
        self.targetProgress = -1;
    } else {
        [self stop];
    }
}

- (void)tapLeftArrow:(UITapGestureRecognizer*)sender {
    if (_hudInHidenProgress) return;
    NSLog(@"taped leftArrow");
    if (self.playerState == PS_PLAYING) {
        CGFloat progress = self.player.progress - 5.0f;
        CGFloat target = progress>=0 ? progress: 0;
        NSLog(@"seek to time %f", progress);
        if (self.player.seekEnable) {
            [self.player pause];
            [self.player seekToTime:target completeHandler:^(BOOL finished) {
                [self.player play];
            }];
        }
    } else if (self.playerState == PS_PAUSED) {
        oriPauseImageRect = pauseImageView.frame;
        oriPauseTimeRect = pauseTimeLabel.frame;
        oriPauseImageRect.origin.x -= _progress.frame.size.width*5/100;
        if (oriPauseImageRect.origin.x < _progress.frame.origin.x) {
            oriPauseImageRect.origin.x = _progress.frame.origin.x;
        } else if (oriPauseImageRect.origin.x > _progress.frame.origin.x + _progress.frame.size.width) {
            oriPauseImageRect.origin.x = (_progress.frame.origin.x + _progress.frame.size.width);
        }
        oriPauseTimeRect.origin.x = oriPauseImageRect.origin.x - 78;
        
        CGFloat targetTime = self.player.duration * (oriPauseImageRect.origin.x - _progress.frame.origin.x) / _progress.frame.size.width;
        self.targetProgress = targetTime;
        pauseTimeLabel.text = [self timeToStr:targetTime];
        pauseImageView.frame = oriPauseImageRect;
        pauseTimeLabel.frame = oriPauseTimeRect;
    }
}

- (void)tapRightArrow:(UITapGestureRecognizer*)sender {
    if (_hudInHidenProgress) return;
    NSLog(@"taped rightArrow");
    if (self.playerState == PS_PLAYING) {
        CGFloat progress = self.player.progress + 5.0f;
        CGFloat duration = self.player.duration;
        CGFloat target = progress>duration ? duration: progress;
        NSLog(@"seek to time %f", progress);
        if (self.player.seekEnable) {
            [self.player pause];
            [self.player seekToTime:target completeHandler:^(BOOL finished) {
                [self.player play];
            }];
        }
    } else if (self.playerState == PS_PAUSED) {
        oriPauseImageRect = pauseImageView.frame;
        oriPauseTimeRect = pauseTimeLabel.frame;
        oriPauseImageRect.origin.x += _progress.frame.size.width*5/100;
        if (oriPauseImageRect.origin.x < _progress.frame.origin.x) {
            oriPauseImageRect.origin.x = _progress.frame.origin.x;
        } else if (oriPauseImageRect.origin.x > _progress.frame.origin.x + _progress.frame.size.width) {
            oriPauseImageRect.origin.x = (_progress.frame.origin.x + _progress.frame.size.width);
        }
        oriPauseTimeRect.origin.x = oriPauseImageRect.origin.x - 78;
        
        CGFloat targetTime = self.player.duration * (oriPauseImageRect.origin.x - _progress.frame.origin.x) / _progress.frame.size.width;
        self.targetProgress = targetTime;
        pauseTimeLabel.text = [self timeToStr:targetTime];
        pauseImageView.frame = oriPauseImageRect;
        pauseTimeLabel.frame = oriPauseTimeRect;
    }
}

- (void)tapUpArrow:(UITapGestureRecognizer*)sender {
    if (_hudInHidenProgress) return;
    NSLog(@"taped upArrow");
}

- (void)tapDownArrow:(UITapGestureRecognizer*)sender {
    if (_hudInHidenProgress) return;
    NSLog(@"taped downArrow");
}

- (void)siriTouch:(SiriRemoteGestureRecognizer*)sender {
//    NSLog(@"taped siriRemote state: %ld %@ location %ld %@",
//          (long)sender.state, sender.stateName, (long)sender.touchLocation, sender.touchLocationName);
    NSLog(@"taped siriRemote state: %@ click %d", sender.stateName, sender.isClick);
    if (sender.state == UIGestureRecognizerStateEnded && sender.isClick) {
        //NSLog(@"taped siriRemote, location %@", sender.touchLocationName);
        NSLog(@"taped click action");
        if (sender.touchLocation == MMSiriRemoteTouchLocationCenter) {
            [self tapSelect];
        } else if (sender.touchLocation == MMSiriRemoteTouchLocationLeft) {
            [self tapLeftArrow:nil];
        } else if (sender.touchLocation == MMSiriRemoteTouchLocationRight) {
            [self tapRightArrow:nil];
        }
    } else if ((sender.state == UIGestureRecognizerStateEnded
                || sender.state == UIGestureRecognizerStateCancelled)
               && !sender.isClick) {
        NSLog(@"taped not click action");
        if (self.isHudHidden) {
            [self setHidenHud:NO withDelay:NO];
            [self setHidenHud:YES withDelay:YES];
        } else {
            [self setHidenHud:YES withDelay:NO];
        }
    }
}

- (void)tapSelect {
    if (_hudInHidenProgress) return;
    if (self.playerState == PS_PAUSED) {
        if (self.targetProgress != -1) {
            NSLog(@"seek to progress %f", self.targetProgress);
            [self updatePointTime:self.targetProgress];
            [self.player seekToTime:self.targetProgress completeHandler:^(BOOL finished) {
                self.targetProgress = -1;
                [self.player play];
            }];
        } else {
            [self.player play];
        }
        _isPlaying=!_isPlaying;
        pauseTimeLabel.hidden = YES;
        pauseImageView.hidden = YES;
        _title.hidden = NO;
        _pointTime.textColor = UIColor.whiteColor;
    } else if (self.playerState == PS_PLAYING) {
        _isPlaying=!_isPlaying;
        [self.player pause];
        pauseTimeLabel.text = [self timeToStr: self.player.progress];
        pauseTimeLabel.hidden = NO;
        pauseImageView.hidden = NO;
        _title.hidden = YES;
        _pointTime.textColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0];
    }
}

- (void)updateTargetProgress: (float)progress {
    
}

- (void)pan:(UIPanGestureRecognizer*)sender {
    if (_hudInHidenProgress) return;
    //CGPoint location = [sender translationInView:self.view];
    CGPoint v = [sender velocityInView:self.view];
    {//show logs here
        NSString *stateStr = @"";
        if (sender.state == UIGestureRecognizerStateBegan) {
            stateStr = @"Began";
        } else if (sender.state == UIGestureRecognizerStateChanged) {
            stateStr = @"Changed";
        } else if (sender.state == UIGestureRecognizerStateEnded) {
            stateStr = @"Ended";
        } else if (sender.state == UIGestureRecognizerStateCancelled) {
            stateStr = @"Cancelled";
        } else if (sender.state == UIGestureRecognizerStateFailed) {
            stateStr = @"Failed";
        } else if (sender.state == UIGestureRecognizerStatePossible) {
            stateStr = @"Possible";
        } else if (sender.state == UIGestureRecognizerStateRecognized) {
            stateStr = @"Recognized";
        } else {
            stateStr = @"Unknown";
        }
        //NSLog(@"taped pan event state %@ point %f %f velocity %f %f", stateStr, location.x, location.y, v.x, v.y);
    }
    if (self.playerState != PS_PAUSED) {
        if (self.playerState == PS_PLAYING) {
            if (sender.state == UIGestureRecognizerStateBegan
                || sender.state == UIGestureRecognizerStateChanged) {
                [self setHidenHud:NO withDelay:YES];
            } else if (sender.state == UIGestureRecognizerStateEnded) {
                [self setHidenHud:YES withDelay:YES];
            }
        }
        return;
    }
    if (sender.state == UIGestureRecognizerStateBegan) {
        //NSLog(@"Began");
        //save the init position
        oriPauseImageRect = pauseImageView.frame;
        oriPauseTimeRect = pauseTimeLabel.frame;
        self.targetProgress = -1;
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        if (!self.player.seekEnable) return;
        //NSLog(@"Changed");
        oriPauseImageRect.origin.x += v.x / 300.0f;
        oriPauseTimeRect.origin.x += v.x / 300.0f;
        if (oriPauseImageRect.origin.x < _progress.frame.origin.x) {
            oriPauseImageRect.origin.x = _progress.frame.origin.x;
        } else if (oriPauseImageRect.origin.x > _progress.frame.origin.x + _progress.frame.size.width) {
            oriPauseImageRect.origin.x = (_progress.frame.origin.x + _progress.frame.size.width);
        }
        oriPauseTimeRect.origin.x = oriPauseImageRect.origin.x - 78;
        
        CGFloat targetTime = self.player.duration * (oriPauseImageRect.origin.x - _progress.frame.origin.x) / _progress.frame.size.width;
        self.targetProgress = targetTime;
        pauseTimeLabel.text = [self timeToStr:targetTime];
        pauseImageView.frame = oriPauseImageRect;
        pauseTimeLabel.frame = oriPauseTimeRect;
    } else if (sender.state == UIGestureRecognizerStateEnded) {
        //NSLog(@"End");
    } else if (sender.state == UIGestureRecognizerStateCancelled) {
        NSLog(@"Calcelled");
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.player.view.frame = self.view.bounds;
    if (hudInited == NO) {
        [self initHud];
        hudInited = YES;
    }
}

- (void)progressAction:(NSNotification *)notification
{
    SGProgress * progress = [SGProgress progressFromUserInfo:notification.userInfo];
    //NSLog(@"progress: %f %f %f", progress.current, self.player.playableTime, self.player.playableBufferInterval);
    if (fabs(self.player.duration)<0.001 && progress.current > 0.001) {
        NSDate *date = [NSDate date];
        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
        NSInteger hour = [components hour];
        NSInteger minute = [components minute];
        //NSInteger seconds = [components second];
        _timeLabel.text = [NSString stringWithFormat:@"%02ld:%02ld", hour, minute];
        
        _currentTime.text = [NSString stringWithFormat:@"%02ld:%02d", hour, (minute>30)?30:0];
        _pointTime.text = [NSString stringWithFormat:@"%02ld:%02ld", hour, minute];
        _leftTime.text = [NSString stringWithFormat:@"%02ld:%02d", (minute>30)?hour+1:hour, (minute>30)?0:30];
    } else {
        _currentTime.text = [self timeToStr:progress.current];
        _pointTime.text = [self timeToStr:progress.current];
        _leftTime.text = [self timeToStr: (self.player.duration-progress.current)];
    }
    [self.delegate timeDidChanged:progress.current];
}

- (void) setHidenHud: (BOOL) hide withDelay:(BOOL)delay {
    //NSLog(@"delay set Hiden Hud %d _hudInHidenProgress %@", hide, (_hudInHidenProgress)?@"true":@"false");
    if (_hudInHidenProgress) {
        return;
    }
    if (hide) {
        [hudLayer setAlpha:1.0f];
        [_timeLabel setAlpha:1.0f];
        if (_hideDelayTimer) {
            [_hideDelayTimer invalidate];
            _hideDelayTimer = nil;
        }
        if (delay) {
            _hideDelayTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
                _hudInHidenProgress = YES;
                [UIView animateWithDuration:1.0f animations:^{
                    [hudLayer setAlpha:0.0f];
                    [_timeLabel setAlpha:0.0f];
                } completion:^(BOOL finished) {
                    [hudLayer setHidden:YES];
                    [_timeLabel setHidden:YES];
                    _hudInHidenProgress = NO;
                    self.isHudHidden = YES;
                }];
            }];
        } else {
            _hudInHidenProgress = YES;
            [UIView animateWithDuration:1.0f animations:^{
                [hudLayer setAlpha:0.0f];
                [_timeLabel setAlpha:0.0f];
            } completion:^(BOOL finished) {
                [hudLayer setHidden:YES];
                [_timeLabel setHidden:YES];
                _hudInHidenProgress = NO;
                self.isHudHidden = YES;
            }];
        }
    } else {
        if (_hideDelayTimer) {
            [_hideDelayTimer invalidate];
            _hideDelayTimer = nil;
        }
        [_timeLabel setAlpha:1.0f];
        [hudLayer setAlpha:1.0f];
        [hudLayer setHidden:NO];
        [_timeLabel setHidden:NO];
        self.isHudHidden = NO;
    }
}

- (void)playableAction:(NSNotification *)notification
{
    SGPlayable * playable = [SGPlayable playableFromUserInfo:notification.userInfo];
    [_progress setProgress:playable.percent];
    //NSLog(@"playable time : %f", playable.current);
}

- (void)errorAction:(NSNotification *)notification
{
    SGError * error = [SGError errorFromUserInfo:notification.userInfo];
    NSLog(@"player did error : %@", error.error);
    UIAlertController* errorAlert = [UIAlertController alertControllerWithTitle:@"出错了"
                                                                        message:error.error.localizedDescription
                                                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *stopWatching = [UIAlertAction actionWithTitle:@"关闭"
                                                           style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
                                                               [self stop];
                                                           }];
    [errorAlert addAction:stopWatching];
    [self presentViewController:errorAlert animated:YES completion:^{
    }];
}

- (void)notificationState:(PlayerState)state {
    if (self.delegate) {
        [self.delegate playStateDidChanged:state];
    }
}

- (void)stateAction:(NSNotification *)notification
{
    SGState * state = [SGState stateFromUserInfo:notification.userInfo];
    NSString * text;
    switch (state.current) {
        case SGPlayerStateNone:
            text = @"None";
            [self stopUpdateProgress];
            self.playerState = PS_INIT;
            [self notificationState:PS_INIT];
            break;
        case SGPlayerStateBuffering:
            text = @"Buffering...";
            [loadingIndicator setHidden:NO];
            [loadingIndicator startAnimating];
            [self notificationState:PS_LOADING];
            [self stopUpdateProgress];
            break;
        case SGPlayerStateReadyToPlay:
            text = @"Prepare";
            //self.totalTimeLabel.text = [self timeStringFromSeconds:self.player.duration];
            _leftTime.text = [self timeToStr:self.player.duration];
            [loadingIndicator setHidden:YES];
            [loadingIndicator stopAnimating];
            self.playerState = PS_INIT;
            [self notificationState:PS_INIT];
            if (_resumeTime > 0.0f && self.player.duration > 0.0f) {
                NSString *msg = [NSString stringWithFormat:@"上次观看到 %@ 共 %@ 是否继续观看？",
                                 [self timeToStr: _resumeTime],
                                 [self timeToStr: self.player.duration]];
                UIAlertController* continueWatchingAlert = [UIAlertController alertControllerWithTitle:@"视频准备就绪" message:msg preferredStyle:UIAlertControllerStyleActionSheet];
                UIAlertAction *continueWatching = [UIAlertAction actionWithTitle:@"继续观看"
                                                                           style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
                    NSLog(@"continue play from %.2f", _resumeTime);
                    [self.player seekToTime:_resumeTime];
                    [self.player play];
                }];
                UIAlertAction *startWatching = [UIAlertAction actionWithTitle:@"重新观看"
                                                                        style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
                    _resumeTime = 0.0f;
                    [self.player play];
                }];
                UIAlertAction *stopWatching = [UIAlertAction actionWithTitle:@"放弃观看"
                                                                       style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
                                                                           [self stop];
                }];
                [continueWatchingAlert addAction:continueWatching];
                [continueWatchingAlert addAction:startWatching];
                [continueWatchingAlert addAction:stopWatching];
                [self presentViewController:continueWatchingAlert animated:YES completion:nil];
            } else {
                _resumeTime = 0.0f;
                [self.player play];
            }
            break;
        case SGPlayerStatePlaying:
            text = @"Playing";
            [loadingIndicator setHidden:YES];
            [loadingIndicator stopAnimating];
            [self setHidenHud:YES withDelay:YES];
            _isPlaying = YES;
            self.playerState = PS_PLAYING;
            [self notificationState:PS_PLAYING];
            [self startUpdateProgress];
            break;
        case SGPlayerStateSuspend:
            text = @"Suspend";
            [self setHidenHud:NO withDelay:YES];
            _isPlaying = NO;
            self.playerState = PS_PAUSED;
            [self notificationState:PS_PAUSED];
            [self stopUpdateProgress];
            break;
        case SGPlayerStateFinished:
            text = @"Finished";
            [self setHidenHud:NO withDelay:YES];
            _isPlaying = NO;
            self.playerState = PS_FINISH;
            [self notificationState:PS_FINISH];
            [self stopUpdateProgress];
            [self stop];
            break;
        case SGPlayerStateFailed:
            text = @"Error";
            self.playerState = PS_ERROR;
            [self notificationState:PS_ERROR];
            [self stopUpdateProgress];
            break;
    }
    //self.stateLabel.text = text;
    NSLog(@"stateAction: %@", text);
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (NSString*)timeToStr:(int)time {
    int min = time/60;
    int sec = time-min*60;
    return [NSString stringWithFormat:@"%02d:%02d", min, sec];
}

-(void)play {
    [_player play];
}

-(void)pause {
    [_player pause];
}
-(void)stop {
    [_player pause];
    displayLink.paused = YES;
    [self notificationState:PS_FINISH];
    [_player removePlayerNotificationTarget:self];
    [_player replaceEmpty];
    [self dismissViewControllerAnimated:YES completion:^{
        NSLog(@"dismiss");
    }];
}

-(void)addDanMu:(NSString*)content
      withStyle:(DanmuStyle)style
      withColor:(UIColor*)color
withStrokeColor:(UIColor*)bgcolor
   withFontSize:(CGFloat)fontSize {
    [danmu addDanMu:content
               withStyle:style
               withColor:color
         withStrokeColor:bgcolor
            withFontSize:fontSize];
}
-(void)setSubTitle:(NSString*)subTitle_ {
    subTitle.text = subTitle_;
}
@end
