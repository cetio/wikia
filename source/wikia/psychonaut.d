module wikia.psychonaut;

import std.json : JSONValue, parseJSON, JSONType;
import std.conv : to;
import std.string : assumeUTF, strip, toLower, indexOf;
import std.regex : matchAll, ctRegex;
import std.array : replace, join;
import std.algorithm : canFind, min, map, filter;
import std.math : abs, isNaN;
import std.functional : toDelegate;

import wikia.composer;
import wikia.page;
import wikia.pubchem;

private:

static Orchestrator orchestrator =
    Orchestrator("https://psychonautwiki.org/w", 200);

JSONValue query(string[string] params)
{
    JSONValue json;
    params["format"] = "json";
    params["formatversion"] = "2";

    orchestrator.rateLimit();
    orchestrator.client.get(
        orchestrator.buildURL("/api.php", params),
        (ubyte[] data) {
            json = parseJSON(data.assumeUTF);
        },
        null
    );
    return json;
}

package:

void _psFetchContent(Page page)
{
    JSONValue json = query([
        "action": "parse", "prop": "wikitext",
        "page": page.title
    ]);
    if ("parse" !in json || "wikitext" !in json["parse"])
        return;

    JSONValue wikitext = json["parse"]["wikitext"];

    if (wikitext.type == JSONType.object && "*" in wikitext)
        page._raw = wikitext["*"].str;
    else if (wikitext.type == JSONType.string)
        page._raw = wikitext.str;
}

public:

Page[] getPages(string DB)(string term, int limit = 10)
    if (DB == "psychonaut")
{
    JSONValue json = query([
        "action": "query", "list": "search",
        "srsearch": term,
        "srlimit": limit.to!string, "srnamespace": "0",
        "srprop": "snippet|titlesnippet"
    ]);

    if ("query" !in json || "search" !in json["query"])
        return [];

    Page[] ret;
    foreach (res; json["query"]["search"].array)
    {
        string title = res["title"].str;
        ret ~= new Page(title, "psychonaut",
            "https://psychonautwiki.org/wiki/"~title,
            toDelegate(&_psFetchContent));
            
        if (ret.length >= limit)
            break;
    }
    return ret;
}

Page[] getPagesByTitle(string DB)(string[] titles...)
    if (DB == "psychonaut")
{
    if (titles.length == 0)
        return [];

    JSONValue json = query([
        "action": "query",
        "titles": titles.join("|"),
        "prop": ""
    ]);

    if ("query" !in json || "pages" !in json["query"])
        return [];

    Page[] ret;
    foreach (page; json["query"]["pages"].array)
    {
        if ("missing" in page)
            continue;

        string title = page["title"].str;
        ret ~= new Page(title, "psychonaut",
            "https://psychonautwiki.org/wiki/"~title,
            toDelegate(&_psFetchContent));
    }
    return ret;
}

// TODO: [[Effect::Cognitive euphoria]] effect parsing
// TODO: [[DangerousInteraction::Alcohol]] interaction parsing
Page[] getReports(Page page, int limit = 20)
{
    JSONValue json = query([
        "action": "query", "list": "search",
        "srsearch": "intitle:Experience:"~page.title,
        "srlimit": limit.to!string, "srnamespace": "0",
        "srprop": "snippet|titlesnippet"
    ]);

    if ("query" !in json || "search" !in json["query"])
        return [];

    Page[] ret;
    foreach (res; json["query"]["search"].array)
    {
        string title = res["title"].str;
        ret ~= new Page(title, "psychonaut",
            "https://psychonautwiki.org/wiki/"~title,
            toDelegate(&_psFetchContent));

        if (ret.length >= limit)
            break;
    }
    return ret;
}

struct Dosage
{
    string route;
    string bioavailability;
    string threshold;
    string light;
    string common;
    string strong;
    string heavy;
}

struct DosageResult
{
    Dosage[] dosages;
    Compound source;
}

DosageResult getDosage(Compound compound)
{
    Dosage[] tryParseDosage(string title)
    {
        JSONValue json = query([
            "action": "parse", "prop": "wikitext",
            "page": "Template:SubstanceBox/"~title
        ]);
        if ("parse" !in json || "wikitext" !in json["parse"])
            return [];

        JSONValue wikitext = json["parse"]["wikitext"];
        string raw;
        if (wikitext.type == JSONType.object && "*" in wikitext)
            raw = wikitext["*"].str;
        else if (wikitext.type == JSONType.string)
            raw = wikitext.str;

        if (raw is null)
            return [];

        return parseDosageText(raw);
    }

    bool isExactPage(string title, string[] syns)
    {
        string lower = title.toLower;
        foreach (syn; syns)
        {
            if (syn.toLower == lower)
                return true;
        }
        return false;
    }

    // 1. Fetch all similar compounds (CIDs only) - includes primary compound
    Compound[] similar = similaritySearch(compound.cid, 90, 5);
    int[] simCids;
    foreach (sim; similar)
        simCids ~= sim.cid;

    if (simCids.length == 0)
        return DosageResult([], null);

    // 2. Batch get properties for all similar CIDs
    Compound[] withProps = getProperties!"cid"(simCids);

    // 3. Filter by XLogP difference > 0.5 or MW difference > 8%
    // Always include the primary compound (diff = 0)
    double refXLogP = compound.properties.xlogp;
    double refMW = compound.properties.weight;
    Compound[] filtered;
    foreach (sim; withProps)
    {
        // Always include the primary compound
        if (sim.cid == compound.cid)
        {
            filtered ~= sim;
            continue;
        }
        
        if (!isNaN(refXLogP) && !isNaN(sim.properties.xlogp))
        {
            if (abs(sim.properties.xlogp - refXLogP) > 0.5)
                continue;
        }
        if (!isNaN(refMW) && refMW > 0 && !isNaN(sim.properties.weight) && sim.properties.weight > 0)
        {
            if (abs(sim.properties.weight - refMW) / refMW > 0.08)
                continue;
        }
        filtered ~= sim;
    }

    if (filtered.length == 0)
        return DosageResult([], null);

    // 4. Batch fetch psychonaut pages by compound names
    string[] names;
    foreach (sim; filtered)
        names ~= sim.name;
    Page[] simPages = getPagesByTitle!"psychonaut"(names);

    // 5. Batch get synonyms for filtered CIDs
    int[] filteredCids;
    foreach (sim; filtered)
        filteredCids ~= sim.cid;
    string[][] allSyns = getSynonyms!"cid"(filteredCids);

    // Build CID -> synonyms map
    string[][int] synsByCid;
    foreach (i, sim; filtered)
    {
        if (i < allSyns.length)
            synsByCid[sim.cid] = allSyns[i];
    }

    // 6. Match synonyms to pages and extract dosage
    foreach (sim; filtered)
    {
        string[] simSyns = sim.cid in synsByCid ? synsByCid[sim.cid] : [];
        foreach (page; simPages)
        {
            if (isExactPage(page.title, simSyns))
            {
                Dosage[] d = tryParseDosage(page.title);
                if (d.length > 0)
                {
                    Compound source = (sim.cid == compound.cid) ? null : sim;
                    return DosageResult(d, source);
                }
            }
        }
    }

    return DosageResult([], null);
}

Dosage[] parseDosageText(string raw)
{
    Dosage[] ret;
    string[string][string] routes;

    string cleanValue(string val, string rank)
    {
        enum semRe = ctRegex!(`\[\[[^\]]*::([^\]]*)\]\]`);
        foreach (sm; matchAll(val, semRe))
        {
            if (sm.captures.length > 1)
                val = val.replace(sm[0], sm[1].strip);
        }
        
        enum linkRe = ctRegex!(`\[\[([^\]|]+)(?:\|([^\]]+))?\]\]`);
        foreach (lm; matchAll(val, linkRe))
        {
            string display = lm.captures.length > 2 && lm[2].length > 0
                ? lm[2] : lm[1];
            val = val.replace(lm[0], display.strip);
        }

        enum refRe = ctRegex!(`(?:</*ref[^>]*>|\{\{.*)`);
        foreach (rm; matchAll(val, refRe))
            val = val.replace(rm[0], "");
        return val.strip;
    }

    enum roaRe = ctRegex!(
        `\|\s*(\w+)ROA_(Bioavailability|Threshold|Light|Common|Strong|Heavy)`
       ~`\s*=\s*([^\n|]+)`);
    foreach (m; matchAll(raw, roaRe))
    {
        string range = cleanValue(m[3], m[2]);
        if (range.length == 0 || range.indexOf(" x ") != -1)
            continue;

        string route = m[1];
        string rank = m[2];

        if (route !in routes)
            routes[route] = (string[string]).init;

        routes[route][rank] = range;
    }

    foreach (route, ranks; routes)
    {
        ret ~= Dosage(
            route,
            "Bioavailability" in ranks ? ranks["Bioavailability"] : null,
            "Threshold" in ranks ? ranks["Threshold"] : null,
            "Light" in ranks ? ranks["Light"] : null,
            "Common" in ranks ? ranks["Common"] : null,
            "Strong" in ranks ? ranks["Strong"] : null,
            "Heavy" in ranks ? ranks["Heavy"] : null
        );
    }

    return ret;
}
