//
//  MyStreamDeckPlugin+Scripting.m
//  Omnifocus
//
//  Created by David Stephens on 02/10/2021.
//  Copyright © 2021 Elgato Systems. All rights reserved.
//

#import "MyStreamDeckPlugin+Scripting.h"
#import "ESDConnectionManager.h"
#import "ESDUtilities.h"

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

// MARK: - MyStreamDeckPlugin (Scripting)

@implementation MyStreamDeckPlugin (Scripting)

/**
 Initialises the AppleScript with the provided name
 
 @param name The path to the script, excluding the extension.
 */
- (NSAppleScript *)setupScriptWithName:(NSString *)name {
    NSURL* url = [NSURL fileURLWithPath:GetResourcePath([NSString stringWithFormat:@"%@.scpt", name])];
    NSDictionary *errors = nil;
    NSAppleScript *script = [[NSAppleScript alloc] initWithContentsOfURL:url error:&errors];
    if (script == nil) {
        [self.connectionManager logMessage:[NSString stringWithFormat:@"Error loading %@.scpt: %@", name, errors]];
    }
    return script;
}

/**
 Fetches the due count using the provided script .
 
 The result is written to the location of the  `number` pointer.
 If `number < 0`, it will be set to the result. Otherwise, the result will be added to `number`.
 
 @param number A pointer to count to update.
 @param script The AppleScript to run
 */
- (void)numberDue:(int*)number fromScript:(NSAppleScript *) script {
    NSDictionary *errors = nil;
    int numberOfTasks = 0;
    if (script != nil) {
        NSAppleEventDescriptor *eventDescriptor = [script executeAndReturnError:&errors];
        if (eventDescriptor != nil && [eventDescriptor descriptorType] != kAENullEvent) {
            numberOfTasks = (int)[eventDescriptor int32Value];
            if (numberOfTasks == 0 && ![eventDescriptor.stringValue isEqualToString: @"0"]) {
                NSString *logString = [NSString stringWithFormat:@"Error converting '%@' to int", eventDescriptor.stringValue];
                [self.connectionManager logMessage:logString];
            }
        } else {
            [self.connectionManager logMessage:[NSString stringWithFormat:@"Error running script: %@",errors]];
        }
    }
    if (*number < 0) {
        *number = numberOfTasks;
    } else {
        *number += numberOfTasks;
    }
}

@end
