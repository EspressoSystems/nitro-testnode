import { LOCAL_WS_PORT, REMOTE_WS_URL } from './consts'
import { BroadcastMessage, SequencerMessage } from './types'
import WebSocket, { Server as WebSocketServer } from 'ws'

export class MockSequencer {
    constructor() {
        this.wss = new WebSocketServer({ port: LOCAL_WS_PORT });
        this.wss.on('connection', (ws) => {
            this.clients.add(ws)
            this.connectRemoteWs()
            console.log('Client connected', this.clients.size)
            ws.on('close', () => {
                this.clients.delete(ws)
            })
        })
        this.wss.on('message', (data) => {
            console.log('receive message:', data)
            if (this.remoteWs) {
                this.remoteWs.send(data)
            }
        })

    }

    public getCurrentCount() {
        return this.blockNumber
    }

    public setSkipNext() {
        console.log('setting next block to be skipped', this.getCurrentCount() + 1)
        this.skipNext = this.getCurrentCount() + 1
    }

    public setSendInRandom() {
        this.sendInRandom = true
    }

    public setSendOversized() {
        console.log('setting next block to be oversized', this.getCurrentCount() + 1)
        this.sendOversized = this.getCurrentCount() + 1
    }

    public setSendInvalidDelayedMessages() {
        console.log('setting next block to be invalid delayed messages', this.getCurrentCount() + 1)
        this.sendInvalidDelayedMessages = true
    }

    public reset() {
        this.skipNext = 0
        this.sendInRandom = false
        this.sendOversized = 0
        this.sendInvalidDelayedMessages = false
    }

    private processAndBroadcast(data: WebSocket.Data) {
        const str = typeof data === 'string' ? data : data.toString();
        const messages = JSON.parse(str) as BroadcastMessage;
        if (!messages.messages) {
            return this.broadcastToClients(data)
        }
        const newMessages: SequencerMessage[] = []
        let intercept = false
        messages.messages.forEach((message) => {
            const blockNumber = message.sequenceNumber
            const delayedCount = message.message.delayedMessagesRead
            this.blockNumberToDelayedCount.set(blockNumber, delayedCount)

            if (blockNumber == this.skipNext) {
                console.log('Skipping block', blockNumber)
                intercept = true
                return
            }
            if (blockNumber == this.sendOversized) {
                intercept = true
                const overSized = '0'.repeat(10000000)
                const l2MsgBytes = new TextEncoder().encode(overSized)
                console.log("oversized message length:", l2MsgBytes.length)
                message.message.message.l2Msg = overSized
            }

            if (this.sendInvalidDelayedMessages) {
                const previousDelayedCount = this.blockNumberToDelayedCount.get(blockNumber - 1)
                if (previousDelayedCount === undefined) {
                    // we don't know if this is a delayed message, will skip it first
                    return
                }
                if (previousDelayedCount + 1 === delayedCount) {
                    console.log('tampering delayed messages', delayedCount)
                    message.message.message.l2Msg = ''
                    intercept = true
                }
            }

            if (blockNumber > this.blockNumber) {
                this.blockNumber = blockNumber
            }
            newMessages.push(message)
        })

        if (!this.skipNext &&
            !this.sendOversized &&
            !this.sendInvalidDelayedMessages) {
            return this.broadcastToClients(data)
        }
        if (intercept) {
            console.log('Intercepting block', newMessages, this.skipNext)
            data = JSON.stringify({ version: 1, messages: newMessages })
        } else if (this.sendInRandom) {
            if (this.buffer.length < this.bufferSize) {
                this.buffer.push(data)
            } else {
                this.buffer.sort((_a, _b) => {
                    return Math.random() - 0.5
                })
                this.buffer.forEach((d) => {
                    this.broadcastToClients(d)
                })
                this.buffer = []
            }
            this.sendInRandom = false
            return
        }
        this.broadcastToClients(data)
    }

    private connectRemoteWs() {
        this.remoteWs = new WebSocket(REMOTE_WS_URL)

        this.remoteWs.on('open', () => {
            console.log('Connected to remote WebSocket server:', REMOTE_WS_URL)
        })

        this.remoteWs.on('message', (data) => {
            this.processAndBroadcast(data)
        })

        this.remoteWs.on('close', () => {
            console.log('Remote WebSocket closed, reconnecting in 1s...')
            setTimeout(this.connectRemoteWs, 1000)
        })

        this.remoteWs.on('error', (err) => {
            console.error('Remote WebSocket error:', err)
        })

    }

    private broadcastToClients(data: WebSocket.Data) {
        for (const client of this.clients) {
            if (client.readyState === WebSocket.OPEN) {
                client.send(data)
            }
        }
    }

    // Only after bufferSize messages are received, will the messages be broadcasted
    private buffer: WebSocket.Data[] = []
    private bufferSize = 20

    private clients: Set<WebSocket> = new Set()
    private wss: WebSocketServer
    private remoteWs!: WebSocket
    private blockNumber = 0
    private blockNumberToDelayedCount = new Map<number, number>([[0, 1]])

    private skipNext: number | null = null
    private sendInRandom = false
    private sendOversized: number | null = null
    private sendInvalidDelayedMessages = false
}
