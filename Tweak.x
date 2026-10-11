#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/runtime.h>

// =========================================================
// 配置域
// =========================================================
static NSString * const kDomain               = @"com.imodcommission.iconsizefix";
static const char * const kPrefsChangedNotifC = "com.imodcommission.iconsizefix.changed";

static const char *k26HomeNotifs[] = {
    "ngkhoi.26home.UpdateIconStyle",
    "ngkhoi.26home.clearCache",
    "ngkhoi.26home.PurgeCaches",
    "ngkhoi.26home.reloadPrefs",
};

// =========================================================
// 私有类声明
// =========================================================
@interface SBIconView : UIView
- (id)icon;
- (UIView *)labelView;
@end

@interface SBIconLabelView : UIView
@end

// =========================================================
// 全局状态
// =========================================================
static BOOL    g_enabled         = YES;
static CGFloat g_iconScale       = 1.0;
static BOOL    g_hideAppNames    = NO;
static BOOL    g_hideWidgetNames = NO;

static const void *kLabelHiddenByUsKey = &kLabelHiddenByUsKey;

// =========================================================
// 加载偏好
// =========================================================
static void LoadPrefs(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kDomain];
    g_enabled         = [d objectForKey:@"enabled"]    ? [d boolForKey:@"enabled"]    : YES;
    g_iconScale       = [d objectForKey:@"iconScale"]  ? [d floatForKey:@"iconScale"] : 1.0;
    g_hideAppNames    = [d boolForKey:@"hideAppNames"];
    g_hideWidgetNames = [d boolForKey:@"hideWidgetNames"];

    if (g_iconScale < 0.5) g_iconScale = 0.5;
    if (g_iconScale > 1.5) g_iconScale = 1.5;
}

// =========================================================
// 图标类型判断
// =========================================================
static BOOL IsWidgetView(SBIconView *iconView) {
    if (!iconView) return NO;
    if ([iconView respondsToSelector:@selector(icon)]) {
        id icon = [iconView icon];
        if (icon && [icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) {
            return YES;
        }
    }
    return NO;
}

// 精确匹配：只在打开的文件夹容器内才返回 YES
// 排除 SBRootFolderView（主屏幕根容器）
static BOOL IsInOpenFolder(SBIconView *iconView) {
    static NSSet *folderClasses = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        folderClasses = [NSSet setWithArray:@[
            @"SBFolderView",
            @"SBFloatyFolderView",
            @"SBFolderControllerBackgroundView",
            @"SBFolderScrollView",
            @"SBFolderIconListView"
        ]];
    });
    UIView *v = iconView.superview;
    while (v) {
        NSString *cls = NSStringFromClass([v class]);
        if ([folderClasses containsObject:cls]) {
            return YES;
        }
        v = v.superview;
    }
    return NO;
}

// =========================================================
// 获取内部子视图
// =========================================================
static UIView *GetIconImageView(SBIconView *iconView) {
    static NSArray *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[@"_iconImageView", @"iconImageView", @"_imageView", @"imageView"];
    });
    for (NSString *key in keys) {
        @try {
            id v = [iconView valueForKey:key];
            if (v && [v isKindOfClass:[UIView class]]) return v;
        } @catch (NSException *e) {}
    }
    return nil;
}

static UIView *GetLabelView(SBIconView *iconView) {
    UIView *labelView = nil;
    @try {
        labelView = [iconView valueForKey:@"_labelView"];
    } @catch (NSException *e) {}
    if (!labelView && [iconView respondsToSelector:@selector(labelView)]) {
        labelView = [iconView labelView];
    }
    return labelView;
}

// =========================================================
// 标签隐藏 / 恢复（只处理我们隐藏过的）
// =========================================================
static void SetLabelHiddenByUs(UIView *labelView, BOOL hide) {
    if (!labelView) return;
    labelView.hidden = hide;
    labelView.alpha  = hide ? 0.0 : 1.0;
    objc_setAssociatedObject(labelView,
                             kLabelHiddenByUsKey,
                             hide ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL WasLabelHiddenByUs(UIView *labelView) {
    if (!labelView) return NO;
    return [objc_getAssociatedObject(labelView, kLabelHiddenByUsKey) boolValue];
}

static void RecurseLabels(UIView *view, BOOL hide, BOOL onlyIfOurs) {
    for (UIView *sub in view.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"Label"] || [cls containsString:@"Legibility"]) {
            if (hide) {
                SetLabelHiddenByUs(sub, YES);
            } else if (!onlyIfOurs || WasLabelHiddenByUs(sub)) {
                SetLabelHiddenByUs(sub, NO);
            }
        }
        RecurseLabels(sub, hide, onlyIfOurs);
    }
}

// =========================================================
// 应用标签可见性（幂等）
// =========================================================
static void ApplyLabelVisibility(SBIconView *iconView) {
    if (!iconView) return;

    BOOL isWidget   = IsWidgetView(iconView);
    BOOL mySwitchOn = g_enabled && (isWidget ? g_hideWidgetNames : g_hideAppNames);

    UIView *labelView = GetLabelView(iconView);

    if (mySwitchOn) {
        if (labelView) SetLabelHiddenByUs(labelView, YES);
        RecurseLabels(iconView, YES, NO);
    } else {
        if (labelView && WasLabelHiddenByUs(labelView)) {
            SetLabelHiddenByUs(labelView, NO);
        }
        RecurseLabels(iconView, NO, YES);
    }
}

// =========================================================
// 图标缩放（transform，幂等）
// =========================================================
static void ApplyIconScale(SBIconView *iconView) {
    if (!iconView) return;

    UIView *iv = GetIconImageView(iconView);
    if (!iv) return;

    // 跳过：小组件、打开的文件夹内部
    if (IsWidgetView(iconView) || IsInOpenFolder(iconView)) {
        if (!CGAffineTransformIsIdentity(iv.transform)) {
            iv.transform = CGAffineTransformIdentity;
        }
        return;
    }

    CGAffineTransform target = CGAffineTransformIdentity;
    if (g_enabled && g_iconScale != 1.0) {
        target = CGAffineTransformMakeScale(g_iconScale, g_iconScale);
    }
    if (!CGAffineTransformEqualToTransform(iv.transform, target)) {
        iv.transform = target;
    }
}

// =========================================================
// 刷新所有图标
// =========================================================
static void RefreshIconViewsRecursive(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:NSClassFromString(@"SBIconView")]) {
        SBIconView *iv = (SBIconView *)view;
        ApplyIconScale(iv);
        ApplyLabelVisibility(iv);
        [view setNeedsLayout];
        [view layoutIfNeeded];
    }
    for (UIView *sub in view.subviews) {
        RefreshIconViewsRecursive(sub);
    }
}

static void RefreshAllIcons(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *window in ws.windows) {
                RefreshIconViewsRecursive(window);
            }
        }
    });
}

// =========================================================
// Hook SBIconView
// =========================================================
%hook SBIconView

- (void)prepareForReuse {
    %orig;
    UIView *iv = GetIconImageView(self);
    if (iv) {
        iv.transform = CGAffineTransformIdentity;
    }
    UIView *labelView = GetLabelView(self);
    if (labelView && WasLabelHiddenByUs(labelView)) {
        SetLabelHiddenByUs(labelView, NO);
    }
}

- (void)layoutSubviews {
    %orig;
    ApplyIconScale(self);
    ApplyLabelVisibility(self);
}

- (void)setIcon:(id)icon {
    %orig;
    ApplyIconScale(self);
    ApplyLabelVisibility(self);
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    if (!hidden) {
        ApplyIconScale(self);
        ApplyLabelVisibility(self);
    }
}

- (void)setAlpha:(CGFloat)alpha {
    %orig;
    if (alpha > 0.0) {
        ApplyIconScale(self);
        ApplyLabelVisibility(self);
    }
}

%end

// =========================================================
// Hook SBIconLabelView
// =========================================================
%hook SBIconLabelView

- (void)layoutSubviews {
    %orig;
    UIView *parent = self.superview;
    while (parent && ![parent isKindOfClass:NSClassFromString(@"SBIconView")]) {
        parent = parent.superview;
    }
    if (!parent) return;

    SBIconView *iconView = (SBIconView *)parent;
    BOOL isWidget   = IsWidgetView(iconView);
    BOOL mySwitchOn = g_enabled && (isWidget ? g_hideWidgetNames : g_hideAppNames);

    if (mySwitchOn) {
        SetLabelHiddenByUs(self, YES);
    } else if (WasLabelHiddenByUs(self)) {
        SetLabelHiddenByUs(self, NO);
    }
}

- (void)setAlpha:(CGFloat)alpha {
    UIView *parent = self.superview;
    while (parent && ![parent isKindOfClass:NSClassFromString(@"SBIconView")]) {
        parent = parent.superview;
    }
    if (parent) {
        SBIconView *iconView = (SBIconView *)parent;
        BOOL isWidget   = IsWidgetView(iconView);
        BOOL mySwitchOn = g_enabled && (isWidget ? g_hideWidgetNames : g_hideAppNames);
        if (mySwitchOn) {
            %orig(0.0);
            objc_setAssociatedObject(self, kLabelHiddenByUsKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
    }
    %orig(alpha);
}

- (void)setHidden:(BOOL)hidden {
    UIView *parent = self.superview;
    while (parent && ![parent isKindOfClass:NSClassFromString(@"SBIconView")]) {
        parent = parent.superview;
    }
    if (parent) {
        SBIconView *iconView = (SBIconView *)parent;
        BOOL isWidget   = IsWidgetView(iconView);
        BOOL mySwitchOn = g_enabled && (isWidget ? g_hideWidgetNames : g_hideAppNames);
        if (mySwitchOn) {
            %orig(YES);
            objc_setAssociatedObject(self, kLabelHiddenByUsKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
    }
    %orig(hidden);
}

%end

// =========================================================
// 初始化
// =========================================================
%ctor {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if (![bundleId isEqualToString:@"com.apple.springboard"]) return;

    LoadPrefs();
    %init;

    for (size_t i = 0; i < sizeof(k26HomeNotifs) / sizeof(k26HomeNotifs[0]); i++) {
        int token;
        notify_register_dispatch(k26HomeNotifs[i], &token,
                                 dispatch_get_main_queue(), ^(int t) {
            LoadPrefs();
            RefreshAllIcons();
        });
    }

    int ownToken;
    notify_register_dispatch(kPrefsChangedNotifC, &ownToken,
                             dispatch_get_main_queue(), ^(int t) {
            LoadPrefs();
            RefreshAllIcons();
        });
}