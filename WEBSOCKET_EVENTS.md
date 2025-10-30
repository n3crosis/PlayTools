# WebSocket Events

PlayTools includes a WebSocket client that connects to a server at `ws://localhost:8088` to receive touch events for simulating multi-touch input.

The WebSocket messages should be JSON objects with the following format:

```json
{
  "id": 1,
  "phase": "began",
  "x": 0.5,
  "y": 0.3
}
```

- `id`: A unique integer identifier for the touch point.
- `phase`: The touch phase, one of `"began"`, `"moved"`, `"ended"`, `"cancelled"`.
- `x`: The x-coordinate as a percentage of screen width (0.0 to 1.0).
- `y`: The y-coordinate as a percentage of screen height (0.0 to 1.0).

The client will simulate the touches using the existing touch simulation infrastructure.

## Node.js Server Example

Here's a simple Node.js server using the `ws` library to send touch events:

```javascript
const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 8088 });

wss.on('connection', function connection(ws) {
  console.log('Client connected');

  // Example: Send a touch began event
  ws.send(JSON.stringify({
    id: 1,
    phase: 'began',
    x: 0.5,
    y: 0.3
  }));

  // Simulate moving the touch
  setTimeout(() => {
    ws.send(JSON.stringify({
      id: 1,
      phase: 'moved',
      x: 0.6,
      y: 0.4
    }));
  }, 100);

  // End the touch
  setTimeout(() => {
    ws.send(JSON.stringify({
      id: 1,
      phase: 'ended',
      x: 0.6,
      y: 0.4
    }));
  }, 200);

  ws.on('close', () => {
    console.log('Client disconnected');
  });
});

console.log('WebSocket server running on ws://localhost:8088');
```

Install the `ws` library with `npm install ws` and run the server with `node server.js`.
