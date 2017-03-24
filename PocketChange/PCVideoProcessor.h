//
//  PCVideoProcessor.h
//  PocketChange
//
//  Created by Bryce Hammond on 7/22/12.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@class PCVideoProcessor;

@protocol PCVideoProcessorDelegate <NSObject>

- (CGSize)presentationLayerViewSizeForVideoProcessor:(PCVideoProcessor *)processor;
- (NSString *)presentationLayerVideoGravityForVideoProcessor:(PCVideoProcessor *)processor;
- (void)videoProcessor:(PCVideoProcessor *)processor didFindCoinsInRects:(NSArray *)rects;

@end

@interface PCVideoProcessor : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, assign) float fps;
@property (nonatomic, weak) id<PCVideoProcessorDelegate> delegate;
@property (nonatomic, readonly) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, assign) BOOL processGrayscale;

@end
