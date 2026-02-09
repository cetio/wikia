module wikia.wikipedia;

import std.json : JSONValue, parseJSON, JSONType;
import std.conv : to;
import std.string : assumeUTF, strip;
import std.regex : matchAll, ctRegex;
import std.array : join;
import std.algorithm : canFind;
import std.functional : toDelegate;

import wikia.composer;
import wikia.page;

private:

static Orchestrator orchestrator =
    Orchestrator("https://en.wikipedia.org/w", 200);

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
    if (DB == "wikipedia")
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
        ret ~= new Page(title, "wikipedia",
            "https://en.wikipedia.org/wiki/"~title,
            toDelegate(&fetchContent));
        if (ret.length >= limit)
            break;
    }
    return ret;
}

Page[] getPagesByTitle(string DB)(string[] titles...)
    if (DB == "wikipedia")
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
        ret ~= new Page(title, "wikipedia",
            "https://en.wikipedia.org/wiki/"~title,
            toDelegate(&fetchContent));
    }
    return ret;
}

string[] extractCIDs(Page page)
{
    string[] cids;
    enum pubChemRe = ctRegex!`PubChem\s*=\s*(\d+)`;
    foreach (m; matchAll(page.raw, pubChemRe))
    {
        string cid = strip(m[1]);
        if (cid.length && !cids.canFind(cid))
            cids ~= cid;
    }

    enum pubChemCidRe = ctRegex!`PubChemCID\s*=\s*(\d+)`;
    foreach (m; matchAll(page.raw, pubChemCidRe))
    {
        string cid = strip(m[1]);
        if (cid.length && !cids.canFind(cid))
            cids ~= cid;
    }

    enum pubChemTemplateRe = ctRegex!`\{\{\s*PubChem\s*\|\s*(\d+)\s*\}\}`;
    foreach (m; matchAll(page.raw, pubChemTemplateRe))
    {
        string cid = strip(m[1]);
        if (cid.length && !cids.canFind(cid))
            cids ~= cid;
    }

    enum pubChemUrlRe = ctRegex!`https?://(?:www\.)?pubchem\.ncbi\.nlm\.nih\.gov/compound/(\d+)`;
    foreach (m; matchAll(page.raw, pubChemUrlRe))
    {
        string cid = strip(m[1]);
        if (cid.length && !cids.canFind(cid))
            cids ~= cid;
    }
    return cids;
}
