//
//  OFSDDefines.h
//  Omnifocus
//
//  Created by David on 29/09/2021.
//  Copyright © 2021 Elgato Systems. All rights reserved.
//

#ifndef OFSDDefines_h
#define OFSDDefines_h

// MARK: Settings

#define kOFSDSettingPerspective                         "perspective"
#define kOFSDSettingCustomPerspective                   "customPerspective"
#define kOFSDSettingRefreshInterval                     "refreshInterval"
#define kOFSDSettingBadgeCount                          "badgeCount"
#define kOFSDSettingBadgeCountFromOverdue               "overdueCount"
#define kOFSDSettingBadgeCountFromToday                 "todayCount"
#define kOFSDSettingBadgeCountFromFlagged               "flaggedCount"

// MARK: Payload

#define kOFSDPayloadEventType                           "eventType"
#define kOFSDPayloadPerspectives                        "perspectives"

typedef NS_ENUM(NSInteger, OFSDDueTasksState) {
    OFSDDueTasksStateNone = 0,
    OFSDDueTasksStateShort = 1,
    OFSDDueTasksStateLong = 2,
};

#endif /* OFSDDefines_h */
