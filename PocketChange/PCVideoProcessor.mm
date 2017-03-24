//
//  PCVideoProcessor.m
//  PocketChange
//
//  Created by Bryce Hammond on 7/22/12.
//

#import "PCVideoProcessor.h"

@interface PCVideoProcessor ()
{
    // Fps calculation
    CMTimeValue _lastFrameTimestamp;
    float *_frameTimes;
    int _frameTimesIndex;
    int _framesToAverage;
    float _captureQueueFps;
}

@end

@implementation PCVideoProcessor

// Number of frames to average for FPS calculation
#define kFrameTimeBufferSize 5

@synthesize fps = _fps;
@synthesize videoOutput = _videoOutput;
@synthesize processGrayscale = _processGrayscale;
@synthesize delegate;

- (id)init
{
    self = [super init];
    if(self)
    {
        _lastFrameTimestamp = 0;
        _frameTimesIndex = 0;
        _captureQueueFps = 0.0f;
        _fps = 0.0;
        self.processGrayscale = YES;
        
        // Create frame time circular buffer for calculating averaged fps
        _frameTimes = (float*)malloc(sizeof(float) * kFrameTimeBufferSize);

        [self setupVideoOutput];
    }
    
    return self;
}

- (void)setupVideoOutput
{
    if(nil == self.videoOutput)
    {
        // Create and configure device output
        _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    
        dispatch_queue_t processingQueue = dispatch_queue_create("cameraQueue", NULL); 
        [self.videoOutput setSampleBufferDelegate:self queue:processingQueue];
        dispatch_release(processingQueue); 
    
        self.videoOutput.alwaysDiscardsLateVideoFrames = YES; 
    
        // For grayscale mode, the luminance channel from the YUV fromat is used
        // For color mode, BGRA format is used
        OSType format = kCVPixelFormatType_32BGRA;
    
        // Check YUV format is available before selecting it (iPhone 3 does not support it)
        if (self.processGrayscale && 
            [self.videoOutput.availableVideoCVPixelFormatTypes containsObject:
                      [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]]) 
        {
            format = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
        }
    
        self.videoOutput.videoSettings = 
            [NSDictionary dictionaryWithObject:
                [NSNumber numberWithUnsignedInt:format]
                                forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    }
}
#pragma mark -
#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate delegate methods

// AVCaptureVideoDataOutputSampleBufferDelegate delegate method called when a video frame is available
//
// This method is called on the video capture GCD queue. A cv::Mat is created from the frame data and
// passed on for processing with OpenCV.
- (void)captureOutput:(AVCaptureOutput *)captureOutput 
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer 
       fromConnection:(AVCaptureConnection *)connection
{
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
    CGRect videoRect = CGRectMake(0.0f, 0.0f, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
    AVCaptureVideoOrientation videoOrientation = [[[captureOutput connections] objectAtIndex:0] videoOrientation];
    
    if (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        // For grayscale mode, the luminance channel of the YUV data is used
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        void *baseaddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        
        cv::Mat mat(videoRect.size.height, videoRect.size.width, CV_8UC1, baseaddress, 0);
        
        [self processFrame:mat videoRect:videoRect videoOrientation:videoOrientation];
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0); 
    }
    else if (format == kCVPixelFormatType_32BGRA) {
        // For color mode a 4-channel cv::Mat is created from the BGRA data
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        void *baseaddress = CVPixelBufferGetBaseAddress(pixelBuffer);
        
        cv::Mat mat(videoRect.size.height, videoRect.size.width, CV_8UC4, baseaddress, 0);
        
        [self processFrame:mat videoRect:videoRect videoOrientation:videoOrientation];
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);    
    }
    else {
        NSLog(@"Unsupported video format");
    }
    
    // Update FPS calculation
    CMTime presentationTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
    
    if (_lastFrameTimestamp == 0) {
        _lastFrameTimestamp = presentationTime.value;
        _framesToAverage = 1;
    }
    else {
        float frameTime = (float)(presentationTime.value - _lastFrameTimestamp) / presentationTime.timescale;
        _lastFrameTimestamp = presentationTime.value;
        
        _frameTimes[_frameTimesIndex++] = frameTime;
        
        if (_frameTimesIndex >= kFrameTimeBufferSize) {
            _frameTimesIndex = 0;
        }
        
        float totalFrameTime = 0.0f;
        for (int i = 0; i < _framesToAverage; i++) {
            totalFrameTime += _frameTimes[i];
        }
        
        float averageFrameTime = totalFrameTime / _framesToAverage;
        float fps = 1.0f / averageFrameTime;
        
        if (fabsf(fps - _captureQueueFps) > 0.1f) {
            _captureQueueFps = fps;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setFps:fps];
            });    
        }
        
        _framesToAverage++;
        if (_framesToAverage > kFrameTimeBufferSize) {
            _framesToAverage = kFrameTimeBufferSize;
        }
    }
    
}

#pragma mark -
#pragma mark Processing methods

// Override this method to process the video frame with OpenCV
//
// Note that this method is called on the video capture GCD queue. Use dispatch_sync or dispatch_async to update UI
// from the main queue.
//
// mat: The frame as an OpenCV::Mat object. The matrix will have 1 channel for grayscale frames and 4 channels for
//      BGRA frames. (Use -[VideoCaptureViewController setGrayscale:])
// rect: A CGRect describing the video frame dimensions
// orientation: Will generally by AVCaptureVideoOrientationLandscapeRight for the back camera and
//              AVCaptureVideoOrientationLandscapeRight for the front camera
//
- (void)processFrame:(cv::Mat &)mat videoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)orientation
{
    // Shrink video frame to 320X240
    cv::resize(mat, mat, cv::Size(), 0.5f, 0.5f, CV_INTER_LINEAR);
    rect.size.width /= 2.0f;
    rect.size.height /= 2.0f;
    
    // Rotate video frame by 90deg to portrait by combining a transpose and a flip
    // Note that AVCaptureVideoDataOutput connection does NOT support hardware-accelerated
    // rotation and mirroring via videoOrientation and setVideoMirrored properties so we
    // need to do the rotation in software here.
    cv::transpose(mat, mat);
    CGFloat temp = rect.size.width;
    rect.size.width = rect.size.height;
    rect.size.height = temp;
    
    if (orientation == AVCaptureVideoOrientationLandscapeRight)
    {
        // flip around y axis for back camera
        cv::flip(mat, mat, 1);
    }
    else {
        // Front camera output needs to be mirrored to match preview layer so no flip is required here
    }
    
    orientation = AVCaptureVideoOrientationPortrait;
    
    //Reduce the noise a bit
    cv::GaussianBlur(mat, mat, cv::Size(9, 9), 2, 2 );
    
    std::vector<cv::Vec3f> circles;
    
    /// Apply the Hough Transform to find the circles
    cv::HoughCircles( mat, circles, CV_HOUGH_GRADIENT, 1, mat.rows/16, 80, 40, 0, 0 );
    
    if(circles.size() > 0)
    {
    
        // Create transform to convert from video frame coordinate space to view coordinate space
        CGAffineTransform coordinateTransform = [self affineTransformForVideoFrame:rect orientation:orientation];
        
        NSMutableArray *coinRects = [[NSMutableArray alloc] initWithCapacity:circles.size()];
   
        for( size_t i = 0; i < circles.size(); i++ )
        {
            int radius = cvRound(circles[i][2]);
            int frameWidth = radius * 2;
            
            int centerX = cvRound(circles[i][0]);
            int centerY = cvRound(circles[i][1]);
            
            CGRect coinRect = CGRectMake(centerX - radius, centerY - radius, 
                                         frameWidth, frameWidth);

            coinRect = CGRectApplyAffineTransform(coinRect, coordinateTransform);
            
            [coinRects addObject:[NSValue valueWithCGRect:coinRect]];
        
            NSLog(@"origin (%i, %i) radius %i",centerX, centerY, radius);
        }
        
        // Dispatch updating of coin markers to main queue
        dispatch_sync(dispatch_get_main_queue(), ^{
            [delegate videoProcessor:self didFindCoinsInRects:coinRects];  
        });
    }
}

#pragma mark -
#pragma mark Geometry methods

// Create an affine transform for converting CGPoints and CGRects from the video frame coordinate space to the
// preview layer coordinate space. Usage:
//
// CGPoint viewPoint = CGPointApplyAffineTransform(videoPoint, transform);
// CGRect viewRect = CGRectApplyAffineTransform(videoRect, transform);
//
// Use CGAffineTransformInvert to create an inverse transform for converting from the view cooridinate space to
// the video frame coordinate space.
//
// videoFrame: a rect describing the dimensions of the video frame
// video orientation: the video orientation
//
// Returns an affine transform
//
- (CGAffineTransform)affineTransformForVideoFrame:(CGRect)videoFrame orientation:(AVCaptureVideoOrientation)videoOrientation
{
    CGSize viewSize = [delegate presentationLayerViewSizeForVideoProcessor:self];
    NSString *videoGravity = [delegate presentationLayerVideoGravityForVideoProcessor:self];
    CGFloat widthScale = 1.0f;
    CGFloat heightScale = 1.0f;
    
    // Move origin to center so rotation and scale are applied correctly
    CGAffineTransform t = CGAffineTransformMakeTranslation(-videoFrame.size.width / 2.0f, -videoFrame.size.height / 2.0f);
    
    switch (videoOrientation) {
        case AVCaptureVideoOrientationPortrait:
            widthScale = viewSize.width / videoFrame.size.width;
            heightScale = viewSize.height / videoFrame.size.height;
            break;
            
        case AVCaptureVideoOrientationPortraitUpsideDown:
            t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(M_PI));
            widthScale = viewSize.width / videoFrame.size.width;
            heightScale = viewSize.height / videoFrame.size.height;
            break;
            
        case AVCaptureVideoOrientationLandscapeRight:
            t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(M_PI_2));
            widthScale = viewSize.width / videoFrame.size.height;
            heightScale = viewSize.height / videoFrame.size.width;
            break;
            
        case AVCaptureVideoOrientationLandscapeLeft:
            t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(-M_PI_2));
            widthScale = viewSize.width / videoFrame.size.height;
            heightScale = viewSize.height / videoFrame.size.width;
            break;
    }
    
    // Adjust scaling to match video gravity mode of video preview
    if (videoGravity == AVLayerVideoGravityResizeAspect) {
        heightScale = MIN(heightScale, widthScale);
        widthScale = heightScale;
    }
    else if (videoGravity == AVLayerVideoGravityResizeAspectFill) {
        heightScale = MAX(heightScale, widthScale);
        widthScale = heightScale;
    }
    
    // Apply the scaling
    t = CGAffineTransformConcat(t, CGAffineTransformMakeScale(widthScale, heightScale));
    
    // Move origin back from center
    t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(viewSize.width / 2.0f, viewSize.height / 2.0f));
    
    return t;
}



@end
