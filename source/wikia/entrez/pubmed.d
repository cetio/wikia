module wikia.entrez.pubmed;

import std.json : JSONValue;
import std.algorithm : map;
import std.array : array;
import std.regex : matchAll, matchFirst, ctRegex, regex;
import std.string : strip, replace;

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
    foreach (m; matchAll(xml, ctRegex!(`<PubmedArticle>[\s\S]*?</PubmedArticle>`)))
    {
        string ax = m.hit;

        string pmid = quickTag(ax, `<PMID[^>]*>(\d+)</PMID>`);
        if (pmid is null)
            continue;

        string title = quickTag(ax, `<ArticleTitle[^>]*>([\s\S]*?)</ArticleTitle>`);

        Page page = new Page();
        page.title = title !is null ? title : pmid;
        page.source = "pubmed";
        page.url = "https://pubmed.ncbi.nlm.nih.gov/"~pmid~"/";

        // Store the full XML article so the AST XML parser can process it.
        page._raw = ax;
        page._parsed = false;

        ret ~= page;
    }
    return ret;
}

public:

Page[] getPages(string DB)(string term, int limit = 10, string apiKey = null)
    if (DB == "pubmed")
{
    JSONValue json = esearch!"pubmed"(term, limit, 0, apiKey);

    if ("esearchresult" !in json || "idlist" !in json["esearchresult"])
        return [];

    string[] pmids = json["esearchresult"]["idlist"].array.map!(x => x.str).array;
    if (pmids.length == 0)
        return [];

    string xml = efetch!"pubmed"(pmids, "abstract", apiKey);
    return parseArticles(xml);
}

Page[] getPagesByID(string DB)(string[] pmids...) if (DB == "pubmed")
{
    if (pmids.length == 0)
        return [];

    string xml = efetch!"pubmed"(pmids, "abstract");
    return parseArticles(xml);
}
