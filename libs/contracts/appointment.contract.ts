import { z } from 'zod';

// Le schéma de validation partagé (Frontend & Backend)
export const AppointmentSchema = z.object({
  id: z.string().uuid(),
  patientId: z.string().uuid(),
  doctorId: z.string().uuid(),
  slot: z.date(),
  status: z.enum(['PENDING', 'CONFIRMED', 'CANCELLED']),
});

export type Appointment = z.infer<typeof AppointmentSchema>;

// L'événement Kafka que tout le monde doit comprendre
export const AppointmentCreatedEvent = z.object({
  appointmentId: z.string().uuid(),
  occurredAt: z.string().datetime(),
  version: z.number().int().default(1),
});
