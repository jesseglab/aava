#import <Cocoa/Cocoa.h>
#include "Engine.h"
#include "ChromeHost.h"
#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_parser.h"
#include "include/wrapper/cef_helpers.h"
#include <map>
#include <string>
#include <vector>
#include <functional>
#include <memory>
#include <algorithm>
#include "include/cef_cookie.h"
#include <set>
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/cef_request_context_handler.h"

namespace {
AavaEventCallback callback = nullptr;
std::map<std::string, CefRefPtr<CefBrowser>> browsers;
std::map<std::string, CefRefPtr<CefRequestContext>> profiles;
bool quitting = false;
std::set<std::string> automaticCloses;
std::map<std::string, CefRefPtr<CefRegistration>> archiveProbes;
int archiveProbeSequence = 1000000;
std::map<std::string, std::set<uint32_t>> activeDownloads;
struct DownloadControl { std::string profile; CefRefPtr<CefDownloadItemCallback> callback; };
std::map<std::string, DownloadControl> downloadControls;
std::string DownloadToken(uint32_t id) {
  static const std::string run = NSUUID.UUID.UUIDString.UTF8String;
  return run + "-" + std::to_string(id);
}
std::set<std::string> lockedProfiles;
std::set<std::string> privateProfiles;
std::map<std::string, bool> audioBeforeLock;
std::set<std::string> hiddenForLock;
std::string ProfileID(CefRefPtr<CefRequestContext> context) {
  for(const auto& entry:profiles) if(entry.second->IsSame(context)) return entry.first;
  return "";
}
bool Locked(CefRefPtr<CefBrowser> browser) { return lockedProfiles.count(ProfileID(browser->GetHost()->GetRequestContext())) != 0; }
void HideLockedBrowser(const std::string& id, CefRefPtr<CefBrowser> browser) {
  if(!audioBeforeLock.count(id)) audioBeforeLock[id]=browser->GetHost()->IsAudioMuted();
  browser->GetHost()->SetAudioMuted(true);
  browser->GetHost()->SetAccessibilityState(STATE_DISABLED);
  AavaChromeLock(id,true);
  NSWindow* window=CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle()).window;
  window.accessibilityHidden=YES; window.contentView.accessibilityHidden=YES;
  if(window.visible) hiddenForLock.insert(id);
  [window orderOut:nil];
}
std::set<std::string> pendingTabs;
std::set<std::string> readyProfiles;
std::map<std::string, std::vector<std::function<void()>>> pendingProfiles;
class ProfileHandler final : public CefRequestContextHandler {
 public:
  explicit ProfileHandler(std::string id) : id_(std::move(id)) {}
  void OnRequestContextInitialized(CefRefPtr<CefRequestContext>) override {
    readyProfiles.insert(id_);
    auto pending = std::move(pendingProfiles[id_]); pendingProfiles.erase(id_);
    for (auto& create : pending) create();
  }
 private:
  std::string id_;
  IMPLEMENT_REFCOUNTING(ProfileHandler);
};
void Emit(const std::string& id, const std::string& event, const std::string& value) {
  if (callback) callback(id.c_str(), event.c_str(), value.c_str());
}
void Status(const std::string& id, CefRefPtr<CefBrowser> browser) {
  Emit(id, "status", std::string(browser->IsLoading() ? "1" : "0") + "," + (browser->CanGoBack() ? "1" : "0") + "," + (browser->CanGoForward() ? "1" : "0"));
}
CefRefPtr<CefRequestContext> Profile(const std::string& id) {
  if (profiles.count(id)) return profiles[id];
  CefRequestContextSettings settings;
  NSString* data = NSProcessInfo.processInfo.environment[@"AAVA_DATA_DIRECTORY"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Aava"];
  NSString* path = [[data stringByAppendingPathComponent:@"Chromium"] stringByAppendingPathComponent:[NSString stringWithUTF8String:id.c_str()]];
  CefString(&settings.cache_path) = path.UTF8String;
  settings.persist_session_cookies = true;
  profiles[id] = CefRequestContext::CreateContext(settings, new ProfileHandler(id));
  return profiles[id];
}
class ArcCookieFlush final : public CefCompletionCallback {
 public:
  ArcCookieFlush(std::string token, int saved, int failed) : token_(token), saved_(saved), failed_(failed) {}
  void OnComplete() override {
    Emit(token_, "arc-cookies", "{\"saved\":" + std::to_string(saved_) + ",\"failed\":" + std::to_string(failed_) + "}");
  }
 private:
  std::string token_; int saved_, failed_;
  IMPLEMENT_REFCOUNTING(ArcCookieFlush);
};
struct ArcCookieBatch {
  std::string token;
  CefRefPtr<CefCookieManager> manager;
  int remaining = 0, saved = 0, failed = 0;
  void completed(bool success) {
    if (success) ++saved; else ++failed;
    if (--remaining != 0) return;
    if (!manager->FlushStore(new ArcCookieFlush(token, saved, failed)))
      Emit(token, "arc-cookies", "{\"saved\":0,\"failed\":" + std::to_string(saved + failed) + ",\"error\":\"The imported cookie store could not be saved. No existing space was changed.\"}");
  }
};
class ArcCookieSet final : public CefSetCookieCallback {
 public:
  explicit ArcCookieSet(std::shared_ptr<ArcCookieBatch> batch) : batch_(batch) {}
  void OnComplete(bool success) override { batch_->completed(success); }
 private:
  std::shared_ptr<ArcCookieBatch> batch_;
  IMPLEMENT_REFCOUNTING(ArcCookieSet);
};
class ArcCookieStart final : public CefCompletionCallback {
 public:
  ArcCookieStart(CefRefPtr<CefRequestContext> context, NSArray* rows, std::string token)
      : context_(context), rows_(rows), token_(token) {}
  void OnComplete() override {
    auto batch = std::make_shared<ArcCookieBatch>();
    batch->manager = context_->GetCookieManager(nullptr); batch->token = token_; batch->remaining = (int)rows_.count;
    if (!batch->manager) { Emit(token_, "arc-cookies", "{\"saved\":0,\"failed\":0,\"error\":\"Could not open the new cookie store.\"}"); rows_ = nil; return; }
    if (rows_.count == 0) { Emit(token_, "arc-cookies", "{\"saved\":0,\"failed\":0}"); return; }
    for (NSDictionary* row in rows_) {
      bool valid = [row isKindOfClass:NSDictionary.class];
      for (NSString* key in @[@"host", @"name", @"value", @"path", @"expires"]) valid = valid && [row[key] isKindOfClass:NSString.class];
      for (NSString* key in @[@"secure", @"httpOnly", @"persistent", @"sameSite"]) valid = valid && [row[key] isKindOfClass:NSNumber.class];
      if (!valid) { batch->completed(false); continue; }
      NSString* host = row[@"host"];
      if (host.length == 0 || [host containsString:@"/"] || [host containsString:@":"]) { batch->completed(false); continue; }
      NSString* bareHost = [host hasPrefix:@"."] ? [host substringFromIndex:1] : host;
      NSString* url = [NSString stringWithFormat:@"%@://%@/", [row[@"secure"] boolValue] ? @"https" : @"http", bareHost];
      CefCookie cookie;
      CefString(&cookie.name) = [row[@"name"] UTF8String]; CefString(&cookie.value) = [row[@"value"] UTF8String];
      CefString(&cookie.path) = [row[@"path"] UTF8String];
      // Empty domain preserves host-only scope; leading-dot domains retain subdomain scope.
      if ([host hasPrefix:@"."]) CefString(&cookie.domain) = host.UTF8String;
      cookie.secure = [row[@"secure"] boolValue]; cookie.httponly = [row[@"httpOnly"] boolValue];
      cookie.has_expires = [row[@"persistent"] boolValue]; cookie.expires.val = [row[@"expires"] longLongValue];
      cookie.same_site = (cef_cookie_same_site_t)std::clamp([row[@"sameSite"] intValue] + 1, 0, 3);
      cookie.priority = CEF_COOKIE_PRIORITY_MEDIUM;
      if (!batch->manager->SetCookie(url.UTF8String, cookie, new ArcCookieSet(batch))) batch->completed(false);
    }
    rows_ = nil;
  }
 private:
  CefRefPtr<CefRequestContext> context_; NSArray* __strong rows_; std::string token_;
  IMPLEMENT_REFCOUNTING(ArcCookieStart);
};

struct PendingPrompt {
  std::string owner, profile, kind;
  std::function<void(bool, std::string)> complete;
};
std::map<std::string, PendingPrompt> prompts;
void Prompt(const std::string& owner, CefRefPtr<CefBrowser> browser, const std::string& kind,
            NSString* title, NSString* detail, NSString* accept, bool input, NSString* preset,
            std::function<void(bool, std::string)> complete) {
  if (Locked(browser)) { complete(false, ""); return; }
  std::string token = NSUUID.UUID.UUIDString.UTF8String;
  auto profile = ProfileID(browser->GetHost()->GetRequestContext());
  prompts[token] = {owner, profile, kind, std::move(complete)};
  NSDictionary* payload = @{@"token": @(token.c_str()), @"profile": @(profile.c_str()),
    @"title": title, @"detail": detail, @"accept": accept, @"input": @(input), @"preset": preset};
  NSData* data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
  Emit(owner, "prompt", std::string((const char*)data.bytes, data.length));
}
void CancelPrompts(const std::string& owner, bool dialogsOnly = false) {
  std::vector<std::string> keys;
  for (const auto& pair : prompts) if (pair.second.owner == owner && (!dialogsOnly || pair.second.kind == "js")) keys.push_back(pair.first);
  for (const auto& key : keys) {
    auto found = prompts.find(key); if (found == prompts.end()) continue;
    auto pending = std::move(found->second); prompts.erase(found);
    Emit(owner, "prompt-cancelled", key); pending.complete(false, "");
  }
}
class IconDownload final : public CefDownloadImageCallback {
 public:
  IconDownload(std::string owner, std::string page) : owner_(owner), page_(page) {}
  void OnDownloadImageFinished(const CefString&, int, CefRefPtr<CefImage> image) override {
    auto found = browsers.find(owner_);
    if (!image || found == browsers.end() || Locked(found->second) || found->second->GetMainFrame()->GetURL().ToString() != page_) return;
    int width = 0, height = 0;
    auto png = image->GetAsPNG(1, true, width, height);
    if (!png || png->GetSize() > 131072 || width > 128 || height > 128) return;
    std::vector<unsigned char> bytes(png->GetSize()); png->GetData(bytes.data(), bytes.size(), 0);
    NSString* encoded = [[NSData dataWithBytes:bytes.data() length:bytes.size()] base64EncodedStringWithOptions:0];
    NSDictionary* payload = @{@"page": @(page_.c_str()), @"png": encoded};
    NSData* data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    Emit(owner_, "favicon", std::string((const char*)data.bytes, data.length));
  }
 private:
  std::string owner_, page_;
  IMPLEMENT_REFCOUNTING(IconDownload);
};

class ArchiveProbe final : public CefDevToolsMessageObserver {
 public:
  ArchiveProbe(std::string id, int sequence) : id_(std::move(id)), sequence_(sequence) {}
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser, int message_id, bool success, const void* result, size_t size) override {
    if (message_id != sequence_) return;
    CefRefPtr<ArchiveProbe> keepAlive(this);
    auto parsed = success ? CefParseJSON(result, size, JSON_PARSER_RFC) : nullptr;
    auto root = parsed && parsed->GetType() == VTYPE_DICTIONARY ? parsed->GetDictionary() : nullptr;
    auto value = root ? root->GetDictionary("result") : nullptr;
    bool protectedPage = !value || value->GetType("value") != VTYPE_BOOL || value->GetBool("value");
    archiveProbes.erase(id_);
    if (protectedPage || Locked(browser) || browser->IsLoading() || !activeDownloads[id_].empty()) { Emit(id_, "close-cancelled", ""); return; }
    automaticCloses.insert(id_);
    browser->GetHost()->CloseBrowser(false);
  }
 private:
  std::string id_; int sequence_;
  IMPLEMENT_REFCOUNTING(ArchiveProbe);
};

class BrowserClient final : public CefClient, public CefLifeSpanHandler, public CefDisplayHandler,
                            public CefLoadHandler, public CefDownloadHandler, public CefPermissionHandler,
                            public CefJSDialogHandler, public CefRequestHandler {
 public:
  BrowserClient(std::string id, bool embedded, std::string pipOwner = "", std::string linkOwner = "", std::string linkSource = "")
      : id_(std::move(id)), embedded_(embedded), pipOwner_(std::move(pipOwner)), linkOwner_(std::move(linkOwner)), linkSource_(std::move(linkSource)) {}
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD(); browsers[id_] = browser;
    if (quitting) { browser->GetHost()->CloseBrowser(false); return; }
    if (!pipOwner_.empty()) Emit(pipOwner_, "site-pip", "1");
    browser->GetHost()->SetAccessibilityState(STATE_ENABLED);
    if (embedded_ && browser->GetHost()->GetRuntimeStyle() == CEF_RUNTIME_STYLE_ALLOY) {
      NSView* view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
      view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
      view.frame = view.superview.bounds;
    }
    if (Locked(browser)) HideLockedBrowser(id_,browser);
    Status(id_, browser);
  }
  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    if (!embedded_ || browser->GetHost()->GetRuntimeStyle() == CEF_RUNTIME_STYLE_CHROME) return false;
    NSView* view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
    [view removeFromSuperview];
    return true;
  }
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD(); CancelPrompts(id_); automaticCloses.erase(id_); archiveProbes.erase(id_); activeDownloads.erase(id_); browsers.erase(id_); audioBeforeLock.erase(id_); hiddenForLock.erase(id_); Emit(id_, "closed", "");
    if (!pipOwner_.empty()) Emit(pipOwner_, "site-pip", "0");
    if (quitting && browsers.empty()) { profiles.clear(); CefQuitMessageLoop(); }
  }
  bool OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int popup_id,
                     const CefString& url, const CefString& name, WindowOpenDisposition disposition,
                     bool user_gesture, const CefPopupFeatures& features, CefWindowInfo& info,
                     CefRefPtr<CefClient>& client, CefBrowserSettings& settings,
                     CefRefPtr<CefDictionaryValue>& extra, bool* no_js) override {
    if (Locked(browser)) return true;
    if (!user_gesture && disposition != CEF_WOD_NEW_PICTURE_IN_PICTURE) return true;
    // Leave explicit windows, modified clicks, subframes and PiP with Chromium.
    auto modifiers = NSEvent.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl);
    if (embedded_ && frame && frame->IsMain() && user_gesture && !modifiers &&
        disposition == CEF_WOD_NEW_FOREGROUND_TAB && !features.widthSet && !features.heightSet &&
        AavaCanOfferLinkChoice(id_.c_str(), frame->GetURL().ToString().c_str(), url.ToString().c_str())) {
      client = new BrowserClient("popup-" + std::string(NSUUID.UUID.UUIDString.UTF8String), false, "", id_, frame->GetURL());
      return false;
    }
    client = new BrowserClient("popup-" + std::string(NSUUID.UUID.UUIDString.UTF8String), false, disposition == CEF_WOD_NEW_PICTURE_IN_PICTURE ? id_ : "");
    return false;
  }
  bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request,
                      bool user_gesture, bool is_redirect) override {
    if (linkOwner_.empty() || !frame->IsMain()) return false;
    auto owner = std::move(linkOwner_); linkOwner_.clear();
    // Popup creation does not expose the HTTP method. Inspect it here so form
    // submissions (including POST bodies) retain Chromium's original request.
    bool link = request->GetMethod() == "GET" && !request->GetPostData() &&
                (request->GetTransitionType() & TT_SOURCE_MASK) != TT_FORM_SUBMIT;
    if (link && AavaOfferLinkChoice(owner.c_str(), linkSource_.c_str(), request->GetURL().ToString().c_str())) {
      dispatch_async(dispatch_get_main_queue(), ^{ browser->GetHost()->CloseBrowser(true); });
      return true;
    }
    return false;
  }
  void OnBeforeDevToolsPopup(CefRefPtr<CefBrowser>, CefWindowInfo&, CefRefPtr<CefClient>& client,
                            CefBrowserSettings&, CefRefPtr<CefDictionaryValue>&, bool*) override {
    client = new BrowserClient("devtools-" + std::string(NSUUID.UUID.UUIDString.UTF8String), false);
  }
  void OnMediaAccessChange(CefRefPtr<CefBrowser> browser, bool video, bool audio) override {
    Emit(id_, "capture", video || audio ? "1" : "0");
  }
  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString>& urls) override {
    if (Locked(browser) || urls.empty()) return;
    browser->GetHost()->DownloadImage(urls.front(), true, 32, false, new IconDownload(id_, browser->GetMainFrame()->GetURL()));
  }
  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override { Emit(id_, "title", title); }
  void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) override {
    if (frame->IsMain()) { CancelPrompts(id_); AavaChromeURL(id_, url); Emit(id_, "url", url); }
  }
  void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int status) override {
    if (frame->IsMain() && status >= 200 && status < 400 && !Locked(browser)) Emit(id_, "visited", frame->GetURL());
  }
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool loading, bool back, bool forward) override { Status(id_, browser); }
  void OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, ErrorCode code,
                   const CefString& text, const CefString& url) override {
    if (frame->IsMain() && code != ERR_ABORTED) Emit(id_, "error", "Could not load " + url.ToString() + ": " + text.ToString());
  }
  void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser, TerminationStatus status, int code, const CefString& text) override {
    Emit(id_, "error", "A page process stopped. Reload the tab to continue. Unsaved page changes may have been lost.");
  }
  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                        const CefString& suggested_name, CefRefPtr<CefBeforeDownloadCallback> cb) override {
    if (Locked(browser)) return true;
    NSString* filename = [[NSString stringWithUTF8String:suggested_name.ToString().c_str()] lastPathComponent];
    // Chrome must choose extension targets so its installer and security checks run.
    // This delegates handling; a .crx suffix does not grant installation permission.
    if ([filename.pathExtension.lowercaseString isEqualToString:@"crx"] ||
        item->GetMimeType().ToString() == "application/x-chrome-extension") return false;
    Prompt(id_, browser, "download", @"Save download", @"Save this file to your Downloads folder. Existing files will not be replaced.", @"Save file", true, filename,
      [cb](bool allow, std::string name) {
        if (!allow) return;
        NSString* clean = [[NSString stringWithUTF8String:name.c_str()] lastPathComponent];
        if (!clean.length || [clean isEqualToString:@"."] || [clean isEqualToString:@".."]) return;
        NSURL* root = [[NSFileManager defaultManager] URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
        NSString* destination = [root.path stringByAppendingPathComponent:clean];
        for (int n=1; [[NSFileManager defaultManager] fileExistsAtPath:destination]; ++n) {
          NSString* base = [clean stringByDeletingPathExtension]; NSString* ext = clean.pathExtension;
          NSString* unique = [NSString stringWithFormat:@"%@ (%d)%@%@", base, n, ext.length ? @"." : @"", ext];
          destination = [root.path stringByAppendingPathComponent:unique];
        }
        cb->Continue(destination.UTF8String, false);
      });
    return true;
  }
  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item, CefRefPtr<CefDownloadItemCallback> cb) override {
    if (item->IsInProgress()) activeDownloads[id_].insert(item->GetId());
    else activeDownloads[id_].erase(item->GetId());
    Emit(id_, "downloading", activeDownloads[id_].empty() ? "0" : "1");
    auto profile = ProfileID(browser->GetHost()->GetRequestContext());
    auto token = DownloadToken(item->GetId());
    if (item->IsInProgress()) downloadControls[token] = {profile, cb};
    else downloadControls.erase(token);
    NSString* path = @(item->GetFullPath().ToString().c_str());
    NSString* name = path.length ? path.lastPathComponent : @(item->GetSuggestedFileName().ToString().c_str());
    NSString* status = item->IsComplete() ? @"complete" : item->IsCanceled() ? @"cancelled" : item->IsInterrupted() ? @"interrupted" : item->IsPaused() ? @"paused" : path.length ? @"downloading" : @"waiting";
    NSDictionary* payload = @{@"id": @(token.c_str()), @"profile": @(profile.c_str()), @"name": name.length ? name : @"Download",
      @"path": path, @"received": @(item->GetReceivedBytes()), @"total": @(item->GetTotalBytes()), @"status": status,
      @"createdAt": @([NSDate date].timeIntervalSinceReferenceDate)};
    NSData* data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (data) Emit(id_, "download-state", std::string((const char*)data.bytes, data.length));
  }
  bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
      const CefString& origin, uint32_t permissions, CefRefPtr<CefMediaAccessCallback> cb) override {
    if (Locked(browser)) { cb->Continue(0); return true; }
    if (permissions & (CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE)) return false;
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    if (permissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) [names addObject:@"microphone"];
    if (permissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) [names addObject:@"camera"];
    if (permissions & (CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE)) [names addObject:@"screen sharing"];
    NSString* text = [NSString stringWithFormat:@"%@ requests %@.", [NSString stringWithUTF8String:origin.ToString().c_str()], [names componentsJoinedByString:@", "]];
    Prompt(id_, browser, "permission", @"Website media permission", text, @"Allow this time", false, @"",
      [cb, permissions](bool allow, std::string) { cb->Continue(allow ? permissions : 0); });
    return true;
  }
  bool OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser, uint64_t prompt, const CefString& origin,
      uint32_t permissions, CefRefPtr<CefPermissionPromptCallback> cb) override {
    if (Locked(browser) || ((permissions & CEF_PERMISSION_TYPE_NOTIFICATIONS) && privateProfiles.count(ProfileID(browser->GetHost()->GetRequestContext())))) { cb->Continue(CEF_PERMISSION_RESULT_DENY); return true; }
    std::vector<std::pair<uint32_t, NSString*>> types = {
      {CEF_PERMISSION_TYPE_GEOLOCATION, @"location"}, {CEF_PERMISSION_TYPE_NOTIFICATIONS, @"notifications"},
      {CEF_PERMISSION_TYPE_CLIPBOARD, @"clipboard"}, {CEF_PERMISSION_TYPE_LOCAL_FONTS, @"local fonts"},
      {CEF_PERMISSION_TYPE_CAMERA_STREAM, @"camera"}, {CEF_PERMISSION_TYPE_MIC_STREAM, @"microphone"},
      {CEF_PERMISSION_TYPE_STORAGE_ACCESS, @"cross-site storage"}, {CEF_PERMISSION_TYPE_TOP_LEVEL_STORAGE_ACCESS, @"cross-site storage"},
      {CEF_PERMISSION_TYPE_MULTIPLE_DOWNLOADS, @"multiple downloads"}, {CEF_PERMISSION_TYPE_FILE_SYSTEM_ACCESS, @"files"},
      {CEF_PERMISSION_TYPE_LOCAL_NETWORK, @"local network"}, {CEF_PERMISSION_TYPE_LOOPBACK_NETWORK, @"loopback network"}, {CEF_PERMISSION_TYPE_POINTER_LOCK, @"pointer lock"},
      {CEF_PERMISSION_TYPE_KEYBOARD_LOCK, @"keyboard lock"}, {CEF_PERMISSION_TYPE_WINDOW_MANAGEMENT, @"window management"}
    };
    NSMutableArray<NSString*>* names = [NSMutableArray array]; uint32_t known = 0;
    for (const auto& entry : types) if (permissions & entry.first) { [names addObject:entry.second]; known |= entry.first; }
    if (known != permissions || names.count == 0) { cb->Continue(CEF_PERMISSION_RESULT_DENY); return true; }
    NSString* text = [NSString stringWithFormat:@"%@ requests access to %@.", [NSString stringWithUTF8String:origin.ToString().c_str()], [names componentsJoinedByString:@", "]];
    Prompt(id_, browser, "permission", @"Website permission", text, @"Allow this time", false, @"",
      [cb](bool allow, std::string) { cb->Continue(allow ? CEF_PERMISSION_RESULT_ACCEPT : CEF_PERMISSION_RESULT_DENY); });
    return true;
  }
  bool OnJSDialog(CefRefPtr<CefBrowser> browser, const CefString& origin, JSDialogType type,
                  const CefString& text, const CefString& preset, CefRefPtr<CefJSDialogCallback> cb, bool& suppress) override {
    if (Locked(browser)) { suppress=true; return false; }
    NSString* title = [NSString stringWithFormat:@"Message from %@", @(origin.ToString().c_str())];
    Prompt(id_, browser, "js", title, @(text.ToString().c_str()), @"OK", type == JSDIALOGTYPE_PROMPT, @(preset.ToString().c_str()),
      [cb](bool allow, std::string answer) { cb->Continue(allow, answer); });
    return true;
  }
  void OnResetDialogState(CefRefPtr<CefBrowser>) override { CancelPrompts(id_, true); }
  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser, const CefString&, bool, CefRefPtr<CefJSDialogCallback> cb) override {
    auto owner = id_;
    if (automaticCloses.erase(id_)) { cb->Continue(false, ""); Emit(id_, "close-cancelled", ""); return true; }
    Prompt(id_, browser, "unload", @"Leave this page?", @"Changes you made may not be saved.", @"Leave page", false, @"",
      [cb, owner](bool allow, std::string) {
        if (!allow) { quitting = false; Emit(owner, "close-cancelled", ""); }
        cb->Continue(allow, "");
      });
    return true;
  }
 private:
  std::string id_;
  bool embedded_;
  std::string pipOwner_;
  std::string linkOwner_, linkSource_;
  IMPLEMENT_REFCOUNTING(BrowserClient);
};
}

extern "C" void AavaEngineImportArcCookies(const char* profile, const char* json, const char* token) {
  CEF_REQUIRE_UI_THREAD();
  std::string profileID(profile), request(token);
  NSString* data = NSProcessInfo.processInfo.environment[@"AAVA_DATA_DIRECTORY"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Aava"];
  NSString* directory = [[data stringByAppendingPathComponent:@"Chromium"] stringByAppendingPathComponent:@(profile)];
  // Only fresh profile IDs are accepted. This API must never overwrite an active user's sessions.
  if (quitting || ![[NSUUID alloc] initWithUUIDString:@(profile)] || profiles.count(profileID) || lockedProfiles.count(profileID) || [NSFileManager.defaultManager fileExistsAtPath:directory]) {
    Emit(request, "arc-cookies", "{\"saved\":0,\"failed\":0,\"error\":\"Session transfer requires a new, unused space.\"}"); return;
  }
  NSData* payload = [@(json) dataUsingEncoding:NSUTF8StringEncoding];
  id rows = payload.length <= 128 * 1024 * 1024 ? [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil] : nil;
  if (![rows isKindOfClass:NSArray.class] || [rows count] > 20000) {
    Emit(request, "arc-cookies", "{\"saved\":0,\"failed\":0,\"error\":\"The session transfer data could not be read.\"}"); return;
  }
  auto context = Profile(profileID);
  auto begin = [context, rows, request] { context->GetCookieManager(new ArcCookieStart(context, rows, request)); };
  if (readyProfiles.count(profileID)) begin(); else pendingProfiles[profileID].push_back(begin);
}

CefRefPtr<CefClient> AavaEngineDefaultClient() {
  // Chrome-created extension windows must participate in privacy and shutdown.
  return new BrowserClient("chrome-" + std::string(NSUUID.UUID.UUIDString.UTF8String), false);
}
extern "C" void AavaEngineSetCallback(AavaEventCallback cb) { callback = cb; }
extern "C" void AavaEngineCreate(void* parent, const char* id, const char* profile, const char* url) {
  CEF_REQUIRE_UI_THREAD();
  std::string identifier(id), location(url), profileID(profile);
  if (quitting || browsers.count(identifier) || pendingTabs.count(identifier)) return;
  pendingTabs.insert(identifier);
  auto context = Profile(profileID);
  NSView* anchor = (__bridge NSView*)parent;
  auto create = [anchor, identifier, location, context]() {
    if (!pendingTabs.erase(identifier) || quitting) return;
    if (lockedProfiles.count(ProfileID(context))) { Emit(identifier,"closed",""); return; }
    if (!AavaChromeCreate((__bridge void*)anchor, identifier, new BrowserClient(identifier, true), context, location)) { Emit(identifier, "closed", ""); Emit(identifier, "error", "Chromium could not create this tab. Select it again to retry."); }
  };
  if (readyProfiles.count(profileID)) create(); else pendingProfiles[profileID].push_back(create);
}
extern "C" void AavaEngineNavigate(const char* id, const char* url) { if (browsers.count(id)) browsers[id]->GetMainFrame()->LoadURL(url); }
extern "C" void AavaEngineDownloadAction(const char* token, const char* profile, const char* action) {
  CEF_REQUIRE_UI_THREAD();
  auto entry = downloadControls.find(token);
  if (entry == downloadControls.end() || entry->second.profile != profile || lockedProfiles.count(profile)) return;
  auto cb = entry->second.callback; std::string command(action);
  if (command == "pause") cb->Pause();
  else if (command == "resume") cb->Resume();
  else if (command == "cancel") cb->Cancel();
}
extern "C" void AavaEngineAction(const char* id, const char* action) {
  if (std::string(action) == "downloads") { [[NSWorkspace sharedWorkspace] openURL:[[NSFileManager defaultManager] URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject]; return; }
  if (!browsers.count(id)) return;
  auto browser = browsers[id];
  if(Locked(browser) && std::string(action)!="dock") return;
  auto host = browser->GetHost(); std::string command(action);
  if (command == "back") browser->GoBack();
  else if (command == "forward") browser->GoForward();
  else if (command == "reload") browser->Reload();
  else if (command == "stop") browser->StopLoad();
  else if (command == "status") Status(id, browser);
  else if (command == "toolbar") AavaChromeToolbar(id);
  else if (command == "popout") AavaChromePopout(id, true);
  else if (command == "dock") AavaChromePopout(id, false);
  else if (command == "zoom-in") host->SetZoomLevel(host->GetZoomLevel() + 0.5);
  else if (command == "zoom-out") host->SetZoomLevel(host->GetZoomLevel() - 0.5);
  else if (command == "zoom-reset") host->SetZoomLevel(0);
  else if (command.rfind("find:", 0) == 0) host->Find(command.substr(5), true, false, false);
  else if (command == "stop-find") host->StopFinding(true);
  else if (command == "devtools") { CefWindowInfo info; CefBrowserSettings settings; host->ShowDevTools(info, new BrowserClient("devtools-" + std::string(id), false), settings, CefPoint()); }
  else if (command == "pip") {
    auto params = CefDictionaryValue::Create();
    params->SetString("expression", "(()=>{const videos=[...document.querySelectorAll('video')].filter(v=>v.readyState>0).sort((a,b)=>b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight);if(document.pictureInPictureElement)return document.exitPictureInPicture();if(videos[0])return videos[0].requestPictureInPicture();alert('No playable video was found on this page.');})()");
    params->SetBool("userGesture", true);
    host->ExecuteDevToolsMethod(0, "Runtime.evaluate", params);
  }
}
extern "C" void AavaEngineClose(const char* id) {
  if (pendingTabs.erase(id)) { Emit(id, "closed", ""); return; }
  if (browsers.count(id)) browsers[id]->GetHost()->CloseBrowser(false);
}
extern "C" void AavaEngineArchive(const char* id) {
  CEF_REQUIRE_UI_THREAD();
  if (!browsers.count(id) || Locked(browsers[id]) || browsers[id]->IsLoading() || !activeDownloads[id].empty()) { Emit(id, "close-cancelled", ""); return; }
  auto host = browsers[id]->GetHost();
  int sequence = ++archiveProbeSequence;
  archiveProbes[id] = host->AddDevToolsMessageObserver(new ArchiveProbe(id, sequence));
  auto parameters = CefDictionaryValue::Create();
  parameters->SetString("expression", "(()=>{try{return [...document.querySelectorAll('video,audio')].some(m=>!m.paused&&!m.ended)||[...document.querySelectorAll('input,textarea,select')].some(e=>e.type==='checkbox'||e.type==='radio'?e.checked!==e.defaultChecked:e.tagName==='SELECT'?[...e.options].some(o=>o.selected!==o.defaultSelected):e.value!==e.defaultValue)||[...document.querySelectorAll('[contenteditable=true]')].some(e=>e.textContent.trim().length>0)}catch{return true}})()");
  parameters->SetBool("returnByValue", true);
  if (!host->ExecuteDevToolsMethod(sequence, "Runtime.evaluate", parameters)) { archiveProbes.erase(id); Emit(id, "close-cancelled", ""); }
}
extern "C" void AavaEngineExtensions(const char* profile) {
  if(lockedProfiles.count(profile)) return;
  CefWindowInfo info; info.runtime_style = CEF_RUNTIME_STYLE_CHROME;
  CefBrowserSettings settings;
  CefBrowserHost::CreateBrowser(info, new BrowserClient("extensions-" + std::string(NSUUID.UUID.UUIDString.UTF8String), false), "chrome://extensions/", settings, nullptr, Profile(profile));
}
extern "C" void AavaEngineQuit() {
  CEF_REQUIRE_UI_THREAD(); quitting = true; pendingTabs.clear(); pendingProfiles.clear();
  if (browsers.empty()) { profiles.clear(); CefQuitMessageLoop(); return; }
  auto copy = browsers;
  for (const auto& entry : copy) entry.second->GetHost()->CloseBrowser(false);
}

extern "C" void AavaEngineSync(const char* id) { AavaChromeSync(id); }
extern "C" void AavaEngineOverlay(bool visible) { AavaChromeOverlay(visible); }

extern "C" void AavaEngineRequestSelect(const char* id) { Emit(id, "select", ""); }

extern "C" bool AavaEngineCloseFocused() {
  for (const auto& entry : browsers) {
    NSView* view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(entry.second->GetHost()->GetWindowHandle());
    if (view.window != NSApp.keyWindow) continue;
    if (Locked(entry.second)) return true;
    if ([[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:entry.first.c_str()]]) Emit(entry.first, "request-close", "");
    else entry.second->GetHost()->CloseBrowser(false);
    return true;
  }
  return false;
}

extern "C" void AavaEngineRequestSearch(const char* id) { Emit(id, "search", ""); }

extern "C" void AavaEngineLockProfile(const char* profile, bool locked) {
  CEF_REQUIRE_UI_THREAD();
  bool wasLocked=lockedProfiles.count(profile)!=0;
  privateProfiles.insert(profile);
  if(locked) lockedProfiles.insert(profile); else lockedProfiles.erase(profile);
  if(wasLocked==locked) return;
  auto context=profiles.find(profile); if(context==profiles.end()) return;
  auto copy=browsers;
  for(const auto& entry:copy) {
    if(!entry.second->GetHost()->GetRequestContext()->IsSame(context->second)) continue;
    if(locked) {
      CancelPrompts(entry.first);
      HideLockedBrowser(entry.first,entry.second);
      // Auxiliary windows cannot reopen themselves while the owning profile is locked.
      if(![[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:entry.first.c_str()]]) entry.second->GetHost()->CloseBrowser(true);
    }
    else {
      NSWindow* native=CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(entry.second->GetHost()->GetWindowHandle()).window;
      native.accessibilityHidden=NO; native.contentView.accessibilityHidden=NO;
      entry.second->GetHost()->SetAccessibilityState(STATE_ENABLED);
      AavaChromeLock(entry.first,false);
      auto audio=audioBeforeLock.find(entry.first);
      if(audio!=audioBeforeLock.end()) { entry.second->GetHost()->SetAudioMuted(audio->second); audioBeforeLock.erase(audio); }
      if(hiddenForLock.erase(entry.first)) {
        NSWindow* window=CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(entry.second->GetHost()->GetWindowHandle()).window;
        // Page windows are synchronized against their selected anchors, never blindly reopened.
        if(![[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:entry.first.c_str()]]) [window orderFront:nil];
      }
    }
  }
}
extern "C" const char* AavaEngineFocusedProfile() {
  static std::string focused;
  focused.clear();
  for(const auto& entry:browsers) {
    NSWindow* window=CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(entry.second->GetHost()->GetWindowHandle()).window;
    if(window==NSApp.keyWindow) { focused=ProfileID(entry.second->GetHost()->GetRequestContext()); break; }
  }
  return focused.empty()?nullptr:focused.c_str();
}

extern "C" void AavaEngineResolvePrompt(const char* token, bool allow, const char* value) {
  CEF_REQUIRE_UI_THREAD();
  auto found = prompts.find(token); if (found == prompts.end()) return;
  auto prompt = std::move(found->second); prompts.erase(found);
  bool permitted = allow && browsers.count(prompt.owner) && !lockedProfiles.count(prompt.profile);
  prompt.complete(permitted, value ? value : "");
}

extern "C" void AavaEngineNotifyCopied(const char* id) { Emit(id, "copied", ""); }
