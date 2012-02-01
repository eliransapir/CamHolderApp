//
//  chaDocument.m
//  CamHolderApp
//
//  Created by Heiko Behrens on 31.01.12.
//  Copyright (c) 2012 BeamApp. All rights reserved.
//

#import "CHDocument.h"
#import "CHWindowController.h"

@implementation CHDocument

@synthesize isAutoExposureActive, exposureTimeFactor, isAutoFocusActive, focusFactor, activeCaptureDevice, 
    normalizedCroppingRect, isMirroredHorizontally, isMirroredVertically, rotation,
    showsInspector, contentSize;

- (id)init
{
    self = [super init];
    if (self) {
        isAutoExposureActive = YES;
        isAutoFocusActive = YES;
        showsInspector = YES;
    }
    return self;
}

-(void)dealloc {
    [_cameraControl release];
    [super dealloc];
}

-(void)makeWindowControllers {
    CHWindowController *controller = [[[CHWindowController alloc] initWithWindowNibName:@"CHDocument"] autorelease];
    [self addWindowController:controller];
}

-(void)addToDictionary:(NSMutableDictionary*)dictionary valuesOfKeys:(NSString*)keys, ...  {
    va_list args;
    va_start(args, keys);
    for (NSString *arg = keys; arg != nil; arg = va_arg(args, NSString*)){
        [dictionary setObject:[self valueForKey:arg] forKey:arg];
    }
    va_end(args);    
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    [self addToDictionary:values valuesOfKeys:
     @"isAutoExposureActive", @"exposureTimeFactor", @"isAutoFocusActive", @"focusFactor", 
     @"isMirroredHorizontally", @"isMirroredVertically", @"rotation",
     @"showsInspector",
     nil];
    [values setObject:NSStringFromRect(self.normalizedCroppingRect) forKey:@"normalizedCroppingRect"];
    [values setObject:NSStringFromSize(self.contentSize) forKey:@"contentSize"];
    [values setObject:self.activeCaptureDevice.uniqueID forKey:@"captureDevice"];
    
    return [NSPropertyListSerialization dataWithPropertyList:values format:NSPropertyListXMLFormat_v1_0 options:0 error:outError];
    
//    NSException *exception = [NSException exceptionWithName:@"UnimplementedMethod" reason:[NSString stringWithFormat:@"%@ is unimplemented", NSStringFromSelector(_cmd)] userInfo:nil];
//    @throw exception;
//    return nil;
}

-(void)loadFromDictionary:(NSDictionary*)dictionary valuesOfKeys:(NSString*)keys, ...  {
    va_list args;
    va_start(args, keys);
    for (NSString *arg = keys; arg != nil; arg = va_arg(args, NSString*)){
        id object = [dictionary objectForKey:arg];
        [self setValue:object forKey:arg];
    }
    va_end(args);    
}


- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
    /*
    Insert code here to read your document from the given data of the specified type. If outError != NULL, ensure that you create and set an appropriate error when returning NO.
    You can also choose to override -readFromFileWrapper:ofType:error: or -readFromURL:ofType:error: instead.
    */
    NSDictionary *values = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:outError];
    if(!values)
        return NO;
    
    NSString *captureDeviceID = [values objectForKey:@"captureDevice"];
    self.activeCaptureDevice = [QTCaptureDevice deviceWithUniqueID:captureDeviceID];
    [self loadFromDictionary:values valuesOfKeys:
        @"isAutoExposureActive", @"exposureTimeFactor", @"isAutoFocusActive", @"focusFactor", 
        @"isMirroredHorizontally", @"isMirroredVertically", @"rotation",
        @"showsInspector",
        nil];
    self.normalizedCroppingRect = NSRectFromString([values objectForKey:@"normalizedCroppingRect"]);
    self.contentSize = NSSizeFromString([values objectForKey:@"contentSize"]);
    
    
//    NSException *exception = [NSException exceptionWithName:@"UnimplementedMethod" reason:[NSString stringWithFormat:@"%@ is unimplemented", NSStringFromSelector(_cmd)] userInfo:nil];
//    @throw exception;
    return YES;
}

#pragma mark - QT class helpers {

NSArray* CHCachedCaptureDevices;

+(NSArray*)arrayWithAllSuitableDevices {
	static NSString* suitableModelUniqueID = @"UVC Camera VendorID_1118 ProductID_1906";
	NSArray *unfiltered = [QTCaptureDevice inputDevicesWithMediaType:QTMediaTypeVideo];
	NSMutableArray *result = [NSMutableArray array];
	for(QTCaptureDevice *d in unfiltered) {
		if([suitableModelUniqueID isEqualToString:[d modelUniqueID]])
			[result addObject: d];
	}
	return result;
}

+(NSArray*)cachedCaptureDevices {
    if(!CHCachedCaptureDevices) {
        CHCachedCaptureDevices = [[self arrayWithAllSuitableDevices] copy];
    }
    return CHCachedCaptureDevices;
}

#pragma mark - camera input

-(NSArray*)captureDevices {
    return [self.class cachedCaptureDevices];
}

-(void)setIsAutoExposureActive:(BOOL)isAutoExposureActive_ {
    isAutoExposureActive = isAutoExposureActive_;
    [_cameraControl setAutoExposure:isAutoExposureActive];
}

-(void)setExposureTimeFactor:(float)exposureTimeFactor_ {
    exposureTimeFactor = MAX(0, MIN(1, exposureTimeFactor_));
    [_cameraControl setExposure:1 - exposureTimeFactor];
}

-(void)setIsAutoFocusActive:(BOOL)isAutoFocusActive_ {
    isAutoFocusActive = isAutoFocusActive_;
    [_cameraControl setAutoFocus:isAutoFocusActive];
}

-(void)setFocusFactor:(float)focusFactor_ {
    focusFactor = MAX(0, MIN(1, focusFactor_));
    [_cameraControl setAbsoluteFocus:focusFactor];
}

-(void)setActiveCaptureDevice:(QTCaptureDevice *)activeCaptureDevice_{
    [_cameraControl release];
    _cameraControl = nil;
    
    if(activeCaptureDevice_) {
        UInt32 locationID = 0;
        sscanf( [[activeCaptureDevice_ uniqueID] UTF8String], "0x%8x", (unsigned int*)&locationID );
        

        _cameraControl = [[UVCCameraControl alloc] initWithLocationID:locationID];
        
        [_cameraControl setAutoExposure:self.isAutoExposureActive];
        [_cameraControl setExposure:self.exposureTimeFactor];
        [_cameraControl setAutoFocus:self.isAutoFocusActive];
        [_cameraControl setAbsoluteFocus:self.focusFactor];
    }
    activeCaptureDevice = activeCaptureDevice_;
}

-(void)changeExposureTimeInDirection:(int)direction {
	float delta = _cameraControl.discreteExposureValues.count > 0 ? 1.0 / _cameraControl.discreteExposureValues.count : 0.01;
	self.exposureTimeFactor += direction * delta;
    self.isAutoExposureActive = NO;
}

-(void)exposeLonger:(id)sender {
    [self changeExposureTimeInDirection:1];
}

-(void)exposeShorter:(id)sender {
    [self changeExposureTimeInDirection:-1];
}

-(void)changeFocusInDirection:(int)direction {
    self.focusFactor += direction * 0.01;
	self.isAutoFocusActive = NO;
}

-(void)focusCloser:(id)sender {
    [self changeFocusInDirection: 1];
}

-(void)focusFarther:(id)sender {
    [self changeFocusInDirection: -1];
}

#pragma mark - output transformation

+(NSSet *)keyPathsForValuesAffectingIsZoomed {
    return [NSSet setWithObjects:@"normalizedCroppingRect", nil];
}

-(BOOL)isZoomed {
    return !NSEqualRects(NSZeroRect, self.normalizedCroppingRect);
}

-(void)resetZoom {
    self.normalizedCroppingRect = NSZeroRect;
}

// TODO: normalize rotation

-(void)rotateRight:(id)sender {
    self.rotation -= 90;
}

-(void)rotateLeft:(id)sender {
    self.rotation += 90;
}

-(void)flipHorizontal:(id)sender {
    self.isMirroredHorizontally = !self.isMirroredHorizontally;
}

-(void)flipVertical:(id)sender {
    self.isMirroredVertically = !self.isMirroredVertically;
}

#pragma mark - UI Options

-(IBAction)toggleInspector:(id)sender {
    self.showsInspector = !self.showsInspector;
}

-(void)setContentSize:(NSSize)contentSize_ {
    contentSize = contentSize_;
    NSLog(@"setContentSize: %@", NSStringFromSize(contentSize));
}



@end
