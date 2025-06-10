import { MockSequencer } from './wss';
import express from 'express';

const sequencer = new MockSequencer()

const app = express();
app.use(express.json());

app.get('/skip-next', (req, res) => {
  const count = sequencer.getCurrentCount()
  sequencer.setSkipNext(true)
  res.json({ count });
});

app.get('/send-in-random', (req, res) => {
  const count = sequencer.getCurrentCount()
  sequencer.setSendInRandom(true)
  res.json({ count });
});

app.get('/send-oversized', (req, res) => {
  const count = sequencer.getCurrentCount()
  sequencer.setSendOversized(true)
  res.json({ count });
});
