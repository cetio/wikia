module wikia.entrez.pmc;

import std.json : JSONValue;
import std.algorithm : map;
import std.array : array;
import std.regex : matchAll, matchFirst, ctRegex, regex;
import std.string : strip, replace, indexOf;

import wikia.entrez.eutils;
import wikia.page;

private:

string quickTag(string xml, string re)
{
    auto m = matchFirst(xml, regex(re));
    if (m.empty) return null;
    return m[1].replace("&lt;", "<").replace("&gt;", ">")
        .replace("&amp;", "&").strip;
}

Page[] parseArticles(string xml)
{
    if (xml is null || xml.length == 0)
        return [];

    Page[] ret;
    foreach (m; matchAll(xml, ctRegex!(`<article[\s>][\s\S]*?</article>`)))
    {
        string ax = m.hit;

        string pmcId = quickTag(ax, `<article-id[^>]*pub-id-type="pmc"[^>]*>(\d+)</article-id>`);
        if (pmcId is null)
            continue;

        string title = quickTag(ax, `<article-title[^>]*>([\s\S]*?)</article-title>`);

        Page page = new Page();
        page.title = title !is null ? title : pmcId;
        page.source = "pmc";
        page.url = "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC"~pmcId~"/";

        // Store the full XML article so the AST XML parser can process it.
        page._raw = ax;
        page._parsed = false;

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

    return quickTag(page._raw,
        `<article-id[^>]*pub-id-type="doi"[^>]*>([\s\S]*?)</article-id>`);
}
