//
//  RNFrostedMenu.m
//  RNFrostedMenu
//
//  Created by Ryan Nystrom on 8/13/13.
//  Copyright (c) 2013 Ryan Nystrom. All rights reserved.
//

#define __IPHONE_OS_VERSION_SOFT_MAX_REQUIRED __IPHONE_7_0

#import "RNFrostedSidebar.h"
#import <QuartzCore/QuartzCore.h>
#import <Accelerate/Accelerate.h>

#pragma mark - Private Classes

@interface RNBlurredView : UIView

@property (nonatomic, strong) UIView *parentTarget;
@property (nonatomic) CGFloat blurRadius;
@property (nonatomic, strong) UIColor *tintColor;
@property (nonatomic) CGFloat saturationDeltaFactor;

@end

@implementation RNBlurredView

- (void)drawRect:(CGRect)rect
{
	CGFloat blurRadius = self.blurRadius;
	CGFloat saturationDeltaFactor = self.saturationDeltaFactor;
	UIColor *tintColor = self.tintColor;
    
	CGRect target = [self.parentTarget convertRect:self.parentTarget.bounds toView:self];

	// Draw effect image.
	BOOL hasBlur = blurRadius > __FLT_EPSILON__;
    BOOL hasSaturationChange = fabs(saturationDeltaFactor - 1.) > __FLT_EPSILON__;

	UIImage *effectImage = nil;
	if (hasBlur || hasSaturationChange) {
		UIGraphicsBeginImageContextWithOptions(rect.size, YES, 0);
        CGContextRef effectInContext = UIGraphicsGetCurrentContext();
        CGContextScaleCTM(effectInContext, 1.0, -1.0);
		CGContextTranslateCTM(effectInContext, 0, -rect.size.height);

		[self.parentTarget drawViewHierarchyInRect:target afterScreenUpdates:YES];
        
        vImage_Buffer effectInBuffer;
        effectInBuffer.data     = CGBitmapContextGetData(effectInContext);
        effectInBuffer.width    = CGBitmapContextGetWidth(effectInContext);
        effectInBuffer.height   = CGBitmapContextGetHeight(effectInContext);
        effectInBuffer.rowBytes = CGBitmapContextGetBytesPerRow(effectInContext);
        
		UIGraphicsBeginImageContextWithOptions(rect.size, YES, 0);
        CGContextRef effectOutContext = UIGraphicsGetCurrentContext();
        vImage_Buffer effectOutBuffer;
        effectOutBuffer.data     = CGBitmapContextGetData(effectOutContext);
        effectOutBuffer.width    = CGBitmapContextGetWidth(effectOutContext);
        effectOutBuffer.height   = CGBitmapContextGetHeight(effectOutContext);
        effectOutBuffer.rowBytes = CGBitmapContextGetBytesPerRow(effectOutContext);
        
        if (hasBlur) {
            // A description of how to compute the box kernel width from the Gaussian
            // radius (aka standard deviation) appears in the SVG spec:
            // http://www.w3.org/TR/SVG/filters.html#feGaussianBlurElement
            //
            // For larger values of 's' (s >= 2.0), an approximation can be used: Three
            // successive box-blurs build a piece-wise quadratic convolution kernel, which
            // approximates the Gaussian kernel to within roughly 3%.
            //
            // let d = floor(s * 3*sqrt(2*pi)/4 + 0.5)
            //
            // ... if d is odd, use three box-blurs of size 'd', centered on the output pixel.
            //
			CGFloat inputRadius = blurRadius * self.window.screen.scale;
            NSUInteger radius = floor(inputRadius * 3. * sqrt(2 * M_PI) / 4 + 0.5);
            if (radius % 2 != 1) {
                radius += 1; // force radius to be odd so that the three box-blur methodology works.
            }
            vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, radius, radius, 0, kvImageEdgeExtend);
            vImageBoxConvolve_ARGB8888(&effectOutBuffer, &effectInBuffer, NULL, 0, 0, radius, radius, 0, kvImageEdgeExtend);
            vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, radius, radius, 0, kvImageEdgeExtend);
        }

		BOOL effectImageBuffersAreSwapped = (hasSaturationChange && hasBlur);

        if (hasSaturationChange) {
            CGFloat s = saturationDeltaFactor;
			const size_t size = 16;
			CGFloat floatingPointSaturationMatrix[size] = {
				0.0722 + 0.9278 * s,  0.0722 - 0.0722 * s,  0.0722 - 0.0722 * s, 0,
				0.7152 - 0.7152 * s,  0.7152 + 0.2848 * s,  0.7152 - 0.7152 * s, 0,
				0.2126 - 0.2126 * s,  0.2126 - 0.2126 * s,  0.2126 + 0.7873 * s, 0,
				0,                    0,                    0,					 1,
            };
            const int32_t divisor = 256;
			int16_t saturationMatrix[size];
			for (size_t i = 0; i < size; ++i) {
                saturationMatrix[i] = (int16_t)roundf(floatingPointSaturationMatrix[i] * divisor);
            }

            if (hasBlur) {
                vImageMatrixMultiply_ARGB8888(&effectOutBuffer, &effectInBuffer, saturationMatrix, divisor, NULL, NULL, kvImageNoFlags);
			} else {
                vImageMatrixMultiply_ARGB8888(&effectInBuffer, &effectOutBuffer, saturationMatrix, divisor, NULL, NULL, kvImageNoFlags);
            }
        }

        if (!effectImageBuffersAreSwapped)
            effectImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        if (effectImageBuffersAreSwapped)
            effectImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    
    // Set up output context.
    CGContextRef outputContext = UIGraphicsGetCurrentContext();

	if (!hasBlur) {
		[self.parentTarget drawViewHierarchyInRect:target afterScreenUpdates:YES];
	}

	if (tintColor) {
		CGContextSaveGState(outputContext);
	}

	if (hasBlur) {
		CGContextDrawImage(outputContext, rect, effectImage.CGImage);
	}

    if (tintColor) {
        CGContextSetFillColorWithColor(outputContext, tintColor.CGColor);
		CGContextFillRect(outputContext, rect);
		CGContextRestoreGState(outputContext);
    }
}

@end

@interface RNCalloutItemView : UIView

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, assign) NSInteger itemIndex;
@property (nonatomic, strong) UIColor *originalBackgroundColor;

@end

@implementation RNCalloutItemView

- (instancetype)init {
    if (self = [super init]) {
        _imageView = [[UIImageView alloc] init];
        _imageView.backgroundColor = [UIColor clearColor];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_imageView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat inset = self.bounds.size.height/2;
    self.imageView.frame = CGRectMake(0, 0, inset, inset);
    self.imageView.center = CGPointMake(inset, inset);
}

- (void)setOriginalBackgroundColor:(UIColor *)originalBackgroundColor {
    _originalBackgroundColor = originalBackgroundColor;
    self.backgroundColor = originalBackgroundColor;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    
    float r, g, b, a;
    float darkenFactor = 0.3f;
    UIColor *darkerColor;
    if ([self.originalBackgroundColor getRed:&r green:&g blue:&b alpha:&a]) {
        darkerColor = [UIColor colorWithRed:MAX(r - darkenFactor, 0.0) green:MAX(g - darkenFactor, 0.0) blue:MAX(b - darkenFactor, 0.0) alpha:a];
    }
    else if ([self.originalBackgroundColor getWhite:&r alpha:&a]) {
        darkerColor = [UIColor colorWithWhite:MAX(r - darkenFactor, 0.0) alpha:a];
    }
    else {
        @throw @"Item color should be RGBA or White/Alpha in order to darken the button color.";
    }
    self.backgroundColor = darkerColor;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    self.backgroundColor = self.originalBackgroundColor;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    self.backgroundColor = self.originalBackgroundColor;
}

@end

#pragma mark - Public Classes

@interface RNFrostedSidebar ()

@property (nonatomic, weak) UIScrollView *contentView;
@property (nonatomic, weak) RNBlurredView *blurView;
@property (nonatomic, strong) UIView *blurClipView;
@property (nonatomic, strong) NSArray *images;
@property (nonatomic, strong) NSArray *borderColors;
@property (nonatomic, strong) NSMutableArray *itemViews;
@property (nonatomic, strong) NSMutableIndexSet *selectedIndices;

@end

static RNFrostedSidebar *rn_frostedMenu;

@implementation RNFrostedSidebar

+ (instancetype)visibleSidebar {
    return rn_frostedMenu;
}

- (instancetype)initWithImages:(NSArray *)images selectedIndices:(NSIndexSet *)selectedIndices borderColors:(NSArray *)colors {
    if (self = [super init]) {
        _width = 150;
        _animationDuration = 0.25f;
        _itemSize = CGSizeMake(_width/2, _width/2);
        _itemViews = [NSMutableArray array];
        _tintColor = [UIColor colorWithWhite:0.2 alpha:0.73];
        _borderWidth = 2;
        _itemBackgroundColor = [UIColor colorWithRed:1 green:1 blue:1 alpha:0.25];
        
        if (colors) {
            NSAssert([colors count] == [images count], @"Border color count must match images count. If you want a blank border, use [UIColor clearColor].");
        }
        
        _selectedIndices = [selectedIndices mutableCopy] ?: [NSMutableIndexSet indexSet];
        _borderColors = colors;
        _images = images;
    }
    return self;
}

- (instancetype)initWithImages:(NSArray *)images selectedIndices:(NSIndexSet *)selectedIndices {
    return [self initWithImages:images selectedIndices:selectedIndices borderColors:nil];
}

- (instancetype)initWithImages:(NSArray *)images {
    return [self initWithImages:images selectedIndices:nil borderColors:nil];
}

- (instancetype)init {
    NSAssert(NO, @"Unable to create with plain init.");
    return nil;
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	UIScrollView *contentView = [[UIScrollView alloc] init];
	contentView.alwaysBounceHorizontal = NO;
	contentView.alwaysBounceVertical = YES;
	contentView.bounces = YES;
	contentView.clipsToBounds = NO;
	contentView.showsHorizontalScrollIndicator = NO;
	contentView.showsVerticalScrollIndicator = NO;
	[self.view addSubview:contentView];
	self.contentView = contentView;

	[_images enumerateObjectsUsingBlock:^(UIImage *image, NSUInteger idx, BOOL *stop) {
		RNCalloutItemView *view = [[RNCalloutItemView alloc] init];
		view.itemIndex = idx;
		view.clipsToBounds = YES;
		view.imageView.image = image;
		[_contentView addSubview:view];

		[_itemViews addObject:view];

		if (_borderColors && _selectedIndices && [_selectedIndices containsIndex:idx]) {
			UIColor *color = _borderColors[idx];
			view.layer.borderColor = color.CGColor;
		}
		else {
			view.layer.borderColor = [UIColor clearColor].CGColor;
		}
	}];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
	[self.view addGestureRecognizer:tap];
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
	[super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];

	if (self.isViewLoaded && self.view.window != nil) {
		[UIView animateWithDuration:duration/2 animations:^{
			self.view.alpha = 0;
		}];
	}
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    if (self.isViewLoaded && self.view.window != nil) {
        [self.view setNeedsLayout];
    }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
	if (self.isViewLoaded && self.view.window != nil) {
		[UIView animateWithDuration:0.2 animations:^{
			[self.blurView setNeedsDisplay];
			self.view.alpha = 1;
		}];
	}
}

#pragma mark - Show

- (void)showInViewController:(UIViewController *)controller animated:(BOOL)animated {
    if (rn_frostedMenu != nil) {
        [rn_frostedMenu dismissAnimated:NO];
    }
    
    rn_frostedMenu = self;
    
    [self rn_addToParentViewController:controller callingAppearanceMethods:YES];
    self.view.frame = controller.view.bounds;
    
    CGFloat parentWidth = self.view.bounds.size.width;
    
    CGRect contentFrame = self.view.bounds;
    contentFrame.origin.x = _showFromRight ? parentWidth : -_width;
    contentFrame.size.width = _width;
    self.contentView.frame = contentFrame;
    
    [self layoutItems];
    
    contentFrame.origin.x = _showFromRight ? parentWidth - _width : 0;
	CGRect blurFrame = (CGRect){ contentFrame.origin, { _width, self.view.bounds.size.height }};

	RNBlurredView *blur = [[RNBlurredView alloc] initWithFrame:blurFrame];
	blur.parentTarget = controller.view;
	blur.blurRadius = 5;
	blur.tintColor = self.tintColor;
	blur.saturationDeltaFactor = 1.8;
	blur.contentMode = _showFromRight ? UIViewContentModeTopRight : UIViewContentModeTopLeft;
	[self.view insertSubview:blur belowSubview:self.contentView];
	self.blurView = blur;

	CGRect clipFrame = blurFrame;
	clipFrame.origin.x = _showFromRight ? _width : 0;
	clipFrame.size.width = 0;

	UIView *clip = [[UIView alloc] initWithFrame:clipFrame];
	clip.backgroundColor = [UIColor blackColor];
	blur.layer.mask = clip.layer;
	self.blurClipView = clip;
    
	clipFrame.origin.x = 0;
	clipFrame.size.width = _width;

    [UIView animateWithDuration:self.animationDuration
                          delay:0
                        options:kNilOptions
                     animations:^{
                         self.contentView.frame = contentFrame;
						 self.blurClipView.frame = clipFrame;
                     }
                     completion:nil];
    
    CGFloat initDelay = 0.1f;
    [self.itemViews enumerateObjectsUsingBlock:^(RNCalloutItemView *view, NSUInteger idx, BOOL *stop) {
        view.layer.transform = CATransform3DMakeScale(0.3, 0.3, 1);
        view.alpha = 0;
        view.originalBackgroundColor = self.itemBackgroundColor;
        view.layer.borderWidth = self.borderWidth;
        
#if __IPHONE_OS_VERSION_SOFT_MAX_REQUIRED
        [UIView animateWithDuration:0.5
                              delay:(initDelay + idx*0.1f)
             usingSpringWithDamping:10
              initialSpringVelocity:50
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                             view.layer.transform = CATransform3DIdentity;
                             view.alpha = 1;
                         }
                         completion:nil];
#else
        [UIView animateWithDuration:0.2
                              delay:(initDelay + idx*0.1f)
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationCurveEaseInOut
                         animations:^{
                             view.layer.transform = CATransform3DMakeScale(1.1, 1.1, 1);
                             view.alpha = 1;
                         }
                         completion:^(BOOL finished) {
                             [UIView animateWithDuration:0.1 animations:^{
                                 view.layer.transform = CATransform3DIdentity;
                             }];
                         }];
#endif
    }];
}

- (void)showAnimated:(BOOL)animated {
    UIViewController *controller = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (controller.presentedViewController != nil) {
        controller = controller.presentedViewController;
    }
    [self showInViewController:controller animated:animated];
}

- (void)show {
    [self showAnimated:YES];
}

#pragma mark - Dismiss

- (void)dismiss {
    [self dismissAnimated:YES];
}

- (void)dismissAnimated:(BOOL)animated {
    void (^completion)(BOOL) = ^(BOOL finished){
        [self rn_removeFromParentViewControllerCallingAppearanceMethods:YES];
    };
    
    if (animated) {
        CGFloat parentWidth = self.view.bounds.size.width;
        CGRect contentFrame = self.contentView.frame;
        contentFrame.origin.x = self.showFromRight ? parentWidth : -_width;

		CGRect clipFrame = self.blurView.frame;
		clipFrame.origin.x = self.showFromRight ? _width : 0;
		clipFrame.size.width = 0;
        
        [UIView animateWithDuration:self.animationDuration
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                             self.contentView.frame = contentFrame;
							 self.blurClipView.frame = clipFrame;
                         }
                         completion:completion];
    }
    else {
        completion(YES);
    }
}

#pragma mark - Gestures

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    CGPoint location = [recognizer locationInView:self.view];
    if (! CGRectContainsPoint(self.contentView.frame, location)) {
        [self dismissAnimated:YES];
    }
    else {
        NSInteger tapIndex = [self indexOfTap:[recognizer locationInView:self.contentView]];
        if (tapIndex != NSNotFound) {
            [self didTapItemAtIndex:tapIndex];
        }
    }
}

#pragma mark - Private

- (void)didTapItemAtIndex:(NSUInteger)index {
    BOOL didEnable = ! [self.selectedIndices containsIndex:index];
    
    if (self.borderColors) {
        UIColor *stroke = self.borderColors[index];
        UIView *view = self.itemViews[index];
        
        if (didEnable) {
            view.layer.borderColor = stroke.CGColor;
            
            CABasicAnimation *borderAnimation = [CABasicAnimation animationWithKeyPath:@"borderColor"];
            borderAnimation.fromValue = (id)[UIColor clearColor].CGColor;
            borderAnimation.toValue = (id)stroke.CGColor;
            borderAnimation.duration = 0.5f;
            [view.layer addAnimation:borderAnimation forKey:nil];
            
            [self.selectedIndices addIndex:index];
        }
        else {
            view.layer.borderColor = [UIColor clearColor].CGColor;
            [self.selectedIndices removeIndex:index];
        }
        
        CGRect pathFrame = CGRectMake(-CGRectGetMidX(view.bounds), -CGRectGetMidY(view.bounds), view.bounds.size.width, view.bounds.size.height);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:pathFrame cornerRadius:view.layer.cornerRadius];
        
        // accounts for left/right offset and contentOffset of scroll view
        CGPoint shapePosition = [self.view convertPoint:view.center fromView:self.contentView];
        
        CAShapeLayer *circleShape = [CAShapeLayer layer];
        circleShape.path = path.CGPath;
        circleShape.position = shapePosition;
        circleShape.fillColor = [UIColor clearColor].CGColor;
        circleShape.opacity = 0;
        circleShape.strokeColor = stroke.CGColor;
        circleShape.lineWidth = self.borderWidth;
        
        [self.view.layer addSublayer:circleShape];
        
        CABasicAnimation *scaleAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        scaleAnimation.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
        scaleAnimation.toValue = [NSValue valueWithCATransform3D:CATransform3DMakeScale(2.5, 2.5, 1)];
        
        CABasicAnimation *alphaAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        alphaAnimation.fromValue = @1;
        alphaAnimation.toValue = @0;
        
        CAAnimationGroup *animation = [CAAnimationGroup animation];
        animation.animations = @[scaleAnimation, alphaAnimation];
        animation.duration = 0.5f;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [circleShape addAnimation:animation forKey:nil];
    }
    
    if ([self.delegate respondsToSelector:@selector(sidebar:didTapItemAtIndex:)]) {
        [self.delegate sidebar:self didTapItemAtIndex:index];
    }
    if ([self.delegate respondsToSelector:@selector(sidebar:didEnable:itemAtIndex:)]) {
        [self.delegate sidebar:self didEnable:didEnable itemAtIndex:index];
    }
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	
    CGFloat x = self.showFromRight ? self.parentViewController.view.bounds.size.width - _width : 0;
	CGRect contentFrame = CGRectMake(x, 0, _width, self.parentViewController.view.bounds.size.height);;
	self.contentView.frame = contentFrame;
	self.blurView.frame = contentFrame;
	self.blurClipView.frame = self.blurView.bounds;
    
    [self layoutItems];
}

- (void)layoutItems {
    CGFloat leftPadding = (self.width - self.itemSize.width)/2;
    CGFloat topPadding = leftPadding;
    [self.itemViews enumerateObjectsUsingBlock:^(RNCalloutItemView *view, NSUInteger idx, BOOL *stop) {
        CGRect frame = CGRectMake(leftPadding, topPadding*idx + self.itemSize.height*idx + topPadding, self.itemSize.width, self.itemSize.height);
        view.frame = frame;
        view.layer.cornerRadius = frame.size.width/2.f;
    }];
    
    NSInteger items = [self.itemViews count];
    self.contentView.contentSize = CGSizeMake(0, items * (self.itemSize.height + leftPadding) + leftPadding);
}

- (NSInteger)indexOfTap:(CGPoint)location {
    __block NSUInteger index = NSNotFound;
    
    [self.itemViews enumerateObjectsUsingBlock:^(UIView *view, NSUInteger idx, BOOL *stop) {
        if (CGRectContainsPoint(view.frame, location)) {
            index = idx;
            *stop = YES;
        }
    }];
    
    return index;
}

- (void)rn_addToParentViewController:(UIViewController *)parentViewController callingAppearanceMethods:(BOOL)callAppearanceMethods {
    if (self.parentViewController != nil) {
        [self rn_removeFromParentViewControllerCallingAppearanceMethods:callAppearanceMethods];
    }
    
    if (callAppearanceMethods) [self beginAppearanceTransition:YES animated:NO];
    [parentViewController addChildViewController:self];
    [parentViewController.view addSubview:self.view];
    [self didMoveToParentViewController:self];
    if (callAppearanceMethods) [self endAppearanceTransition];
}

- (void)rn_removeFromParentViewControllerCallingAppearanceMethods:(BOOL)callAppearanceMethods {    
    if (callAppearanceMethods) [self beginAppearanceTransition:NO animated:NO];
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
    if (callAppearanceMethods) [self endAppearanceTransition];
}

@end
