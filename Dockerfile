# Use ARM-compatible base image for building
FROM arm32v7/python:3.11-slim-bookworm AS builder

# Argument definitions for rebuilding dependencies
ARG REBUILD_HNSWLIB
ARG PROTOBUF_VERSION=28.2

# Install build tools and dependencies for compiling Protobuf and other libraries
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

# Install Protobuf compiler from source
RUN apt-get update && apt-get install -y autoconf automake libtool curl make g++ unzip git && \
    git clone https://github.com/protocolbuffers/protobuf.git && \
    cd protobuf && \
    git checkout v${PROTOBUF_VERSION} && \
    git submodule update --init --recursive && \
    ./autogen.sh && ./configure && make && make install && ldconfig && \
    protoc --version  # Verify installed version

# Set working directory to install dependencies
WORKDIR /install

# Copy requirements file and install Python dependencies
COPY ./requirements.txt requirements.txt

# Use pip cache for installing dependencies efficiently
RUN --mount=type=cache,target=/root/.cache/pip pip install --upgrade --prefix="/install" -r requirements.txt

# Optionally rebuild chroma-hnswlib if requested
RUN --mount=type=cache,target=/root/.cache/pip if [ "$REBUILD_HNSWLIB" = "true" ]; then pip install --no-binary :all: --force-reinstall --prefix="/install" chroma-hnswlib; fi

# Install gRPC tools for Python
RUN pip install grpcio==1.58.0 grpcio-tools==1.58.0

# Copy source files for Protobuf generation
COPY ./ /chroma

# Generate Protobufs (for Python)
WORKDIR /chroma
RUN make -C idl proto_python

# Final runtime image
FROM arm32v7/python:3.11-slim-bookworm AS final

# Create working directory for the app
RUN mkdir /chroma
WORKDIR /chroma

# Copy entrypoint script and make it executable
COPY ./bin/docker_entrypoint.sh /docker_entrypoint.sh

# Install necessary runtime dependencies and clean up apt cache
RUN apt-get update --fix-missing && apt-get install -y curl && \
    chmod +x /docker_entrypoint.sh && \
    rm -rf /var/lib/apt/lists/*

# Copy over installed dependencies and generated Protobufs
COPY --from=builder /install /usr/local
COPY --from=builder /chroma /chroma

# Set environment variables
ENV CHROMA_HOST_ADDR="0.0.0.0"
ENV CHROMA_HOST_PORT=8000
ENV CHROMA_WORKERS=1
ENV CHROMA_LOG_CONFIG="chromadb/log_config.yml"
ENV CHROMA_TIMEOUT_KEEP_ALIVE=30

# Expose the required port
EXPOSE 8000

# Set the entrypoint and command to run the application
ENTRYPOINT ["/docker_entrypoint.sh"]
CMD ["--workers ${CHROMA_WORKERS} --host ${CHROMA_HOST_ADDR} --port ${CHROMA_HOST_PORT} --proxy-headers --log-config ${CHROMA_LOG_CONFIG} --timeout-keep-alive ${CHROMA_TIMEOUT_KEEP_ALIVE}"]
