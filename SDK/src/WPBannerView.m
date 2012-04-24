/**
 * WPBannerView.m
 *
 * Copyright (c) 2010, Alexey Goliatin <alexey.goliatin@gmail.com>
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without 
 * modification, are permitted provided that the following conditions are met:
 * 
 *   * Redistributions of source code must retain the above copyright notice, 
 *     this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright notice, 
 *     this list of conditions and the following disclaimer in the documentation
 *     and/or other materials provided with the distribution.
 *   * Neither the name of the "Wapstart" nor the names of its contributors 
 *     may be used to endorse or promote products derived from this software 
 *     without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR 
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; 
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, 
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "WPBannerView.h"
#import "MRAdView.h"
#import "WPAdView.h"
#import "WPLogging.h"
#import "WPUtils.h"

#define BANNER_HEIGHT 50
#define MINIMIZED_BANNER_HEIGHT 20
#define DEFAULT_MINIMIZED_LABEL @"Открыть баннер"

@interface WPBannerView (PrivateMethods)

- (void) configureSubviews;

- (UIWebView *) makeAdViewWithFrame:(CGRect)frame;

- (void) startAutoupdateTimer;
- (void) stopAutoupdateTimer;

- (void) cleanCurrentView;
- (void) updateCurrentViewWidth;

+ (CGRect) aspectFittedRect:(CGSize)imageSize max:(CGRect)maxRect;

@end


@implementation WPBannerView

@synthesize delegate = _delegate;
@synthesize isMinimized = _isMinimized;
@synthesize minimizedLabel = _minimizedLabel;
@synthesize showCloseButton = _showCloseButton;
@synthesize hideWhenEmpty = _hideWhenEmpty;
@synthesize disableAutoDetectLocation = _disableAutoDetectLocation;
@synthesize autoupdateTimeout = _autoupdateTimeout;
@synthesize orientation = _orientation;

- (id) initWithBannerRequestInfo:(WPBannerRequestInfo *) requestInfo
{
    if ((self = [super initWithFrame:CGRectZero]))
	{
		self.minimizedLabel = DEFAULT_MINIMIZED_LABEL;
		self.isMinimized = NO;
		_showCloseButton = YES;
		_hideWhenEmpty = NO;
		_disableAutoDetectLocation = YES;

		_bannerRequestInfo = [requestInfo retain];
		_adviewPool = [[NSMutableSet set] retain];

		self.backgroundColor = [UIColor clearColor];
		
		_shildImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"wp_banner_shild.png"]];
		[_shildImageView setHidden:false];
		_shildImageView.frame = CGRectMake(0, 0, 9, BANNER_HEIGHT);
		[self addSubview:_shildImageView];
		
		_closeButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
		[_closeButton setImage:[UIImage imageNamed:@"wp_banner_close.png"] forState:UIControlStateNormal];
		[_closeButton addTarget:self action:@selector(closeButtonPressed) forControlEvents:UIControlEventTouchUpInside];
		
		[self addSubview:_closeButton];
		
		_loadingInfoIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
		_loadingInfoIndicator.hidesWhenStopped = YES;
		[self addSubview:_loadingInfoIndicator];
		
		[self configureSubviews];
        
        _locationManager = [[WPLocationManager alloc] init];
        _locationManager.delegate = self;
    }
    
    return self;
}

- (void) dealloc
{
	[_autoupdateTimer invalidate];
	[_bannerInfoLoader cancel];
	
    [_locationManager release];
	[_bannerRequestInfo release];
	[_shildImageView release];
	[_closeButton release];
	self.minimizedLabel = nil;

	[_currentContentView release];

	for (UIView *adView in _adviewPool) {
		[adView release];
	}
	[_adviewPool release];

    [super dealloc];
}

#pragma mark Properties

- (CGFloat) bannerHeight
{
	return self.isMinimized ? MINIMIZED_BANNER_HEIGHT : BANNER_HEIGHT;
}

- (BOOL) isEmpty
{
	return _currentContentView == nil;
}

- (void) setShowCloseButton:(BOOL)show
{
	_showCloseButton = show;
	[_closeButton setHidden:!_showCloseButton || self.isMinimized];
}

- (void) setIsMinimized:(BOOL)minimize
{
	[self setIsMinimized:minimize animated:NO];
}

- (void) setIsMinimized:(BOOL)minimize animated:(BOOL) animated
{
	if (_isMinimized == minimize)
		return;

	if (animated) {
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:0.5];
		[UIView setAnimationTransition:UIViewAnimationTransitionNone forView:self.superview cache:YES];
		[UIView setAnimationBeginsFromCurrentState:YES];
	}
	
	_isMinimized = minimize;

	CGRect currentFrame = self.frame;

	if (_isMinimized)
	{
		[_bannerInfoLoader cancel];
		[_bannerInfoLoader release], _bannerInfoLoader = nil;

		[self stopAutoupdateTimer];

		if ((self.frame.origin.y+self.frame.size.height) == (self.superview.bounds.origin.y+self.superview.bounds.size.height))
		{
			// Banner from bottom
			currentFrame.origin.y = self.superview.bounds.origin.y+self.superview.bounds.size.height-MINIMIZED_BANNER_HEIGHT;
		}

		currentFrame.size.height = MINIMIZED_BANNER_HEIGHT;

		[self cleanCurrentView];
	} else {
		if ((self.frame.origin.y+self.frame.size.height) == (self.superview.bounds.origin.y+self.superview.bounds.size.height))
		{
			// Banner from bottom
			currentFrame.origin.y = self.superview.bounds.origin.y+self.superview.bounds.size.height-BANNER_HEIGHT;
		}

		currentFrame.size.height = BANNER_HEIGHT;

		if (![self isEmpty]) { // NOTE: current view may be assigned in adDidLoad method
			_currentContentView.frame = currentFrame;
			_currentContentView.hidden = false;
			[self startAutoupdateTimer];
		} else {
			if (animated) {
				[UIView setAnimationDelegate:self];
				[UIView setAnimationDidStopSelector:@selector(reloadBanner)];
			} else
				[self reloadBanner];
		}
	}

	self.showCloseButton = _showCloseButton;
	self.frame = currentFrame;
	
	_shildImageView.frame = CGRectMake(0, 0, 9, self.frame.size.height);
	[_shildImageView setHidden:_isMinimized];

	if (animated)
		[UIView commitAnimations];

	if ([_delegate respondsToSelector:@selector(bannerViewMinimizedStateChanged:)])
		[_delegate bannerViewMinimizedStateChanged:self];
}

- (void) startAutoupdateTimer
{
	if (_autoupdateTimeout > 0 && _autoupdateTimer == nil) {
		_autoupdateTimer = [NSTimer timerWithTimeInterval:_autoupdateTimeout target:self selector:@selector(reloadBanner) userInfo:nil repeats:YES];
		[[NSRunLoop currentRunLoop] addTimer:_autoupdateTimer forMode:NSDefaultRunLoopMode];
	}
}

- (void) stopAutoupdateTimer
{
	if (_autoupdateTimer != nil) {
		// Turn off timer
		[_autoupdateTimer invalidate], _autoupdateTimer = nil;
	}
}

- (void) setDisableAutoDetectLocation:(BOOL)disableAutoDetectLocation
{
    _disableAutoDetectLocation = disableAutoDetectLocation;
    
    if (_disableAutoDetectLocation)
        [_locationManager stopUpdatingLocation];
    else
        [_locationManager startUpdatingLocation];
}

- (void) setOrientation:(UIInterfaceOrientation)orientation
{
	if (_orientation != orientation) {
		_orientation = orientation;

		[self updateCurrentViewWidth];

		if ([_currentContentView isKindOfClass:[MRAdView class]])
			[(MRAdView*)_currentContentView rotateToOrientation:orientation];
	}
}

#pragma mark Drawing and Views

- (void) configureSubviews
{
	if (_bannerInfoLoader == nil)
		[_loadingInfoIndicator stopAnimating];
	else if ([self isEmpty])
		[_loadingInfoIndicator startAnimating];
}

- (void) setFrame:(CGRect)newFrame
{
	[super setFrame:newFrame];
	
	[self setNeedsLayout];
	[self setNeedsDisplay];
}

- (void) drawRect:(CGRect)rect
{
	UIImage *bgImage = [UIImage imageNamed:@"wp_banner_background.png"];
	[bgImage drawInRect:CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height)];

	[[UIColor whiteColor] set];

	if (self.isMinimized)
	{
		CGRect rect = CGRectMake(10, 2, self.bounds.size.width-20, self.bounds.size.height-4);

		UIFont *font = [UIFont systemFontOfSize:12];

		[self.minimizedLabel drawInRect:rect
							   withFont:font
						  lineBreakMode:UILineBreakModeTailTruncation
							  alignment:UITextAlignmentRight];
	
		return;
	}
}

- (void) layoutSubviews
{
	_closeButton.frame = CGRectMake(self.bounds.size.width-24, 2, 22, 22);
	_loadingInfoIndicator.frame = CGRectMake((self.bounds.size.width-30)/2, (self.bounds.size.height-30)/2, 30, 30);
}

- (void) touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
	[super touchesEnded:touches withEvent:event];
	
	if (self.isMinimized)
	{
		[self setIsMinimized:NO animated:YES];
		return;
	}
	
	UITouch *touch = [touches anyObject];
	CGPoint tapLocation = [touch locationInView:self];
	
	if (tapLocation.x > (self.bounds.size.width-40))
	{
		[self performSelector:@selector(closeButtonPressed)];
		return;
	}
	
	[_delegate bannerViewPressed:self];
}

#pragma mark Methods

- (void) showFromTop:(BOOL) animated
{
	if (animated)
	{
		self.frame = CGRectMake(0, -[self bannerHeight], self.superview.bounds.size.width, [self bannerHeight]);
		self.alpha = 0;

		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:0.5];
		[UIView setAnimationTransition:UIViewAnimationTransitionNone forView:self.superview cache:NO];
		[UIView setAnimationBeginsFromCurrentState:YES];
	}
	
	self.frame = CGRectMake(0, 0, self.superview.bounds.size.width, [self bannerHeight]);
	self.alpha = 1;

	if (animated)
		[UIView commitAnimations];
}

- (void) showFromBottom:(BOOL) animated
{
	if (animated)
	{
		self.frame = CGRectMake(0, self.superview.bounds.size.height, self.superview.bounds.size.width, [self bannerHeight]);
		self.alpha = 0;
		
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:0.5];
		[UIView setAnimationTransition:UIViewAnimationTransitionNone forView:self.superview cache:NO];
		[UIView setAnimationBeginsFromCurrentState:YES];
	}
	
	self.frame = CGRectMake(0, self.superview.bounds.size.height-[self bannerHeight], self.superview.bounds.size.width, [self bannerHeight]);
	self.alpha = 1;
	
	if (animated)
		[UIView commitAnimations];
}

- (void) hide:(BOOL) animated
{
	if (((self.frame.origin.y+self.frame.size.height) == (self.superview.bounds.origin.y+self.superview.bounds.size.height)) ||
		(self.frame.origin.y == self.superview.bounds.origin.y))
	{
		if (animated)
		{
			[UIView beginAnimations:nil context:NULL];
			[UIView setAnimationDuration:0.5];
			[UIView setAnimationTransition:UIViewAnimationTransitionNone forView:self.superview cache:NO];
			[UIView setAnimationBeginsFromCurrentState:YES];
			if ([_delegate respondsToSelector:@selector(bannerViewDidHide:)])
			{
				[UIView setAnimationDelegate:self];
				[UIView setAnimationDidStopSelector:@selector(hideAnimationDidStop:finished:context:)];
			}
		}
		
		if ((self.frame.origin.y+self.frame.size.height) == (self.superview.bounds.origin.y+self.superview.bounds.size.height))
			self.frame = CGRectMake(0, self.superview.bounds.size.height, self.superview.bounds.size.width, [self bannerHeight]);
		else
			self.frame = CGRectMake(0, -[self bannerHeight], self.superview.bounds.size.width, [self bannerHeight]);
		self.alpha = 0;
		
		if (animated)
			[UIView commitAnimations];
		else if ([_delegate respondsToSelector:@selector(bannerViewDidHide:)])
			[_delegate bannerViewDidHide:self];
	}
}

- (void) hideAnimationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context
{
	[_delegate bannerViewDidHide:self];
}

- (void) closeButtonPressed
{
	[self setIsMinimized:YES animated:YES];
}

- (void) cleanCurrentView
{
	if (_currentContentView != nil) {
		[_adviewPool removeObject:_currentContentView];
		[_currentContentView removeFromSuperview];
		[_currentContentView release], _currentContentView = nil;
	}
}

- (void) updateCurrentViewWidth
{
	CGRect frame = _currentContentView.frame;
	frame.size.width = [WPUtils getApplicationFrame].size.width;
	_currentContentView.frame = frame;
}

#pragma mark Network

- (void) reloadBanner
{
	if (self.isMinimized || _isExpanded)
		return;

	[_bannerInfoLoader cancel];
	[_bannerInfoLoader release];

	_bannerInfoLoader = [[WPBannerInfoLoader alloc] initWithRequestInfo:_bannerRequestInfo];
	_bannerInfoLoader.containerRect = self.frame;
	_bannerInfoLoader.delegate = self;

	if (![_bannerInfoLoader start]) {
		[_bannerInfoLoader release], _bannerInfoLoader = nil;
	}

	[self configureSubviews];
	[self setNeedsDisplay];

	[self startAutoupdateTimer];
}

#pragma mark Network delegates

- (void) bannerInfoLoaderDidFinish:(WPBannerInfoLoader *) loader
{
	NSString *html = [[NSString alloc] initWithData:loader.data encoding:NSUTF8StringEncoding];
	WPLogDebug(@"Creating adView for type: %@, html: %@", loader.adType, html);

	if ([@"mraid" isEqualToString:loader.adType]) {
		MRAdView *mraidView = [[MRAdView alloc] initWithFrame:self.frame];
		mraidView.delegate = self;
		[mraidView loadCreativeWithHTMLString:html baseURL:nil];
		[_adviewPool addObject:mraidView];
	} else {
		WPAdView *adView = [[WPAdView alloc] initWithFrame:self.frame];
		adView.delegate = self;
		[adView loadAdWithHTMLString:html baseURL:nil];
		[_adviewPool addObject:adView];
	}

	[_bannerInfoLoader release], _bannerInfoLoader = nil;
}

- (void) bannerInfoLoader:(WPBannerInfoLoader *) loader didFailWithCode:(WPBannerInfoLoaderErrorCode) errorCode
{
	[_bannerInfoLoader release], _bannerInfoLoader = nil;
	[self configureSubviews];
	[self setNeedsDisplay];
}

#pragma mark Location manager delegates

- (void) locationUpdate:(CLLocation *)location
{
    _bannerRequestInfo.location = location;
}

- (void) locationError:(NSError *)error { /*_*/ }

#pragma mark MRAdViewDelegate

- (UIViewController *)viewControllerForPresentingModalView
{
	return (UIViewController*)self.delegate;
}

- (void) willExpandAd:(MRAdView *)adView toFrame:(CGRect)frame
{
	WPLogDebug(@"MRAID: Will expanded!");
	
	_isExpanded = true;

	[_bannerInfoLoader cancel];
	[self stopAutoupdateTimer];
}

- (void)didExpandAd:(MRAdView *)adView toFrame:(CGRect)frame
{
	WPLogDebug(@"MRAID: Did expanded!");
}

- (void)adDidClose:(MRAdView *)adView
{
	WPLogDebug(@"MRAID: Did closed!");

	[self updateCurrentViewWidth];

	_isExpanded = false;
	[adView removeFromSuperview];
	[self insertSubview:adView atIndex:0];
	[self startAutoupdateTimer];
}

// MRAdViewDelegate / WPAdViewDelegate
- (void)adDidLoad:(UIView *)adView;
{
	[self cleanCurrentView];
	_currentContentView = adView;

	[self insertSubview:_currentContentView atIndex:0];

	[self configureSubviews];
	[self setNeedsDisplay];

	if ([_delegate respondsToSelector:@selector(bannerViewInfoLoaded:)])
		[_delegate bannerViewInfoLoaded:self];
}

@end
