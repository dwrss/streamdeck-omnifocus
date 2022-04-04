//
//  MyStreamDeckPlugin+EventSending.h
//  Omnifocus
//
//  Created by David Stephens on 24/03/2022.
//  Copyright © 2022 Elgato Systems. All rights reserved.
//

#import "MyStreamDeckPlugin.h"

NS_ASSUME_NONNULL_BEGIN

@interface MyStreamDeckPlugin (EventSending)
- (void)sendPerspectiveListForAction:(NSString *)action withContext:(id)context;
@end

NS_ASSUME_NONNULL_END
