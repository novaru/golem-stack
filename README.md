Golem Stack is a microservices architecture project that demonstrates how to build and deploy scalable applications with load balancing capabilities. The core of this stack is the [Golem](https://github.com/novaru/golem) load balancer that distributes traffic across multiple instances of the same application.

## Project Components:

1. **Golem Load Balancer**: A custom-developed load balancer that routes traffic between multiple instances of the same application. It provides intelligent traffic distribution, health checking, and monitoring capabilities.

2. **File Manager API**: A microservice example built with TypeScript and Bun runtime that demonstrates file upload/management functionality. The project runs multiple instances of this API (app1, app2, app3) to demonstrate load balancing.

3. **Postgres Database**: A shared database that all application instances connect to, demonstrating how to handle data consistency across multiple service instances.

4. **Monitoring Stack**:
   - Prometheus: For metrics collection and storage
   - Grafana: For visualization of system and application metrics
   - cAdvisor: For container resource usage and performance metrics

## Tech Stack:

- **Backend**: TypeScript with Hono (Bun)
- **Database**: PostgreSQL
- **Containerization**: Docker and Docker Compose
- **Load Balancing**: Golem (custom solution)
- **Monitoring**: Prometheus and Grafana

## Use Cases

- **Education**: Learn about microservices architecture and load balancing concepts in a practical environment
- **Development Testing**: Test applications under various load conditions with multiple service instances
- **Architecture Prototyping**: Use as a starting point for building larger distributed systems
- **Performance Benchmarking**: Compare different service configurations and load balancing strategies

The `env` file I've created includes all the necessary environment variables for configuring the database connections, service ports, Grafana access, and instance identifiers for the different application services.

To use this configuration:
1. Rename the `env` file to `.env`
2. Customize the values as needed for your environment
3. Start the stack with `docker-compose up`

## Performance Testing

### Using `wrk` with `api-test.lua`

The project includes an `api-test.lua` script for load testing the API using the [wrk](https://github.com/wg/wrk) HTTP benchmarking tool. This script generates realistic API traffic patterns to simulate production load.

#### Installation

Install `wrk` on your system:

```bash
# Ubuntu/Debian
sudo apt-get install wrk

# macOS (using Homebrew)
brew install wrk
```

#### Running Load Tests

To run a load test with the included script:

```bash
wrk -t4 -c100 -d30s -s api-test.lua http://<load-balancer-host>:<load-balancer-port>
```

Parameters:
- `-t4`: Use 4 threads
- `-c100`: Simulate 100 concurrent connections
- `-d30s`: Run test for 30 seconds
- `-s api-test.lua`: Use the provided Lua script
- URL: The endpoint to test (replace with your actual service URL)

#### Script Features

The `api-test.lua` script:
- Simulates realistic traffic patterns with weighted endpoint selection
- Tests various API endpoints including GET and POST requests
- Generates dynamic search queries and file uploads
- Provides detailed statistics including latency percentiles and status code distribution

This tool is ideal for:
- Performance benchmarking
- Load testing before deployment
- Identifying bottlenecks in the system
- Validating the load balancer effectiveness

