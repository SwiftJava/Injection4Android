//
//  AppDelegate.m
//  Injection4Android
//
//  Created by John Holdsworth on 15/09/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import "AppDelegate.h"
#import "Connection.h"

#import <WebKit/WebKit.h>

@interface AppDelegate () <WebPolicyDelegate>
@property (weak) IBOutlet WebView *webView;
@end

@implementation NSString (Replace)

- stringReplace:( NSString  * _Nonnull)pattern withBlock:(NSString * _Nonnull (^)(NSArray<NSString *> *groups))block {
    NSError *error;
    NSRegularExpression *regexp = [[NSRegularExpression alloc] initWithPattern:pattern options:NSRegularExpressionAnchorsMatchLines error:&error];
    if (error)
        [NSAlert alertWithError:error];
    NSMutableString *out = [NSMutableString new];
    __block NSUInteger pos = 0;

    [regexp enumerateMatchesInString:self options:0 range:NSMakeRange(0,self.length) usingBlock:
     ^void (NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
         NSRange range = result.range;
         [out appendString:[self substringWithRange:NSMakeRange(pos, range.location-pos)]];
         NSMutableArray *groups = [NSMutableArray new];
         for ( int i=0; i<=regexp.numberOfCaptureGroups ; i++ )
             [groups addObject:[self substringWithRange:[result rangeAtIndex:i]]];
         [out appendString:block( groups )];
         pos = range.location + range.length;
     }];

    [out appendString:[self substringWithRange:NSMakeRange(pos, self.length-pos)]];
    return out;
}

@end

@implementation AppDelegate

- (void)error:(NSString *)format, ... {
    va_list argp;
    va_start(argp, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:argp];
    [self performSelectorOnMainThread:@selector(alert:) withObject:message waitUntilDone:NO];
}

- (void)alert:(NSString *)msg {
    [self.window orderFront:self];
    [[NSAlert alertWithMessageText:@"Injection Plugin:"
                     defaultButton:@"OK" alternateButton:nil otherButton:nil
         informativeTextWithFormat:@"%@", msg] runModal];
    //    msgField.stringValue = msg;
    //    [self.alertPanel orderFront:self];
}

- (void)setBadge:(NSString *)badge {
    [[[NSApplication sharedApplication] dockTile] performSelectorOnMainThread:@selector(setBadgeLabel:)
                                                                   withObject:badge waitUntilDone:NO];
}

- (void)output:(NSString *)output {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *html = [output stringReplace:@"(^/[^:]+/([^/:]+)):" withBlock:^(NSArray<NSString *> *groups){
            return [NSString stringWithFormat:@"<a href=\"file://%@\">%@</a>:", groups[1], groups[2]];
        }];
        [self.webView.mainFrame loadHTMLString:[NSString stringWithFormat:@"<pre>%@</pre>", html] baseURL:nil];
    });
}

- (void)webView:(WebView *)aWebView decidePolicyForNavigationAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id < WebPolicyDecisionListener >)listener {
    if (request.URL.isFileURL)
        [[NSWorkspace sharedWorkspace] openURL:request.URL];
    else
        [listener use];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    [Connection startSever:self];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
