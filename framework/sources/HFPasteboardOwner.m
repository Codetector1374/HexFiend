//
//  HFPasteboardOwner.m
//  HexFiend_2
//
//  Created by Peter Ammon on 1/12/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <HexFiend/HFPasteboardOwner.h>
#import <HexFiend/HFProgressTracker.h>
#import <objc/message.h>

NSString *const HFPrivateByteArrayPboardType = @"HFPrivateByteArrayPboardType";

@implementation HFPasteboardOwner

- initWithPasteboard:(NSPasteboard *)pboard forByteArray:(HFByteArray *)array withTypes:(NSArray *)types {
    REQUIRE_NOT_NULL(pboard);
    REQUIRE_NOT_NULL(array);
    REQUIRE_NOT_NULL(types);
    [super init];
    byteArray = [array retain];
    pasteboard = pboard;
    [pasteboard declareTypes:types owner:self];
    return self;
}

+ ownPasteboard:(NSPasteboard *)pboard forByteArray:(HFByteArray *)array withTypes:(NSArray *)types {
    return [[[self alloc] initWithPasteboard:pboard forByteArray:array withTypes:types] autorelease];
}

- (void)dealloc {
    [byteArray release];
    [super dealloc];
}

- (void)moveDataToPasteboardWithProgressReporting:(SEL)commandToPerform userInfo:(id)userInfo {
    REQUIRE_NOT_NULL(commandToPerform);
    HFProgressTracker *tracker = [[HFProgressTracker alloc] init];
    typedef void (*FuncPtr_t)(id, SEL, id, id);
    const FuncPtr_t func = (FuncPtr_t)objc_msgSend;
    func(self, commandToPerform, userInfo, tracker);
    [tracker release];
}

- (void)writeDataInBackgroundToPasteboard:(NSPasteboard *)pboard ofLength:(unsigned long long)length forType:(NSString *)type trackingProgress:(HFProgressTracker *)tracker {
    USE(length);
    USE(pboard);
    USE(type);
    USE(tracker);
    UNIMPLEMENTED_VOID();
}

- (void)backgroundMoveDataToPasteboard:(NSString *)type {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [self writeDataInBackgroundToPasteboard:pasteboard ofLength:dataAmountToCopy forType:type trackingProgress:progressTracker];
    [self performSelectorOnMainThread:@selector(backgroundMoveDataFinished:) withObject:nil waitUntilDone:NO];
    [pool release];
}

- (void)backgroundMoveDataFinished:unused {
    USE(unused);
    [NSApp stopModalWithCode:0];
    //stopModal: won't trigger unless we post a do-nothing event
    NSEvent *event = [NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:NULL subtype:0 data1:0 data2:0];
    [NSApp postEvent:event atStart:NO];
}

- (BOOL)moveDataWithProgressReportingToPasteboard:(NSPasteboard *)pboard forType:(NSString *)type {
    HFASSERT(pboard == pasteboard);
    BOOL result = NO;
    [self retain]; //resolving the pasteboard may release us, which deallocates us, which deallocates our tracker...make sure we survive through this function
    progressTracker = [[HFProgressTracker alloc] init];
    /* Give the user a chance to request a smaller amount if it's really big */
    unsigned long long availableAmount = [byteArray length];
    unsigned long long amountToCopy = [self amountToCopyForDataLength:availableAmount stringLength:[self stringLengthForDataLength:availableAmount]];
    if (amountToCopy > 0) {
        if (! [NSBundle loadNibNamed:@"HFModalProgress" owner:self] || ! progressTrackingWindow) {
            [NSException raise:NSInternalInconsistencyException format:@"Unable to load nib named %@", @"HFModalProgress"];
        }
        dataAmountToCopy = amountToCopy;
        unsigned long long stringAmountToCopy = [self stringLengthForDataLength:amountToCopy];
        [progressTrackingDescriptionTextField setStringValue:HFDescribeByteCountWithPrefixAndSuffix("Copying ", stringAmountToCopy, " to the clipboard")];
        [progressTracker setProgressIndicator:progressTrackingIndicator];
        [progressTracker beginTrackingProgress];
        [NSThread detachNewThreadSelector:@selector(backgroundMoveDataToPasteboard:) toTarget:self withObject:type];
        [NSApp runModalForWindow:progressTrackingWindow];
        [progressTracker endTrackingProgress];
        [progressTrackingWindow close];
        [progressTrackingWindow release];
        progressTrackingWindow = nil;
        result = ! progressTracker->cancelRequested;
        [progressTracker release];
        progressTracker = nil;
    }
    [self release];
    return result;
}

/* Action from the cancel button of the progress dialog */
- (IBAction)requestCancel:(id)sender {
    [progressTracker requestCancel:sender];
}

- (void)pasteboardChangedOwner:(NSPasteboard *)pboard {
    HFASSERT(pasteboard == pboard);
}

- (HFByteArray *)byteArray {
    return byteArray;
}

- (void)pasteboard:(NSPasteboard *)pboard provideDataForType:(NSString *)type {
    if ([type isEqualToString:HFPrivateByteArrayPboardType]) {
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
	    [NSNumber numberWithUnsignedLong:(unsigned long)byteArray], @"HFByteArray",
	    [[self class] uuid], @"HFUUID",
	    nil];
	[pboard setPropertyList:dict forType:type];
    }
    else {
	if (! [self moveDataWithProgressReportingToPasteboard:pboard forType:type]) {
            [pboard setData:[NSData data] forType:type];
        }
    }
}

- (void)setBytesPerLine:(NSUInteger)val { bytesPerLine = val; }
- (NSUInteger)bytesPerLine { return bytesPerLine; }

+ (NSString *)uuid {
    static NSString *uuid;
    if (! uuid) {
        CFUUIDRef uuidRef = CFUUIDCreate(NULL);
        uuid = (NSString *)CFUUIDCreateString(NULL, uuidRef);
        CFRelease(uuidRef);
    }
    return uuid;
}

+ (HFByteArray *)_unpackByteArrayFromDictionary:(NSDictionary *)byteArrayDictionary {
    HFByteArray *result = nil;
    if (byteArrayDictionary) {
        NSString *uuid = [byteArrayDictionary objectForKey:@"HFUUID"];
        if ([uuid isEqual:[self uuid]]) {
            result = (HFByteArray *)[[byteArrayDictionary objectForKey:@"HFByteArray"] unsignedLongValue];
        }
    }
    return result;
}

+ (HFByteArray *)unpackByteArrayFromPasteboard:(NSPasteboard *)pasteboard {
    REQUIRE_NOT_NULL(pasteboard);
    HFByteArray *result = [self _unpackByteArrayFromDictionary:[pasteboard propertyListForType:HFPrivateByteArrayPboardType]];
    return result;
}

- (unsigned long long)stringLengthForDataLength:(unsigned long long)dataLength { USE(dataLength); UNIMPLEMENTED(); }

- (unsigned long long)amountToCopyForDataLength:(unsigned long long)numBytes stringLength:(unsigned long long)stringLength {
    unsigned long long dataLengthResult, stringLengthResult;
    NSInteger alertReturn = NSIntegerMax;
    const unsigned long long copyOption1 = MAXIMUM_PASTEBOARD_SIZE_TO_EXPORT;
    const unsigned long long copyOption2 = MINIMUM_PASTEBOARD_SIZE_TO_WARN_ABOUT;
    NSString *option1String = HFDescribeByteCount(copyOption1);
    NSString *option2String = HFDescribeByteCount(copyOption2);
    NSString* dataSizeDescription = HFDescribeByteCount(stringLength);
    if (stringLength >= MAXIMUM_PASTEBOARD_SIZE_TO_EXPORT) {
	NSString *option1 = [@"Copy " stringByAppendingString:option1String];
	NSString *option2 = [@"Copy " stringByAppendingString:option2String];
	alertReturn = NSRunAlertPanel(@"Large Clipboard", @"The copied data would occupy %@ if written to the clipboard.  This is larger than the system clipboard supports.  Do you want to copy only part of the data?", @"Cancel",  option1, option2, dataSizeDescription);
        switch (alertReturn) {
            case NSAlertDefaultReturn:
            default:
                stringLengthResult = 0;
                break;
            case NSAlertAlternateReturn:
                stringLengthResult = copyOption1;
                break;
            case NSAlertOtherReturn:
                stringLengthResult = copyOption2;
                break;
        }
        
    }
    else if (stringLength >= MINIMUM_PASTEBOARD_SIZE_TO_WARN_ABOUT) {
	NSString *option1 = [@"Copy " stringByAppendingString:HFDescribeByteCount(stringLength)];
	NSString *option2 = [@"Copy " stringByAppendingString:HFDescribeByteCount(copyOption2)];
	alertReturn = NSRunAlertPanel(@"Large Clipboard", @"The copied data would occupy %@ if written to the clipboard.  Performing this copy may take a long time.  Do you want to copy only part of the data?", @"Cancel",  option1, option2, dataSizeDescription);
        switch (alertReturn) {
            case NSAlertDefaultReturn:
            default:
                stringLengthResult = 0;
                break;
            case NSAlertAlternateReturn:
                stringLengthResult = stringLength;
                break;
            case NSAlertOtherReturn:
                stringLengthResult = copyOption2;
                break;
        }
    }
    else {
        /* Small enough to copy it all */
        stringLengthResult = stringLength;
    }
    
    /* Convert from string length to data length */
    if (stringLengthResult == stringLength) {
        dataLengthResult = numBytes;
    }
    else {
        unsigned long long divisor = stringLength / numBytes;
        dataLengthResult = stringLengthResult / divisor;
    }
    
    return dataLengthResult;
}

@end
