#import "PhotoQualityController.h"

#import "ImageUtils.h"
#import "StringUtils.h"
#import "PhotoEditorUtils.h"

#import "PhotoEditorInterfaceAssets.h"
#import "PhotoEditorAnimation.h"

#import "ModernGalleryVideoView.h"
#import "PhotoEditorPreviewView.h"
#import "PhotoEditorGenericToolView.h"
#import "PhotoEditorToolButtonsView.h"

#import "MediaAsset.h"
#import "MediaAssetImageSignals.h"
#import "MediaVideoConverter.h"

#import "PaintingWrapperView.h"
#import "MessageImageViewOverlayView.h"
#import "Common.h"
#import "PhotoEditor.h" 

const NSTimeInterval PhotoQualityPreviewDuration = 15.0f;

@interface PhotoQuality : NSObject <PhotoEditorItem>

@property (nonatomic, assign) bool hasAudio;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, readonly) NSInteger finalValue;
@property (nonatomic, assign) CGFloat maximumValue;

@end

@interface PhotoQualityController ()
{
    PhotoQuality *_quality;
    
    UIView *_initialPreviewSuperview;
    UIView *_wrapperView;
    UIView *_portraitToolsWrapperView;
    UIView *_landscapeToolsWrapperView;
    
    UIView <PhotoEditorToolView> *_portraitToolControlView;
    UIView <PhotoEditorToolView> *_landscapeToolControlView;
    
    PhotoEditorToolButtonsView *_portraitButtonsView;
    PhotoEditorToolButtonsView *_landscapeButtonsView;
    
    bool _dismissing;
    bool _animating;
    
    MessageImageViewOverlayView *_overlayView;
    ModernGalleryVideoView *_videoView;
    AVPlayer *_player;
    SMetaDisposable *_disposable;
    id _playerStartedObserver;
    id _playerReachedEndObserver;
    
    NSInteger _previewId;
    NSTimeInterval _fileDuration;
    bool _hasAudio;
    
    MediaVideoConversionPreset _currentPreset;
}

@property (nonatomic, weak) PhotoEditor *photoEditor;
@property (nonatomic, weak) PhotoEditorPreviewView *previewView;

@end

@implementation PhotoQualityController

- (instancetype)initWithPhotoEditor:(PhotoEditor *)photoEditor
{
    self = [super init];
    if (self != nil)
    {
        self.photoEditor = photoEditor;
        _previewId = (int)arc4random();
        _currentPreset = MediaVideoConversionPresetCompressedDefault;
        
        _quality = [[PhotoQuality alloc] init];
        
        NSInteger value = 0;
        if (photoEditor.preset != MediaVideoConversionPresetCompressedDefault)
        {
            value = photoEditor.preset;
        }
        else
        {
            NSNumber *presetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"TG_preferredVideoPreset_v0"];
            if (presetValue != nil)
                value = [presetValue integerValue];
            else
                value = MediaVideoConversionPresetCompressedMedium;
        }
        
        _disposable = [[SMetaDisposable alloc] init];
        
        _quality.value = @(value - 1);
    }
    return self;
}

- (void)dealloc
{
    [self cleanupVideoPreviews];
}

- (void)loadView
{
    [super loadView];
    
    __weak PhotoQualityController *weakSelf = self;
    void(^interactionEnded)(void) = ^
    {
        __strong PhotoQualityController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        if ([strongSelf shouldAutorotate])
            [ViewController attemptAutorotation];
        
        [strongSelf generateVideoPreview];
    };
    
    CGSize dimensions = CGSizeZero;
    if ([self.item isKindOfClass:[MediaAsset class]])
        dimensions = ((MediaAsset *)self.item).dimensions;
    else if ([self.item isKindOfClass:[AVAsset class]])
        dimensions = [((AVAsset *)self.item) tracksWithMediaType:AVMediaTypeVideo].firstObject.naturalSize;
    
    if (!CGSizeEqualToSize(dimensions, CGSizeZero))
        _quality.maximumValue = [MediaVideoConverter bestAvailablePresetForDimensions:dimensions] - 1;
    else
        _quality.maximumValue = MediaVideoConversionPresetCompressedMedium - 1;
        
    _wrapperView = [[UIView alloc] initWithFrame:CGRectZero];
    _wrapperView.alpha = 0.0f;
    _wrapperView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:_wrapperView];
    
    _portraitToolsWrapperView = [[UIView alloc] initWithFrame:CGRectZero];
    [_wrapperView addSubview:_portraitToolsWrapperView];
    
    _landscapeToolsWrapperView = [[UIView alloc] initWithFrame:CGRectZero];
    [_wrapperView addSubview:_landscapeToolsWrapperView];
    
    _overlayView = [[MessageImageViewOverlayView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 44.0f, 44.0f)];
    _overlayView.alpha = 0.0f;
    [_overlayView setRadius:44.0f];
    [self.view addSubview:_overlayView];
        
    _portraitToolControlView = [_quality itemControlViewWithChangeBlock:^(id newValue, __unused bool animated)
    {
        __strong PhotoQualityController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_landscapeToolControlView setValue:newValue];
    }];
    _portraitToolControlView.backgroundColor = [PhotoEditorInterfaceAssets panelBackgroundColor];
    _portraitToolControlView.clipsToBounds = true;
    _portraitToolControlView.interactionEnded = interactionEnded;
    _portraitToolControlView.layer.rasterizationScale = TGScreenScaling();
    _portraitToolControlView.isLandscape = false;
    [_portraitToolsWrapperView addSubview:_portraitToolControlView];
    
    _landscapeToolControlView = [_quality itemControlViewWithChangeBlock:^(id newValue, __unused bool animated)
    {
        __strong PhotoQualityController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_portraitToolControlView setValue:newValue];
    }];
    _landscapeToolControlView.backgroundColor = [PhotoEditorInterfaceAssets panelBackgroundColor];
    _landscapeToolControlView.clipsToBounds = true;
    _landscapeToolControlView.interactionEnded = interactionEnded;
    _landscapeToolControlView.layer.rasterizationScale = TGScreenScaling();
    _landscapeToolControlView.isLandscape = true;
    _landscapeToolControlView.toolbarLandscapeSize = self.toolbarLandscapeSize;
    [_landscapeToolsWrapperView addSubview:_landscapeToolControlView];
    
    void(^cancelPressed)(void) = ^
    {
        __strong PhotoQualityController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf.mainController dismissEditor];
    };
    
    void(^confirmPressed)(void) = ^
    {
        __strong PhotoQualityController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        if (strongSelf->_portraitToolControlView.isTracking || strongSelf->_landscapeToolControlView.isTracking || strongSelf->_animating)
            return;
        
        [[NSUserDefaults standardUserDefaults] setObject:@(strongSelf.preset) forKey:@"TG_preferredVideoPreset_v0"];
    
        [strongSelf.mainController applyEditor];
    };
    
    NSString *cancelButton = TGLocalized(@"Cancel");
    NSString *doneButton = TGLocalized(@"Done");
    
    _portraitButtonsView = [[PhotoEditorToolButtonsView alloc] initWithCancelButton:cancelButton doneButton:doneButton];
    _portraitButtonsView.cancelPressed = cancelPressed;
    _portraitButtonsView.confirmPressed = confirmPressed;
    [_portraitToolsWrapperView addSubview:_portraitButtonsView];
    
    _landscapeButtonsView = [[PhotoEditorToolButtonsView alloc] initWithCancelButton:cancelButton doneButton:doneButton];
    _landscapeButtonsView.cancelPressed = cancelPressed;
    _landscapeButtonsView.confirmPressed = confirmPressed;
    [_landscapeToolsWrapperView addSubview:_landscapeButtonsView];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self transitionIn];
}

- (void)attachPreviewView:(PhotoEditorPreviewView *)previewView
{
    self.previewView = previewView;
    _initialPreviewSuperview = previewView.superview;
    [self.view insertSubview:previewView aboveSubview:_wrapperView];
    
    if (self.finishedCombinedTransition != nil)
        self.finishedCombinedTransition();
    
    [UIView animateWithDuration:0.3f animations:^
    {
        _overlayView.alpha = 1.0f;
    }];
    [self generateVideoPreview];
}

#pragma mark - Transition

- (void)prepareForCombinedAppearance
{
    _wrapperView.backgroundColor = [UIColor clearColor];
    _portraitToolControlView.backgroundColor = [UIColor clearColor];
    _landscapeToolControlView.backgroundColor = [UIColor clearColor];
}

- (void)finishedCombinedAppearance
{
    _wrapperView.backgroundColor = [UIColor blackColor];
    _portraitToolControlView.backgroundColor = [PhotoEditorInterfaceAssets panelBackgroundColor];
    _landscapeToolControlView.backgroundColor = [PhotoEditorInterfaceAssets panelBackgroundColor];
}

- (void)transitionIn
{
    if (UIInterfaceOrientationIsPortrait(self.interfaceOrientation))
        _portraitToolControlView.layer.shouldRasterize = true;
    else
        _landscapeToolControlView.layer.shouldRasterize = true;
    
    CGRect targetFrame;
    CGRect toolTargetFrame;
    switch (self.interfaceOrientation)
    {
        case UIInterfaceOrientationLandscapeLeft:
        {
            targetFrame = _landscapeButtonsView.frame;
            _landscapeButtonsView.frame = CGRectOffset(_landscapeButtonsView.frame, -_landscapeButtonsView.frame.size.width, 0);
            toolTargetFrame = _landscapeToolsWrapperView.frame;
            _landscapeToolsWrapperView.frame = CGRectOffset(_landscapeToolsWrapperView.frame, -_landscapeToolsWrapperView.frame.size.width / 2 - 20, 0);
        }
            break;
        case UIInterfaceOrientationLandscapeRight:
        {
            targetFrame = _landscapeButtonsView.frame;
            _landscapeButtonsView.frame = CGRectOffset(_landscapeButtonsView.frame, _landscapeButtonsView.frame.size.width, 0);
            toolTargetFrame = _landscapeToolsWrapperView.frame;
            _landscapeToolsWrapperView.frame = CGRectOffset(_landscapeToolsWrapperView.frame, _landscapeToolsWrapperView.frame.size.width / 2 + 20, 0);
        }
            break;
            
        default:
        {
            targetFrame = _portraitButtonsView.frame;
            _portraitButtonsView.frame = CGRectOffset(_portraitButtonsView.frame, 0, _portraitButtonsView.frame.size.height);
            toolTargetFrame = _portraitToolsWrapperView.frame;
            _portraitToolsWrapperView.frame = CGRectOffset(_portraitToolsWrapperView.frame, 0, _portraitToolsWrapperView.frame.size.height / 2 + 20);
        }
            break;
    }
    
    void (^animationBlock)(void) = ^
    {
        if (UIInterfaceOrientationIsPortrait(self.interfaceOrientation)) {
            _portraitButtonsView.frame = targetFrame;
            _portraitToolsWrapperView.frame = toolTargetFrame;
        }
        else {
            _landscapeButtonsView.frame = targetFrame;
            _landscapeToolsWrapperView.frame = toolTargetFrame;
        }
    };
    
    [UIView animateWithDuration:0.3f animations:^
    {
        _wrapperView.alpha = 1.0f;
    } completion:^(BOOL finished)
    {
        if (finished)
        {
            _portraitToolControlView.layer.shouldRasterize = false;
            _landscapeToolControlView.layer.shouldRasterize = false;
        }
    }];

    if (iosMajorVersion() >= 7)
        [UIView animateWithDuration:0.4f delay:0.0f usingSpringWithDamping:1.0f initialSpringVelocity:0.0f options:UIViewAnimationOptionCurveLinear animations:animationBlock completion:nil];
    else
        [UIView animateWithDuration:0.3f delay:0.0f options:UIViewAnimationOptionAllowUserInteraction animations:animationBlock completion:nil];
}

- (void)_animatePreviewViewTransitionOutToFrame:(CGRect)targetFrame saving:(bool)saving parentView:(UIView *)__unused parentView completion:(void (^)(void))completion
{
    [_disposable dispose];
    
    _dismissing = true;
    
    _overlayView.hidden = true;
    if (_player != nil)
        [_player pause];
    
    if (self.beginTransitionOut != nil)
        self.beginTransitionOut();
    
    _wrapperView.backgroundColor = [UIColor clearColor];
    
    [_initialPreviewSuperview addSubview:self.previewView];
    
    if (UIInterfaceOrientationIsPortrait(self.interfaceOrientation))
        _portraitToolControlView.layer.shouldRasterize = true;
    else
        _landscapeToolControlView.layer.shouldRasterize = true;
    
    [UIView animateWithDuration:0.3f animations:^
    {
        _wrapperView.alpha = 0.0f;
    } completion:^(__unused BOOL finished)
    {

    }];
    
    void (^animationBlock)(void) = ^
    {
        switch (self.interfaceOrientation)
        {
            case UIInterfaceOrientationLandscapeLeft:
            {
                _landscapeButtonsView.frame = CGRectOffset(_landscapeButtonsView.frame, -_landscapeButtonsView.frame.size.width, 0);
            }
                break;
            case UIInterfaceOrientationLandscapeRight:
            {
                _landscapeButtonsView.frame = CGRectOffset(_landscapeButtonsView.frame, _landscapeButtonsView.frame.size.width, 0);
            }
                break;
                
            default:
            {
                _portraitButtonsView.frame = CGRectOffset(_portraitButtonsView.frame, 0, _portraitButtonsView.frame.size.height);
            }
                break;
        }
    };
    
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
//    if ([self inFormSheet] || [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
//    {
        orientation = UIInterfaceOrientationPortrait;
//    }
//    else if ([self.presentingViewController isKindOfClass:[TGNavigationController class]] &&
//             [(TGNavigationController *)self.presentingViewController presentationStyle] == TGNavigationControllerPresentationStyleInFormSheet)
//    {
//        orientation = UIInterfaceOrientationPortrait;
//    }
    
    if (UIInterfaceOrientationIsPortrait(orientation))
        _landscapeToolsWrapperView.hidden = true;
    else
        _portraitToolsWrapperView.hidden = true;
    
    void (^finishedBlock)(BOOL) = ^(__unused BOOL finished)
    {
        completion();
    };
    
    if (iosMajorVersion() >= 7)
    {
        [UIView animateWithDuration:0.4f delay:0.0f usingSpringWithDamping:1.0f initialSpringVelocity:0.0f options:UIViewAnimationOptionCurveLinear animations:animationBlock completion:finishedBlock];
    }
    else
    {
        [UIView animateWithDuration:0.3f delay:0.0f options:UIViewAnimationOptionAllowUserInteraction animations:animationBlock completion:finishedBlock];
    }
    
    UIView *previewView = _videoView ?: self.previewView;
    UIView *snapshotView = nil;
    POPSpringAnimation *snapshotAnimation = nil;
    POPSpringAnimation *snapshotAlphaAnimation = nil;

    if (saving && CGRectIsNull(targetFrame) && parentView != nil)
    {
        snapshotView = [previewView snapshotViewAfterScreenUpdates:false];
        snapshotView.frame = previewView.frame;
        
        CGSize fittedSize = ScaleToSize(previewView.frame.size, self.view.frame.size);
        targetFrame = CGRectMake((self.view.frame.size.width - fittedSize.width) / 2,
                                 (self.view.frame.size.height - fittedSize.height) / 2,
                                 fittedSize.width,
                                 fittedSize.height);
        
        [parentView addSubview:snapshotView];
        
        snapshotAnimation = [PhotoEditorAnimation prepareTransitionAnimationForPropertyNamed:kPOPViewFrame];
        snapshotAnimation.fromValue = [NSValue valueWithCGRect:snapshotView.frame];
        snapshotAnimation.toValue = [NSValue valueWithCGRect:targetFrame];
        
        snapshotAlphaAnimation = [PhotoEditorAnimation prepareTransitionAnimationForPropertyNamed:kPOPViewAlpha];
        snapshotAlphaAnimation.fromValue = @(snapshotView.alpha);
        snapshotAlphaAnimation.toValue = @(0.0f);
    }
    
    if (previewView != self.previewView)
        self.previewView.hidden = true;

    POPSpringAnimation *previewAnimation = [PhotoEditorAnimation prepareTransitionAnimationForPropertyNamed:kPOPViewFrame];
    previewAnimation.fromValue = [NSValue valueWithCGRect:previewView.frame];
    previewAnimation.toValue = [NSValue valueWithCGRect:targetFrame];
    
    POPSpringAnimation *previewAlphaAnimation = [PhotoEditorAnimation prepareTransitionAnimationForPropertyNamed:kPOPViewAlpha];
    previewAlphaAnimation.fromValue = @(previewView.alpha);
    previewAlphaAnimation.toValue = @(0.0f);
    
    NSMutableArray *animations = [NSMutableArray arrayWithArray:@[ previewAnimation, previewAlphaAnimation ]];
    if (snapshotAnimation != nil)
        [animations addObject:snapshotAnimation];
    
    [PhotoEditorAnimation performBlock:^(__unused bool allFinished)
    {
        [snapshotView removeFromSuperview];
         
        if (completion != nil)
            completion();
    } whenCompletedAllAnimations:animations];
    
    if (snapshotAnimation != nil)
    {
        [snapshotView pop_addAnimation:snapshotAnimation forKey:@"frame"];
    }
    [previewView pop_addAnimation:previewAnimation forKey:@"frame"];
    [previewView pop_addAnimation:previewAlphaAnimation forKey:@"alpha"];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    [self updateLayout:[UIApplication sharedApplication].statusBarOrientation];
}

- (CGSize)referenceViewSize
{
    if (self.parentViewController != nil)
    {
        PhotoEditorController *controller = (PhotoEditorController *)self.parentViewController;
        return [controller referenceViewSize];
    }
    
    return CGSizeZero;
}

- (MediaVideoConversionPreset)preset
{
    return (MediaVideoConversionPreset)_quality.finalValue;
}

- (void)updateLayout:(UIInterfaceOrientation)orientation
{
    CGSize referenceSize = [self referenceViewSize];
    
//    if ([self inFormSheet] || [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
//    {
        orientation = UIInterfaceOrientationPortrait;
//    }
//    else if ([self.presentingViewController isKindOfClass:[TGNavigationController class]] && [(TGNavigationController *)self.presentingViewController presentationStyle] == TGNavigationControllerPresentationStyleInFormSheet)
//    {
//        orientation = UIInterfaceOrientationPortrait;
//    }
    
    CGFloat screenSide = MAX(referenceSize.width, referenceSize.height) + 2 * PhotoEditorPanelSize;
    _wrapperView.frame = CGRectMake((referenceSize.width - screenSide) / 2, (referenceSize.height - screenSide) / 2, screenSide, screenSide);
    
    CGFloat panelToolbarPortraitSize = PhotoEditorPanelSize + PhotoEditorToolbarSize;
    CGFloat panelToolbarLandscapeSize = PhotoEditorPanelSize + self.toolbarLandscapeSize;
    
    switch (orientation)
    {
        case UIInterfaceOrientationLandscapeLeft:
        {
            [UIView performWithoutAnimation:^
            {
                _landscapeToolsWrapperView.frame = CGRectMake(0, (screenSide - referenceSize.height) / 2, panelToolbarLandscapeSize, _landscapeToolsWrapperView.frame.size.height);
                _landscapeToolControlView.frame = CGRectMake(panelToolbarLandscapeSize - PhotoEditorPanelSize, 0, PhotoEditorPanelSize, _landscapeToolsWrapperView.frame.size.height);
                
                if (!_dismissing)
                    _landscapeButtonsView.frame = CGRectMake(0, 0, [_landscapeButtonsView landscapeSize], referenceSize.height);
            }];
            
            _landscapeToolsWrapperView.frame = CGRectMake((screenSide - referenceSize.width) / 2, (screenSide - referenceSize.height) / 2, panelToolbarLandscapeSize, referenceSize.height);
            
            _landscapeToolControlView.frame = CGRectMake(panelToolbarLandscapeSize - PhotoEditorPanelSize, 0, PhotoEditorPanelSize, _landscapeToolsWrapperView.frame.size.height);
            
            _portraitToolsWrapperView.frame = CGRectMake((screenSide - referenceSize.width) / 2, screenSide - panelToolbarPortraitSize, referenceSize.width, panelToolbarPortraitSize);
        }
            break;
            
        case UIInterfaceOrientationLandscapeRight:
        {
            [UIView performWithoutAnimation:^
            {
                _landscapeToolsWrapperView.frame = CGRectMake(screenSide - panelToolbarLandscapeSize, (screenSide - referenceSize.height) / 2, panelToolbarLandscapeSize, _landscapeToolsWrapperView.frame.size.height);
                _landscapeToolControlView.frame = CGRectMake(0, 0, PhotoEditorPanelSize, _landscapeToolsWrapperView.frame.size.height);
                
                if (!_dismissing)
                    _landscapeButtonsView.frame = CGRectMake(panelToolbarLandscapeSize - [_landscapeButtonsView landscapeSize], 0, [_landscapeButtonsView landscapeSize], referenceSize.height);
            }];
            
            _landscapeToolsWrapperView.frame = CGRectMake((screenSide + referenceSize.width) / 2 - panelToolbarLandscapeSize, (screenSide - referenceSize.height) / 2, panelToolbarLandscapeSize, referenceSize.height);
            
            _landscapeToolControlView.frame = CGRectMake(0, 0, PhotoEditorPanelSize, _landscapeToolsWrapperView.frame.size.height);
            
            _portraitToolsWrapperView.frame = CGRectMake((screenSide - referenceSize.width) / 2, screenSide - panelToolbarPortraitSize, referenceSize.width, panelToolbarPortraitSize);
        }
            break;
            
        default:
        {
            CGFloat x = _landscapeToolsWrapperView.frame.origin.x;
            if (x < screenSide / 2)
                x = 0;
            else
                x = screenSide - PhotoEditorPanelSize;
            _landscapeToolsWrapperView.frame = CGRectMake(x, (screenSide - referenceSize.height) / 2, panelToolbarLandscapeSize, referenceSize.height);
            
            _portraitToolsWrapperView.frame = CGRectMake((screenSide - referenceSize.width) / 2, (screenSide + referenceSize.height) / 2 - panelToolbarPortraitSize, referenceSize.width, panelToolbarPortraitSize);
            
            if (!_dismissing)
                _portraitButtonsView.frame = CGRectMake(0, _portraitToolsWrapperView.frame.size.height - PhotoEditorToolButtonsViewSize, _portraitToolsWrapperView.frame.size.width, PhotoEditorToolButtonsViewSize);
            
            _portraitToolControlView.frame = CGRectMake(0, 0, _portraitToolsWrapperView.frame.size.width, _portraitToolsWrapperView.frame.size.height - _portraitButtonsView.frame.size.height);
        }
            break;
    }
    
    PhotoEditor *photoEditor = self.photoEditor;
    PhotoEditorPreviewView *previewView = self.previewView;
    
    if (_dismissing || previewView.superview != self.view)
        return;
    
    CGRect containerFrame = [PhotoEditorTabController photoContainerFrameForParentViewFrame:CGRectMake(0, 0, referenceSize.width, referenceSize.height) toolbarLandscapeSize:self.toolbarLandscapeSize orientation:orientation panelSize:PhotoEditorPanelSize];
    CGSize fittedSize = ScaleToSize(photoEditor.rotatedCropSize, containerFrame.size);
    previewView.frame = CGRectMake(containerFrame.origin.x + (containerFrame.size.width - fittedSize.width) / 2,
                                   containerFrame.origin.y + (containerFrame.size.height - fittedSize.height) / 2,
                                   fittedSize.width,
                                   fittedSize.height);
    
    _videoView.frame = previewView.frame;
    
    _overlayView.frame = CGRectMake(floor(previewView.frame.origin.x + (previewView.frame.size.width - _overlayView.frame.size.width) / 2.0f), floor(previewView.frame.origin.y + (previewView.frame.size.height - _overlayView.frame.size.height) / 2.0f), _overlayView.frame.size.width, _overlayView.frame.size.height);
}

- (void)_updateVideoDuration:(NSTimeInterval)duration hasAudio:(bool)hasAudio
{
    _fileDuration = duration;
    _hasAudio = hasAudio;
    
    VideoEditAdjustments *adjustments = [self.photoEditor exportAdjustments];
    if ([adjustments trimApplied])
        _quality.duration = adjustments.trimEndValue - adjustments.trimStartValue;
    else
        _quality.duration = _fileDuration;
}

- (NSURL *)_previewDirectoryURL
{
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"videopreview_%d", (int)_previewId]]];
}

- (void)cleanupVideoPreviews
{
    [[NSFileManager defaultManager] removeItemAtURL:[self _previewDirectoryURL] error:NULL];
}

- (void)generateVideoPreview
{
    if (self.preset == _currentPreset)
        return;
    
    _currentPreset = self.preset;
    
    SSignal *assetSignal = [self.item isKindOfClass:[MediaAsset class]] ? [MediaAssetImageSignals avAssetForVideoAsset:(MediaAsset *)self.item] : [SSignal single:(AVAsset *)self.item];

    if ([self.item isKindOfClass:[MediaAsset class]])
        [self _updateVideoDuration:((MediaAsset *)self.item).videoDuration hasAudio:true];
    
    VideoEditAdjustments *adjustments = [self.photoEditor exportAdjustments];
    adjustments = [adjustments editAdjustmentsWithPreset:self.preset maxDuration:PhotoQualityPreviewDuration];
    
    __block NSTimeInterval delay = 0.0;
    __weak PhotoQualityController *weakSelf = self;
    SSignal *convertSignal = [[assetSignal onNext:^(AVAsset *next) {
        __strong PhotoQualityController *strongSelf = weakSelf;
        if (strongSelf != nil)
        {
            bool hasAudio = [next tracksWithMediaType:AVMediaTypeAudio].count > 0;
            [strongSelf _updateVideoDuration:CMTimeGetSeconds(next.duration) hasAudio:hasAudio];
        }
    }] mapToSignal:^SSignal *(AVAsset *avAsset)
    {
        return  [[[[SSignal single:avAsset] delay:delay onQueue:[SQueue concurrentDefaultQueue]] mapToSignal:^SSignal *(AVAsset *avAsset) {
            return [MediaVideoConverter convertAVAsset:avAsset adjustments:adjustments watcher:nil inhibitAudio:true];
        }] onError:^(id error) {
            delay = 1.0;
        }];
    }];

    SSignal *urlSignal = nil;
    
    NSURL *fileUrl = [NSURL fileURLWithPath:[[self _previewDirectoryURL].path stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"%d.mov", self.preset]]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:fileUrl.path])
    {
        urlSignal = [SSignal single:fileUrl];
    }
    else
    {
        if (_player != nil)
            [_player pause];
        
        _overlayView.hidden = false;
        [_overlayView setProgress:0.03f cancelEnabled:false animated:true];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:[self _previewDirectoryURL].path])
            [[NSFileManager defaultManager] createDirectoryAtPath:[self _previewDirectoryURL].path withIntermediateDirectories:true attributes:nil error:NULL];
        
        urlSignal = [convertSignal map:^id(id value)
        {
            if ([value isKindOfClass:[MediaVideoConversionResult class]])
            {
                MediaVideoConversionResult *result = (MediaVideoConversionResult *)value;
                [[NSFileManager defaultManager] moveItemAtURL:result.fileURL toURL:fileUrl error:NULL];
                return fileUrl;
            }
            return value;
        }];
    }

    [_disposable setDisposable:[[urlSignal deliverOn:[SQueue mainQueue]] startWithNext:^(id next)
    {
        __strong PhotoQualityController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        if (strongSelf->_dismissing)
            return;
        
        if ([next isKindOfClass:[NSURL class]])
        {
            __block AVPlayer *previousPlayer;
            __block id previousPlayerReachedEndObserver;
            if (strongSelf->_player != nil)
            {
                previousPlayer = strongSelf->_player;
                previousPlayerReachedEndObserver = strongSelf->_playerReachedEndObserver;
                strongSelf->_playerReachedEndObserver = nil;
            }
            
            strongSelf->_player = [AVPlayer playerWithURL:next];
            strongSelf->_player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
            strongSelf->_player.muted = true;
            
            UIView *previousVideoView = strongSelf->_videoView;
            strongSelf->_videoView = [[ModernGalleryVideoView alloc] initWithFrame:strongSelf->_previewView.frame player:strongSelf->_player];
            strongSelf->_videoView.playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            strongSelf->_videoView.playerLayer.opaque = false;
            strongSelf->_videoView.playerLayer.backgroundColor = nil;
            UIView *belowView = strongSelf->_overlayView;
            if (previousVideoView != nil)
                belowView = previousVideoView;
            [strongSelf.view insertSubview:strongSelf->_videoView belowSubview:belowView];
            
            [strongSelf->_player play];
            
            [strongSelf updateLayout:strongSelf.interfaceOrientation];
            
            strongSelf->_overlayView.hidden = true;
            [strongSelf->_overlayView setProgress:0.03f cancelEnabled:false animated:true];
            
            DispatchAfter(0.2, dispatch_get_main_queue(), ^
            {
                DispatchAfter(0.1, dispatch_get_main_queue(), ^
                {
                    if (previousVideoView != nil)
                        [previousVideoView removeFromSuperview];
                });
                
                if (previousPlayer != nil)
                {
                    [strongSelf->_player seekToTime:previousPlayer.currentItem.currentTime];
                    if (previousPlayerReachedEndObserver != nil)
                        [previousPlayer removeTimeObserver:previousPlayerReachedEndObserver];
                        
                    previousPlayerReachedEndObserver = nil;
                    [previousPlayer pause];
                    previousPlayer = nil;
                }
                
                [strongSelf _setupPlaybackReachedEndObserver];
            });
        }
        else if ([next isKindOfClass:[NSNumber class]])
        {
            strongSelf->_overlayView.hidden = false;
            CGFloat progress = MAX(0.03, [next doubleValue]);
            [strongSelf->_overlayView setProgress:progress cancelEnabled:false animated:true];
        }
    } error:^(id error) {
        TGLog(@"Video Quality Preview Error: %@", error);
    } completed:nil]];
}

- (void)_setupPlaybackReachedEndObserver
{
    CMTime endTime = CMTimeSubtract(_player.currentItem.duration, CMTimeMake(10, 100));
    CMTime startTime = CMTimeMake(5, 100);
    
    __weak PhotoQualityController *weakSelf = self;
    _playerReachedEndObserver = [_player addBoundaryTimeObserverForTimes:@[[NSValue valueWithCMTime:endTime]] queue:NULL usingBlock:^
    {
        __strong PhotoQualityController *strongSelf = weakSelf;
        if (strongSelf != nil)
            [strongSelf->_player seekToTime:startTime];
    }];
}

@end


@implementation PhotoQuality

@synthesize value = _value;
@synthesize tempValue = _tempValue;
@synthesize maximumValue = _maximumValue;
@synthesize parameters = _parameters;
@synthesize beingEdited = _beingEdited;
@synthesize shouldBeSkipped = _shouldBeSkipped;
@synthesize parametersChanged = _parametersChanged;
@synthesize disabled = _disabled;

- (instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        _maximumValue = 4.0f;
    }
    return self;
}

- (bool)segmented
{
    return true;
}

- (NSString *)identifier
{
    return @"quality";
}

- (NSString *)title
{
    return TGLocalized(@"QualityTool");
}

- (CGFloat)defaultValue
{
    return 0.0f;
}

- (CGFloat)minimumValue
{
    return 0.0f;
}

- (CGFloat)maximumValue
{
    return _maximumValue;
}

- (void)setMaximumValue:(CGFloat)maximumValue
{
    _maximumValue = maximumValue;
    
    if ([self.value doubleValue] > maximumValue)
        self.value = @(maximumValue);
}

- (id)displayValue
{
    return self.value;
}

- (void)setValue:(id)value
{
    _value = value;
}

- (Class)valueClass
{
    return [NSNumber class];
}

- (NSInteger)finalValue
{
    return [self.value integerValue] + 1;
}

- (NSString *)stringValue
{
    NSInteger value = self.finalValue;
    NSString *title = nil;
    switch (value)
    {
        case MediaVideoConversionPresetCompressedVeryLow:
            title = @"240p"; //TGLocalized(@"QualityVeryLow");
            break;
            
        case MediaVideoConversionPresetCompressedLow:
            title = @"360p"; //TGLocalized(@"PhotoEditor.QualityLow");
            break;
            
        case MediaVideoConversionPresetCompressedMedium:
            title = @"480p"; //TGLocalized(@"QualityMedium");
            break;
            
        case MediaVideoConversionPresetCompressedHigh:
            title = @"720p"; //TGLocalized(@"PhotoEditor.QualityHigh");
            break;
            
        case MediaVideoConversionPresetCompressedVeryHigh:
            title = @"1080p"; //TGLocalized(@"PhotoEditor.QualityVeryHigh");
            break;
            
        default:
            break;
    }
    
    NSUInteger estimatedSize = [MediaVideoConverter estimatedSizeForPreset:(MediaVideoConversionPreset)value duration:self.duration hasAudio:self.hasAudio];
    return [NSString stringWithFormat:@"%@ (~%@)", title, [StringUtils stringForFileSize:estimatedSize precision:1]];
}

- (void)updateParameters
{
    
}

- (UIView <PhotoEditorToolView> *)itemControlViewWithChangeBlock:(void (^)(id newValue, bool animated))changeBlock
{
    __weak PhotoQuality *weakSelf = self;
    
    UIView <PhotoEditorToolView> *view = [[PhotoEditorGenericToolView alloc] initWithEditorItem:self];
    view.valueChanged = ^(id newValue, bool animated)
    {
        __strong PhotoQuality *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        if ([strongSelf.value isEqual:newValue])
            return;
        
        strongSelf.value = newValue;
        
        if (changeBlock != nil)
            changeBlock(newValue, animated);
    };
    return view;
}

- (UIView<PhotoEditorToolView> *)itemAreaViewWithChangeBlock:(void (^)(id))__unused changeBlock
{
    return nil;
}

@end
