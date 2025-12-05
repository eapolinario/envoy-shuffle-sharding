#pragma once

#include "envoy/http/filter.h"
#include "envoy/runtime/runtime.h"
#include "source/common/common/logger.h"

namespace Envoy {
namespace Extensions {
namespace HttpFilters {
namespace ShuffleShard {

class ShuffleShardFilterConfig {
public:
  ShuffleShardFilterConfig() = default;
};

class ShuffleShardFilter : public Http::StreamFilter,
                           public Logger::Loggable<Logger::Id::filter> {
public:
  ShuffleShardFilter(Runtime::Loader& runtime);

  // Http::StreamFilterBase
  void onDestroy() override {}

  // Http::StreamDecoderFilter
  Http::FilterHeadersStatus decodeHeaders(Http::RequestHeaderMap& headers,
                                          bool end_stream) override;
  Http::FilterDataStatus decodeData(Buffer::Instance& data, bool end_stream) override;
  Http::FilterTrailersStatus decodeTrailers(Http::RequestTrailerMap& trailers) override;
  void setDecoderFilterCallbacks(Http::StreamDecoderFilterCallbacks& callbacks) override;

  // Http::StreamEncoderFilter
  Http::Filter1xxHeadersStatus encode1xxHeaders(Http::ResponseHeaderMap&) override;
  Http::FilterHeadersStatus encodeHeaders(Http::ResponseHeaderMap& headers,
                                          bool end_stream) override;
  Http::FilterDataStatus encodeData(Buffer::Instance& data, bool end_stream) override;
  Http::FilterTrailersStatus encodeTrailers(Http::ResponseTrailerMap& trailers) override;
  Http::FilterMetadataStatus encodeMetadata(Http::MetadataMap&) override;
  void setEncoderFilterCallbacks(Http::StreamEncoderFilterCallbacks& callbacks) override;

private:
  std::vector<uint32_t> computeShuffleShard(const std::string& customer_id,
                                            uint32_t total_hosts,
                                            uint32_t shard_size);
  uint32_t selectHostFromShard(const std::vector<uint32_t>& shard,
                               const std::string& path);
  uint64_t djb2Hash(const std::string& str);

  Runtime::Loader& runtime_;
  Http::StreamDecoderFilterCallbacks* decoder_callbacks_{};
  Http::StreamEncoderFilterCallbacks* encoder_callbacks_{};
};

} // namespace ShuffleShard
} // namespace HttpFilters
} // namespace Extensions
} // namespace Envoy
