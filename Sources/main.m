#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <stdlib.h>
#import <unistd.h>
#import "ZTechAppDelegate.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Ensure unsandboxed system app has writable HOME and TMPDIR so UIPasteboard / UITextField never abort
        setenv("HOME", "/var/mobile", 1);
        setenv("TMPDIR", "/tmp", 1);
        mkdir("/tmp", 0777);
        chmod("/tmp", 0777);
        mkdir("/var/mobile/Library/Caches", 0777);
        chmod("/var/mobile/Library/Caches", 0777);
        mkdir("/var/mobile/Library/Caches/com.apple.Pasteboard", 0777);
        chmod("/var/mobile/Library/Caches/com.apple.Pasteboard", 0777);
        chown("/var/mobile/Library/Caches/com.apple.Pasteboard", 501, 501);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([ZTechAppDelegate class]));
    }
}
