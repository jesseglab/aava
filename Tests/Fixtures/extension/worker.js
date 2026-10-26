chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message.type !== 'aava-probe' || !sender.url?.startsWith('http://127.0.0.1:8769/')) return;
  chrome.storage.local.get({visits: 0}).then(async ({visits}) => {
    await chrome.storage.local.set({visits: visits + 1});
    reply({worker: true, visits: visits + 1, tabId: sender.tab?.id});
  });
  return true;
});
