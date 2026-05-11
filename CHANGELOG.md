# Changelog

## [v0.2.0] - 2025-01-11

### Added
- Refactored to use PostgreSQL 18's COPY FROM PROGRAM mechanism
- Removed C extension dependency, no compilation required
- Added embedding_wrapper.sh wrapper script
- Added more comprehensive error handling and logging
- Added batch processing configuration parameters
- Added statistics function embedding_stats()
- Added error query function embedding_errors()

### Improved
- Optimized Python proxy script performance
- Improved configuration file structure
- Updated documentation with detailed usage examples
- Added performance optimization section to README

### Fixed
- Fixed certain encoding issues
- Fixed timeout handling logic

### Compatibility
- Requires PostgreSQL 18 or higher
- Requires Python 3.8 or higher

## [v0.1.0] - 2025-01-05

### Added
- Initial version
- Support for basic text embedding generation
- Support for OpenAI and Ollama models
- Configuration file support
- Basic documentation

---

Version meaning:
- Major version: Major changes, incompatible API modifications
- Minor version: Feature additions, backward compatible
- Patch version: Bug fixes and minor improvements
