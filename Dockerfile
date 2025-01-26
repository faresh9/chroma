# Use ARM-compatible base image
FROM arm32v7/python:3.11-slim-bookworm AS builder
ARG REBUILD_HNSWLIB
ARG PROTOBUF_VERSION=28.2

# Install necessary build tools and dependencies
RUN apt-get update --fix-missing && apt-get install -y --fix-missing \
    build-essential \
    gcc \
    g++ \
    cmake \
    autoconf \
    python3-dev \
    unzip \
    curl \
    make && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir /install

# Install specific Protobuf compiler for ARM (use source build if precompiled not available)
RUN apt-get update && apt-get install -y autoconf automake libtool curl make g++ unzip git && \
    git clone https://github.com/protocolbuffers/protobuf.git && \
    cd protobuf && git checkout v${PROTOBUF_VERSION} && \
    git submodule update --init --recursive && \
    ./autogen.sh && ./configure && make && make install && ldconfig && \
    protoc --version  # Verify installed version

WORKDIR /install

COPY ./requirements.txt requirements.txt

# Install Python dependencies
RUN --mount=type=cache,target=/root/.cache/pip pip install --upgrade --prefix="/install" -r requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip if [ "$REBUILD_HNSWLIB" = "true" ]; then pip install --no-binary :all: --force-reinstall --prefix="/install" chroma-hnswlib; fi

# Install gRPC tools for Python with fixed version
RUN pip install grpcio==1.58.0 grpcio-tools==1.58.0

# Copy source files to build Protobufs
COPY ./ /chroma

# Generate Protobufs
WORKDIR /chroma
RUN make -C idl proto_python

FROM arm32v7/python:3.11-slim-bookworm AS final

# Create working directory
RUN mkdir /chroma
WORKDIR /chroma

# Copy entrypoint
COPY ./bin/docker_entrypoint.sh /docker_entrypoint.sh

RUN apt-get update --fix-missing && apt-get install -y curl && \
    chmod +x /docker_entrypoint.sh && \
    rm -rf /var/lib/apt/lists/*

# Copy built dependencies and generated Protobufs
COPY --from=builder /install /usr/local
COPY --from=builder /chroma /chroma

ENV CHROMA_HOST_ADDR="0.0.0.0"
ENV CHROMA_HOST_PORT=8000
ENV CHROMA_WORKERS=1
ENV CHROMA_LOG_CONFIG="chromadb/log_config.yml"
ENV CHROMA_TIMEOUT_KEEP_ALIVE=30

EXPOSE 8000

ENTRYPOINT ["/docker_entrypoint.sh"]
CMD [ "--workers ${CHROMA_WORKERS} --host ${CHROMA_HOST_ADDR} --port ${CHROMA_HOST_PORT} --proxy-headers --log-config ${CHROMA_LOG_CONFIG} --timeout-keep-alive ${CHROMA_TIMEOUT_KEEP_ALIVE}"]
