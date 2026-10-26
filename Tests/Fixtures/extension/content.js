chrome.runtime.sendMessage({type: 'aava-probe'}, result => {
  const status = document.createElement('p');
  status.id = 'extension-result';
  status.textContent = chrome.runtime.lastError ? 'Extension messaging failed: ' + chrome.runtime.lastError.message : `Extension content script + worker + storage passed. Visits: ${result.visits}; tab: ${result.tabId}`;
  status.style.cssText = 'border:2px solid #39775b;padding:16px;background:#d5f6de;color:#183c2d';
  document.body.prepend(status);
});
