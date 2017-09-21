//
//  Connection.m
//  Injection4Android
//
//  Created by John Holdsworth on 15/09/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import "Connection.h"
#import "AppDelegate.h"
#import "FileWatcher.h"

#import <sys/socket.h>
#import <netinet/tcp.h>
#import <arpa/inet.h>

#import <zlib.h>

#define INJECTION_PORT 31441

static AppDelegate *owner;
static FileWatcher *fileWatcher;

static int serverSocket;

@implementation Connection {
    int clientSocket, injectionNumber;
    FILE *clientRead, *clientWrite;
    NSString *projectDirectory;
    BOOL building;
}

+ (void)startSever:(AppDelegate *)appDelegate {
    owner = appDelegate;
    static struct sockaddr_in serverAddr;

    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = htonl(INADDR_ANY);
    serverAddr.sin_port = htons(INJECTION_PORT);

    int optval = 1;
    if ((serverSocket = socket(AF_INET, SOCK_STREAM, 0)) < 0)
        [owner error:@"Could not open service socket: %s", strerror(errno)];
    else if (setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof optval) < 0)
        [owner error:@"Could not set socket option: %s", strerror(errno)];
    else if (setsockopt(serverSocket, SOL_SOCKET, SO_NOSIGPIPE, (void *)&optval, sizeof(optval)) < 0)
        [owner error:@"Could not set socket option: %s", strerror(errno)];
    else if (setsockopt(serverSocket, IPPROTO_TCP, TCP_NODELAY, (void *)&optval, sizeof(optval)) < 0)
        [owner error:@"Could not set socket option: %s", strerror(errno)];
    else if (bind(serverSocket, (struct sockaddr *)&serverAddr, sizeof serverAddr) < 0)
        [owner error:@"Could not bind service socket: %s", strerror(errno)];
    else if (listen(serverSocket, 5) < 0)
        [owner error:@"Service socket would not listen: %s", strerror(errno)];
    else
        [self performSelectorInBackground:@selector(backgroundConnectionService) withObject:nil];
}

+ (void)backgroundConnectionService {
    NSLog(@"Injection: Waiting for connections...");
    while (TRUE) {
        struct sockaddr_in clientAddr;
        socklen_t addrLen = sizeof clientAddr;

        int appConnection = accept(serverSocket, (struct sockaddr *)&clientAddr, &addrLen);
        if (appConnection > 0) {
            NSLog(@"Injection: Connection from %s:%d",
                  inet_ntoa(clientAddr.sin_addr), clientAddr.sin_port);
            (void)[[Connection alloc] initSocket:appConnection];
        }
        else
            [NSThread sleepForTimeInterval:.5];
    }
}

- (instancetype)initSocket:(int)socket {

    if ((self = [super init])) {
        int value;
        clientSocket = socket;
        clientRead = fdopen(socket, "r");
        clientWrite = fdopen(socket, "w");

        if (fread(&value, 1, sizeof value, clientRead) != sizeof value || value != INJECTION_PORT ||
            fread(&value, 1, sizeof value, clientRead) != sizeof value) {
            [owner error:@"Could not read header"];
            return nil;
        }

        char *sourcePath = (char *)malloc(value+1);
        if (!sourcePath || fread(sourcePath, 1, value, clientRead) != value) {
            [owner error:@"Could not read filepath"];
            return nil;
        }
        sourcePath[value] = '\000';

        projectDirectory = [NSString stringWithUTF8String:sourcePath]
            .stringByDeletingLastPathComponent.stringByDeletingLastPathComponent
            .stringByDeletingLastPathComponent.stringByDeletingLastPathComponent
            .stringByDeletingLastPathComponent;
        NSLog(@"Project directory: %@", projectDirectory);

        free(sourcePath);

        fileWatcher = [[FileWatcher new] initWithRoot:projectDirectory plugin:^(NSArray *filesChanged) {
            NSLog(@"Files changed: %@", filesChanged);
            [self performSelectorInBackground:@selector(filesChanged:) withObject:filesChanged];
        }];

        [self performSelectorInBackground:@selector(monitorConnection) withObject:nil];
        [owner setBadge:@"Ready"];
    }
    return self;
}

- (void)filesChanged:(NSArray *)fileChanged {
    if (building)
        return;
    building = TRUE;
    [owner setBadge:@"Build"];
    NSString *scriptPath = [[NSBundle mainBundle] pathForResource:@"builder" ofType:@"sh"];
    NSString *libraryPath = [NSString stringWithFormat:@"/tmp/injection_%s_%d.so", getenv("USER"), ++injectionNumber];
    NSString *adbPath = 0 ? @"/Users/user/Android/platform-tools/adb" : @"";
    NSString *tmpPath = @"/data/local/tmp";

#if 0
    // subject to inexplicable pauses...
    NSLog(@"Running %@", scriptPath);
    NSTask *task = [NSTask new];

    task.launchPath = scriptPath;
    task.arguments = @[projectDirectory, fileChanged[0], libraryPath, adbPath];
    NSPipe *pipe = [NSPipe new];
    task.standardOutput = pipe;
    task.standardError = pipe;
    [task launch];

    NSData *output = pipe.fileHandleForReading.readDataToEndOfFile;
    [task waitUntilExit];
    int status = task.terminationStatus;
#else
    // old style..
    NSString *command = [NSString stringWithFormat:@"\"%@\" \"%@\" \"%@\" \"%@\" \"%@\" 2>&1",
                         scriptPath, projectDirectory, fileChanged[0], libraryPath, adbPath];
    NSLog(@"Running %@", command);
    FILE *task = popen(command.UTF8String, "r");
    NSMutableData *output = [NSMutableData dataWithLength:10*1024*1024];
    output.length = fread((void *)output.bytes, 1, output.length, task);
    int status = pclose(task)>>8;
#endif

    building = FALSE;
    NSLog(@"Task completes %d", status);
    [owner output:[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding]];

    if (!clientSocket)
        return;

    if (status != EXIT_SUCCESS) {
#if 0
        [owner error:@"Build failed %d, check console", status];
        [owner setBadge:@"Error"];
#else
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
            [owner.window orderFront:self];
        });
#endif
        return;
    }

    [owner setBadge:@"Send"];

    if (adbPath.length)
        [self performSelectorOnMainThread:@selector(pushedToDevice:)
                               withObject:[tmpPath stringByAppendingPathComponent:libraryPath.lastPathComponent]
                            waitUntilDone:NO];
    else
        [self performSelectorOnMainThread:@selector(writeToDevice:)
                               withObject:libraryPath waitUntilDone:NO];
}

- (void)pushedToDevice:(NSString *)library {
    const char *path = library.UTF8String;
    int value = (int)strlen(path) + 1, one = 1;
    if (fwrite(&value, 1, sizeof value, clientWrite) != sizeof value ||
        fwrite(&one, 1, sizeof one, clientWrite) != sizeof one ||
        fwrite(path, 1, value, clientWrite) != value)
        NSLog(@"Error writing path to device");
    fflush(clientWrite);
}

- (void)writeToDevice:(NSString *)library {
    NSData *buffer = [NSData dataWithContentsOfFile:library];
    if (!buffer) {
        [owner error:@"Could not read library %@", library];
        return;
    }

    NSMutableData *compressed = [NSMutableData dataWithLength:buffer.length+100];
    uLongf destLen = compressed.length;

    if (compress((Bytef *)compressed.bytes, &destLen, (Bytef *)buffer.bytes, buffer.length) != Z_OK) {
        [owner error:@"Error compressing"];
        return;
    }

    NSLog(@"Sending %@[%d -> %d] to device", library, (int)buffer.length, (int)destLen);

    int value = (int)destLen;
    if (fwrite(&value, 1, sizeof value, clientWrite) != sizeof value)
        NSLog(@"Error writing to device");

    value = (int)buffer.length;
    if (fwrite(&value, 1, sizeof value, clientWrite) != sizeof value ||
        fwrite(compressed.bytes, 1, destLen, clientWrite) != destLen)
        NSLog(@"Error writing to device");

    [owner setBadge:@"Load"];
    fflush(clientWrite);
}

- (void)monitorConnection {
    int status;
    while (fread(&status, 1, sizeof status, clientRead) == sizeof status)
    if (status != 0) {
        char error[status+1];
        error[status] = '\000';
        if (fread(error, 1, status, clientRead) != status)
        strcpy(error, "Error reading description");
        [owner error:@"Error applying injection: %s", error];
        [owner setBadge:@"Fail"];
    }
    else
        [owner setBadge:@"Ready"];

    NSLog(@"Client disconnected");
    [owner setBadge:nil];
    fclose(clientWrite);
    fclose(clientRead);
    fileWatcher = nil;
    clientSocket = 0;
}

@end
