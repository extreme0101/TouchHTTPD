//
//  CTransport.m
//  TouchCode
//
//  Created by Jonathan Wight on 12/6/08.
//  Copyright 2008 toxicsoftware.com. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

#import "CTransport.h"

#import "NSStream_Extensions.h"
#import "CStreamConnector.h"

static void RemoteReadStreamClientCallBack(CFReadStreamRef stream, CFStreamEventType type, void *clientCallBackInfo);
static void RemoteWriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void *clientCallBackInfo);

@interface CTransport ()
@property (readwrite, nonatomic, assign) CFReadStreamRef remoteReadStream;
@property (readwrite, nonatomic, assign) CFWriteStreamRef remoteWriteStream;
@property (readwrite, nonatomic, assign) BOOL isOpen;
@property (readwrite, nonatomic, retain) CStreamConnector *streamConnector;
//- (void)inputStreamHandleEvent:(NSStreamEvent)inEventCode;
//- (void)outputStreamHandleEvent:(NSStreamEvent)inEventCode;
@end

#pragma mark -

@implementation CTransport

@synthesize remoteReadStream;
@synthesize remoteWriteStream;
@synthesize delegate;
@synthesize isOpen;
@synthesize streamConnector;

- (id)initWithInputStream:(NSInputStream *)inInputStream outputStream:(NSOutputStream *)inOutputStream
{
if ((self = [self init]) != NULL)
	{	
	remoteReadStream = (__bridge CFReadStreamRef)inInputStream;
	CFRetain(remoteReadStream);

	remoteWriteStream = (__bridge CFWriteStreamRef)inOutputStream;
	CFRetain(remoteWriteStream);
	}
return(self);
}

- (void)dealloc
{
streamConnector.delegate = NULL;

CFRelease(remoteReadStream);
remoteReadStream = NULL;

CFRelease(remoteWriteStream);
remoteWriteStream = NULL;
}

- (CTransport *)transport
{
return(self);
}

#pragma mark -

- (BOOL)open:(NSError **)outError
{
#pragma unused (outError)

BOOL theResult = NO;

if (self.isOpen == NO)
	{
	[self.delegate connectionWillOpen:self];

	CFStreamClientContext theContext = {
		.version = 0,
		.info = (__bridge void *)self,
		.retain = NULL,
		.release = NULL,
		};

	theResult = CFReadStreamSetClient(self.remoteReadStream, kCFStreamEventHasBytesAvailable | kCFStreamEventEndEncountered, RemoteReadStreamClientCallBack, &theContext);
	if (theResult == NO)
		{
		if (outError)
			*outError = [NSError errorWithDomain:@"UNKNOWN_DOMAIN" code:-1 userInfo:NULL];
		return(NO);
		}

	theResult = CFWriteStreamSetClient(self.remoteWriteStream, -1, RemoteWriteStreamClientCallBack, &theContext);
	if (theResult == NO)
		{
		if (outError)
			*outError = [NSError errorWithDomain:@"UNKNOWN_DOMAIN" code:-1 userInfo:NULL];
		return(NO);
		}

	CFReadStreamScheduleWithRunLoop(self.remoteReadStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	CFWriteStreamScheduleWithRunLoop(self.remoteWriteStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

	theResult = CFReadStreamOpen(self.remoteReadStream);
	if (theResult == NO)
		{
		if (outError)
			*outError = [NSError errorWithDomain:@"UNKNOWN_DOMAIN" code:-1 userInfo:NULL];
		return(NO);
		}

	theResult = CFWriteStreamOpen(self.remoteWriteStream);
	if (theResult == NO)
		{
		if (outError)
			*outError = [NSError errorWithDomain:@"UNKNOWN_DOMAIN" code:-1 userInfo:NULL];
		return(NO);
		}

	[self.delegate connectionDidOpen:self];
	
	self.isOpen = YES;
	
	theResult = YES;
	}

return(theResult);
}

- (void)close
{
if (self.isOpen == YES)
	{
	[self.delegate connectionWillClose:self];

	CFReadStreamClose(self.remoteReadStream);
	CFWriteStreamClose(self.remoteWriteStream);

	CFReadStreamUnscheduleFromRunLoop(self.remoteReadStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	CFWriteStreamUnscheduleFromRunLoop(self.remoteWriteStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

	CFReadStreamSetClient(self.remoteReadStream, -1, NULL, NULL);
	CFWriteStreamSetClient(self.remoteWriteStream, -1, NULL, NULL);

	[self.delegate connectionDidClose:self];
	
	self.isOpen = NO;
	}
}

#pragma mark -

- (void)sendStream:(NSInputStream *)inInputStream
{
self.streamConnector = [CStreamConnector streamConnectorWithInputStream:inInputStream outputStream:(__bridge NSOutputStream *)self.remoteWriteStream];
self.streamConnector.delegate = self;
[self.streamConnector connect];

((__bridge NSOutputStream *)self.remoteWriteStream).delegate = self.streamConnector;

inInputStream.delegate = self.streamConnector;
[inInputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
[inInputStream open];
}

#pragma mark -

- (void)outputStreamHandleEvent:(NSStreamEvent)inEventCode
{
#pragma unused (inEventCode)

NSLog(@"STREAM EVENT %@ (unhandled) %@", [NSStream stringForEvent:inEventCode], self.remoteWriteStream);
}

- (void)streamConnectorDidFinish:(CStreamConnector *)inStreamConnector;
{
#pragma unused (inStreamConnector)
self.streamConnector.delegate = NULL;
self.streamConnector = NULL;
}

@end

static void RemoteReadStreamClientCallBack(CFReadStreamRef stream, CFStreamEventType type, void *clientCallBackInfo)
{
@autoreleasepool {

CTransport *theTransport = (__bridge CTransport *)clientCallBackInfo;

if (type == kCFStreamEventEndEncountered)
	{
	[theTransport close];
	}
else if (type == kCFStreamEventHasBytesAvailable)
	{
	NSData *theData = NULL;
	CFIndex theBufferLength = 0;
	const UInt8 *theBufferPtr = CFReadStreamGetBuffer(stream, theBufferLength, &theBufferLength);
	if (theBufferPtr != NULL)
		{
		theData = [NSData dataWithBytesNoCopy:(void *)theBufferPtr length:theBufferLength freeWhenDone:NO];
		}
	else
		{
		NSMutableData *theMutableData = [NSMutableData dataWithLength:16384];
		theBufferLength = CFReadStreamRead(stream, theMutableData.mutableBytes, theMutableData.length);
		if (theBufferLength > 0)
			{
			theMutableData.length = theBufferLength;
			theData = theMutableData;
			}
		}

	if (theData)
		[theTransport dataReceived:theData];
	}
	
}
}

static void RemoteWriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void *clientCallBackInfo)
{
#pragma unused (stream, type, clientCallBackInfo)
// JIWTODO - do i need this function at all now?
}
