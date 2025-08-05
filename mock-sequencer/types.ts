export interface BroadcastMessage {
    version: number
    messages?: SequencerMessage[]
}

export interface SequencerMessage {
    sequenceNumber: number
    message: SequencerMessageDetail
    blockHash: string
    signature: string | null
}

export interface SequencerMessageDetail {
    message: L2Message
    delayedMessagesRead: number
}

export interface L2Message {
    header: L1IncomingMessageHeader
    l2Msg: string
}

export interface L1IncomingMessageHeader {
    kind: number
    sender: string
    blockNumber: number
    timestamp: number
    requestId: string | null
    baseFeeL1: string | null
}
