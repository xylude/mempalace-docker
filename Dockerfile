FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Pin chromadb to a known-good version — newer versions have broken installs
RUN pip install --no-cache-dir "chromadb==0.6.3"
RUN pip install --no-cache-dir mempalace

# supergateway wraps the stdio MCP server over HTTP/SSE
RUN npm install -g supergateway

VOLUME ["/root/.mempalace"]

EXPOSE 8000

# streamableHttp (recommended) — connect with: claude mcp add ... --transport http http://<host>:8000/mcp
CMD ["supergateway", "--stdio", "python -m mempalace.mcp_server", "--port", "8000", "--outputTransport", "streamableHttp", "--stateful"]

# SSE alternative — connect with: claude mcp add ... --transport sse http://<host>:8000/sse
# CMD ["supergateway", "--stdio", "python -m mempalace.mcp_server", "--port", "8000", "--outputTransport", "sse"]
