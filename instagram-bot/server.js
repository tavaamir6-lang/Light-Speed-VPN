import express from 'express';

const app = express();
app.use(express.json({ limit: '1mb' }));

const PORT = process.env.PORT || 3000;
const VERIFY_TOKEN = process.env.META_VERIFY_TOKEN;
const ACCESS_TOKEN = process.env.INSTAGRAM_ACCESS_TOKEN;
const GRAPH_API_VERSION = process.env.GRAPH_API_VERSION || 'v24.0';
const KEYWORD = (process.env.COMMENT_KEYWORD || 'کانفیگ').trim().toLowerCase();
const REPLY_TEXT = process.env.REPLY_TEXT || 'سلام 👋 برای دریافت اطلاعات بیشتر لطفاً دایرکتت رو چک کن.';

app.get('/', (_req, res) => res.status(200).send('Instagram webhook server is running.'));

// Meta webhook verification
app.get('/webhook', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  if (mode === 'subscribe' && token === VERIFY_TOKEN) {
    return res.status(200).send(challenge);
  }
  return res.sendStatus(403);
});

app.post('/webhook', async (req, res) => {
  // Acknowledge Meta quickly; process the event after responding.
  res.sendStatus(200);

  try {
    const body = req.body;
    if (body?.object !== 'instagram') return;

    for (const entry of body.entry ?? []) {
      for (const change of entry.changes ?? []) {
        if (change.field !== 'comments') continue;

        const value = change.value ?? {};
        const commentId = value.id;
        const text = String(value.text ?? '').trim();
        if (!commentId || !text) continue;

        const normalized = text.toLowerCase();
        if (!normalized.includes(KEYWORD)) continue;

        // Prevent replying to the same comment twice when Meta retries a webhook.
        // For production, replace this in-memory Set with a database/Redis store.
        if (seenComments.has(commentId)) continue;
        seenComments.add(commentId);

        await sendPrivateReply(commentId, REPLY_TEXT);
        console.log(`Private reply sent for comment ${commentId}`);
      }
    }
  } catch (error) {
    console.error('Webhook processing error:', error);
  }
});

const seenComments = new Set();

async function sendPrivateReply(commentId, message) {
  if (!ACCESS_TOKEN) throw new Error('INSTAGRAM_ACCESS_TOKEN is not configured');

  const url = `https://graph.facebook.com/${GRAPH_API_VERSION}/${encodeURIComponent(commentId)}/replies`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message, access_token: ACCESS_TOKEN })
  });

  const data = await response.json();
  if (!response.ok) throw new Error(JSON.stringify(data));
  return data;
}

app.listen(PORT, () => {
  console.log(`Instagram webhook server listening on port ${PORT}`);
});
