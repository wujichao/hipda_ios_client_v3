//
//  IDMPhoto.m
//  IDMPhotoBrowser
//
//  Created by Michael Waterfall on 17/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import "IDMPhoto.h"
#import "IDMPhotoBrowser.h"
#import "SDImageCache+URLCache.h"
#import "NSString+CDN.h"
#import "SVProgressHUD.h"
#import "HPSetting.h"

// Private
@interface IDMPhoto () {
    // Image Sources
    NSString *_photoPath;

    // Image
    UIImage *_underlyingImage;

    // Other
    NSString *_caption;
    BOOL _loadingInProgress;
}

// Properties
@property (nonatomic, strong) UIImage *underlyingImage;

// Methods
- (void)imageLoadingComplete;

@end

// IDMPhoto
@implementation IDMPhoto

// Properties
@synthesize underlyingImage = _underlyingImage, 
photoURL = _photoURL,
caption = _caption;

#pragma mark Class Methods

+ (IDMPhoto *)photoWithImage:(UIImage *)image {
	return [[IDMPhoto alloc] initWithImage:image];
}

+ (IDMPhoto *)photoWithFilePath:(NSString *)path {
	return [[IDMPhoto alloc] initWithFilePath:path];
}

+ (IDMPhoto *)photoWithURL:(NSURL *)url {
	return [[IDMPhoto alloc] initWithURL:url];
}

+ (NSArray *)photosWithImages:(NSArray *)imagesArray {
    NSMutableArray *photos = [NSMutableArray arrayWithCapacity:imagesArray.count];
    
    for (UIImage *image in imagesArray) {
        if ([image isKindOfClass:[UIImage class]]) {
            IDMPhoto *photo = [IDMPhoto photoWithImage:image];
            [photos addObject:photo];
        }
    }
    
    return photos;
}

+ (NSArray *)photosWithFilePaths:(NSArray *)pathsArray {
    NSMutableArray *photos = [NSMutableArray arrayWithCapacity:pathsArray.count];
    
    for (NSString *path in pathsArray) {
        if ([path isKindOfClass:[NSString class]]) {
            IDMPhoto *photo = [IDMPhoto photoWithFilePath:path];
            [photos addObject:photo];
        }
    }
    
    return photos;
}

+ (NSArray *)photosWithURLs:(NSArray *)urlsArray {
    NSMutableArray *photos = [NSMutableArray arrayWithCapacity:urlsArray.count];
    
    for (id url in urlsArray) {
        if ([url isKindOfClass:[NSURL class]]) {
            IDMPhoto *photo = [IDMPhoto photoWithURL:url];
            [photos addObject:photo];
        }
        else if ([url isKindOfClass:[NSString class]]) {
            IDMPhoto *photo = [IDMPhoto photoWithURL:[NSURL URLWithString:url]];
            [photos addObject:photo];
        }
    }
    
    return photos;
}

#pragma mark NSObject

- (id)initWithImage:(UIImage *)image {
	if ((self = [super init])) {
		self.underlyingImage = image;
	}
	return self;
}

- (id)initWithFilePath:(NSString *)path {
	if ((self = [super init])) {
		_photoPath = [path copy];
	}
	return self;
}

- (id)initWithURL:(NSURL *)url {
	if ((self = [super init])) {
		_photoURL = [url copy];
	}
	return self;
}

#pragma mark IDMPhoto Protocol Methods

- (UIImage *)underlyingImage {
    return _underlyingImage;
}

- (NSURL *)underlyingImageURL {
    return _photoURL;
}

- (void)loadUnderlyingImageAndNotify {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    _loadingInProgress = YES;
    if (self.underlyingImage) {
        // Image already loaded
        [self imageLoadingComplete];
    } else {
        if (_photoPath) {
            // Load async from file
            [self performSelectorInBackground:@selector(loadImageFromFileAsync) withObject:nil];
        } else if (_photoURL) {
            
            // 加载小图
            NSString *src = [_photoURL absoluteString];
            NSString *thumbUrl = nil;
            
            // CDN模式
            // 传进来原图url, 换成cdn看看有没有缓存, 然后下载原图
            if ([src rangeOfString:HP_IMG_BASE_HOST].location != NSNotFound) {
                thumbUrl = [src hp_thumbnailURL];
            }
            // 论坛自带压缩模式
            // 使用自带thumb图, 传进来是小图, 先看看有没有缓存, 然后换成大图url, 下载
            if ([src hasSuffix:HP_THUMB_URL_SUFFIX]) {
                thumbUrl = src;
                NSString *originalUrl = [src stringByReplacingOccurrencesOfString:HP_THUMB_URL_SUFFIX withString:@""];
                _photoURL = [NSURL URLWithString:originalUrl];
            }
        
            if (thumbUrl) {
                NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:[NSURL URLWithString:thumbUrl]];
                if ([[SDImageCache sharedImageCache] sd_imageExistsForWithKey:key]) {
                    
                    self.loadingOriginalImage = YES;
                    
                    // 从缓存里取出缩略图展示
                    [[SDWebImageManager sharedManager] downloadImageWithURL:[NSURL URLWithString:thumbUrl] options:0 progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                        if (!image) {
                            return;
                        }
                        self.underlyingImage = image;
                        [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
                    }];
                }
            }
            
            // 加载大图
            SDWebImageManager *manager = [SDWebImageManager sharedManager];
            [manager downloadWithURL:_photoURL
                             options:SDWebImageRetryFailed
                            progress:^(NSInteger receivedSize, NSInteger expectedSize) {
                                
                                //NSLog(@"progress %d, %lld", receivedSize, expectedSize);
                                
                                // todo remove
                                if (expectedSize == 0) {
                                    expectedSize = 300 * 1024;
                                }
                                
                                float progress = receivedSize / (float)expectedSize;
                                if (self.progressUpdateBlock) {
                                    self.progressUpdateBlock(progress);
                                }
                            }
                           completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished) {
                               self.loadingOriginalImage = NO;
                               if (error) {
                                   // todo reload
                                   self.underlyingImage = nil;
                                   [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
                                   NSLog(@"SDWebImage failed to download image: %@, url%@", error, _photoURL);
                                   NSString *errMsg = error.localizedDescription;
                                   if (error.domain == NSURLErrorDomain) {
                                       errMsg = [NSString stringWithFormat:@"图片载入失败\n%@(%@)", [NSHTTPURLResponse localizedStringForStatusCode:error.code], @(error.code)];
                                   }
                                   [SVProgressHUD showErrorWithStatus:errMsg];
                                   return;
                               }
                               self.underlyingImage = image;
                               [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
                           }];
        } else {
            // Failed - no source
            self.underlyingImage = nil;
            [self imageLoadingComplete];
        }
    }
}

// Release if we can get it again from path or url
- (void)unloadUnderlyingImage {
    _loadingInProgress = NO;

	if (self.underlyingImage && (_photoPath || _photoURL)) {
		self.underlyingImage = nil;
	}
}

#pragma mark - Async Loading

/*- (UIImage *)decodedImageWithImage:(UIImage *)image {
    CGImageRef imageRef = image.CGImage;
    // System only supports RGB, set explicitly and prevent context error
    // if the downloaded image is not the supported format
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 CGImageGetWidth(imageRef),
                                                 CGImageGetHeight(imageRef),
                                                 8,
                                                 // width * 4 will be enough because are in ARGB format, don't read from the image
                                                 CGImageGetWidth(imageRef) * 4,
                                                 colorSpace,
                                                 // kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little
                                                 // makes system don't need to do extra conversion when displayed.
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);
    
    if ( ! context) {
        return nil;
    }
    
    CGRect rect = (CGRect){CGPointZero, CGImageGetWidth(imageRef), CGImageGetHeight(imageRef)};
    CGContextDrawImage(context, rect, imageRef);
    CGImageRef decompressedImageRef = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    
    UIImage *decompressedImage = [[UIImage alloc] initWithCGImage:decompressedImageRef];
    CGImageRelease(decompressedImageRef);
    return decompressedImage;
}*/

- (UIImage *)decodedImageWithImage:(UIImage *)image {
    if (image.images)
    {
        // Do not decode animated images
        return image;
    }
    
    CGImageRef imageRef = image.CGImage;
    CGSize imageSize = CGSizeMake(CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
    CGRect imageRect = (CGRect){.origin = CGPointZero, .size = imageSize};
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(imageRef);
    
    int infoMask = (bitmapInfo & kCGBitmapAlphaInfoMask);
    BOOL anyNonAlpha = (infoMask == kCGImageAlphaNone ||
                        infoMask == kCGImageAlphaNoneSkipFirst ||
                        infoMask == kCGImageAlphaNoneSkipLast);
    
    // CGBitmapContextCreate doesn't support kCGImageAlphaNone with RGB.
    // https://developer.apple.com/library/mac/#qa/qa1037/_index.html
    if (infoMask == kCGImageAlphaNone && CGColorSpaceGetNumberOfComponents(colorSpace) > 1)
    {
        // Unset the old alpha info.
        bitmapInfo &= ~kCGBitmapAlphaInfoMask;
        
        // Set noneSkipFirst.
        bitmapInfo |= kCGImageAlphaNoneSkipFirst;
    }
    // Some PNGs tell us they have alpha but only 3 components. Odd.
    else if (!anyNonAlpha && CGColorSpaceGetNumberOfComponents(colorSpace) == 3)
    {
        // Unset the old alpha info.
        bitmapInfo &= ~kCGBitmapAlphaInfoMask;
        bitmapInfo |= kCGImageAlphaPremultipliedFirst;
    }
    
    // It calculates the bytes-per-row based on the bitsPerComponent and width arguments.
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 imageSize.width,
                                                 imageSize.height,
                                                 CGImageGetBitsPerComponent(imageRef),
                                                 0,
                                                 colorSpace,
                                                 bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    
    // If failed, return undecompressed image
    if (!context) return image;
	
    CGContextDrawImage(context, imageRect, imageRef);
    CGImageRef decompressedImageRef = CGBitmapContextCreateImage(context);
	
    CGContextRelease(context);
	
    UIImage *decompressedImage = [UIImage imageWithCGImage:decompressedImageRef scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(decompressedImageRef);
    return decompressedImage;
}

// Called in background
// Load image in background from local file
- (void)loadImageFromFileAsync {
    @autoreleasepool {
        @try {
            self.underlyingImage = [UIImage imageWithContentsOfFile:_photoPath];
            if (!_underlyingImage) {
                //IDMLog(@"Error loading photo from path: %@", _photoPath);
            }
        } @finally {
            self.underlyingImage = [self decodedImageWithImage: self.underlyingImage];
            [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
        }
    }
}

// Called on main
- (void)imageLoadingComplete {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    // Complete so notify
    _loadingInProgress = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:IDMPhoto_LOADING_DID_END_NOTIFICATION
                                                        object:self];
}
- (void)dealloc
{
    
}
@end
