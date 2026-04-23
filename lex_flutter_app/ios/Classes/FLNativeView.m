#import "FLNativeView.h"
#import "PPLive2dView.h"

@implementation FLNativeViewFactory {
  NSObject<FlutterBinaryMessenger>* _messenger;
}

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
  self = [super init];
  if (self) {
    _messenger = messenger;
  }
  return self;
}

- (NSObject<FlutterPlatformView>*)createWithFrame:(CGRect)frame
                                   viewIdentifier:(int64_t)viewId
                                        arguments:(id _Nullable)args {
  return [[FLNativeView alloc] initWithFrame:frame
                              viewIdentifier:viewId
                                   arguments:args
                             binaryMessenger:_messenger];
}

@end

@implementation FLNativeView {
  PPLive2dView *_view;
}

- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
              binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
  if (self = [super init]) {
    _view = [[PPLive2dView alloc] init];
    FlutterMethodChannel* l2dChannel = [FlutterMethodChannel
                                        methodChannelWithName:[NSString stringWithFormat:@"plugins.felix.angelov/textview_%lld", viewId]
                                        binaryMessenger:messenger];
    [l2dChannel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
      [self handleL2DMethodCall:call result:result];
    }];
  }
  return self;
}

- (UIView*)view {
  return _view;
}

- (void)handleL2DMethodCall:(FlutterMethodCall* )call result:(FlutterResult)result {
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
    result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
  } else if ([@"l2d_StartRandomMotion" isEqualToString:call.method] ||
             [@"l2d_startRandomMotion" isEqualToString:call.method]) {
    NSString *group = call.arguments[@"group"] ?: call.arguments[@"name"];
    [_view startRandomMotion:group priority:[call.arguments[@"priority"] intValue]];
    result(nil);
  } else if ([@"l2d_StartExpression" isEqualToString:call.method] ||
             [@"l2d_setExpression" isEqualToString:call.method]) {
    NSString *expressionId = call.arguments[@"id"] ?: call.arguments[@"name"];
    [_view startExpression:expressionId];
    result(nil);
  } else if ([@"l2d_StartMotion" isEqualToString:call.method] ||
             [@"l2d_startMotion" isEqualToString:call.method]) {
    NSString *group = call.arguments[@"group"] ?: call.arguments[@"name"];
    NSNumber *number = call.arguments[@"number"] ?: call.arguments[@"no"] ?: @(0);
    [_view startMotion:group no:[number intValue] priority:[call.arguments[@"priority"] intValue]];
    result(nil);
  } else if ([@"shakeEvent" isEqualToString:call.method] ||
             [@"l2d_setRandomExpression" isEqualToString:call.method]) {
    [_view shakeEvent];
    result(nil);
  } else if ([@"l2d_SpeakMotion" isEqualToString:call.method]) {
    [_view speakMotion:[call.arguments[@"isSpeaking"] boolValue]];
    result(nil);
  } else if ([@"l2d_setLipSync" isEqualToString:call.method]) {
    double value = 0.0;
    if ([call.arguments isKindOfClass:[NSNumber class]]) {
      value = [((NSNumber *)call.arguments) doubleValue];
    } else if ([call.arguments isKindOfClass:[NSDictionary class]]) {
      value = [call.arguments[@"value"] doubleValue];
    }
    [_view setLipSyncValue:value];
    result(nil);
  } else if ([@"l2d_setMouthForm" isEqualToString:call.method]) {
    double value = 0.0;
    if ([call.arguments isKindOfClass:[NSNumber class]]) {
      value = [((NSNumber *)call.arguments) doubleValue];
    } else if ([call.arguments isKindOfClass:[NSDictionary class]]) {
      value = [call.arguments[@"value"] doubleValue];
    }
    [_view setMouthFormValue:value];
    result(nil);
  } else if ([@"l2d_setModelJsonPath" isEqualToString:call.method]) {
    [_view setModelJsonPath:call.arguments[@"path"]];
    result(nil);
  } else if ([@"l2d_setBackgroundPath" isEqualToString:call.method]) {
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

@end
