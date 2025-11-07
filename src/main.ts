import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import * as dotenv from 'dotenv';

// Load environment variables from .env file
dotenv.config();

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Configure CORS from environment variables
  const corsOrigin = process.env.CORS_ORIGIN
    ? process.env.CORS_ORIGIN.split(',')
    : '*';
  const corsCredentials = process.env.CORS_CREDENTIALS === 'true';

  app.enableCors({
    origin: corsOrigin,
    credentials: corsCredentials,
  });

  console.log('CORS configured with origin:', corsOrigin);
  console.log('Environment:', process.env.NODE_ENV);
  console.log('MongoDB URI configured:', !!process.env.MONGODB_URI);

  // Health check endpoint with environment variables
  app.getHttpAdapter().get('/health', (req, res) => {
    // Mask sensitive values
    const maskSecret = (value: string) => {
      if (!value) return undefined;
      if (value.length <= 8) return '***';
      return value.substring(0, 4) + '***' + value.substring(value.length - 4);
    };

    res.status(200).json({
      status: 'ok',
      timestamp: new Date().toISOString(),
      environment: {
        NODE_ENV: process.env.NODE_ENV,
        PORT: process.env.PORT,
        MONGODB_URI: maskSecret(process.env.MONGODB_URI),
        MONGODB_DATABASE: process.env.MONGODB_DATABASE,
        MONGODB_USER: process.env.MONGODB_USER,
        MONGODB_PASSWORD: maskSecret(process.env.MONGODB_PASSWORD),
        CORS_ORIGIN: process.env.CORS_ORIGIN,
        CORS_CREDENTIALS: process.env.CORS_CREDENTIALS,
        JWT_SECRET: maskSecret(process.env.JWT_SECRET),
        JWT_EXPIRATION: process.env.JWT_EXPIRATION,
      },
    });
  });

  const port = process.env.PORT || 3000;
  await app.listen(port, '0.0.0.0');
  console.log(`Application is running on: ${await app.getUrl()}`);
}

bootstrap();
