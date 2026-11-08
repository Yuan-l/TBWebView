//
//  TBWebView.h
//  TBWebView
//
//  WKWebView 容器
//
//  能力：
//  1. 顶部进度条（KVO loading progress，自动显示/隐藏）
//  2. Cookie 同步：共享 NSHTTPCookieStorage → WKWebsiteDataStore（iOS11+ API）
//  3. 链接路由拦截：自定义 scheme / 白名单域外跳转回调业务侧决定
//  4. JS 桥宿主：供 TBJSBridge 注入 user script、注册 message handler
//
//  生命周期约定：
//  - 每个实例持有独立 WKWebViewConfiguration；跨页面共享进程由系统管理
//  - dealloc 自动移除 KVO 与 scriptMessageHandler（防止循环引用）
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 链接导航决策：业务侧返回 YES 表示容器自己处理（外部浏览器打开等）
typedef BOOL (^TBWebViewNavigationFilter)(NSURL *url);

@interface TBWebView : UIView

/// 内部 webView（只读暴露，用于进阶定制）
@property (nonatomic, strong, readonly) WKWebView *webView;

/// 配置（loadURL 前设置生效）
/// 导航拦截：返回 YES = 容器放行；NO = 已由业务处理（如弹出 App Store）
@property (nonatomic, copy, nullable) TBWebViewNavigationFilter navigationFilter;

/// 进度条颜色，默认系统蓝；传 clear 隐藏进度条
@property (nonatomic, strong, nullable) UIColor *progressBarColor UI_APPEARANCE_SELECTOR;

/// JS 桥宿主接口（TBJSBridge 使用；业务一般不直接调）
/// 注入 user script：注入到 atDocumentStart（页面脚本执行前）
- (void)injectUserScript:(NSString *)javaScript atDocumentStart:(BOOL)atStart;
/// 注册 script message handler（封装了 addScriptMessageHandler 的循环引用处理）
- (void)addScriptMessageHandler:(id<WKScriptMessageHandler>)handler name:(NSString *)name;
/// 移除 handler
- (void)removeScriptMessageHandlerForName:(NSString *)name;

/// 执行 JS（主线程安全；completion 主线程回调）
- (void)evaluateJavaScript:(NSString *)script
                completion:(nullable void (^)(id _Nullable result, NSError * _Nullable error))completion;

#pragma mark - 加载

/// 加载 URL（内部处理 Cookie 同步）
- (void)loadURLString:(NSString *)urlString;
- (void)loadURL:(NSURL *)url;
/// 加载本地 HTML（离线包场景）
- (void)loadLocalHTMLFile:(NSString *)fileName inBundle:(nullable NSBundle *)bundle;
- (void)loadHTMLString:(NSString *)html baseURL:(nullable NSURL *)baseURL;

- (BOOL)canGoBack;
- (void)goBack;
- (void)goForward;
- (void)reload;

#pragma mark - Cookie

/// 共享 NSHTTPCookieStorage 的 cookie 同步进 WKWebsiteDataStore
/// （在 loadURL 前调用；iOS 11+ 使用 WKHTTPCookieStore）
+ (void)syncSharedCookiesToWebViewStore;
/// 反向：WKWebView 中的 cookie 同步回共享 storage（登录态回写场景）
- (void)syncWebCookiesToSharedStoreWithCompletion:(nullable dispatch_block_t)completion;

@end

NS_ASSUME_NONNULL_END
