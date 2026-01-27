# Akashi

Akashi is a library for accessing diverse public APIs and data sources. Akashi provides clean, type-safe interfaces to scientific databases, financial markets, and knowledge repositories.

## Features

### Scientific & Medical Data
- **NCBI Entrez** — Access to PubMed, PMC, and PubChem databases for research articles and chemical compounds
- **Wikipedia** — Search and retrieve articles with support for extracting structured data
- **PsychonautWiki** — Specialized wiki for psychoactive substances and related information

### Financial Data
- **Precious Metals** — Real-time spot prices from multiple sources (Kitco, Packetizer)
- **Yahoo Finance** — Stock quotes and market data

### Geospatial & Resources
- **USGS MRDS** — Mineral Resources Data System for mining deposit information

## Design Philosophy

Akashi emphasizes:
- **Type Safety** — Structured data types for all API responses
- **Rate Limiting** — Built-in throttling to respect API guidelines
- **Error Handling** — Graceful degradation when services are unavailable
- **Flexibility** — Both high-level convenience methods and low-level raw access

## License

Akashi is licensed under the [AGPL-3.0 license](LICENSE.txt).