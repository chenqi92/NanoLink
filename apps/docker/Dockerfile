# Build stage - Web UI
FROM node:20-alpine AS web-builder

WORKDIR /app/web
COPY apps/server/web/package*.json ./
RUN npm ci

COPY apps/server/web/ ./
RUN npm run build

# Build stage - Go server
FROM golang:1.24-alpine AS go-builder

RUN apk add --no-cache gcc musl-dev protoc

# Install Go protobuf plugins
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest && \
  go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

WORKDIR /app
COPY apps/server/go.mod apps/server/go.sum ./
RUN go mod download

COPY apps/server/ ./
COPY sdk/protocol/nanolink.proto ./sdk/protocol/
COPY --from=web-builder /app/web/dist ./web/dist

# Generate proto code from the updated .proto file
RUN mkdir -p internal/proto && \
  protoc --proto_path=./sdk/protocol \
  --go_out=./internal/proto --go_opt=paths=source_relative \
  --go-grpc_out=./internal/proto --go-grpc_opt=paths=source_relative \
  ./sdk/protocol/nanolink.proto

RUN go mod tidy
RUN CGO_ENABLED=1 GOOS=linux go build -ldflags="-s -w" -o nanolink-server ./cmd

# Final stage
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=go-builder /app/nanolink-server .
COPY --from=go-builder /app/web/dist ./web/dist

# Create data directory
RUN mkdir -p /app/data

# Non-root user
RUN adduser -D -u 1000 nanolink
RUN chown -R nanolink:nanolink /app
USER nanolink

EXPOSE 8080 9100 9200

VOLUME ["/app/data"]

ENV NANOLINK_SERVER_HTTP_PORT=8080 \
  NANOLINK_SERVER_WS_PORT=9100 \
  NANOLINK_SERVER_GRPC_PORT=9200 \
  NANOLINK_STORAGE_PATH=/app/data/nanolink.db \
  NANOLINK_DATABASE_TYPE=sqlite \
  NANOLINK_DATABASE_PATH=/app/data/nanolink.db \
  NANOLINK_ADMIN_USERNAME="" \
  NANOLINK_ADMIN_PASSWORD="" \
  NANOLINK_JWT_SECRET="" \
  NANOLINK_JWT_EXPIRE_HOUR=24

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/api/health || exit 1

ENTRYPOINT ["/app/nanolink-server"]
