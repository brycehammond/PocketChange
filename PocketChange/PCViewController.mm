//
//  PCViewController.m
//  PocketChange
//
//  Created by Bryce Hammond on 7/22/12.
//

#import "PCViewController.h"
#import "PCDetectionView.h"

@interface PCViewController ()
{
    int _camera;
    NSString *_qualityPreset;
}

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureDevice *captureDevice;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *videoPreviewLayer;
@property (nonatomic, strong) PCVideoProcessor *videoProcessor;
@property (nonatomic, strong) NSMutableArray *coinViews;

- (BOOL)createCaptureSessionForCamera:(NSInteger)camera qualityPreset:(NSString *)qualityPreset grayscale:(BOOL)grayscale;

@end

@implementation PCViewController

@synthesize captureSession = _captureSession;
@synthesize captureDevice = _captureDevice;
@synthesize videoPreviewLayer = _videoPreviewLayer;
@synthesize videoProcessor = _videoProcessor;
@synthesize coinViews = _coinViews;

- (void)viewDidLoad
{
    [super viewDidLoad];
    _qualityPreset = AVCaptureSessionPresetMedium;
	[self createCaptureSessionForCamera:_camera qualityPreset:_qualityPreset grayscale:YES];
    [_captureSession startRunning];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

// Sets up the video capture session for the specified camera, quality and grayscale mode
//
//
// camera: -1 for default, 0 for back camera, 1 for front camera
// qualityPreset: [AVCaptureSession sessionPreset] value
// grayscale: YES to capture grayscale frames, NO to capture RGBA frames
//
- (BOOL)createCaptureSessionForCamera:(NSInteger)camera qualityPreset:(NSString *)qualityPreset grayscale:(BOOL)grayscale
{
	
    // Set up AV capture
    NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    
    if ([devices count] == 0) {
        NSLog(@"No video capture devices found");
        return NO;
    }
    
    if (camera == -1) {
        _camera = -1;
        _captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    else if (camera >= 0 && camera < [devices count]) {
        _camera = camera;
        self.captureDevice = [devices objectAtIndex:camera];
    }
    else {
        _camera = -1;
        self.captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        NSLog(@"Camera number out of range. Using default camera");
    }
    
    // Create the capture session
    _captureSession = [[AVCaptureSession alloc] init];
    _captureSession.sessionPreset = (qualityPreset)? qualityPreset : AVCaptureSessionPresetMedium;
    
    // Create device input
    NSError *error = nil;
    AVCaptureDeviceInput *input = [[AVCaptureDeviceInput alloc] initWithDevice:_captureDevice error:&error];
    
    self.videoProcessor = [[PCVideoProcessor alloc] init];
    self.videoProcessor.delegate = self;
    
    
    // Connect up inputs and outputs
    if ([_captureSession canAddInput:input]) {
        [_captureSession addInput:input];
    }
    
    if ([self.captureSession canAddOutput:self.videoProcessor.videoOutput]) {
        [_captureSession addOutput:self.videoProcessor.videoOutput];
    }
    
    // Create the preview layer
    self.videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
    self.videoPreviewLayer.frame = self.view.bounds;
    self.videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:_videoPreviewLayer atIndex:0];
    
    return YES;
}

#pragma mark -
#pragma mark PCVideoProcessorDelgate methods

- (CGSize)presentationLayerViewSizeForVideoProcessor:(PCVideoProcessor *)processor
{
    return self.view.bounds.size;
}

- (NSString *)presentationLayerVideoGravityForVideoProcessor:(PCVideoProcessor *)processor
{
    return _videoPreviewLayer.videoGravity;
}

- (void)videoProcessor:(PCVideoProcessor *)processor didFindCoinsInRects:(NSArray *)rects
{
    if(rects.count > 0)
    {
    
        //clear any existing rects and add the new views
        [self.coinViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        self.coinViews = [[NSMutableArray alloc] init];
        for(NSValue *rectValue in rects)
        {
            PCDetectionView *coinView = [[PCDetectionView alloc] initWithFrame:rectValue.CGRectValue];
            [self.coinViews addObject:coinView];
            [self.view addSubview:coinView];
        }
    }
}

@end
