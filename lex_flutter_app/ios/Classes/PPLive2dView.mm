//
//  PPLive2dView.m
//  flutter_plugin2
//
//  Created by mac on 2020/11/5.
//

#import "PPLive2dView.h"
#import "LAppLive2DManager.h"
#import "LAppDefine.h"
#import "LModelConfig.h"
@implementation PPLive2dView
{
    LAppLive2DManager *_live2DMgr;
    int modelViewTag;
}

- (void)ensureLive2DManagerWithRect:(CGRect)rect {
    if (_live2DMgr != nullptr) {
        return;
    }

    CGRect targetRect = CGRectIsEmpty(rect) ? self.bounds : rect;
    if (CGRectIsEmpty(targetRect)) {
        targetRect = UIScreen.mainScreen.bounds;
    }

    _live2DMgr = new LAppLive2DManager();
    LAppView *lview = _live2DMgr->createView(targetRect);
    lview.frame = targetRect;
    lview.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _live2DMgr->setModelViewTag(modelViewTag);
    [self addSubview:lview];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    [self ensureLive2DManagerWithRect:rect];
}

-(BOOL)startRandomMotion:(NSString *)name priority:(int)priority{
    [self ensureLive2DManagerWithRect:self.bounds];
    _live2DMgr->startRandomMotion([name UTF8String], priority);
    return true;
}

-(BOOL)startMotion:(NSString *)name no:(int)no priority:(int)priority{
    [self ensureLive2DManagerWithRect:self.bounds];
    _live2DMgr->startMotion([name UTF8String], no, priority);
    return true;
}

-(BOOL)startExpression:(NSString *)name{
    [self ensureLive2DManagerWithRect:self.bounds];
    _live2DMgr->setExpression([name UTF8String]);
    return true;
}

-(void)shakeEvent{
    [self ensureLive2DManagerWithRect:self.bounds];
    _live2DMgr->shakeEvent();
}

- (void)speakMotion:(BOOL)isSpeaking{
    [self ensureLive2DManagerWithRect:self.bounds];
    _live2DMgr->speakMotion(isSpeaking);
}

- (void)setLipSyncValue:(double)value {
    [self ensureLive2DManagerWithRect:self.bounds];
    _live2DMgr->setLipSyncValue((float)value);
}

- (void)setMouthFormValue:(double)value {
    [self ensureLive2DManagerWithRect:self.bounds];
    _live2DMgr->setMouthFormValue((float)value);
}

- (void)setModelJsonPath:(NSString *)modelPath{
    [self ensureLive2DManagerWithRect:self.bounds];
    LModelConfig *modelConfig = [[LModelConfig alloc] init];
    modelConfig.center_x = 0;
    modelConfig.y = 0;
    modelConfig.weight = 2;
    _live2DMgr->addModel([modelPath UTF8String], [@"111111" UTF8String],modelConfig);
    _live2DMgr->setModelViewTag(modelViewTag);
}

//设置模型所在视图Tag
- (void)setModelViewTag:(int)viewTag{
    modelViewTag = viewTag;
}
@end
