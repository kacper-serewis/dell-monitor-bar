#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A display matched to its own DCP service, never to a list position.
@interface DMBDisplay : NSObject
@property(nonatomic, readonly) NSString *identifier;
@property(nonatomic, readonly) NSString *name;
@property(nonatomic, readonly) uint32_t displayID;
/// Blocking; call only on the monitor worker queue. Writes are sent once.
- (nullable NSData *)exchange:(NSData *)frame replyLength:(NSUInteger)length error:(NSError **)error;
@end

FOUNDATION_EXPORT NSArray<DMBDisplay *> *DMBDiscoverDisplays(void);

NS_ASSUME_NONNULL_END
