//
//  MyStreamDeckPlugin+Scripting.h
//  Omnifocus
//
//  Created by David Stephens on 02/10/2021.
//  Copyright © 2021 Elgato Systems. All rights reserved.
//

#import "MyStreamDeckPlugin.h"



@interface MyStreamDeckPlugin (Scripting)

- (NSAppleScript *_Nullable)setupScriptWithName:(NSString * _Nonnull)name;
NS_ASSUME_NONNULL_BEGIN
- (void)numberDue:(int*)number fromScript:(NSAppleScript *) script;
- (nullable NSArray<NSString *> *)getPerspectiveList;
NS_ASSUME_NONNULL_END

@end

