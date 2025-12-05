use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use log::info;
use std::collections::HashMap;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> {
        Box::new(ShuffleShardRoot::default())
    });
}}

#[derive(Default)]
struct ShuffleShardRoot;

impl Context for ShuffleShardRoot {}

impl RootContext for ShuffleShardRoot {
    fn on_vm_start(&mut self, _vm_configuration_size: usize) -> bool {
        info!("Shuffle Shard WASM filter started");
        true
    }

    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(ShuffleShardFilter::default()))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

#[derive(Default)]
struct ShuffleShardFilter {
    total_hosts: u32,
    shard_size: u32,
}

impl Context for ShuffleShardFilter {}

impl HttpContext for ShuffleShardFilter {
    fn on_http_request_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        // Get customer ID from header
        let customer_id = match self.get_http_request_header("x-customer-id") {
            Some(id) => id,
            None => {
                self.send_http_response(
                    400,
                    vec![("content-type", "text/plain")],
                    Some(b"Missing x-customer-id header"),
                );
                return Action::Pause;
            }
        };

        // Read dynamic config from RTDS runtime
        self.total_hosts = self.get_property(vec!["runtime", "shuffle_sharding.total_hosts"])
            .and_then(|bytes| String::from_utf8(bytes).ok())
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(8);

        // Try customer-specific shard size first
        let customer_key = format!("shuffle_sharding.customer.{}.shard_size", customer_id);
        self.shard_size = self.get_property(vec!["runtime", &customer_key])
            .and_then(|bytes| String::from_utf8(bytes).ok())
            .and_then(|s| s.parse::<u32>().ok())
            .or_else(|| {
                // Fall back to default shard size
                self.get_property(vec!["runtime", "shuffle_sharding.default_shard_size"])
                    .and_then(|bytes| String::from_utf8(bytes).ok())
                    .and_then(|s| s.parse::<u32>().ok())
            })
            .unwrap_or(2);

        // Ensure shard size doesn't exceed total hosts
        if self.shard_size > self.total_hosts {
            self.shard_size = self.total_hosts;
        }

        // Generate shuffle shard using hash-based selection
        let mut selected_hosts = Vec::new();
        let mut seen = HashMap::new();

        for i in 0..self.shard_size {
            let hash_input = format!("{}_salt_{}", customer_id, i);
            let mut hash_value = djb2_hash(&hash_input);
            let mut host_index = (hash_value % self.total_hosts as u64) as usize;

            // Collision avoidance
            let mut attempts = 0;
            while seen.contains_key(&host_index) && attempts < self.total_hosts {
                hash_value = hash_value.wrapping_mul(31).wrapping_add(attempts as u64);
                host_index = (hash_value % self.total_hosts as u64) as usize;
                attempts += 1;
            }

            if !seen.contains_key(&host_index) {
                selected_hosts.push(host_index);
                seen.insert(host_index, true);
            }
        }

        // Convert to comma-separated string for observability
        let shard_list: Vec<String> = selected_hosts.iter().map(|h| h.to_string()).collect();
        let shard_assignment = shard_list.join(",");

        // Add shard info headers
        self.set_http_request_header("x-shard-assignment", Some(&shard_assignment));
        self.set_http_request_header(
            "x-shard-config",
            Some(&format!("{}/{}", self.shard_size, self.total_hosts)),
        );

        // Pick one host from shard using path hash for stickiness
        let path = self.get_http_request_header(":path").unwrap_or_else(|| "/".to_string());
        let path_hash = djb2_hash(&path);
        let shard_index = (path_hash % self.shard_size as u64) as usize;
        let selected_host = selected_hosts.get(shard_index).copied().unwrap_or(0);

        // Set target cluster for routing
        let target_cluster = format!("backend_{}", selected_host);
        self.set_http_request_header("x-target-cluster", Some(&target_cluster));
        self.set_http_request_header("x-target-host", Some(&selected_host.to_string()));

        info!(
            "Customer {} -> Config {}/{} -> Shard [{:?}] -> Host {}",
            customer_id, self.shard_size, self.total_hosts, shard_list, selected_host
        );

        Action::Continue
    }
}

// DJB2 hash function for deterministic hashing
fn djb2_hash(s: &str) -> u64 {
    let mut hash: u64 = 5381;
    for byte in s.bytes() {
        hash = hash.wrapping_mul(33).wrapping_add(byte as u64);
    }
    hash
}
