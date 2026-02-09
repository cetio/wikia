module wikia.entrez.eutils;

import wikia.composer;
import std.json : JSONValue, parseJSON;
import std.uri : encode;
import std.conv : to;
import std.string : assumeUTF;
import std.array : join;

struct TimeFrame
{
    string from;
    string to;
}

private:

static Orchestrator orchestrator =
    Orchestrator("https://eutils.ncbi.nlm.nih.gov/entrez/eutils", 333);

public:

JSONValue esearch(string DB)(
    string term,
    int retmax = 20,
    int retstart = 0,
    string apiKey = null)
{
    JSONValue json;
    orchestrator.rateLimit();

    string[string] params = [
        "db": DB, "term": term,
        "retmax": retmax.to!string, "retstart": retstart.to!string,
        "retmode": "json"
    ];

    if (apiKey !is null && apiKey.length > 0)
        params["api_key"] = apiKey;

    orchestrator.client.get(
        orchestrator.buildURL("/esearch.fcgi", params),
        (ubyte[] data) { json = parseJSON(data.assumeUTF); },
        null
    );
    return json;
}

string efetch(string DB)(string id, string rettype = "abstract", string apiKey = null)
{
    return efetch!DB([id], rettype, apiKey);
}

string efetch(string DB)(string[] ids, string rettype = "abstract", string apiKey = null)
{
    if (ids.length == 0)
        return null;

    string result;
    orchestrator.rateLimit();

    string idParam = ids.join(",");
    if (ids.length > 200 || idParam.length > 2000)
    {
        string postData = "db="~encode(DB)
           ~"&retmode=xml&rettype="~encode(rettype)
           ~"&id="~encode(idParam);
        if (apiKey !is null && apiKey.length > 0)
            postData ~= "&api_key="~encode(apiKey);

        orchestrator.client.post(
            orchestrator.buildURL("/efetch.fcgi"),
            postData,
            (ubyte[] data) { result = cast(string) data.assumeUTF; },
            null
        );
    }
    else
    {
        string[string] params = [
            "db": DB, "retmode": "xml", "rettype": rettype, "id": idParam
        ];
        if (apiKey !is null && apiKey.length > 0)
            params["api_key"] = apiKey;

        orchestrator.client.get(
            orchestrator.buildURL("/efetch.fcgi", params),
            (ubyte[] data) { result = cast(string) data.assumeUTF; },
            null
        );
    }
    return result;
}

JSONValue elink(string DBFROM, string DBTO)(
    string id,
    string apiKey = null)
{
    JSONValue json;
    orchestrator.rateLimit();

    string[string] params = [
        "dbfrom": DBFROM, "db": DBTO, "id": id, "retmode": "json"
    ];
    if (apiKey !is null && apiKey.length > 0)
        params["api_key"] = apiKey;

    orchestrator.client.get(
        orchestrator.buildURL("/elink.fcgi", params),
        (ubyte[] data) { json = parseJSON(data.assumeUTF); },
        null
    );
    return json;
}
