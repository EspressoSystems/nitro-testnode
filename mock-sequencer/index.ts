import { MockSequencer } from './wss'
import express from 'express'
import { HTTP_PORT } from './consts'

const sequencer = new MockSequencer()

const app = express()
app.use(express.json())

app.get('/skip-next', (_req, res) => {
  const count = sequencer.getCurrentCount()
  sequencer.setSkipNext()
  res.json(count)
})

app.get('/send-in-random', (_req, res) => {
  const count = sequencer.getCurrentCount()
  sequencer.setSendInRandom()
  res.json(count)
})

app.get('/send-oversized', (_req, res) => {
  const count = sequencer.getCurrentCount()
  sequencer.setSendOversized()
  res.json(count)
})

app.get('/block-number', (_req, res) => {
  const count = sequencer.getCurrentCount()
  res.json(count)
})

app.get('/reset', (_req, res) => {
  sequencer.reset()
  res.json(sequencer.getCurrentCount())
})

app.listen(HTTP_PORT, () => {
  console.log(`MockSequencer HTTP server listening on http://localhost:${HTTP_PORT}`)
})
