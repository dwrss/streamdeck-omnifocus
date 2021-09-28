//==============================================================================
/**
@file       MyStreamDeckPlugin.m

@brief      A Stream Deck plugin displaying the number of unread emails in Apple's Mail

@copyright  (c) 2021 David Stephens
            This Source Code Form is subject to the terms of the Mozilla Public
            License, v. 2.0. If a copy of the MPL was not distributed with this
            file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
            This file incorporates work covered by the following copyright and permission notice:
                (c) 2018, Corsair Memory, Inc.
                This source code is licensed under the MIT-style license found in the LICENSE file.

**/
//==============================================================================

#import "MyStreamDeckPlugin.h"

#import "ESDSDKDefines.h"
#import "ESDConnectionManager.h"
#import "ESDUtilities.h"
#import <AppKit/AppKit.h>


// Refresh the unread count every 60s
#define REFRESH_DUE_COUNT_TIME_INTERVAL		60.0


// Size of the images
#define IMAGE_SIZE	144

static NSString * const OMNIFOCUS_BUNDLE_ID = @"com.omnigroup.OmniFocus3";
static NSString * const ACTID_DUE_TASKS = @"org.dwrs.streamdeck.omnifocus.action";

// MARK: - Utility methods


//
// Utility function to get the fullpath of an resource in the bundle
//
static NSString * GetResourcePath(NSString *inFilename)
{
	NSString *outPath = nil;
	
	if([inFilename length] > 0)
	{
		NSString * bundlePath = [ESDUtilities pluginPath];
		if(bundlePath != nil)
		{
			outPath = [bundlePath stringByAppendingPathComponent:inFilename];
		}
	}
	
	return outPath;
}


//
// Utility function to create a CGContextRef
//
static CGContextRef CreateBitmapContext(CGSize inSize)
{
	CGFloat bitmapBytesPerRow = inSize.width * 4;
	CGFloat bitmapByteCount = (bitmapBytesPerRow * inSize.height);
	
	void *bitmapData = calloc(bitmapByteCount, 1);
	if(bitmapData == NULL)
	{
		return NULL;
	}
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(bitmapData, inSize.width, inSize.height, 8, bitmapBytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast);
	if(context == NULL)
	{
		CGColorSpaceRelease(colorSpace);
		free(bitmapData);
		return NULL;
	}
	else
	{
		CGColorSpaceRelease(colorSpace);
		return context;
	}
}

//
// Utility method that takes the path of an image and create a base64 encoded string
//
static NSString * CreateBase64EncodedString(NSString *inImagePath)
{
	NSString *outBase64PNG = nil;
	
	NSImage* image = [[NSImage alloc] initWithContentsOfFile:inImagePath];
	if(image != nil)
	{
		// Find the best CGImageRef
		CGSize iconSize = CGSizeMake(IMAGE_SIZE, IMAGE_SIZE);
		NSRect theRect = NSMakeRect(0, 0, iconSize.width, iconSize.height);
		CGImageRef imageRef = [image CGImageForProposedRect:&theRect context:NULL hints:nil];
		if(imageRef != NULL)
		{
			// Create a CGContext
			CGContextRef context = CreateBitmapContext(iconSize);
			if(context != NULL)
			{
				// Draw the Mail.app icon
				CGContextDrawImage(context, theRect, imageRef);
				
				// Generate the final image
				CGImageRef completeImage = CGBitmapContextCreateImage(context);
				if(completeImage != NULL)
				{
					// Export the image to PNG
					CFMutableDataRef pngData = CFDataCreateMutable(kCFAllocatorDefault, 0);
					if(pngData != NULL)
					{
						CGImageDestinationRef destinationRef = CGImageDestinationCreateWithData(pngData, kUTTypePNG, 1, NULL);
						if (destinationRef != NULL)
						{
							CGImageDestinationAddImage(destinationRef, completeImage, nil);
							if (CGImageDestinationFinalize(destinationRef))
							{
								NSString *base64PNG = [(__bridge NSData *)pngData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithCarriageReturn];
								if([base64PNG length] > 0)
								{
									outBase64PNG = [NSString stringWithFormat:@"data:image/png;base64,%@\">", base64PNG];
								}
							}
							
							CFRelease(destinationRef);
						}
						
						CFRelease(pngData);
					}
					
					CFRelease(completeImage);
				}
				
				CFRelease(context);
			}
		}
	}
	
	return outBase64PNG;
}


// MARK: - MyStreamDeckPlugin

@interface MyStreamDeckPlugin ()

// Tells us if OmniFocus is running
@property (assign) BOOL isOmniFocusRunning;

// A timer fired each minute to update the number of unread email from Apple's Mail
@property (strong) NSTimer *refreshTimer;

// The list of visible contexts
@property (strong) NSMutableArray *knownContexts;

// The current state for each visible action
@property (strong) NSMutableDictionary *actionStates;

@property (strong) NSAppleScript *numberOfDueTasksScript;

@end


@implementation MyStreamDeckPlugin



// MARK: - Setup the instance variables if needed

- (void)setupIfNeeded
{
	// Create the array of known contexts
	if(self.knownContexts == nil)
	{
        self.knownContexts = [[NSMutableArray alloc] init];
	}
	
	// Create a timer to repetivily update the actions
	if(self.refreshTimer == nil)
	{
        self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:REFRESH_DUE_COUNT_TIME_INTERVAL target:self selector:@selector(refreshDueCount) userInfo:nil repeats:YES];
	}
    if (self.numberOfDueTasksScript == nil) {
        NSURL* url = [NSURL fileURLWithPath:GetResourcePath(@"NumberOfDueTasks.scpt")];
        NSDictionary *errors = nil;
        self.numberOfDueTasksScript = [[NSAppleScript alloc] initWithContentsOfURL:url error:&errors];
        if (self.numberOfDueTasksScript == nil) {
            [self.connectionManager logMessage:[NSString stringWithFormat:@"Error loading NumberOfDueTasks.scpt: %@", errors]];
        }
    }
}


// MARK: - Refresh all actions

- (void)refreshDueCount {
	if (!self.isOmniFocusRunning) {
        [self.connectionManager logMessage:@"OmniFocus not running, not refreshing due count"];
		return;
	}
	
	// Execute the NumberOfUnreadMails.scpt Applescript to retrieve the number of due tasks
	int numberOfDueTasks = -1;
	
	NSDictionary *errors = nil;
	if (self.numberOfDueTasksScript != nil) {
		NSAppleEventDescriptor *eventDescriptor = [self.numberOfDueTasksScript executeAndReturnError:&errors];
		if (eventDescriptor != nil && [eventDescriptor descriptorType] != kAENullEvent) {
			numberOfDueTasks = (int)[eventDescriptor int32Value];
            if (numberOfDueTasks == 0 && ![eventDescriptor.stringValue isEqualToString: @"0"]) {
                NSString *logString = [NSString stringWithFormat:@"Error converting '%@' to int", eventDescriptor.stringValue];
                [self.connectionManager logMessage:logString];
            }
		} else {
            [self.connectionManager logMessage:[NSString stringWithFormat:@"Error running NumberOfDueTasks.scpt: %@", errors]];
        }
    } else {
        [self setupIfNeeded];
    }
	
    NSNumber *currentState = [self.actionStates objectForKey:ACTID_DUE_TASKS];
	// Update each known context with the new value
	for (NSString *context in self.knownContexts) {
        if (numberOfDueTasks > 9) {
            if ((!currentState || [currentState intValue] != 2)) {
                [self setStateToNumber:[NSNumber numberWithInt:2] forAction:ACTID_DUE_TASKS inContext:context];
            }
            [self.connectionManager setTitle:[NSString stringWithFormat:@"%d", numberOfDueTasks] withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
        } else if (numberOfDueTasks > 0) {
            if ((!currentState || [currentState intValue] != 1)) {
                [self setStateToNumber:[NSNumber numberWithInt:1] forAction:ACTID_DUE_TASKS inContext:context];
            }
            [self.connectionManager setTitle:[NSString stringWithFormat:@"%d", numberOfDueTasks] withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
        } else {
            if (currentState == nil || [currentState intValue] != 0) {
                [self setStateToNumber:[NSNumber numberWithInt:0] forAction:ACTID_DUE_TASKS inContext:context];
            }
            if (numberOfDueTasks != 0) {
                [self.connectionManager logMessage:[NSString stringWithFormat:@"Unexpected number of tasks: %d", numberOfDueTasks]];
                [self.connectionManager showAlertForContext:context];
            }
            [self.connectionManager setTitle:@"" withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
        }
	}
}

- (void)setStateToNumber:(NSNumber * _Nonnull)number forAction:(NSString *)key inContext:(NSString *)context {
    NSError *error = nil;
    BOOL success = [self.connectionManager setState:number forContext:context error:&error];
    if (!success) {
        [self.connectionManager logMessage:[NSString stringWithFormat:@"Error setting state: '%@'", error]];
        return;
    }
    [self.actionStates setObject:number forKey:key];
}


// MARK: - Events handler


- (void)keyDownForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID {
	// On key press, open OmniFocus
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"omnifocus:///forecast"]];
}

- (void)keyUpForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
    // Pressing the button changes the state, so we update our local storage
    NSNumber *state = (NSNumber *)[payload objectForKey:@kESDSDKPayloadState];
    [self storeStateNumber:state forAction:action];
    
    if ([action isEqualToString:ACTID_DUE_TASKS]) {
        // Make sure the due count is up-to-date
        [self refreshDueCount];
    }
}

- (void)willAppearForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID {
	// Set up the instance variables if needed
	[self setupIfNeeded];
	
	// Add the context to the list of known contexts
	[self.knownContexts addObject:context];
    
    NSNumber *state = (NSNumber *)[payload objectForKey:@kESDSDKPayloadState];
    if (state != nil) {
        [self.actionStates setObject:state forKey:action];
    } else {
        // If we weren't passed a state, make sure we don't have an invalid one lying around
        [self.actionStates removeObjectForKey:action];
    }
	
    if ([action isEqualToString:ACTID_DUE_TASKS]) {
        // Explicitely refresh the number of due tasks
        [self refreshDueCount];
    }
}

- (void)willDisappearForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
	// Remove the context from the list of known contexts
	[self.knownContexts removeObject:context];
    if ([self.knownContexts count] == 0) {
        // Remove stored state for the action
        [self.actionStates removeObjectForKey:action];
        // If we're not active in any known contexts, invalidate the timer
        [self.refreshTimer invalidate];
    }
}

- (void)deviceDidConnect:(NSString *)deviceID withDeviceInfo:(NSDictionary *)deviceInfo
{
	// Nothing to do
}

- (void)deviceDidDisconnect:(NSString *)deviceID
{
	// Nothing to do
}

- (void)applicationDidLaunch:(NSDictionary *)applicationInfo {
	if([applicationInfo[@kESDSDKPayloadApplication] isEqualToString:OMNIFOCUS_BUNDLE_ID]) {
		self.isOmniFocusRunning = YES;
		
		// Explicitely refresh the number of due tasks
		[self refreshDueCount];
        // We invalidate the timer when the application terminates, so run setup again
        [self setupIfNeeded];
	}
}

- (void)applicationDidTerminate:(NSDictionary *)applicationInfo {
    if([applicationInfo[@kESDSDKPayloadApplication] isEqualToString:OMNIFOCUS_BUNDLE_ID]) {
        self.isOmniFocusRunning = NO;
        // Omnifocus isn't running, so we can stop the refresh timer
        [self.refreshTimer invalidate];
    }
}

@end
