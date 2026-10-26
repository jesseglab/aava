#import <Cocoa/Cocoa.h>
#include "ChromeHost.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_browser_view_delegate.h"
#include "include/views/cef_window.h"
#include "include/views/cef_window_delegate.h"
#include "include/views/cef_label_button.h"
#include "include/views/cef_button_delegate.h"
#include "include/views/cef_panel.h"
#include "include/views/cef_box_layout.h"
#include "Engine.h"
#include "include/wrapper/cef_helpers.h"
#include <map>
#include <cmath>

@interface AavaURLReveal : NSView
@property(nonatomic, copy) NSString* tabID;
@property(nonatomic, copy) NSString* URLString;
@property(nonatomic, strong) NSView* bar;
@property(nonatomic, strong) NSButton* addressButton;
@property(nonatomic, strong) NSTrackingArea* hoverArea;
@property(nonatomic, strong) id mouseMonitor;
@end
@implementation AavaURLReveal
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _bar = [[NSView alloc] initWithFrame:NSZeroRect]; _bar.wantsLayer = YES;
    _bar.layer.cornerRadius = AavaInsetRadius(AavaFrameRadius, AavaFrameInset);
    _bar.layer.backgroundColor = [NSColor.windowBackgroundColor colorWithAlphaComponent:0.97].CGColor;
    _bar.alphaValue = 0; [self addSubview:_bar];
    _addressButton = [NSButton buttonWithTitle:@"Address" target:self action:@selector(editURL:)];
    _addressButton.bordered = NO; _addressButton.font = [NSFont systemFontOfSize:12];
    [_bar addSubview:_addressButton];
    NSButton* copy = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"link" accessibilityDescription:@"Copy URL"] target:self action:@selector(copyURL:)];
    copy.bordered = NO; copy.toolTip = @"Copy URL"; copy.tag = 101; [_bar addSubview:copy];
  } return self;
}
- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (_mouseMonitor) { [NSEvent removeMonitor:_mouseMonitor]; _mouseMonitor=nil; }
  if (!self.window) return;
  self.window.acceptsMouseMovedEvents=YES;
  __weak AavaURLReveal* weakSelf=self;
  _mouseMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMouseMoved handler:^NSEvent*(NSEvent* event) {
    AavaURLReveal* view=weakSelf;
    if (view && event.window==view.window) {
      NSPoint point=[view convertPoint:event.locationInWindow fromView:nil];
      BOOL inside=point.y>=0 && point.y<48 && point.x>=0 && point.x<view.bounds.size.width;
      if (inside && view.bar.alphaValue<1) [view mouseEntered:event];
      else if (!inside && view.bar.alphaValue>0) [view mouseExited:event];
    }
    return event;
  }];
}
- (void)dealloc { if (_mouseMonitor) [NSEvent removeMonitor:_mouseMonitor]; }
- (BOOL)isFlipped { return YES; }
- (void)layout {
  [super layout];
  CGFloat width = MIN(560, MAX(160, self.bounds.size.width - 24));
  _bar.frame = NSMakeRect((self.bounds.size.width-width)/2, 6, width, 36);
  _addressButton.frame = NSMakeRect(10, 2, width-54, 32);
  [_bar viewWithTag:101].frame = NSMakeRect(width-40, 2, 32, 32);
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_hoverArea) [self removeTrackingArea:_hoverArea];
  _hoverArea = [[NSTrackingArea alloc] initWithRect:NSMakeRect(0, 0, self.bounds.size.width, 48) options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways owner:self userInfo:nil];
  [self addTrackingArea:_hoverArea];
}
- (NSView*)hitTest:(NSPoint)point {
  NSPoint local = [self convertPoint:point fromView:self.superview];
  if (_bar.alphaValue < 0.1 || !NSPointInRect(local, _bar.frame)) return nil;
  return [super hitTest:point];
}
- (void)mouseEntered:(NSEvent*)event { [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) { context.duration=0.16; self.bar.animator.alphaValue=1; } completionHandler:nil]; }
- (void)mouseExited:(NSEvent*)event { [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) { context.duration=0.16; self.bar.animator.alphaValue=0; } completionHandler:nil]; }
- (void)setURLString:(NSString*)value {
  _URLString = [value copy];
  NSURL* url = [NSURL URLWithString:value];
  _addressButton.title = url.host ?: value;
  _addressButton.toolTip = value;
}
- (void)editURL:(id)sender { AavaEngineRequestSearch(self.tabID.UTF8String); }
- (void)copyURL:(id)sender {
  if (!self.URLString.length) return;
  [NSPasteboard.generalPasteboard clearContents];
  [NSPasteboard.generalPasteboard setString:self.URLString forType:NSPasteboardTypeString];
  AavaEngineNotifyCopied(self.tabID.UTF8String);
}
@end

namespace {
struct PageWindow {
  CefRefPtr<CefWindow> window;
  CefRefPtr<CefBrowserView> browser;
  __weak NSView* anchor;
  CefRefPtr<CefLabelButton> returnButton;
  AavaURLReveal* reveal;
  bool syncing = false;
  bool toolbar = false;
  bool floating = false;
  bool locked = false;
  int layoutWidth = -1, layoutHeight = -1;
  bool layoutFloating = false, layoutToolbar = false;
};
std::map<std::string, PageWindow> pages;
bool overlay = false;
NSWindow* Native(CefRefPtr<CefWindow> window) {
  return CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(window->GetWindowHandle()).window;
}
void SetPageBounds(PageWindow& page, NSRect frame) {
  // CEF screen coordinates start at the primary screen's top-left; AppKit's
  // coordinates start at its bottom-left. Let CEF resize its complete view tree.
  CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
  // Round shared edges, not origin and size independently: truncation can leave
  // a one-pixel strip after fractional sidebar drags or window positioning.
  int left = (int)std::round(NSMinX(frame));
  int right = (int)std::round(NSMaxX(frame));
  int upper = (int)std::round(top - NSMaxY(frame));
  int lower = (int)std::round(top - NSMinY(frame));
  CefRect desired(left, upper, std::max(1, right - left), std::max(1, lower - upper));
  if (page.window->GetBounds() != desired) page.window->SetBounds(desired);
}
void Layout(PageWindow& page) {
  auto size = page.window->GetBounds();
  if (page.layoutWidth == size.width && page.layoutHeight == size.height && page.layoutFloating == page.floating && page.layoutToolbar == page.toolbar) return;
  page.layoutWidth = size.width; page.layoutHeight = size.height;
  page.layoutFloating = page.floating; page.layoutToolbar = page.toolbar;
  NSWindow* native = Native(page.window);
  // The web surface owns its rounded mask. An opaque window backing underneath
  // leaves a rim at its antialiased corners, especially over textured chrome.
  native.opaque = NO;
  native.backgroundColor = NSColor.clearColor;
  native.contentView.layer.backgroundColor = NSColor.clearColor.CGColor;
  native.contentView.layer.contentsScale = native.backingScaleFactor;
  native.contentView.layer.allowsEdgeAntialiasing = YES;
  native.contentView.layer.borderWidth = 0;
  native.movable = page.floating;
  native.movableByWindowBackground = NO;
  NSWindowStyleMask style = native.styleMask;
  NSWindowStyleMask desired = page.floating ? (style | NSWindowStyleMaskResizable) : (style & ~NSWindowStyleMaskResizable);
  if (style != desired) native.styleMask = desired;
  page.reveal.hidden = page.floating || page.toolbar;
  auto bounds = page.window->GetBounds();
  if (page.returnButton) {
    page.returnButton->SetVisible(page.floating);
    page.returnButton->SetMinimumSize(CefSize(120, 40));
  }
  std::vector<CefDraggableRegion> regions;
  if (page.floating) { CefDraggableRegion region; region.bounds = CefRect(140, 0, std::max(1, bounds.width - 140), 40); region.draggable = true; regions.push_back(region); }
  page.window->SetDraggableRegions(regions);
  if (auto toolbar = page.browser->GetChromeToolbar()) {
    toolbar->SetVisible(page.toolbar);
  }
  page.window->Layout();
}
class BrowserDelegate final : public CefBrowserViewDelegate {
 public:
  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView>) override { return CEF_CTT_NORMAL; }
 private:
  IMPLEMENT_REFCOUNTING(BrowserDelegate);
};
class ReturnButtonDelegate final : public CefButtonDelegate {
 public:
  explicit ReturnButtonDelegate(std::string id) : id_(std::move(id)) {}
  void OnButtonPressed(CefRefPtr<CefButton>) override { AavaEngineRequestSelect(id_.c_str()); }
 private:
  std::string id_;
  IMPLEMENT_REFCOUNTING(ReturnButtonDelegate);
};
class WindowDelegate final : public CefWindowDelegate {
 public:
  explicit WindowDelegate(std::string id) : id_(std::move(id)) {}
  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    auto& page = pages.at(id_); page.window = window;
    CefBoxLayoutSettings layoutSettings; layoutSettings.horizontal = false;
    auto layout = window->SetToBoxLayout(layoutSettings);
    window->AddChildView(page.browser);
    layout->SetFlexForView(page.browser, 1);
    if (auto toolbar = page.browser->GetChromeToolbar()) window->AddChildViewAt(toolbar, 0);
    page.returnButton = CefLabelButton::CreateLabelButton(new ReturnButtonDelegate(id_), "Back to tab");
    window->AddChildViewAt(page.returnButton, 0);
    NSWindow* native = Native(window);
    native.hasShadow = NO;
    native.collectionBehavior |= NSWindowCollectionBehaviorFullScreenAuxiliary;
    native.contentView.wantsLayer = YES;
    native.contentView.layer.cornerRadius = AavaInsetRadius(AavaFrameRadius, AavaFrameInset);
    native.contentView.layer.cornerCurve = kCACornerCurveContinuous;
    native.contentView.layer.masksToBounds = YES;
    page.reveal = [[AavaURLReveal alloc] initWithFrame:native.contentView.bounds];
    page.reveal.tabID = [NSString stringWithUTF8String:id_.c_str()];
    page.reveal.URLString = [NSString stringWithUTF8String:page.browser->GetBrowser()->GetMainFrame()->GetURL().ToString().c_str()];
    [native.contentView addSubview:page.reveal positioned:NSWindowAbove relativeTo:nil];
    Layout(page);
    AavaChromeSync(id_);
  }
  void OnWindowBoundsChanged(CefRefPtr<CefWindow>, const CefRect&) override {
    auto it = pages.find(id_);
    if (it == pages.end() || it->second.syncing) return;
    if (it->second.floating) Layout(it->second);
    else AavaChromeSync(id_);
  }
  void OnWindowDestroyed(CefRefPtr<CefWindow>) override { pages.erase(id_); }
  bool CanClose(CefRefPtr<CefWindow>) override {
    auto it = pages.find(id_);
    if (it == pages.end()) return true;
    auto browser = it->second.browser->GetBrowser();
    return !browser || browser->GetHost()->TryCloseBrowser();
  }
  CefSize GetPreferredSize(CefRefPtr<CefView>) override { return CefSize(1000, 780); }
  cef_show_state_t GetInitialShowState(CefRefPtr<CefWindow>) override { return CEF_SHOW_STATE_HIDDEN; }
  bool IsFrameless(CefRefPtr<CefWindow>) override { return true; }
  bool WithStandardWindowButtons(CefRefPtr<CefWindow>) override { return false; }
  bool CanResize(CefRefPtr<CefWindow>) override { return pages.count(id_) && pages.at(id_).floating; }
  bool CanMaximize(CefRefPtr<CefWindow>) override { return false; }
  bool CanMinimize(CefRefPtr<CefWindow>) override { return false; }
  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
 private:
  std::string id_;
  IMPLEMENT_REFCOUNTING(WindowDelegate);
};
}
bool AavaChromeCreate(void* parent, const std::string& id, CefRefPtr<CefClient> client,
                      CefRefPtr<CefRequestContext> context, const std::string& url) {
  CEF_REQUIRE_UI_THREAD();
  if (pages.count(id)) return false;
  PageWindow page; page.anchor = (__bridge NSView*)parent;
  CefBrowserSettings settings;
  page.browser = CefBrowserView::CreateBrowserView(client, url, settings, nullptr, context, new BrowserDelegate());
  if (!page.browser) return false;
  pages.emplace(id, page);
  CefWindow::CreateTopLevelWindow(new WindowDelegate(id));
  return true;
}
void AavaChromeSync(const std::string& id) {
  CEF_REQUIRE_UI_THREAD();
  auto it = pages.find(id); if (it == pages.end() || !it->second.window) return;
  auto& page = it->second;
  if (page.syncing) return;
  struct SyncGuard { bool& value; explicit SyncGuard(bool& flag) : value(flag) { value = true; } ~SyncGuard() { value = false; } } guard(page.syncing);
  if (page.locked) { [Native(page.window).parentWindow removeChildWindow:Native(page.window)]; page.window->Hide(); return; }
  if (page.floating) return;
  NSWindow* native = Native(page.window);
  NSView* anchor = page.anchor;
  NSWindow* parent = anchor.window;
  if (!parent || !parent.visible || overlay || anchor.hiddenOrHasHiddenAncestor) {
    [native.parentWindow removeChildWindow:native];
    page.window->Hide(); return;
  }
  if (native.parentWindow != parent) {
    [native.parentWindow removeChildWindow:native];
    [parent addChildWindow:native ordered:NSWindowAbove];
  }
  NSRect frame = [parent convertRectToScreen:[anchor convertRect:anchor.bounds toView:nil]];
  SetPageBounds(page, frame);
  Layout(page);
  page.reveal.frame = native.contentView.bounds;
  if (page.reveal.superview != native.contentView) [native.contentView addSubview:page.reveal positioned:NSWindowAbove relativeTo:nil];
  if (!native.visible) { page.window->Show(); [parent addChildWindow:native ordered:NSWindowAbove]; }
}
void AavaChromeOverlay(bool visible) {
  if (overlay == visible) return;
  overlay = visible;
  for (const auto& entry : pages) AavaChromeSync(entry.first);
}
void AavaChromeToolbar(const std::string& id) {
  auto it = pages.find(id); if (it == pages.end()) return;
  it->second.toolbar = !it->second.toolbar; Layout(it->second);
}
void AavaChromePopout(const std::string& id, bool floating) {
  auto it = pages.find(id); if (it == pages.end()) return;
  auto& page = it->second;
  if (floating && page.locked) return;
  page.floating = floating;
  NSWindow* native = Native(page.window);
  if (floating) {
    [native.parentWindow removeChildWindow:native];
    native.level = NSFloatingWindowLevel;
    native.collectionBehavior = (native.collectionBehavior & ~NSWindowCollectionBehaviorIgnoresCycle) | NSWindowCollectionBehaviorParticipatesInCycle;
    native.hasShadow = YES;
    NSRect visible = NSScreen.mainScreen.visibleFrame;
    Layout(page);
    SetPageBounds(page, NSMakeRect(NSMaxX(visible) - 540, NSMaxY(visible) - 420, 520, 390));
    Layout(page); page.window->Show();
  } else {
    native.level = NSNormalWindowLevel; native.hasShadow = NO; AavaChromeSync(id);
  }
}

void AavaChromeURL(const std::string& id, const std::string& url) {
  auto it = pages.find(id); if (it == pages.end()) return;
  it->second.reveal.URLString = [NSString stringWithUTF8String:url.c_str()];
}

void AavaChromeLock(const std::string& id, bool locked) {
  auto it=pages.find(id); if(it==pages.end()) return;
  it->second.locked=locked;
  if(locked) { it->second.floating=false; Native(it->second.window).level=NSNormalWindowLevel; }
  AavaChromeSync(id);
}
