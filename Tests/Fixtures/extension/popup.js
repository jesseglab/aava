document.querySelector('#check').addEventListener('click', async () => {
  try {
    const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
    const result = await chrome.scripting.executeScript({target: {tabId: tab.id}, func: () => ({title: document.title, url: location.href})});
    document.querySelector('#result').textContent = JSON.stringify(result[0].result, null, 2);
  } catch (error) { document.querySelector('#result').textContent = String(error); }
});
