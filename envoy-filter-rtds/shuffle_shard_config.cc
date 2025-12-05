#include "shuffle_shard_filter.h"

#include "envoy/registry/registry.h"
#include "envoy/server/filter_config.h"

namespace Envoy {
namespace Extensions {
namespace HttpFilters {
namespace ShuffleShard {

class ShuffleShardFilterFactory
    : public Server::Configuration::NamedHttpFilterConfigFactory {
public:
  Http::FilterFactoryCb
  createFilterFactoryFromProto(const Protobuf::Message&, const std::string&,
                               Server::Configuration::FactoryContext& context) override {
    return [&context](Http::FilterChainFactoryCallbacks& callbacks) -> void {
      callbacks.addStreamFilter(
          std::make_shared<ShuffleShardFilter>(context.serverFactoryContext().runtime()));
    };
  }

  ProtobufTypes::MessagePtr createEmptyConfigProto() override {
    return ProtobufTypes::MessagePtr{new Envoy::ProtobufWkt::Empty()};
  }

  std::string name() const override { return "envoy.filters.http.shuffle_shard"; }
};

static Registry::RegisterFactory<ShuffleShardFilterFactory,
                                 Server::Configuration::NamedHttpFilterConfigFactory>
    register_;

} // namespace ShuffleShard
} // namespace HttpFilters
} // namespace Extensions
} // namespace Envoy
