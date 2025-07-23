# Testing System - OSM-Notes-profile

This directory contains the unit and integration testing system for the OSM-Notes-profile project.

## Directory Structure

```
tests/
├── unit/
│   ├── bash/                    # Unit tests for bash scripts
│   │   ├── functionsProcess.test.bats
│   │   └── processPlanetNotes.test.bats
│   └── sql/                     # Unit tests for SQL
│       ├── functions.test.sql
│       └── tables.test.sql
├── integration/                  # End-to-end integration tests
│   └── end_to_end.test.bats
├── fixtures/                    # Test data
├── docker/                      # Docker configuration for integration
│   ├── docker-compose.yml
│   ├── Dockerfile
│   ├── run_integration_tests.sh
│   └── mock_api/
│       └── mock_osm_api.py
├── test_helper.bash            # Helper functions for BATS
├── run_tests.sh                # Main script to run tests
└── README.md                   # This file
```

## Technologies Used

### BATS (Bash Automated Testing System)
- **Purpose**: Unit tests for bash scripts
- **Advantages**: Native bash syntax, easy integration, mock support
- **Documentation**: https://github.com/bats-core/bats-core

### pgTAP
- **Purpose**: Unit tests for PostgreSQL
- **Advantages**: Native framework for PostgreSQL, standard TAP syntax
- **Documentation**: https://pgtap.org/

### Docker
- **Purpose**: Isolated environment for integration tests
- **Advantages**: Reproducibility, isolation, easy configuration
- **Components**: PostgreSQL, OSM API Mock, Application

## Prerequisites Installation

### Ubuntu/Debian
```bash
# Install BATS
sudo apt-get update
sudo apt-get install bats

# Install pgTAP
sudo apt-get install postgresql-15-pgtap

# Install Docker (if not installed)
sudo apt-get install docker.io docker-compose

# Verify installation
bats --version
pg_prove --version
docker --version
docker-compose --version
```

### macOS
```bash
# Install BATS with Homebrew
brew install bats-core

# Install pgTAP
brew install pgtap

# Install Docker Desktop
# Download from: https://www.docker.com/products/docker-desktop
```

## Test Execution

### 🚀 **Unit Tests (Phase 1)**

#### Run all unit tests
```bash
./tests/run_tests.sh
```

#### Run only BATS tests
```bash
./tests/run_tests.sh --bats-only
```

#### Run only pgTAP tests
```bash
./tests/run_tests.sh --pgtap-only
```

#### Keep test database
```bash
./tests/run_tests.sh --no-cleanup
```

### 🐳 **Integration Tests (Phase 2)**

#### Run all integration tests with Docker
```bash
./tests/docker/run_integration_tests.sh
```

#### Start Docker services only
```bash
./tests/docker/run_integration_tests.sh --start-only
```

#### End-to-end tests only
```bash
./tests/docker/run_integration_tests.sh --e2e-only
```

#### View service logs
```bash
./tests/docker/run_integration_tests.sh --logs
```

#### Clean up Docker resources
```bash
./tests/docker/run_integration_tests.sh --cleanup
```

### 📊 **Specific Tests**

#### Performance tests
```bash
./tests/run_tests.sh --performance-only
```

#### Integration tests (without Docker)
```bash
./tests/run_tests.sh --integration-only
```

#### End-to-end tests (without Docker)
```bash
./tests/run_tests.sh --e2e-only
```

### 🔧 **Advanced Options**

#### View complete help
```bash
./tests/run_tests.sh --help
./tests/docker/run_integration_tests.sh --help
```

#### Custom environment variables
```bash
export TEST_DBNAME="my_test_db"
export TEST_DBUSER="my_user"
export TEST_DBPASSWORD="my_password"
./tests/run_tests.sh
```

## Test Database Configuration

### Environment Variables
```bash
export TEST_DBNAME="osm_notes_test"
export TEST_DBUSER="test_user"
export TEST_DBPASSWORD="test_pass"
export TEST_DBHOST="localhost"
export TEST_DBPORT="5432"
```

### Docker Configuration
```bash
# Variables for Docker tests
export DOCKER_DBNAME="osm_notes_test"
```

## Current Test Status

### ✅ **Successful Tests**
- **Unit Tests (BATS)**: 23 tests passing
- **pgTAP Tests**: 2 tests passing (Docker only)
- **Integration Tests**: 5 tests passing (Docker only)
- **Performance Tests**: 1 test passing
- **Total**: 31 tests passing

### 🔧 **Resolved Configuration**
- ✅ Docker containers configured correctly
- ✅ PostgreSQL database working
- ✅ All required tools installed
- ✅ Environment variables configured
- ✅ End-to-end tests working
- ✅ Script execution issues resolved (set -e handling)

### 🖥️ **Environment Behavior**

#### **Host Environment (Local Development)**
- ✅ **BATS Tests**: 23 tests passing (simulated database)
- ✅ **pgTAP Tests**: Skipped (require real PostgreSQL)
- ✅ **Integration Tests**: Skipped (require Docker)
- ✅ **Performance Tests**: 1 test passing

#### **Docker Environment (CI/CD)**
- ✅ **BATS Tests**: 23 tests passing (real database)
- ✅ **pgTAP Tests**: 2 tests passing (real database)
- ✅ **Integration Tests**: 5 tests passing (real environment)
- ✅ **Performance Tests**: 1 test passing

## Troubleshooting

### Common Issues

#### Docker Issues
```bash
# Docker daemon not running
sudo systemctl start docker

# Permission denied
sudo usermod -aG docker $USER
# Then log out and log back in

# Port conflicts
# Check if ports 5433 and 8001 are available
sudo netstat -tulpn | grep :5433
sudo netstat -tulpn | grep :8001
```

#### Database Issues
```bash
# Test database connection
psql -h localhost -U test_user -d osm_notes_test -c "SELECT 1;"

# Reset test database
dropdb -h localhost -U test_user osm_notes_test
createdb -h localhost -U test_user osm_notes_test
```

#### Test Issues
```bash
# Check BATS installation
bats --version

# Check pgTAP installation
pg_prove --version

# Run tests with verbose output
bats --show-output-of-passing-tests tests/unit/bash/

# Run tests with timing information
bats --timing tests/unit/bash/

# Run tests with trace (debug mode)
bats --trace tests/unit/bash/

# Run tests in parallel
bats --jobs 2 tests/unit/bash/

# Run tests with TAP output
bats --tap tests/unit/bash/

# Run tests with JUnit output
bats --formatter junit tests/unit/bash/

# Run tests with output to directory
mkdir -p /tmp/test_output
bats --output /tmp/test_output tests/unit/bash/

# Run tests with custom code quote style
bats --code-quote-style "''" tests/unit/bash/

# Run tests with gather outputs
mkdir -p /tmp/test_outputs
bats --gather-test-outputs-in /tmp/test_outputs tests/unit/bash/

# Run tests with no tempdir cleanup
bats --no-tempdir-cleanup tests/unit/bash/
```

### Debug Scripts

#### Docker Debug
```bash
# Check container status
sudo docker ps

# View container logs
sudo docker logs osm_notes_postgres
sudo docker logs osm_notes_app
sudo docker logs osm_notes_mock_api

# Execute commands in container
sudo docker exec -it osm_notes_app bash
```

#### Network Debug
```bash
# Test network connectivity
sudo docker exec osm_notes_app ping postgres
sudo docker exec osm_notes_app nc -zv postgres 5432

# Test API connectivity
curl http://localhost:8001/api/0.6/notes
```

## Development Workflow

### 1. **Local Development**
```bash
# Start development environment
./tests/docker/run_integration_tests.sh --start-only

# Run tests during development
./tests/run_tests.sh --bats-only

# Check specific functionality
bats tests/unit/bash/functionsProcess.test.bats
```

### 2. **Integration Testing**
```bash
# Full integration test
./tests/docker/run_integration_tests.sh

# Test specific component
bats tests/integration/end_to_end.test.bats -f "API notes"
```

### 3. **Performance Testing**
```bash
# Run performance tests
./tests/run_tests.sh --performance-only

# Monitor resource usage
sudo docker stats osm_notes_app
```

## CI/CD Integration

### GitHub Actions
The project includes a complete CI/CD pipeline that runs:
- Unit tests on every push
- Integration tests on pull requests
- Performance tests on releases
- Security scans on main branch

### Local CI Simulation
```bash
# Simulate CI environment
sudo docker-compose -f tests/docker/docker-compose.yml up -d
./tests/run_tests.sh
sudo docker-compose -f tests/docker/docker-compose.yml down
```

## Contributing

### Adding New Tests

#### BATS Tests
```bash
# Create new test file
touch tests/unit/bash/new_function.test.bats

# Test structure
#!/usr/bin/env bats

load "$(dirname "$BATS_TEST_FILENAME")/../../test_helper.bash"

@test "function should work correctly" {
  # Test implementation
  run some_function
  [ "$status" -eq 0 ]
  [ "$output" = "expected result" ]
}
```

#### pgTAP Tests
```bash
# Create new SQL test file
touch tests/unit/sql/new_function.test.sql

# Test structure
BEGIN;
SELECT plan(1);

SELECT has_function('function_name');

SELECT * FROM finish();
ROLLBACK;
```

### Test Guidelines

1. **Naming Convention**
   - BATS files: `*.test.bats`
   - SQL files: `*.test.sql`
   - Test functions: `test_*`

2. **Test Structure**
   - Setup: Prepare test environment
   - Execute: Run the function/script
   - Verify: Check results
   - Cleanup: Restore environment

3. **Best Practices**
   - Use descriptive test names
   - Test both success and failure cases
   - Keep tests independent
   - Use mocks for external dependencies

## Performance Considerations

### Test Execution Time
- **Unit Tests**: < 30 seconds
- **Integration Tests**: < 2 minutes
- **End-to-End Tests**: < 5 minutes
- **Full Suite**: < 10 minutes

### Resource Usage
- **Memory**: < 512MB per container
- **CPU**: < 2 cores per container
- **Disk**: < 1GB for test data

## Security

### Test Environment Security
- ✅ Isolated Docker containers
- ✅ Non-root user execution
- ✅ Temporary test databases
- ✅ No production data access
- ✅ Secure environment variables

### Code Quality
- ✅ ShellCheck for bash scripts
- ✅ Bandit for Python security
- ✅ Static analysis in CI/CD
- ✅ Dependency vulnerability scanning

## Monitoring and Logging

### Test Logs
```bash
# View test logs
tail -f /tmp/bats_test_*/test.log

# View application logs
sudo docker logs -f osm_notes_app

# View database logs
sudo docker logs -f osm_notes_postgres
```

### Metrics
- Test execution time
- Success/failure rates
- Resource usage
- Code coverage

## Support

### Documentation
- [BATS Documentation](https://github.com/bats-core/bats-core)
- [pgTAP Documentation](https://pgtap.org/)
- [Docker Documentation](https://docs.docker.com/)

### Issues
- Report bugs via GitHub Issues
- Include test output and environment details
- Provide minimal reproduction steps

### Community
- Join project discussions
- Contribute test improvements
- Share testing best practices

---

**Last Updated**: 2025-07-20  
**Version**: 2.0.0  
**Author**: Andres Gomez (AngocA) 