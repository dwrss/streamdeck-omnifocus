//
//  MyStreamDeckPlugin+EventSending.m
//  Omnifocus
//
//  Created by David Stephens on 24/03/2022.
//  Copyright © 2022 Elgato Systems. All rights reserved.
//

#import "MyStreamDeckPlugin+EventSending.h"
#import "MyStreamDeckPlugin+Scripting.h"
#import "OFSDDefines.h"
#import "ESDConnectionManager.h"

static NSString * const PT_PERSPECTIVE_LIST = @"perspectiveList";

@implementation MyStreamDeckPlugin (EventSending)
- (void)sendPerspectiveListForAction:(NSString *)action withContext:(id)context {
    [self.connectionManager logMessage:@"Sending perspective list"];
    NSArray *perspectives = [self getPerspectiveList];
    NSError *error;
    NSDictionary *payload = @{
        @kOFSDPayloadEventType: PT_PERSPECTIVE_LIST,
        @kOFSDPayloadPerspectives: perspectives
    };
    BOOL success = [self.connectionManager sendToPropertyInspectorWithPayload:payload forAction:action withContext:context error:&error];
    if (!success) {
        [self.connectionManager logMessage:[NSString stringWithFormat:@"Error setting state: '%@'", error]];
        return;
    }
    
    [self.connectionManager logMessage:@"Sent perspectives list"];
}
@end
