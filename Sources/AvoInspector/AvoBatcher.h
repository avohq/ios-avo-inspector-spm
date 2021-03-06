//
//  AvoBatcher.h
//  AvoInspector
//
//  Created by Alex Verein on 18.02.2020.
//

#import <Foundation/Foundation.h>

#import "AvoNetworkCallsHandler.h"
#import "types/AvoEventSchemaType.h"

NS_ASSUME_NONNULL_BEGIN

@interface AvoBatcher : NSObject

- (instancetype) initWithNetworkCallsHandler: (AvoNetworkCallsHandler *) networkCallsHandler;

- (void) handleSessionStarted;
- (void) handleTrackSchema: (NSString *) eventName schema: (NSDictionary<NSString *, AvoEventSchemaType *> *) schema eventId:(NSString * _Nullable) eventId eventHash:(NSString * _Nullable) eventHash;

- (void) enterBackground;
- (void) enterForeground;

@end

NS_ASSUME_NONNULL_END
