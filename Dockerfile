FROM node:22-alpine AS build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 AS adapter

FROM node:22-alpine

WORKDIR /app

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=4321
ENV AWS_LWA_PORT=4321
ENV AWS_LWA_READINESS_CHECK_PATH=/
ENV AWS_LWA_READINESS_CHECK_TIMEOUT=30000
ENV NODE_OPTIONS=--max-old-space-size=768

COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter

COPY --from=build /app/package.json /app/package-lock.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist

EXPOSE 4321

CMD ["node", "./dist/server/entry.mjs"]
