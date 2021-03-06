//
//  CHWindowController.m
//  CamHolderApp
//
//  Created by Heiko Behrens on 31.01.12.
//  Copyright (c) 2012 BeamApp. All rights reserved.
//

#import "CHWindowController.h"
#import <QTKit/QTKit.h>
#import "CHGeometryUtils.h"

@implementation CHWindowController

@synthesize isFullscreen;
@synthesize captureSession = _captureSession;
@synthesize videoDevice = _videoDevice;

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    _originalWindowMask = self.window.styleMask;
    
    // workaround: an initially hidden rect somehow does not appear at runtime
    [zoomRectView.superview addSubview:zoomRectView positioned:NSWindowAbove relativeTo:captureView];
    zoomRectView.frame = NSZeroRect;
    
    [captureDevicesCombobox removeAllItems];
	for (QTCaptureDevice* d in self.document.captureDevices) {
		[captureDevicesCombobox addItemWithObjectValue: [d localizedDisplayName]];
	}
    
    _updateTimer = [[NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(reflectCameraStateInUI) userInfo:nil repeats:YES] retain];
}

-(void)windowWillClose:(NSNotification *)notification {
    captureView.captureSession = nil;
    captureView.delegate = nil;
    [_captureSession release];
    _captureSession = nil;
    
    [_updateTimer release];
}

#pragma mark - Preview Delegate and Handling

-(NSPoint)convertPointToDocumentSpace:(NSPoint)viewSpacePoint {
    NSPoint result = viewSpacePoint;

    if(self.document.rotation == 90) {
        result = NSMakePoint(result.y, 1-result.x);
    } else if(self.document.rotation == 180) {
        result = NSMakePoint(1-result.x, 1-result.y);
    } else if(self.document.rotation == 270) {
        result = NSMakePoint(1-result.y, result.x);
    }
    
    result.x = self.document.isMirroredHorizontally ? 1-result.x : result.x;
    result.y = self.document.isMirroredVertically   ? 1-result.y : result.y;

    if(!NSEqualRects(NSZeroRect, self.document.normalizedCroppingRect)){
        NSRect ncr = self.document.normalizedCroppingRect;
        result = NSMakePoint(ncr.origin.x + ncr.size.width * result.x, 
                             ncr.origin.y + ncr.size.height * result.y);
    }
    
    
    return result;
}

-(void)viewWillSelectRect:(QTCaptureView *)view {
	[zoomRectView setHidden:NO];
	[zoomRectView setFrame:NSZeroRect];
}

-(void)view:(QTCaptureView *)view mightSelectRectInViewCoordinates:(NSRect)rect {
	[zoomRectView setFrame: rect];
}

-(void)view:(QTCaptureView *)view didSelectRect:(NSRect)rect {
	[zoomRectView setHidden:YES];
    
    NSPoint p1 = [self convertPointToDocumentSpace:rect.origin];
    NSPoint p2 = [self convertPointToDocumentSpace:NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y + rect.size.height)];
    
    self.document.normalizedCroppingRect = NSRectFromPoints(p1, p2);
}


- (CIImage *)view:(QTCaptureView *)view willDisplayImage:(CIImage*)image {
    static NSDate* lastDate;
    static int frames = 0;
    frames++;
    
    NSTimeInterval elapsed = lastDate ? -[lastDate timeIntervalSinceNow] : 1;
    if(elapsed >= 1) {
        self.FPSLabel.stringValue = [NSString stringWithFormat:@"%d FPS", (int)(frames/elapsed)];
        frames = 0;
        [lastDate release];
        lastDate = [[NSDate date] retain];
    };
    
	if(!NSEqualRects(NSZeroRect, self.document.normalizedCroppingRect)) {
		float w = image.extent.size.width;
		float h = image.extent.size.height;
		CGRect transformedCrop = NSRectToCGRect(self.document.normalizedCroppingRect);
		transformedCrop.origin.x *= w;
		transformedCrop.origin.y *= h;
		transformedCrop.size.width *= w;
		transformedCrop.size.height *= h;
		
		image = [image imageByCroppingToRect:transformedCrop];
	}
	
	float scaleX = self.document.isMirroredHorizontally ? -1 : 1;
	float scaleY = self.document.isMirroredVertically ? -1 : 1;
	
	return [image
			imageByApplyingTransform:CGAffineTransformScale(
															CGAffineTransformMakeRotation(self.document.rotation * M_PI /180.0),
															scaleX, scaleY)
			];
}

-(void)connectToVideoDevice:(QTCaptureDevice*)device {
    if(device == nil || device == _videoDevice)
        return;
    
	[_captureSession release];
	
//	[[NSUserDefaults standardUserDefaults] setObject: [device uniqueID] forKey:@"deviceId"];
    
	_videoDevice = device;
	[_videoDevice open:nil];
	
	if( !_videoDevice ) {
		NSLog( @"No video input device" );
		exit( 1 );
	}
	
	_videoInput = [[QTCaptureDeviceInput alloc] initWithDevice:_videoDevice];
	
	_captureSession = [[QTCaptureSession alloc] init];
	[_captureSession addInput:_videoInput error:nil];	
	[_captureSession startRunning];
	
	[captureView setCaptureSession:_captureSession];
	[captureView setVideoPreviewConnection:[[captureView availableVideoPreviewConnections] objectAtIndex:0]];
	captureView.delegate = self;
	captureView.canSelectRect = YES;
	
	// Setting a lower resolution for the CaptureOutput here, since otherwise QTCaptureView
	// pulls full-res frames from the camera, which is slow. This is just for cosmetics.
	
	// NOTE: for Logitech QuickCam Pro 9000 Webcam everythin >=1280 or > 720  puts camera into widescreen
	NSDictionary * pixelBufferAttr = [NSDictionary dictionaryWithObjectsAndKeys:
									  [NSNumber numberWithInt:1280], kCVPixelBufferWidthKey,
									  [NSNumber numberWithInt:720], kCVPixelBufferHeightKey, nil];
    // NOTE this doesn't have to be object at index 0, but for LifeCam it is: 
	[[[_captureSession outputs] objectAtIndex:0] setPixelBufferAttributes:pixelBufferAttr];
    
    [captureDevicesCombobox selectItemAtIndex: [self.document.captureDevices indexOfObject:device]];
}

#pragma mark - Property Overloads

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if(object == self.document && [@"activeCaptureDevice" isEqualToString:keyPath]) {
        [self connectToVideoDevice:self.document.activeCaptureDevice];
    } else
    if(object == self.document && [@"showsInspector" isEqualToString:keyPath]) {
        [self setShowsInspector:self.document.showsInspector];
    } else
    if(object == self.document && [@"contentSize" isEqualToString:keyPath]) {
        [self setContentSize:self.document.contentSize];
    } else
        
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


-(CHDocument *)document {
    return super.document;
}

-(void)setDocument:(CHDocument *)document {
    //NSLog(@"setDocument: %@", document);
    [self.document removeObserver:self forKeyPath:@"activeCaptureDevice"];
    [self.document removeObserver:self forKeyPath:@"showsInspector"];
    [self.document removeObserver:self forKeyPath:@"contentSize"];

    [super setDocument:document];
    if(document) {
        [self.document addObserver:self forKeyPath:@"activeCaptureDevice" options:NSKeyValueObservingOptionNew context:nil];
        [self.document addObserver:self forKeyPath:@"showsInspector" options:NSKeyValueObservingOptionNew context:nil];
        [self.document addObserver:self forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:nil];
        
        [self setContentSize:self.document.contentSize];
        self.showsInspector = self.document.showsInspector;
        [self connectToVideoDevice:self.document.activeCaptureDevice];
        
        if(document.activeCaptureDevice == nil)
            [document performSelector:@selector(tryToHaveActiveCaptureDevice) withObject:nil afterDelay:0.1];
    }
}

-(void)captureDeviceChanged:(id)sender {
    self.document.activeCaptureDevice = [self.document.captureDevices objectAtIndex:[captureDevicesCombobox indexOfSelectedItem]];
}

-(CHDraggableWindow*)window {
    return super.window;
}

-(void)setWindow:(CHDraggableWindow *)window {
    [super setWindow:window];
}

-(void)reflectCameraStateInUI {
    if(self.document) {
        [self.document readCameraValuesIntoProperties];
    }
}

#pragma mark - view options

- (void)toggleDebugViews:(id)sender {
    self.FPSLabel.hidden = !self.FPSLabel.isHidden;
}

- (void)tryToReduceRunningCaptureSessions {
    [NSApplication.sharedApplication.delegate performSelector:@selector(tryToReduceRunningCaptureSessions)];
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
    [self tryToReduceRunningCaptureSessions];
}

- (void)windowDidDeminiaturize:(NSNotification *)notification {
    [self tryToReduceRunningCaptureSessions];
}

-(void)windowDidResize:(NSNotification *)notification {
//- (void)windowDidEndLiveResize:(NSNotification *)notification {    
    // TODO: listen to property
    if(self.isFullscreen || _ignoreWindowDidResize)
        return;

    _ignoreWindowDidResize = YES;
    self.document.contentSize = captureView.frame.size;
    _ignoreWindowDidResize = NO;
}

-(void)setContentSize:(NSSize)size {
    if(NSEqualSizes(size, captureView.frame.size))
        return;
    
    NSRect r = self.isFullscreen ? _nonFullScreenFrame : self.window.frame;
    NSRect rr = self.isFullscreen ? _nonFullScreenFrame : captureView.frame;
    NSSize delta = NSMakeSize((size.width - rr.size.width)/2, (size.height - rr.size.height)/2);
    r = NSInsetRect(r, -delta.width, -delta.height);
    
    if(self.isFullscreen) {
        _nonFullScreenFrame = r;
    } else {
        [self.window.animator setFrame:r display:YES];
    }
}

-(BOOL)showsInspector {
    return ![inspectorView isHidden];
}

-(void)setShowsInspector:(BOOL)value {
    if(self.showsInspector == value)
        return;
    [inspectorView setHidden:!value];
    
    BOOL oldIgnoreWindowDidResize = _ignoreWindowDidResize;
    _ignoreWindowDidResize = YES;
    self.window.styleMask = value ? _originalWindowMask : NSBorderlessWindowMask;
    NSRect r = self.window.frame;
    float widthDelta = inspectorView.frame.size.width * (value ? 1 : -1);
    r.size.width += widthDelta;
    [self.window setFrame: r display:YES];
    
    r = [(NSView*)self.window.contentView frame];
    if(value)r.size.width -= widthDelta;
    captureView.frame = r;
    self.window.isDraggable = !value && !self.isFullscreen;
    captureView.canSelectRect = value && !self.isFullscreen;
    _ignoreWindowDidResize = oldIgnoreWindowDidResize;;
}

-(void)displayAsFullScreenInRect:(NSRect)frame {
    isFullscreen = YES;
    if(self.document.showsInspector)
        [self setShowsInspector:NO];
    
    _nonFullScreenFrame = self.window.frame;
    
    [[NSApplication sharedApplication] setPresentationOptions:(NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar)];
    self.window.hasShadow = NO;
 
    // workaround to animate zoom (needs another even in main loop since setting styleMask prevents animation otherwise)
    _fullscreenFrame = frame;

    self.window.isDraggable = NO;
    [self.window.animator setFrame:_fullscreenFrame display:YES];
    captureView.hiddenCursor = YES;

}

-(void)clearIgnoreWindowDidResize {
}

-(BOOL)canBeFullscreen {
    return !self.window.isMiniaturized;
}

-(void)setIsFullscreen:(BOOL)isFullscreen_ {
    isFullscreen = isFullscreen_;
    if(isFullscreen) {
        [self displayAsFullScreenInRect: self.window.screen.frame];
    } else {
        _ignoreWindowDidResize = YES;
        
        [self.window.animator setFrame:_nonFullScreenFrame display:YES];
        // poor man's completionHandler for <10.7
        // uses window's frame as semaphore
        [self performSelector:@selector(finishSetIsFullscreenNo) withObject:nil afterDelay:[[NSAnimationContext currentContext] duration]];
        captureView.hiddenCursor = NO;
    }
}


-(void)finishSetIsFullscreenNo {
    if(!NSEqualRects(self.window.frame, _nonFullScreenFrame)) {
        [self performSelector:@selector(finishSetIsFullscreenNo) withObject:nil afterDelay:0.1];
        return;
    }
    _ignoreWindowDidResize = NO;
    self.window.hasShadow = YES;
    [[NSApplication sharedApplication] setPresentationOptions:NSApplicationPresentationDefault];
    [self setShowsInspector:self.document.showsInspector];
    self.window.isDraggable = !self.document.showsInspector;
}

-(NSComparisonResult)horizontalCompare:(CHWindowController*)other {
    return self.window.frame.origin.x < other.window.frame.origin.x ? NSOrderedAscending : NSOrderedDescending;
}

-(NSComparisonResult)verticalCompare:(CHWindowController*)other {
    return self.window.frame.origin.y < other.window.frame.origin.y ? NSOrderedAscending : NSOrderedDescending;
}


@end
