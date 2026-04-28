import express from 'express';

const app = express();
const port = process.env.PORT || 3001;
const cellId = process.env.CELL_ID || 'unknown';

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    cellId: cellId,
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

app.get('/ready', (req, res) => {
  res.json({ status: 'ready', cellId: cellId });
});

app.post('/appointments', (req, res) => {
  res.json({
    id: `apt-${Date.now()}`,
    ...req.body,
    cellId: cellId,
    createdAt: new Date().toISOString()
  });
});

app.listen(port, () => {
  console.log(`🚀 Appointment service (${cellId}) running on port ${port}`);
});
