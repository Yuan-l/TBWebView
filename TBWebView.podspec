Pod::Spec.new do |s|
  s.name             = 'TBWebView'
  s.version          = '0.1.0'
  s.summary          = 'WKWebView 容器：进度条、Cookie 同步、JS 桥宿主能力'

  s.description      = <<-DESC
  WKWebView 轻量容器封装。
  - 加载进度条、标题/返回手势自适应
  - Cookie（共享 HTTPCookieStorage）双向同步
  - 链接拦截路由（scheme 黑白名单）
  - 为 TBJSBridge 提供 user script 注入与 message handler 宿主
                       DESC

  s.homepage         = 'https://github.com/Yuan-l/TBWebView.git'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Yuan-l' => '1013540016@qq.com' }
  s.source           = { :git => 'https://github.com/Yuan-l/TBWebView.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'

  s.source_files = 'TBWebView/Classes/**/*'

  s.frameworks = 'UIKit', 'WebKit'
end
