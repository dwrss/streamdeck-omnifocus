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
#import "OFSDDefines.h"
#import "MyStreamDeckPlugin+Scripting.h"


// Refresh the unread count every 30s
#define REFRESH_DUE_COUNT_TIME_INTERVAL		30.0
// Minimum interval between refreshes
#define REFRESH_DUE_COUNT_MINIMUM_INTERVAL  10.0
// Number of seconds "late" the timer is allowed to fire
#define REFRESH_DUE_COUNT_TOLERANCE         10.0


// Size of the images
#define IMAGE_SIZE	144

static NSString * const OMNIFOCUS_BUNDLE_ID = @"com.omnigroup.OmniFocus3";
static NSString * const ACTID_DUE_TASKS = @"org.dwrs.streamdeck.omnifocus.action";


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

@property (strong) NSAppleScript *numberOfOverdueTasksScript;

@property (strong) NSAppleScript *numberOfFlaggedTasksScript;

@property (strong) NSMutableDictionary *settingsForContext;

@property (assign) NSTimeInterval refreshInterval;

@property (assign) NSTimeInterval lastRefresh;

@end


@implementation MyStreamDeckPlugin



// MARK: - Setup the instance variables if needed

- (void)setupRefresh {
    // Create/update a timer to repetitively update the actions
    BOOL shouldUpdateInterval = self.refreshInterval > 0 && self.refreshInterval != self.refreshTimer.timeInterval;
    if (shouldUpdateInterval) {
        [self.connectionManager logMessage:[NSString stringWithFormat:@"Refresh interval changed to %.2f", self.refreshInterval]];
        [self.refreshTimer invalidate];
    }
    if(![[self refreshTimer] isValid] || shouldUpdateInterval) {
        NSTimeInterval interval = self.refreshInterval > 0 ? self.refreshInterval : REFRESH_DUE_COUNT_TIME_INTERVAL;
        self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(refreshDueCount) userInfo:nil repeats:YES];
        // Update intervals are not absolutely critical, so allow a 10s tolerance
        self.refreshTimer.tolerance = REFRESH_DUE_COUNT_TOLERANCE;
    }
    NSWorkspace *sharedWorkspace = [NSWorkspace sharedWorkspace];
    NSNotificationCenter *notificationCentre = [sharedWorkspace notificationCenter];
    [notificationCentre addObserver:self selector:@selector(deactivateNotification:) name:NSWorkspaceDidDeactivateApplicationNotification object:sharedWorkspace];
}

- (void)invalidateRefresh {
    [self.refreshTimer invalidate];
    NSWorkspace *sharedWorkspace = [NSWorkspace sharedWorkspace];
    [[sharedWorkspace notificationCenter] removeObserver:self name:NSWorkspaceDidDeactivateApplicationNotification object:sharedWorkspace];
}

- (void)setupIfNeeded
{
	// Create the array of known contexts
	if(self.knownContexts == nil)
	{
        self.knownContexts = [[NSMutableArray alloc] init];
	}
	
    // Setup badge count refresh
    [self setupRefresh];
    
    // Create the array of known contexts
    if(self.settingsForContext == nil)
    {
        self.settingsForContext = [[NSMutableDictionary alloc] init];
    }
}

// MARK: - Listen for OmniFocus deactivation
- (void) deactivateNotification:(NSNotification *)notification {
    NSRunningApplication *deactivatedApplication = notification.userInfo[NSWorkspaceApplicationKey];
    if ([deactivatedApplication.bundleIdentifier isEqualToString:OMNIFOCUS_BUNDLE_ID]) {
        [self.connectionManager logMessage:@"Omnifocus deactivated. Refreshing due count"];
        [self refreshDueCount];
    }
}


// MARK: - Refresh all actions

- (void)refreshDueCount {
    if (!self.isOmniFocusRunning) {
        [self.connectionManager logMessage:@"OmniFocus not running, not refreshing due count"];
        return;
    }
    
    NSDate *now = [[NSDate alloc] init];
    NSTimeInterval timeSinceLastRefresh = [now timeIntervalSince1970] - self.lastRefresh;
    if (timeSinceLastRefresh < REFRESH_DUE_COUNT_MINIMUM_INTERVAL) {
        [self.connectionManager logMessage:[NSString stringWithFormat:@"Not refreshing. Only %.2f since last refresh", timeSinceLastRefresh]];
        return;
    }
    self.lastRefresh = [[[NSDate alloc] init] timeIntervalSince1970];
	
	int numberOfDueTasks = -1;
	
	// Update each known context with the new value
	for (NSString *context in self.knownContexts) {
        // Execute the Applescripts to retrieve the number of due tasks
        NSMutableDictionary *settingsPayload = [self.settingsForContext objectForKey:context];
        NSSet *badgeCountSources = settingsPayload[@kOFSDSettingBadgeCount];
        if (badgeCountSources == nil) {
            [self.connectionManager logMessage:@"No sources for badge count"];
        }
        if ([badgeCountSources containsObject:@kOFSDSettingBadgeCountFromOverdue]) {
            if (self.numberOfOverdueTasksScript == nil) {
                self.numberOfOverdueTasksScript = [self setupScriptWithName:@"NumberOfOverdueTasks"];
            }
            [self numberDue:&numberOfDueTasks fromScript:self.numberOfOverdueTasksScript];
        }
        if ([badgeCountSources containsObject:@kOFSDSettingBadgeCountFromToday]) {
            if (self.numberOfDueTasksScript == nil) {
                self.numberOfDueTasksScript = [self setupScriptWithName:@"NumberOfDueTasks"];
            }
            [self numberDue:&numberOfDueTasks fromScript:self.numberOfDueTasksScript];
        }
        if ([badgeCountSources containsObject:@kOFSDSettingBadgeCountFromFlagged]) {
            if (self.numberOfFlaggedTasksScript == nil) {
                self.numberOfFlaggedTasksScript = [self setupScriptWithName:@"NumberOfFlaggedTasks"];
            }
            [self numberDue:&numberOfDueTasks fromScript:self.numberOfFlaggedTasksScript];
        }
        
        if (numberOfDueTasks > 9) {
            [self setStateToNumber:[NSNumber numberWithInt:2] forAction:ACTID_DUE_TASKS inContext:context];
            [self.connectionManager setTitle:[NSString stringWithFormat:@"%d", numberOfDueTasks] withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
        } else if (numberOfDueTasks > 0) {
            [self setStateToNumber:[NSNumber numberWithInt:1] forAction:ACTID_DUE_TASKS inContext:context];
            [self.connectionManager setTitle:[NSString stringWithFormat:@"%d", numberOfDueTasks] withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
        } else {
            [self setStateToNumber:[NSNumber numberWithInt:0] forAction:ACTID_DUE_TASKS inContext:context];
            if (numberOfDueTasks != 0) {
                [self.connectionManager logMessage:[NSString stringWithFormat:@"Unexpected number of tasks: %d", numberOfDueTasks]];
                [self.connectionManager showAlertForContext:context];
            }
            [self.connectionManager setTitle:@"" withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
        }
	}
}

// MARK: - State helpers

- (void)setStateToNumber:(NSNumber * _Nonnull)number forAction:(NSString *)key inContext:(NSString *)context {
    NSNumber *currentState = [self.actionStates objectForKey:ACTID_DUE_TASKS];
    // No need to update when the new state matches out local state
    if (currentState && [currentState intValue] == [number intValue]) {
        return;
    }
    NSError *error = nil;
    BOOL success = [self.connectionManager setState:number forContext:context error:&error];
    if (!success) {
        [self.connectionManager logMessage:[NSString stringWithFormat:@"Error setting state: '%@'", error]];
        return;
    }
    [self storeStateNumber:number forAction:key];
}

- (void)storeStateNumber:(nullable NSNumber *)stateNumber forAction:(NSString *)action {
    if (stateNumber != nil) {
        [self.actionStates setObject:stateNumber forKey:action];
    } else {
        // If we weren't passed a state, make sure we don't have an invalid one lying around
        [self.actionStates removeObjectForKey:action];
    }
}

// MARK: - Settings helpers

- (void)saveSettingsFromPayload:(NSDictionary * _Nonnull)payload forContext:(id)context {
    // Settings a context-specific
    NSMutableDictionary *settingsPayload = [payload[@"settings"] mutableCopy];
    NSArray *badgeCountSourcesArray = settingsPayload[@kOFSDSettingBadgeCount];
    if (badgeCountSourcesArray != nil) {
        NSSet *badgeCountSourcesSet = [[NSSet alloc] initWithArray:badgeCountSourcesArray];
        [settingsPayload setObject:@kOFSDSettingBadgeCount forKey:badgeCountSourcesSet];
        [self.connectionManager logMessage:[NSString stringWithFormat:@"Badge count sources: %@", badgeCountSourcesSet.description]];
    }
    NSDictionary *settingsPayloadForContext = @{context: settingsPayload};
    if (settingsPayloadForContext == nil) {
        [self.connectionManager logMessage:@"Payload did not contain settings"];
        return;
    }
    [self.settingsForContext addEntriesFromDictionary:settingsPayloadForContext];
}


// MARK: - Stream Deck Events handler


- (void)keyDownForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID {
    NSDictionary *settings = [self.settingsForContext objectForKey:context];
    NSString *perspective = [settings objectForKey:@kOFSDSettingPerspective];
    NSString *path = @"forecast";
    if (perspective != nil) {
        if ([perspective isEqualToString:@"custom"]) {
            NSString *customPerspective = [settings objectForKey:@kOFSDSettingCustomPerspective];
            if (customPerspective != nil) {
                path = [NSString stringWithFormat:@"perspective/%@", customPerspective];
            } else {
                [self.connectionManager logMessage:@"Custom perspective selected but none provided"];
            }
        } else {
            path = [settings objectForKey:@kOFSDSettingPerspective];
        }
    }
    
	// On key press, open OmniFocus
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"omnifocus:///%@", path]]];
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
    
    // Store the settings for future use
    [self saveSettingsFromPayload:payload forContext:context];
	
	// Add the context to the list of known contexts
	[self.knownContexts addObject:context];
    
    // Ensure our action state is up-to-date
    NSNumber *state = (NSNumber *)[payload objectForKey:@kESDSDKPayloadState];
    [self storeStateNumber:state forAction:action];
	
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
        // If we're not active in any known contexts, invalidate refreshes
        [self invalidateRefresh];
    }
}

- (void)deviceDidConnect:(NSString *)deviceID withDeviceInfo:(NSDictionary *)deviceInfo
{
    if ([self.knownContexts count] > 0) {
        // Last we heard, we were being displayed.
        // Device connection seems like a good time to refresh
        [self refreshDueCount];
    }
}

- (void)deviceDidDisconnect:(NSString *)deviceID
{
	// Nothing to do
}

- (void)applicationDidLaunch:(NSDictionary *)applicationInfo {
	if([applicationInfo[@kESDSDKPayloadApplication] isEqualToString:OMNIFOCUS_BUNDLE_ID]) {
		self.isOmniFocusRunning = YES;
		
		// Explicitly refresh the number of due tasks
		[self refreshDueCount];
        // We invalidate the refreshes when the application terminates, so run setup again
        [self setupIfNeeded];
	}
}

- (void)applicationDidTerminate:(NSDictionary *)applicationInfo {
    if([applicationInfo[@kESDSDKPayloadApplication] isEqualToString:OMNIFOCUS_BUNDLE_ID]) {
        self.isOmniFocusRunning = NO;
        // Omnifocus isn't running, so we can stop the refresh timer
        [self invalidateRefresh];
    }
}

- (void) didReceiveSettingsForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID {
    [self saveSettingsFromPayload:payload forContext:context];
    [self refreshDueCount];
}

- (void) didReceiveGlobalSettings:(NSDictionary *)payload {
    NSDictionary *settings = payload[@"settings"];
    double refreshInterval = [[settings objectForKey:@kOFSDSettingRefreshInterval] doubleValue];
    self.refreshInterval = refreshInterval;
    if ([[self refreshTimer] isValid]) {
        [self setupIfNeeded];
    }
}
@end
