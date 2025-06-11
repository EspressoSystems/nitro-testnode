import { MockSequencer } from './wss';
import express from 'express';
import {HTTP_PORT} from './consts';

const sequencer = new MockSequencer()

const app = express();
app.use(express.json());

app.get('/skip-next', (req, res) => {
  const count = sequencer.getCurrentCount()
  sequencer.setSkipNext(true)
  res.json(count);
});

app.get('/send-in-random', (req, res) => {
  const count = sequencer.getCurrentCount()
  sequencer.setSendInRandom(true)
  res.json(count);
});

app.get('/send-oversized', (req, res) => {
  const count = sequencer.getCurrentCount()
  sequencer.setSendOversized(true)
  res.json(count);
});

app.get('/current-count', (req, res) => {
  const count = sequencer.getCurrentCount()
  res.json(count);
});

app.listen(HTTP_PORT, () => {
  console.log(`MockSequencer HTTP server listening on http://localhost:${HTTP_PORT}`);
});
