#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// All objects are created, used and released by the background tag service.
@interface MTTagLibBridge : NSObject
+ (nullable NSDictionary *)readURL:(NSURL *)url error:(NSError **)error;
+ (BOOL)writeURL:(NSURL *)url fields:(NSDictionary<NSString *, NSString *> *)fields
    artworkChanged:(BOOL)artworkChanged artwork:(nullable NSData *)artwork error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
