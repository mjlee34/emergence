#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#include <algorithm>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>

@interface SettlementWebDelegate : NSObject <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>
@property(nonatomic, strong) NSURL *origin;
@property(nonatomic, strong) NSMutableArray<NSString *> *events;
@end

@implementation SettlementWebDelegate
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)msg {
  NSURL *url = msg.frameInfo.request.URL;
  if (!msg.frameInfo.isMainFrame || ![url isEqual:self.origin] ||
      ![msg.body isKindOfClass:NSString.class] || [msg.body length] > 512)
    return;
  if (self.events.count < 8) [self.events addObject:msg.body];
}
- (void)webView:(WKWebView *)view decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decide {
  if (!action.targetFrame || action.targetFrame.isMainFrame) {
    NSURL *url = action.request.URL;
    if (![url isEqual:self.origin]) {
      if (action.navigationType == WKNavigationTypeLinkActivated && [url.scheme isEqual:@"https"])
        [NSWorkspace.sharedWorkspace openURL:url];
      decide(WKNavigationActionPolicyCancel);
      return;
    }
  }
  decide(WKNavigationActionPolicyAllow);
}
- (void)webView:(WKWebView *)view didFailProvisionalNavigation:(WKNavigation *)nav withError:(NSError *)error {
  if (error.code != NSURLErrorCancelled) [self.events addObject:@"{\"action\":\"failed\"}"];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)view {
  [self.events addObject:@"{\"action\":\"failed\"}"];
}
@end

using namespace godot;
class GoogleMapView : public RefCounted {
  GDCLASS(GoogleMapView, RefCounted)
  WKWebView *view_ = nil;
  SettlementWebDelegate *delegate_ = nil;
protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("open_page","window","url"), &GoogleMapView::open_page);
    ClassDB::bind_method(D_METHOD("next_event"), &GoogleMapView::next_event);
    ClassDB::bind_method(D_METHOD("notify_page","payload"), &GoogleMapView::notify_page);
    ClassDB::bind_method(D_METHOD("set_opacity","alpha"), &GoogleMapView::set_opacity);
    ClassDB::bind_method(D_METHOD("dismiss"), &GoogleMapView::dismiss);
  }
public:
  bool open_page(int64_t window, String url) {
    dismiss();
    NSWindow *host = (__bridge NSWindow *)(void *)window;
    if (!host.contentView) return false;
    NSURL *page = [NSURL URLWithString:[NSString stringWithUTF8String:url.utf8().get_data()]];
    if (![page.host isEqual:@"127.0.0.1"] || ![page.scheme isEqual:@"http"]) return false;
    delegate_ = [SettlementWebDelegate new];
    delegate_.events = [NSMutableArray new];
    delegate_.origin = page;
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    [config.userContentController addScriptMessageHandler:delegate_ name:@"settlement"];
    view_ = [[WKWebView alloc] initWithFrame:host.contentView.bounds configuration:config];
    view_.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view_.navigationDelegate = delegate_;
    view_.UIDelegate = delegate_;
    [host.contentView addSubview:view_];
    [view_ loadRequest:[NSURLRequest requestWithURL:page]];
    return true;
  }
  String next_event() {
    if (!delegate_.events.count) return {};
    NSString *message = delegate_.events.firstObject;
    [delegate_.events removeObjectAtIndex:0];
    return String::utf8(message.UTF8String);
  }
  void notify_page(String payload) {
    // callAsyncJavaScript passes data as an argument without evaluating it.
    NSString *value = [NSString stringWithUTF8String:payload.utf8().get_data()];
    [view_ callAsyncJavaScript:@"window.cityEvent(JSON.parse(message))"
                     arguments:@{@"message": value} inFrame:nil
                inContentWorld:WKContentWorld.pageWorld completionHandler:nil];
  }
  void set_opacity(double alpha) { view_.alphaValue = std::clamp(alpha, 0., 1.); }
  void dismiss() {
    [view_ stopLoading];
    [view_.configuration.userContentController removeScriptMessageHandlerForName:@"settlement"];
    [view_ removeFromSuperview];
    view_ = nil;
    delegate_ = nil;
  }
  ~GoogleMapView() { dismiss(); }
};
void register_map_view() { GDREGISTER_CLASS(GoogleMapView); }
