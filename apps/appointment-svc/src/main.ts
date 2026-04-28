import express from 'express';

const app = express();
const port = process.env.PORT || 3001;
const cellId = process.env.CELL_ID || 'unknown';

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Health check endpoint
app.get('/health', (req: express.Request, res: express.Response) => {
  res.status(200).json({
    status: 'healthy',
    cellId: cellId,
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Readiness probe
app.get('/ready', (req: express.Request, res: express.Response) => {
  res.status(200).json({ 
    status: 'ready', 
    cellId: cellId 
  });
});

// Create appointment
app.post('/appointments', (req: express.Request, res: express.Response) => {
  const appointment = {
    id: `apt-${Date.now()}`,
    ...req.body,
    cellId: cellId,
    createdAt: new Date().toISOString()
  };
  
  res.status(201).json(appointment);
});

// Get appointment by ID
app.get('/appointments/:id', (req: express.Request, res: express.Response) => {
  res.status(200).json({
    id: req.params.id,
    cellId: cellId,
    message: 'Appointment details'
  });
});

// Start server
app.listen(port, () => {
  console.log(`🚀 Appointment service (${cellId}) running on port ${port}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  process.exit(0);
});
