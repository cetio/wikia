module wikia.psychonaut;

import std.json : JSONValue, parseJSON, JSONType;
import std.conv : to;
import std.string : assumeUTF, strip, toLower, indexOf;
import std.regex : matchAll, ctRegex;
import std.array : replace;
import std.algorithm : canFind, min;
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

void fetchContent(Page page)
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
    foreach (JSONValue res; json["query"]["search"].array)
    {
        string title = res["title"].str;
        ret ~= new Page(title, "psychonaut",
            "https://psychonautwiki.org/wiki/" ~ title,
            toDelegate(&fetchContent));
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
    bool fromSimilar;
    string sourceName;
}

DosageResult getDosage(Compound compound, bool similarity = true)
{
    Dosage[] tryParseDosage(string pageTitle)
    {
        JSONValue json = query([
            "action": "parse", "prop": "wikitext",
            "page": "Template:SubstanceBox/" ~ pageTitle
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

    bool isExactPage(string pageTitle, string[] syns)
    {
        string lower = pageTitle.toLower;
        foreach (syn; syns)
        {
            if (syn.toLower == lower)
                return true;
        }
        return false;
    }

    string[] syns = compound.synonyms;

    Page[] pages = getPages!"psychonaut"(compound.name);
    foreach (page; pages)
    {
        if (isExactPage(page.title, syns))
        {
            Dosage[] d = tryParseDosage(page.title);
            if (d.length > 0)
                return DosageResult(d, false, null);
        }
    }

    if (!similarity)
        return DosageResult([], false, null);

    Compound[] similar = similaritySearch(compound.cid, 90, 5);
    foreach (sim; similar[0 .. min($, 5)])
    {
        if (sim.cid == compound.cid)
            continue;

        string[] simSyns = sim.synonyms;
        Page[] simPages = getPages!"psychonaut"(sim.name);
        foreach (page; simPages)
        {
            if (isExactPage(page.title, simSyns))
            {
                Dosage[] d = tryParseDosage(page.title);
                if (d.length > 0)
                    return DosageResult(d, true, sim.name);
            }
        }
    }

    return DosageResult([], false, null);
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
        ~ `\s*=\s*([^\n|]+)`);
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
