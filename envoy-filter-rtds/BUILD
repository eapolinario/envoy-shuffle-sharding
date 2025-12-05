load(
    "@envoy//bazel:envoy_build_system.bzl",
    "envoy_cc_extension",
    "envoy_cc_library",
    "envoy_extension_package",
)

licenses(["notice"])  # Apache 2

envoy_extension_package()

envoy_cc_library(
    name = "shuffle_shard_filter_lib",
    srcs = ["shuffle_shard_filter.cc"],
    hdrs = ["shuffle_shard_filter.h"],
    repository = "@envoy",
    deps = [
        "@envoy//envoy/http:filter_interface",
        "@envoy//envoy/runtime:runtime_interface",
        "@envoy//source/common/common:logger_lib",
        "@envoy//source/common/http:utility_lib",
    ],
)

envoy_cc_extension(
    name = "config",
    srcs = ["shuffle_shard_config.cc"],
    repository = "@envoy",
    deps = [
        ":shuffle_shard_filter_lib",
        "@envoy//envoy/registry",
        "@envoy//envoy/server:filter_config_interface",
    ],
)
