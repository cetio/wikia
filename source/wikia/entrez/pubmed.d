module wikia.entrez.pubmed;

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
    foreach (m; matchAll(xml, ctRegex!(`<PubmedArticle>[\s\S]*?</PubmedArticle>`)))
    {
        string ax = m.hit;

        string pmid = xmlTag(ax, `<PMID[^>]*>(\d+)</PMID>`);
        if (pmid is null)
            continue;

        string title = xmlTag(ax, `<ArticleTitle[^>]*>([\s\S]*?)</ArticleTitle>`);
        string doi = xmlTag(ax, `<ELocationID[^>]*EIdType="doi"[^>]*>([\s\S]*?)</ELocationID>`);
        string journal = xmlTag(ax, `<Title[^>]*>([\s\S]*?)</Title>`);

        Page page = new Page();
        page.title = title !is null ? title : pmid;
        page.source = "pubmed";
        page.url = "https://pubmed.ncbi.nlm.nih.gov/"~pmid~"/";

        // Abstract as section
        string abs = xmlTag(ax, `<AbstractText[^>]*>([\s\S]*?)</AbstractText>`);
        if (abs !is null)
            page._sections ~= Section("Abstract", abs, 1);

        // Store DOI and PMID in raw for later extraction
        page._raw = "PMID="~pmid
           ~(doi !is null ? "\nDOI="~doi : "")
           ~(journal !is null ? "\nJournal="~journal : "");

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
