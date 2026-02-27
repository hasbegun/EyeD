# ---- Stage 1: Build Flutter web ----
FROM ghcr.io/cirruslabs/flutter:3.38.3 AS build

WORKDIR /app

# Copy pubspec first for dependency caching
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

# Copy source and build
COPY . .
RUN dart run build_runner build --delete-conflicting-outputs
RUN flutter build web --release --dart-define=API_MODE=proxy

# ---- Stage 2: Serve with nginx ----
FROM nginx:stable-alpine

RUN rm /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/conf.d/eyed.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD wget -qO- http://localhost:80/ || exit 1
