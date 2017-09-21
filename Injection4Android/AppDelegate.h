//
//  AppDelegate.h
//  Injection4Android
//
//  Created by John Holdsworth on 15/09/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (weak) IBOutlet NSWindow *window;

- (void)error:(NSString *)format, ...;
- (void)setBadge:(NSString *)badge;
- (void)output:(NSString *)output;

@end

