//
//  TBWebView.m
//  TBWebView
//

#import "TBWebView.h"

static void *kProgressKVOContext = &kProgressKVOContext;
static NSString * const kTitleKVOPath = @"title";

@interface TBWebView () <WKNavigationDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) NSMutableSet<NSString *> *handlerNames;
@end

@implementation TBWebView

#pragma mark - 初始化

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    _webView = [[WKWebView alloc] initWithFrame:self.bounds configuration:config];
    _webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _webView.navigationDelegate = self;
    _webView.scrollView.delegate = nil;   // 默认不接管滚动，避免手势冲突；需要时业务可自设
    [self addSubview:_webView];

    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    _progressView.frame = CGRectMake(0, 0, self.bounds.size.width, 2);
    _progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _progressView.tintColor = [UIColor systemBlueColor];
    _progressView.progressTintColor = self.progressBarColor ?: [UIColor systemBlueColor];
    _progressView.hidden = YES;
    [self addSubview:_progressView];

    _handlerNames = [NSMutableSet set];

    [_webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:kProgressKVOContext];
    [_webView addObserver:self forKeyPath:kTitleKVOPath options:NSKeyValueObservingOptionNew context:kProgressKVOContext];
}

- (void)dealloc {
    [_webView removeObserver:self forKeyPath:@"estimatedProgress" context:kProgressKVOContext];
    [_webView removeObserver:self forKeyPath:kTitleKVOPath context:kProgressKVOContext];
    [_webView.configuration.userContentController removeAllScriptMessageHandlers];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kProgressKVOContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        CGFloat progress = self.webView.estimatedProgress;
        if (progress >= 1.0) {
            // 加载完成后延迟隐藏，避免进度条闪没
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                self.progressView.hidden = YES;
                self.progressView.progress = 0;
            });
        } else {
            self.progressView.hidden = NO;
            self.progressView.progress = progress;
        }
    } else if ([keyPath isEqualToString:kTitleKVOPath]) {
        // 标题变化仅暴露给 KVO 观察者，容器本身不展示
    }
}

#pragma mark - 加载

- (void)loadURLString:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) { return; }
    [self loadURL:url];
}

- (void)loadURL:(NSURL *)url {
    [TBWebView syncSharedCookiesToWebViewStore];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 30;
    [self.webView loadRequest:request];
}

- (void)loadLocalHTMLFile:(NSString *)fileName inBundle:(NSBundle *)bundle {
    bundle = bundle ?: [NSBundle bundleForClass:[TBWebView class]];
    NSURL *url = [bundle URLForResource:fileName withExtension:@"html"];
    if (!url) { return; }
    [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
}

- (void)loadHTMLString:(NSString *)html baseURL:(NSURL *)baseURL {
    [self.webView loadHTMLString:html baseURL:baseURL];
}

- (BOOL)canGoBack { return self.webView.canGoBack; }
- (void)goBack { [self.webView goBack]; }
- (void)goForward { [self.webView goForward]; }
- (void)reload { [self.webView reload]; }

#pragma mark - Cookie 同步

+ (void)syncSharedCookiesToWebViewStore {
    if (@available(iOS 11.0, *)) {
        WKHTTPCookieStore *store = [WKWebsiteDataStore defaultDataStore].httpCookieStore;
        NSArray<NSHTTPCookie *> *cookies = [NSHTTPCookieStorage sharedHTTPCookieStorage].cookies;
        for (NSHTTPCookie *cookie in cookies) {
            [store setCookie:cookie completionHandler:nil];
        }
    }
    // iOS 11 以下通过请求头 Cookie 字段兜底（deployment target 13，保留方法以防降级）
}

- (void)syncWebCookiesToSharedStoreWithCompletion:(dispatch_block_t)completion {
    if (@available(iOS 11.0, *)) {
        WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
        [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
            for (NSHTTPCookie *cookie in cookies) {
                [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:cookie];
            }
            if (completion) { completion(); }
        }];
    } else if (completion) {
        completion();
    }
}

#pragma mark - 导航代理

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;

    // 自定义 scheme（tel:/mailto:/alipay:/weixin:// 等）交给业务
    if (![url.scheme.lowercaseString isEqualToString:@"http"] &&
        ![url.scheme.lowercaseString isEqualToString:@"https"] &&
        ![url.scheme.lowercaseString isEqualToString:@"about"] &&
        ![url.scheme.lowercaseString isEqualToString:@"file"]) {
        BOOL handled = self.navigationFilter ? self.navigationFilter(url) : NO;
        decisionHandler(handled ? WKNavigationActionPolicyCancel : WKNavigationActionPolicyAllow);
        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error {
    if (error.code != NSURLErrorCancelled) {
#ifdef DEBUG
        fprintf(stderr, "[TBWebView] 加载失败: %s\n", error.localizedDescription.UTF8String);
#endif
    }
}

#pragma mark - JS 宿主接口

- (void)injectUserScript:(NSString *)javaScript atDocumentStart:(BOOL)atStart {
    if (javaScript.length == 0) { return; }
    WKUserScript *script = [[WKUserScript alloc]
        initWithSource:javaScript
        injectionTime:atStart ? WKUserScriptInjectionTimeAtDocumentStart
                              : WKUserScriptInjectionTimeAtDocumentEnd
        forMainFrameOnly:YES];
    [self.webView.configuration.userContentController addUserScript:script];
}

- (void)addScriptMessageHandler:(id<WKScriptMessageHandler>)handler name:(NSString *)name {
    // 直接 add 会 retain handler 导致 controller↔handler 循环引用；
    // 约定：handler 必须是弱引用代理对象（见 TBJSBridge 实现）
    [self.webView.configuration.userContentController addScriptMessageHandler:handler name:name];
    [_handlerNames addObject:name];
}

- (void)removeScriptMessageHandlerForName:(NSString *)name {
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:name];
    [_handlerNames removeObject:name];
}

- (void)evaluateJavaScript:(NSString *)script completion:(void (^)(id, NSError *))completion {
    void (^block)(void) = ^{
        [self.webView evaluateJavaScript:script completionHandler:completion];
    };
    if ([NSThread isMainThread]) { block(); }
    else { dispatch_async(dispatch_get_main_queue(), block); }
}

@end
