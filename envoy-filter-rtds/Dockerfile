FROM envoyproxy/envoy-build-ubuntu:0ca52447572ee105a4730da5e76fe47c9c5a7c64 AS build

# Create non-root user for building
RUN useradd -m -u 1000 envoyuser && \
    chown -R envoyuser:envoyuser /tmp

USER envoyuser
WORKDIR /home/envoyuser/build

# Clone Envoy
RUN git clone https://github.com/envoyproxy/envoy.git && \
    cd envoy && \
    git checkout v1.28.0

WORKDIR /home/envoyuser/build/envoy

# Copy our custom filter
COPY --chown=envoyuser:envoyuser envoy-filter-rtds /home/envoyuser/build/envoy/source/extensions/filters/http/shuffle_shard

# Add our filter to extensions_build_config.bzl
RUN echo "    'envoy.filters.http.shuffle_shard': '//source/extensions/filters/http/shuffle_shard:config'," >> \
    source/extensions/extensions_build_config.bzl

# Build Envoy with our custom filter
RUN bazel build -c opt //source/exe:envoy-static --jobs=4

# Runtime stage
FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /home/envoyuser/build/envoy/bazel-bin/source/exe/envoy-static /usr/local/bin/envoy

RUN chmod +x /usr/local/bin/envoy

ENTRYPOINT ["/usr/local/bin/envoy"]
CMD ["-c", "/etc/envoy/envoy.yaml"]
