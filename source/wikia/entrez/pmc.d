module wikia.entrez.pmc;

import std.json : JSONValue;
import std.algorithm : map;
import std.array : array;
import std.regex : matchAll, matchFirst, ctRegex, regex;
import std.string : strip, replace;

import wikia.entrez.eutils;
import wikia.page;

private:

string decodeXml(string text)
{
    if (text is null)
        return null;
    return text
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&#39;", "'")
        .strip;
}

string xmlTag(string xml, string re)
{
    auto m = matchFirst(xml, regex(re));
    return m.empty ? null : decodeXml(m[1]);
}

Page[] parseArticles(string xml)
{
    if (xml is null || xml.length == 0)
        return [];

    Page[] ret;
    foreach (m; matchAll(xml, ctRegex!(`<article[\s>][\s\S]*?</article>`)))
    {
        string ax = m.hit;

        string pmcId = xmlTag(ax, `<article-id[^>]*pub-id-type="pmc"[^>]*>(\d+)</article-id>`);
        if (pmcId is null)
            continue;

        string title = xmlTag(ax, `<article-title[^>]*>([\s\S]*?)</article-title>`);
        string doi = xmlTag(ax, `<article-id[^>]*pub-id-type="doi"[^>]*>([\s\S]*?)</article-id>`);
        string pmid = xmlTag(ax, `<article-id[^>]*pub-id-type="pmid"[^>]*>(\d+)</article-id>`);

        Page page = new Page();
        page.title = title !is null ? title : pmcId;
        page.source = "pmc";
        page.url = "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC"~pmcId~"/";

        // Abstract as section
        string abs = xmlTag(ax, `<abstract[^>]*>([\s\S]*?)</abstract>`);
        if (abs !is null)
            page._sections ~= Section("Abstract", abs, 1);

        // Body as section
        string body_ = xmlTag(ax, `<body[^>]*>([\s\S]*?)</body>`);
        if (body_ !is null)
            page._sections ~= Section("Body", body_, 1);

        // Store metadata in raw for later extraction
        page._raw = "PMC="~pmcId
           ~(pmid !is null ? "\nPMID="~pmid : "")
           ~(doi !is null ? "\nDOI="~doi : "");

        ret ~= page;
    }
    return ret;
}

public:

Page[] getPages(string DB)(string term, int limit = 10, string apiKey = null)
    if (DB == "pmc")
{
    JSONValue json = esearch!"pmc"(term, limit, 0, apiKey);

    if ("esearchresult" !in json || "idlist" !in json["esearchresult"])
        return [];

    string[] pmcIds = json["esearchresult"]["idlist"].array.map!(x => x.str).array;
    if (pmcIds.length == 0)
        return [];

    string xml = efetch!"pmc"(pmcIds, "full", apiKey);
    return parseArticles(xml);
}

Page[] getPagesByID(string DB)(string[] ids...) if (DB == "pmc")
{
    if (ids.length == 0)
        return [];

    string xml = efetch!"pmc"(ids, "full");
    return parseArticles(xml);
}

string getDOI(Page page)
{
    if (page is null || page._raw is null)
        return null;

    import std.string : indexOf;
    string raw = page._raw;
    auto idx = raw.indexOf("DOI=");
    if (idx < 0)
        return null;

    string rest = raw[idx + 4 .. $];
    auto nl = rest.indexOf("\n");
    return nl >= 0 ? rest[0 .. nl] : rest;
}
