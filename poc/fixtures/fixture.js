// Generic fixture HTTP server for Linux Preview test scenarios.
// Listens on FIXTURE_PORT (default 3000). What the application under test
// is expected to recognize is the process command line, not this file.
const http = require('http');
const port = Number(process.env.FIXTURE_PORT) || 3000;
http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('Linux Preview fixture\n');
}).listen(port, '0.0.0.0', () => console.log('fixture listening on', port));
