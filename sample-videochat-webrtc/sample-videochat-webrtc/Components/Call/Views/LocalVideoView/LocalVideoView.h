//
//  LocalVideoView.h
//  sample-videochat-webrtc
//
//  Created by Injoit on 2/25/19.
//  Copyright © 2019 Quickblox. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LocalVideoView : UIView
- (instancetype)initWithPreviewlayer:(AVCaptureVideoPreviewLayer *)layer;
@end
