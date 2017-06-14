#import "ImageManager.h"
#import "Common.h"
#import "ImageManagerTask.h"

@interface ImageManager ()
{
    NSMutableArray *_dataSourceList;
}

@end

@implementation ImageManager

+ (ImageManager *)instance
{
    static ImageManager *singleton = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        singleton = [[ImageManager alloc] init];
    });
    return singleton;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        _dataSourceList = [[NSMutableArray alloc] init];
    }
    return self;
}

#pragma mark -

static UIImage *forceImageDecoding(UIImage *image)
{
    if (image == nil || CGSizeEqualToSize(image.size, CGSizeZero))
        return nil;
    
    UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale);
    [image drawAtPoint:CGPointZero blendMode:kCGBlendModeCopy alpha:1.0f];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return result;
}

- (UIImage *)loadImageSyncWithUri:(NSString *)uri canWait:(bool)canWait decode:(bool)decode acceptPartialData:(bool)acceptPartialData asyncTaskId:(__autoreleasing id *)asyncTaskId progress:(void (^)(float))progress partialCompletion:(void (^)(UIImage *))partialCompletion completion:(void (^)(UIImage *))completion
{
    DataResource *imageData = [self loadDataSyncWithUri:uri canWait:canWait acceptPartialData:acceptPartialData asyncTaskId:asyncTaskId progress:progress partialCompletion:^(DataResource *resource)
    {
        if (resource != nil)
        {
            UIImage *image = [resource image];
            if (image != nil)
            {
                if (decode && ![resource isImageDecoded])
                    image = forceImageDecoding(image);
                
                if (partialCompletion != nil)
                    partialCompletion(image);
            }
            else
            {
                NSData *data = [resource data];
                UIImage *dataImage = [[UIImage alloc] initWithData:data];
                if (dataImage != nil && decode)
                    dataImage = forceImageDecoding(dataImage);
                
                if (partialCompletion != nil)
                    partialCompletion(dataImage);
            }
        }
    } completion:^(DataResource *resource)
    {
        if (resource != nil)
        {
            UIImage *image = [resource image];
            if (image != nil)
            {
                if (decode && ![resource isImageDecoded])
                    image = forceImageDecoding(image);
                
                if (completion != nil)
                    completion(image);
            }
            else
            {
                NSData *data = [resource data];
                UIImage *dataImage = [[UIImage alloc] initWithData:data];
                if (dataImage != nil && decode)
                    dataImage = forceImageDecoding(dataImage);
                
                if (completion != nil)
                    completion(dataImage);
            }
        }
        else if (completion != nil)
            completion(nil);
    }];
    if (imageData != nil)
    {
        UIImage *image = [imageData image];
        if (image != nil)
        {
            if (decode && ![imageData isImageDecoded])
                image = forceImageDecoding(image);
            
            return image;
        }
        else
        {
            NSData *data = [imageData data];
            UIImage *dataImage = [[UIImage alloc] initWithData:data];
            if (dataImage != nil)
            {
                if (decode)
                    return forceImageDecoding(dataImage);
                else
                    return dataImage;
            }
        }
    }
    
    return nil;
}

- (id)beginLoadingImageAsyncWithUri:(NSString *)uri decode:(bool)decode progress:(void (^)(float))progress partialCompletion:(void (^)(UIImage *))partialCompletion completion:(void (^)(UIImage *))completion
{
    return [self _loadDataAsyncWithUri:uri progress:progress partialCompletion:^(DataResource *resource)
    {
        if (resource != nil)
        {
            UIImage *image = [resource image];
            if (image != nil)
            {
                if (decode && ![resource isImageDecoded])
                    image = forceImageDecoding(image);
                
                if (partialCompletion != nil)
                    partialCompletion(image);
            }
            else
            {
                NSData *data = [resource data];
                UIImage *dataImage = [[UIImage alloc] initWithData:data];
                if (dataImage != nil && decode)
                    dataImage = forceImageDecoding(dataImage);
                
                if (partialCompletion != nil)
                    partialCompletion(dataImage);
            }
        }
    } completion:^(DataResource *resource)
    {
        if (resource != nil)
        {
            UIImage *image = [resource image];
            if (image != nil)
            {
                if (decode && ![resource isImageDecoded])
                    image = forceImageDecoding(image);
                
                if (completion != nil)
                    completion(image);
            }
            else
            {
                NSData *data = [resource data];
                UIImage *dataImage = [[UIImage alloc] initWithData:data];
                if (dataImage != nil && decode)
                    dataImage = forceImageDecoding(dataImage);
                
                if (completion != nil)
                    completion(dataImage);
            }
        }
        else if (completion != nil)
            completion(nil);
    }];
}

- (DataResource *)loadDataSyncWithUri:(NSString *)uri canWait:(bool)canWait acceptPartialData:(bool)acceptPartialData asyncTaskId:(__autoreleasing id *)asyncTaskId progress:(void (^)(float))progress partialCompletion:(void (^)(DataResource *))partialCompletion completion:(void (^)(DataResource *))completion
{
    __block ImageDataSource *selectedDataSource = nil;
    [ImageDataSource enumerateDataSources:^bool(ImageDataSource *dataSource)
    {
        if ([dataSource canHandleUri:uri])
        {
            selectedDataSource = dataSource;
            return true;
        }
        
        return false;
    }];
    
    if (selectedDataSource != nil)
        return [selectedDataSource loadDataSyncWithUri:uri canWait:canWait acceptPartialData:acceptPartialData asyncTaskId:asyncTaskId progress:progress partialCompletion:partialCompletion completion:completion];
    
    return nil;
}

- (id)loadAttributeSyncForUri:(NSString *)uri attribute:(NSString *)attribute
{
    __block ImageDataSource *selectedDataSource = nil;
    [ImageDataSource enumerateDataSources:^bool(ImageDataSource *dataSource)
    {
        if ([dataSource canHandleAttributeUri:uri])
        {
            selectedDataSource = dataSource;
            return true;
        }
        
        return false;
    }];
    
    if (selectedDataSource != nil)
        return [selectedDataSource loadAttributeSyncForUri:uri attribute:attribute];
    
    return nil;
}

- (id)_loadDataAsyncWithUri:(NSString *)uri progress:(void (^)(float progress))progress partialCompletion:(void (^)(DataResource *resource))partialCompletion completion:(void (^)(DataResource *resource))completion
{
    __block ImageDataSource *selectedDataSource = nil;
    [ImageDataSource enumerateDataSources:^bool(ImageDataSource *dataSource)
    {
        if ([dataSource canHandleUri:uri])
        {
            selectedDataSource = dataSource;
            return true;
        }
        
        return false;
    }];
    
    if (selectedDataSource != nil)
    {
        ImageManagerTask *taskId = [[ImageManagerTask alloc] init];
        taskId.dataSource = selectedDataSource;
        taskId.childTaskId = [selectedDataSource loadDataAsyncWithUri:uri progress:progress partialCompletion:partialCompletion completion:completion];
        
        return taskId;
    }
    else
    {
        TGLog(@"[ImageManager#%p Data source not found for URI: %@]", self, uri);
        
        if (completion)
            completion(nil);
    }
    
    return nil;
}

- (void)cancelTaskWithId:(id)taskId
{
    if ([taskId isKindOfClass:[ImageManagerTask class]])
    {
        ImageManagerTask *concreteTaskId = (ImageManagerTask *)taskId;
        concreteTaskId->_isCancelled = true;
        if (concreteTaskId.childTaskId != nil)
            [concreteTaskId.dataSource cancelTaskById:concreteTaskId.childTaskId];
    }
}

@end
