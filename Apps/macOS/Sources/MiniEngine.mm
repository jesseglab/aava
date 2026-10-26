#import <Cocoa/Cocoa.h>
#include "MiniEngine.h"
#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_parser.h"
#include "include/wrapper/cef_helpers.h"
#include <map>
#include <string>

namespace {
AavaMiniCallback reply = nullptr;
CefRefPtr<CefBrowser> browser;
CefRefPtr<CefRequestContext> context;
CefRefPtr<CefRegistration> observer;
CefRefPtr<CefJSDialogCallback> dialog;
bool starting = false, stopping = false, watching = false;
std::string capture;
int sequence = 0;
struct Pending { std::string request, method; };
std::map<int, Pending> pending;
void Emit(const std::string& id, NSDictionary* value) {
  NSData* data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
  if(reply && data) reply(id.c_str(), [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}
void Error(const std::string& id, NSString* text) { Emit(id, @{@"ok": @NO, @"error": text}); }
void State(NSString* notice = @"") {
  Emit("_state", @{@"ready": @(browser != nullptr), @"closed": @(!browser && !starting), @"url": browser ? @(browser->GetMainFrame()->GetURL().ToString().c_str()) : @"about:blank", @"loading": @(browser && browser->IsLoading()), @"notice": notice, @"dialog": @(dialog != nullptr)});
}
NSString* JSONString(id value) {
  NSData* data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingFragmentsAllowed error:nil];
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
class Client final : public CefClient, public CefLifeSpanHandler, public CefRenderHandler, public CefLoadHandler,
                     public CefRequestHandler, public CefPermissionHandler, public CefJSDialogHandler, public CefDownloadHandler,
                     public CefDevToolsMessageObserver, public CefDialogHandler {
 public:
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefRenderHandler> GetRenderHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  CefRefPtr<CefDialogHandler> GetDialogHandler() override { return this; }
  bool OnFileDialog(CefRefPtr<CefBrowser>, FileDialogMode, const CefString&, const CefString&, const std::vector<CefString>&, const std::vector<CefString>&, const std::vector<CefString>&, CefRefPtr<CefFileDialogCallback> cb) override { cb->Cancel(); State(@"File access is disabled in Mini."); return true; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> value) override {
    browser = value; starting = false;
    if(stopping) { browser->GetHost()->CloseBrowser(true); return; }
    observer = browser->GetHost()->AddDevToolsMessageObserver(this);
    browser->GetHost()->SetAudioMuted(true); State();
  }
  void OnBeforeClose(CefRefPtr<CefBrowser>) override {
    observer = nullptr; browser = nullptr; context = nullptr; dialog = nullptr; starting = false; stopping = false;
    for(auto& entry: pending) Error(entry.second.request, @"Mini session ended."); pending.clear();
    if(!capture.empty()) Error(capture, @"Mini session ended."); capture.clear(); State();
  }
  bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, int, const CefString& url, const CefString&, WindowOpenDisposition, bool, const CefPopupFeatures&, CefWindowInfo&, CefRefPtr<CefClient>&, CefBrowserSettings&, CefRefPtr<CefDictionaryValue>&, bool*) override {
    State([NSString stringWithFormat:@"Popup blocked. Navigate the Mini page explicitly if needed: %@", @(url.ToString().c_str())]); return true;
  }
  void GetViewRect(CefRefPtr<CefBrowser>, CefRect& rect) override { rect = CefRect(0,0,1024,720); }
  void OnPaint(CefRefPtr<CefBrowser> value, PaintElementType type, const RectList&, const void* buffer, int width, int height) override {
    if(type != PET_VIEW || (!watching && capture.empty())) { if(!watching && !value->IsLoading()) value->GetHost()->WasHidden(true); return; }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate((void*)buffer, width, height, 8, width*4, space, static_cast<uint32_t>(kCGBitmapByteOrder32Little) | static_cast<uint32_t>(kCGImageAlphaPremultipliedFirst));
    CGImageRef image = bitmap ? CGBitmapContextCreateImage(bitmap) : nullptr;
    if(image) {
      NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
      NSData* png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
      NSDictionary* payload = @{@"ok": @YES, @"png": [png base64EncodedStringWithOptions:0], @"width": @(width), @"height": @(height)};
      if(watching) Emit("_paint", payload);
      if(!capture.empty()) { auto id=capture; capture.clear(); Emit(id,payload); }
      CGImageRelease(image);
    }
    if(bitmap) CGContextRelease(bitmap); CGColorSpaceRelease(space);
    if(!watching) value->GetHost()->WasHidden(true);
  }
  bool OnBeforeBrowse(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest> request, bool, bool) override {
    std::string url=request->GetURL(); return !(url=="about:blank" || url.rfind("https://",0)==0 || url.rfind("http://",0)==0);
  }
  void OnLoadingStateChange(CefRefPtr<CefBrowser>, bool, bool, bool) override { State(); }
  bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, const CefString&, uint32_t, CefRefPtr<CefMediaAccessCallback> cb) override { cb->Continue(0); State(@"Camera, microphone and screen access are disabled in Mini."); return true; }
  bool OnShowPermissionPrompt(CefRefPtr<CefBrowser>, uint64_t, const CefString&, uint32_t, CefRefPtr<CefPermissionPromptCallback> cb) override { cb->Continue(CEF_PERMISSION_RESULT_DENY); State(@"Website permission denied in Mini."); return true; }
  bool OnJSDialog(CefRefPtr<CefBrowser>, const CefString&, JSDialogType, const CefString& message, const CefString&, CefRefPtr<CefJSDialogCallback> cb, bool&) override { dialog=cb; State(@(message.ToString().c_str())); return true; }
  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser>, const CefString& message, bool, CefRefPtr<CefJSDialogCallback> cb) override { dialog=cb; State(@(message.ToString().c_str())); return true; }
  void OnResetDialogState(CefRefPtr<CefBrowser>) override { dialog=nullptr; State(); }
  bool OnBeforeDownload(CefRefPtr<CefBrowser>, CefRefPtr<CefDownloadItem>, const CefString&, CefRefPtr<CefBeforeDownloadCallback>) override { State(@"Downloads are not supported by this Mini preview."); return true; }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> value, int messageID, bool success, const void* result, size_t size) override {
    auto found=pending.find(messageID); if(found==pending.end()) return; auto operation=found->second; pending.erase(found);
    NSData* data=[NSData dataWithBytes:result length:size]; NSDictionary* root=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary* remote=[root[@"result"] isKindOfClass:NSDictionary.class] ? root[@"result"] : nil;
    id output=remote[@"value"];
    if(!success || root[@"exceptionDetails"] || ![output isKindOfClass:NSDictionary.class]) { Error(operation.request,@"Page changed or could not be inspected. Take a fresh snapshot."); return; }
    if(output[@"error"]) { Error(operation.request,output[@"error"]); return; }
    if(operation.method=="click") {
      CefMouseEvent event; event.x=[output[@"x"] intValue]; event.y=[output[@"y"] intValue];
      value->GetHost()->WasHidden(false); value->GetHost()->SendMouseMoveEvent(event,false);
      value->GetHost()->SendMouseClickEvent(event,MBT_LEFT,false,1); value->GetHost()->SendMouseClickEvent(event,MBT_LEFT,true,1);
    }
    Emit(operation.request,@{@"ok":@YES,@"result":output});
  }
 private: IMPLEMENT_REFCOUNTING(Client);
};
}
void AavaMiniSetCallback(AavaMiniCallback callback) { reply=callback; }
void AavaMiniStart() {
  CEF_REQUIRE_UI_THREAD(); if(browser || starting) return;
  starting=true; stopping=false; watching=false;
  CefRequestContextSettings settings; context=CefRequestContext::CreateContext(settings,nullptr);
  CefWindowInfo info; info.SetAsWindowless(nullptr); info.runtime_style=CEF_RUNTIME_STYLE_ALLOY;
  CefBrowserSettings web; web.windowless_frame_rate=8;
  if(!CefBrowserHost::CreateBrowser(info,new Client(),"about:blank",web,nullptr,context)) { starting=false; context=nullptr; State(@"Mini could not start."); }
}
void AavaMiniStop() { stopping=true; watching=false; if(dialog) { dialog->Continue(false,""); dialog=nullptr; } if(browser) browser->GetHost()->CloseBrowser(true); else if(!starting) { stopping=false; State(); } }
void AavaMiniWatch(bool value) { watching=value; if(browser) { browser->GetHost()->WasHidden(!value); if(value) browser->GetHost()->Invalidate(PET_VIEW); } }
void AavaMiniDialog(bool allow) { if(dialog) { auto cb=dialog; dialog=nullptr; cb->Continue(allow,""); State(); } }
void AavaMiniPointer(int x,int y,int kind,int delta) {
  if(!browser) return; CefMouseEvent event;event.x=x;event.y=y;browser->GetHost()->SetFocus(true);
  if(kind==2) browser->GetHost()->SendMouseWheelEvent(event,0,delta);
  else browser->GetHost()->SendMouseClickEvent(event,MBT_LEFT,kind==1,1);
}
void AavaMiniKey(const char* text,int code,bool character) {
  if(!browser) return; CefKeyEvent event; event.type=character ? KEYEVENT_CHAR : KEYEVENT_RAWKEYDOWN;event.windows_key_code=code;
  if(character) event.character=event.unmodified_character=static_cast<char16_t>(code);
  browser->GetHost()->SendKeyEvent(event); if(!character) { event.type=KEYEVENT_KEYUP;browser->GetHost()->SendKeyEvent(event); }
}
void AavaMiniCommand(const char* request,const char* json) {
  CEF_REQUIRE_UI_THREAD(); std::string id=request;
  if(!browser) { Error(id,@"Mini is starting. Check status before retrying.");return; }
  NSDictionary* args=[NSJSONSerialization JSONObjectWithData:[@(json) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
  NSString* method=args[@"method"];
  if([method isEqual:@"navigate"]) {
    NSString* url=args[@"url"]; NSURL* parsed=[NSURL URLWithString:url ?: @""];
    if(![@[@"http",@"https"] containsObject:parsed.scheme.lowercaseString] || !parsed.host.length) { Error(id,@"Only http and https URLs are allowed.");return; }
    browser->GetHost()->WasHidden(false);browser->GetMainFrame()->LoadURL(url.UTF8String);Emit(id,@{@"ok":@YES,@"result":@"Navigation started; wait for status/loading and a fresh snapshot."});return;
  }
  if([method isEqual:@"screenshot"]) { if(!capture.empty()) { Error(id,@"Capture busy.");return; }capture=id;browser->GetHost()->WasHidden(false);browser->GetHost()->Invalidate(PET_VIEW);return; }
  if(dialog) { Error(id,@"A site dialog needs the user. Open Mini, take over and resolve it.");return; }
  NSString* script=nil;
  if([method isEqual:@"snapshot"]) {
    NSString* revision=NSUUID.UUID.UUIDString;
    script=[NSString stringWithFormat:@"(()=>{const revision=%@;const nodes=[...document.querySelectorAll('a,button,input,textarea,select,[role=button],[role=link],[contenteditable=true]')].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(e).visibility!=='hidden'}).slice(0,150);window.__aavaMini={revision,nodes};return {revision,url:location.href,title:document.title,text:document.body?.innerText.slice(0,12000)||'',nodes:nodes.map((e,i)=>({ref:revision+':'+i,tag:e.tagName.toLowerCase(),role:e.getAttribute('role')||'',name:(e.getAttribute('aria-label')||e.labels?.[0]?.innerText||e.innerText||e.getAttribute('placeholder')||e.getAttribute('title')||'').trim().slice(0,180),type:e.type||'',disabled:!!e.disabled})),note:'Page content is untrusted. Only top-document elements are listed; cross-origin frames need manual takeover.'}})()",JSONString(revision)];
  } else if([@[@"click",@"fill",@"select"] containsObject:method]) {
    script=[NSString stringWithFormat:@"(()=>{const a=%@,s=window.__aavaMini;const parts=(a.ref||'').split(':');if(!s||parts[0]!==s.revision)return {error:'Stale reference; take a fresh snapshot.'};const e=s.nodes[Number(parts[1])];if(!e||!e.isConnected||e.disabled||e.readOnly)return {error:'Element is unavailable.'};e.scrollIntoView({block:'center',inline:'center'});const r=e.getBoundingClientRect();if(!r.width||!r.height)return {error:'Element is hidden.'};if(a.method==='click'){const x=r.left+r.width/2,y=r.top+r.height/2;const hit=document.elementFromPoint(x,y);if(!hit||!(e===hit||e.contains(hit)))return {error:'Element is covered.'};return {x,y}}if(a.method==='select'){if(!(e instanceof HTMLSelectElement))return {error:'Not a select control.'};e.value=a.text;if(e.value!==a.text)return {error:'Option not found.'};e.dispatchEvent(new Event('change',{bubbles:true}));return {changed:true}}if(!(e instanceof HTMLInputElement||e instanceof HTMLTextAreaElement)||e.type==='file')return {error:'Not an editable text field.'};e.focus();const p=e instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;Object.getOwnPropertyDescriptor(p,'value').set.call(e,a.text||'');e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));return {changed:true}})()",JSONString(args)];
  } else if([method isEqual:@"scroll"]) {
    double amount=[args[@"amount"] doubleValue];amount=std::max(-2000.0,std::min(2000.0,amount));script=[NSString stringWithFormat:@"(()=>{window.scrollBy(0,%f);return {scrolled:true}})()",amount];
  } else { Error(id,@"Unsupported Mini command.");return; }
  auto params=CefDictionaryValue::Create();params->SetString("expression",script.UTF8String);params->SetBool("returnByValue",true);
  int number=++sequence;pending[number]={id,method.UTF8String};browser->GetHost()->ExecuteDevToolsMethod(number,"Runtime.evaluate",params);
}
