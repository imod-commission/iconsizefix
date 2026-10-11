#import "IconSizeFixRootListController.h"
#import <notify.h>
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;

static NSString * const kDomain   = @"com.imodcommission.iconsizefix";
static NSString * const kNotif    = @"com.imodcommission.iconsizefix.changed";
static const char * const kNotifC = "com.imodcommission.iconsizefix.changed";

@implementation IconSizeFixRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Respring"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(respringTapped)];
}

- (void)respringTapped {
    NSFileManager *fm = [NSFileManager defaultManager];

    // sbreload 优先
    if ([fm isExecutableFileAtPath:@"/var/jb/usr/bin/sbreload"]) {
        if ([self runTask:@"/var/jb/usr/bin/sbreload" args:@[]]) return;
    }
    if ([fm isExecutableFileAtPath:@"/usr/bin/sbreload"]) {
        if ([self runTask:@"/usr/bin/sbreload" args:@[]]) return;
    }
    // 退回到 killall SpringBoard
    if ([fm isExecutableFileAtPath:@"/var/jb/usr/bin/killall"]) {
        if ([self runTask:@"/var/jb/usr/bin/killall" args:@[@"-9", @"SpringBoard"]]) return;
    }
    if ([fm isExecutableFileAtPath:@"/usr/bin/killall"]) {
        if ([self runTask:@"/usr/bin/killall" args:@[@"-9", @"SpringBoard"]]) return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Respring 失败"
        message:@"找不到 sbreload 或 killall，请手动重启桌面。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)runTask:(NSString *)path args:(NSArray *)args {
    const char *argv[16];
    int i = 0;
    argv[i++] = path.UTF8String;
    for (NSString *a in args) {
        if (i >= 14) break;
        argv[i++] = a.UTF8String;
    }
    argv[i] = NULL;

    pid_t pid = 0;
    int rc = posix_spawn(&pid, path.UTF8String, NULL, NULL,
                         (char * const *)argv, environ);
    return (rc == 0);
}

#pragma mark - 设置变化时通知 Tweak

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    notify_post(kNotifC);
}

- (void)reloadPrefs {
    notify_post(kNotifC);
    [self reloadSpecifiers];
}

@end