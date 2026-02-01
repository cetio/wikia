# Akashi

> [!NOTE]
> Future development for Akashi is currently ambiguous. It will likely remain a floating repository for various API integrations and data sources for the foreseeable future.

Akashi is a collection of D-based interfaces for accessing diverse public APIs and specialized data sources. It provides structured access to scientific databases, financial markets, and knowledge repositories.

## Features

### Knowledge & Research
- **Wikipedia** - Search, article retrieval, and structured data extraction (PubChem CIDs)
- **PsychonautWiki** - Specialized wiki access for substance information and Erowid cross-references
- **NCBI Entrez** - Interface for PubMed, PMC, and PubChem research databases

### Financial & Commodity Data
- **Yahoo Finance** - Real-time stock quotes and historical market data
- **Precious Metals** - Spot prices for gold, silver, and other metals via Kitco and Packetizer

### Geospatial
- **USGS MRDS** - Mineral Resources Data System for mining deposit and geological information

## Quick Start

**Requirements:**
- D compiler (DMD, LDC, or GDC)
- `dub` package manager

**Install:**
Add `akashi` to your `dub.json` or `dub.sdl`:
```bash
dub add akashi
```

## Architecture

- `akashi.wikipedia` - Wikipedia API interaction and parser
- `akashi.psychonaut` - PsychonautWiki and Erowid data integration
- `akashi.yahoo` - Yahoo Finance quote retrieval
- `akashi.entrez` - NCBI research database access
- `akashi.kitco` / `akashi.packetizer` - Metal price scrapers and APIs
- `akashi.mrds` - USGS mineral database access

## License

Akashi is licensed under the [AGPL-3.0 license](LICENSE.txt).