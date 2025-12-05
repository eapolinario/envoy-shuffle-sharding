#include "shuffle_shard_filter.h"

#include <algorithm>
#include <unordered_set>

#include "source/common/http/utility.h"

namespace Envoy {
namespace Extensions {
namespace HttpFilters {
namespace ShuffleShard {

ShuffleShardFilter::ShuffleShardFilter(Runtime::Loader& runtime) : runtime_(runtime) {}

uint64_t ShuffleShardFilter::djb2Hash(const std::string& str) {
  uint64_t hash = 5381;
  for (char c : str) {
    hash = ((hash << 5) + hash) + static_cast<uint8_t>(c);
  }
  return hash;
}

std::vector<uint32_t> ShuffleShardFilter::computeShuffleShard(
    const std::string& customer_id, uint32_t total_hosts, uint32_t shard_size) {
  
  std::vector<uint32_t> shard;
  std::unordered_set<uint32_t> seen;

  for (uint32_t i = 0; i < shard_size; i++) {
    std::string hash_input = customer_id + "_salt_" + std::to_string(i);
    uint64_t hash = djb2Hash(hash_input);
    uint32_t host_index = hash % total_hosts;

    uint32_t attempts = 0;
    while (seen.count(host_index) > 0 && attempts < total_hosts) {
      hash = (hash * 31 + attempts) % INT64_MAX;
      host_index = hash % total_hosts;
      attempts++;
    }

    if (seen.count(host_index) == 0) {
      shard.push_back(host_index);
      seen.insert(host_index);
    }
  }

  return shard;
}

uint32_t ShuffleShardFilter::selectHostFromShard(const std::vector<uint32_t>& shard,
                                                 const std::string& path) {
  if (shard.empty()) {
    return 0;
  }

  uint64_t path_hash = djb2Hash(path);
  uint32_t index = path_hash % shard.size();
  return shard[index];
}

Http::FilterHeadersStatus ShuffleShardFilter::decodeHeaders(Http::RequestHeaderMap& headers,
                                                            bool) {
  // Get customer ID from header
  auto customer_id_header = headers.get(Http::LowerCaseString("x-customer-id"));
  if (customer_id_header.empty()) {
    decoder_callbacks_->sendLocalReply(Http::Code::BadRequest, "Missing x-customer-id header",
                                      nullptr, absl::nullopt, "");
    return Http::FilterHeadersStatus::StopIteration;
  }

  std::string customer_id(customer_id_header[0]->value().getStringView());

  // Read runtime configuration with RTDS support
  uint32_t total_hosts = runtime_.snapshot().getInteger("shuffle_sharding.total_hosts", 8);
  
  // Try customer-specific shard size
  std::string customer_key = "shuffle_sharding.customer." + customer_id + ".shard_size";
  uint32_t shard_size = runtime_.snapshot().getInteger(customer_key, 0);
  
  // Fall back to default if customer-specific not found
  if (shard_size == 0) {
    shard_size = runtime_.snapshot().getInteger("shuffle_sharding.default_shard_size", 2);
  }

  // Ensure shard size doesn't exceed total hosts
  if (shard_size > total_hosts) {
    shard_size = total_hosts;
  }

  // Compute shuffle shard
  auto shard = computeShuffleShard(customer_id, total_hosts, shard_size);

  // Build shard list string for observability
  std::string shard_list;
  for (size_t i = 0; i < shard.size(); i++) {
    if (i > 0) shard_list += ",";
    shard_list += std::to_string(shard[i]);
  }

  // Add headers for observability
  headers.setCopy(Http::LowerCaseString("x-shard-assignment"), shard_list);
  
  std::string config_str = std::to_string(shard_size) + "/" + std::to_string(total_hosts);
  headers.setCopy(Http::LowerCaseString("x-shard-config"), config_str);

  // Select one host from shard based on path
  auto path = headers.getPathValue();
  uint32_t selected_host = selectHostFromShard(shard, std::string(path));

  // Set routing headers
  headers.setCopy(Http::LowerCaseString("x-target-host"), std::to_string(selected_host));
  
  std::string cluster_name = "backend_" + std::to_string(selected_host);
  headers.setCopy(Http::LowerCaseString("x-target-cluster"), cluster_name);

  ENVOY_LOG(info, "Customer {} -> Config {}/{} -> Shard [{}] -> Host {}",
            customer_id, shard_size, total_hosts, shard_list, selected_host);

  return Http::FilterHeadersStatus::Continue;
}

Http::FilterDataStatus ShuffleShardFilter::decodeData(Buffer::Instance&, bool) {
  return Http::FilterDataStatus::Continue;
}

Http::FilterTrailersStatus ShuffleShardFilter::decodeTrailers(Http::RequestTrailerMap&) {
  return Http::FilterTrailersStatus::Continue;
}

void ShuffleShardFilter::setDecoderFilterCallbacks(
    Http::StreamDecoderFilterCallbacks& callbacks) {
  decoder_callbacks_ = &callbacks;
}

Http::Filter1xxHeadersStatus ShuffleShardFilter::encode1xxHeaders(Http::ResponseHeaderMap&) {
  return Http::Filter1xxHeadersStatus::Continue;
}

Http::FilterHeadersStatus ShuffleShardFilter::encodeHeaders(Http::ResponseHeaderMap&, bool) {
  return Http::FilterHeadersStatus::Continue;
}

Http::FilterDataStatus ShuffleShardFilter::encodeData(Buffer::Instance&, bool) {
  return Http::FilterDataStatus::Continue;
}

Http::FilterTrailersStatus ShuffleShardFilter::encodeTrailers(Http::ResponseTrailerMap&) {
  return Http::FilterTrailersStatus::Continue;
}

Http::FilterMetadataStatus ShuffleShardFilter::encodeMetadata(Http::MetadataMap&) {
  return Http::FilterMetadataStatus::Continue;
}

void ShuffleShardFilter::setEncoderFilterCallbacks(
    Http::StreamEncoderFilterCallbacks& callbacks) {
  encoder_callbacks_ = &callbacks;
}

} // namespace ShuffleShard
} // namespace HttpFilters
} // namespace Extensions
} // namespace Envoy
