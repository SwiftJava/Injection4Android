//
//  Connection.h
//  Injection4Android
//
//  Created by John Holdsworth on 15/09/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import <Foundation/Foundation.h>

@class AppDelegate;
@interface Connection : NSObject
+ (void)startSever:(AppDelegate *)appDelegate;
@end
