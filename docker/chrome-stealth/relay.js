// Expose Chrome's DevTools port to the compose network.
// A windowed Chrome only listens on loopback, and it refuses any request whose
// Host is not an IP or localhost ("chrome-stealth:9222" is neither), so this
// relays TCP and rewrites the Host of each connection's first request: crw
// makes one request per connection (the /json/version lookup, then the
// WebSocket upgrade).
const net = require('net');

const [listenPort, chromePort] = process.argv.slice(2).map(Number);
const HEAD_END = '\r\n\r\n';
const MAX_HEAD = 64 * 1024;

net
  .createServer((client) => {
    const chrome = net.connect(chromePort, '127.0.0.1');
    const close = () => {
      client.destroy();
      chrome.destroy();
    };
    client.on('error', close);
    chrome.on('error', close);

    let head = '';
    const onHead = (chunk) => {
      head += chunk.toString('latin1');
      const end = head.indexOf(HEAD_END);
      if (end === -1) {
        if (head.length > MAX_HEAD) close();
        return;
      }
      client.off('data', onHead);
      const rewritten = head.slice(0, end).replace(/\r\nHost:[^\r]*/i, `\r\nHost: localhost:${chromePort}`);
      chrome.write(Buffer.from(rewritten + head.slice(end), 'latin1'));
      client.pipe(chrome);
    };
    client.on('data', onHead);
    chrome.pipe(client);
  })
  .listen(listenPort, '0.0.0.0');
