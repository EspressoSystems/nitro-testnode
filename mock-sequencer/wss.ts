import { LOCAL_WS_PORT, REMOTE_WS_URL } from './consts'
import WebSocket, { Server as WebSocketServer } from 'ws';

export class MockSequencer {
    constructor() {
        this.wss = new WebSocketServer({ port: LOCAL_WS_PORT });
        this.wss.on('connection', (ws) => {
            this.clients.add(ws);
            ws.on('close', () => {
                this.clients.delete(ws);
            });
        });

        this.connectRemoteWs();
    }

    public getCurrentCount() {
        return this.count;
    }

    public setSkipNext(skip: boolean) {
        this.skipNext = skip;
    }

    public setSendInRandom(send: boolean) {
        this.sendInRandom = send;
    }

    public setSendOversized(send: boolean) {
        this.sendOversized = send;
    }

    private processAndBroadcast(data: WebSocket.Data) {
        this.count++;
        if (this.skipNext) {
            this.skipNext = false;
            return;
        }
        if (this.sendInRandom) {
            if (this.buffer.length < this.bufferSize) {
                this.buffer.push(data);
            } else {
                this.buffer.sort((_a, _b) => {
                    return Math.random() - 0.5;
                });
                this.buffer.forEach((d) => {
                    this.broadcastToClients(d);
                });
                this.buffer = []
            }
            this.sendInRandom = false;
            return
        }

        if (this.sendOversized) {
            // todo
            return
        }
        this.broadcastToClients(data);
    }

    private connectRemoteWs() {
        this.remoteWs = new WebSocket(REMOTE_WS_URL);

        this.remoteWs.on('open', () => {
            console.log('Connected to remote WebSocket server:', REMOTE_WS_URL);
        });

        this.remoteWs.on('message', (data) => {
            this.processAndBroadcast(data);
        });

        this.remoteWs.on('close', () => {
            console.log('Remote WebSocket closed, reconnecting in 1s...');
            setTimeout(this.connectRemoteWs, 1000);
        });

        this.remoteWs.on('error', (err) => {
            console.error('Remote WebSocket error:', err);
        });
    }

    private broadcastToClients(data: WebSocket.Data) {
        for (const client of this.clients) {
            if (client.readyState === WebSocket.OPEN) {
                client.send(data);
            }
        }
    }

    // Only after bufferSize messages are received, will the messages be broadcasted
    private buffer: WebSocket.Data[] = [];
    private bufferSize = 20;

    private clients: Set<WebSocket> = new Set();
    private wss: WebSocketServer;
    private remoteWs!: WebSocket;
    private count = 0;

    private skipNext = false
    private sendInRandom = false
    private sendOversized = false
}
