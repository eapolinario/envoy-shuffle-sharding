package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/keepalive"
	"google.golang.org/protobuf/types/known/structpb"

	runtime "github.com/envoyproxy/go-control-plane/envoy/service/runtime/v3"
	discovery "github.com/envoyproxy/go-control-plane/envoy/service/discovery/v3"
	"github.com/envoyproxy/go-control-plane/pkg/cache/types"
	"github.com/envoyproxy/go-control-plane/pkg/cache/v3"
	"github.com/envoyproxy/go-control-plane/pkg/resource/v3"
	"github.com/envoyproxy/go-control-plane/pkg/server/v3"
)

const (
	grpcKeepaliveTime        = 30 * time.Second
	grpcKeepaliveTimeout     = 5 * time.Second
	grpcKeepaliveMinTime     = 30 * time.Second
	grpcMaxConcurrentStreams = 1000000
)

type ControlPlane struct {
	cache  cache.SnapshotCache
	nodeID string
}

func NewControlPlane() *ControlPlane {
	cache := cache.NewSnapshotCache(false, cache.IDHash{}, nil)
	return &ControlPlane{
		cache:  cache,
		nodeID: "envoy-shuffle-shard",
	}
}

func (cp *ControlPlane) SetRuntimeConfig(totalHosts int, defaultShardSize int, customerShards map[string]int) error {
	fields := make(map[string]*structpb.Value)
	
	// Set global config
	fields["shuffle_sharding.total_hosts"] = &structpb.Value{
		Kind: &structpb.Value_NumberValue{NumberValue: float64(totalHosts)},
	}
	fields["shuffle_sharding.default_shard_size"] = &structpb.Value{
		Kind: &structpb.Value_NumberValue{NumberValue: float64(defaultShardSize)},
	}
	
	// Set per-customer shard sizes
	for customer, shardSize := range customerShards {
		key := fmt.Sprintf("shuffle_sharding.customer.%s.shard_size", customer)
		fields[key] = &structpb.Value{
			Kind: &structpb.Value_NumberValue{NumberValue: float64(shardSize)},
		}
	}
	
	runtimeLayer := &structpb.Struct{
		Fields: fields,
	}
	
	snapshot, err := cache.NewSnapshot(
		fmt.Sprintf("snapshot-%d", time.Now().Unix()),
		map[resource.Type][]types.Resource{
			resource.RuntimeType: {
				&runtime.Runtime{
					Name:  "runtime",
					Layer: runtimeLayer,
				},
			},
		},
	)
	if err != nil {
		return err
	}
	
	return cp.cache.SetSnapshot(context.Background(), cp.nodeID, snapshot)
}

func (cp *ControlPlane) Start(port int) error {
	grpcServer := grpc.NewServer(
		grpc.MaxConcurrentStreams(grpcMaxConcurrentStreams),
		grpc.KeepaliveParams(keepalive.ServerParameters{
			Time:    grpcKeepaliveTime,
			Timeout: grpcKeepaliveTimeout,
		}),
		grpc.KeepaliveEnforcementPolicy(keepalive.EnforcementPolicy{
			MinTime:             grpcKeepaliveMinTime,
			PermitWithoutStream: true,
		}),
	)
	
	srv := server.NewServer(context.Background(), cp.cache, nil)
	discovery.RegisterAggregatedDiscoveryServiceServer(grpcServer, srv)
	runtime.RegisterRuntimeDiscoveryServiceServer(grpcServer, srv)
	
	listener, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		return err
	}
	
	log.Printf("xDS control plane listening on :%d", port)
	return grpcServer.Serve(listener)
}

func main() {
	cp := NewControlPlane()
	
	// Set initial configuration
	log.Println("Setting initial runtime configuration...")
	err := cp.SetRuntimeConfig(
		8,  // total_hosts
		2,  // default_shard_size
		map[string]int{
			"customer-A": 2,
			"customer-B": 2,
			"customer-C": 2,
		},
	)
	if err != nil {
		log.Fatalf("Failed to set initial config: %v", err)
	}
	
	// Simulate dynamic updates in background
	go func() {
		time.Sleep(30 * time.Second)
		log.Println(">>> Updating runtime: increasing total_hosts to 12")
		cp.SetRuntimeConfig(
			12, // total_hosts increased!
			2,
			map[string]int{
				"customer-A": 3, // customer-A gets larger shard
				"customer-B": 2,
				"customer-C": 2,
			},
		)
		
		time.Sleep(30 * time.Second)
		log.Println(">>> Updating runtime: giving customer-B larger shard")
		cp.SetRuntimeConfig(
			12,
			2,
			map[string]int{
				"customer-A": 3,
				"customer-B": 4, // customer-B gets even larger shard
				"customer-C": 2,
			},
		)
	}()
	
	// Start server
	if err := cp.Start(18000); err != nil {
		log.Fatalf("Failed to start control plane: %v", err)
	}
}
