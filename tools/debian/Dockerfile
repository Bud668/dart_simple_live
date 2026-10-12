FROM debian:13-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git curl unzip xz-utils ca-certificates python3 libgtk-3-0 wine64 && rm -rf /var/lib/apt/lists/*
ENV PUB_CACHE=/workspace/pub-cache FLUTTER_SUPPRESS_ANALYTICS=true CI=true WINEDEBUG=-all WINEPREFIX=/workspace/wine-prefix WINEARCH=win64
WORKDIR /workspace
RUN apt-get update && apt-get install -y --no-install-recommends clang && rm -rf /var/lib/apt/lists/*
