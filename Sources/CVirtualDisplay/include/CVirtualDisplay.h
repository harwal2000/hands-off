#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// A virtual display that exists for as long as this object does.
@interface HOVirtualDisplay : NSObject
/// `width` and `height` in points; `hiDPI` makes it a 2x (Retina) display. Nil if macOS refuses.
- (nullable instancetype)initWithName:(NSString *)name width:(NSUInteger)width height:(NSUInteger)height hiDPI:(BOOL)hiDPI;
@property (nonatomic, readonly) CGDirectDisplayID displayID;
@end

NS_ASSUME_NONNULL_END
