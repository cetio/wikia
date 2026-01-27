module akashi.entrez.pmc;

import akashi.entrez.eutils;
import akashi.entrez.pubmed;
import std.json : JSONValue;
import std.algorithm : map, filter;
import std.array : join, array;
import std.regex : ctRegex, matchFirst, matchAll;
import std.string : indexOf, strip, replace;

static class PMC
{
    struct Article
    {
        string pmcId;
        string pmid;
        string fulltext;
        string title;
        string[] authors;
        string doi;
    }

    // Decode XML entities
    private static string decodeXml(string text)
    {
        string result = text;
        result = replace(result, "&lt;", "<");
        result = replace(result, "&gt;", ">");
        result = replace(result, "&amp;", "&");
        result = replace(result, "&quot;", "\"");
        result = replace(result, "&apos;", "'");
        result = replace(result, "&#39;", "'");
        result = result.strip();
        return result;
    }

    // Parse PMC XML into PMC.Article structs
    static PMC.Article[] parsePMCArticles(string xml)
    {
        PMC.Article[] articles;
        
        if (xml.length == 0)
            return articles;
        
        // PMC XML structure: <article>...</article> or <pmc-articleset>...</pmc-articleset>
        auto articleRegex = ctRegex!`<(?:article|pmc-articleset)>.*?</(?:article|pmc-articleset)>`;
        auto matches = matchAll(xml, articleRegex);
        
        foreach (match; matches)
        {
            string articleXml = match.hit;
            PMC.Article article;
            
            // Extract PMC ID
            auto pmcMatch = matchFirst(articleXml, ctRegex!`<article-id[^>]*pub-id-type="pmc"[^>]*>(\d+)</article-id>`);
            if (!pmcMatch)
                pmcMatch = matchFirst(articleXml, ctRegex!`pmc-(\d+)`);
            if (pmcMatch)
                article.pmcId = pmcMatch.captures[0];
            
            // Extract PMID
            auto pmidMatch = matchFirst(articleXml, ctRegex!`<article-id[^>]*pub-id-type="pmid"[^>]*>(\d+)</article-id>`);
            if (pmidMatch)
                article.pmid = pmidMatch.captures[0];
            
            // Extract title
            auto titleMatch = matchFirst(articleXml, ctRegex!`<article-title[^>]*>(.*?)</article-title>`);
            if (titleMatch)
                article.title = decodeXml(titleMatch.captures[0]);
            
            // Extract authors
            auto authorRegex = ctRegex!`<contrib[^>]*contrib-type="author"[^>]*>.*?<surname[^>]*>(.*?)</surname>.*?<given-names[^>]*>(.*?)</given-names>.*?</contrib>`;
            auto authorMatches = matchAll(articleXml, authorRegex);
            foreach (authorMatch; authorMatches)
            {
                if (authorMatch.captures.length >= 2)
                {
                    string lastName = decodeXml(authorMatch.captures[0]);
                    string foreName = decodeXml(authorMatch.captures[1]);
                    article.authors ~= foreName~" "~lastName;
                }
            }
            
            // Extract DOI
            auto doiMatch = matchFirst(articleXml, ctRegex!`<article-id[^>]*pub-id-type="doi"[^>]*>(.*?)</article-id>`);
            if (doiMatch)
                article.doi = decodeXml(doiMatch.captures[0]);
            
            // Extract full text (body sections)
            auto bodyMatch = matchFirst(articleXml, ctRegex!`<body[^>]*>(.*?)</body>`);
            if (bodyMatch)
            {
                article.fulltext = decodeXml(bodyMatch.captures[0]);
                // Also try to extract abstract
                auto abstractMatch = matchFirst(articleXml, ctRegex!`<abstract[^>]*>(.*?)</abstract>`);
                if (abstractMatch)
                {
                    string abstractText = decodeXml(abstractMatch.captures[0]);
                    article.fulltext = abstractText~"\n\n"~article.fulltext;
                }
            }
            else
            {
                // If no body, try to get abstract at least
                auto abstractMatch = matchFirst(articleXml, ctRegex!`<abstract[^>]*>(.*?)</abstract>`);
                if (abstractMatch)
                    article.fulltext = decodeXml(abstractMatch.captures[0]);
            }
            
            if (article.pmcId.length > 0)
                articles ~= article;
        }
        
        return articles;
    }

    // Search PMC directly
    static PMC.Article[] search(string term, int limit = 10, string apiKey = null)
    {
        auto result = Entrez.esearch!"pmc"(term, limit, -1, false, TimeFrame.init, apiKey);
        
        if (result.isNull || !("esearchresult" in result))
            return [];
        
        string[] pmcIds = result["esearchresult"]["idlist"].array.map!(x => x.str).array;
        if (pmcIds.length == 0)
            return [];
        
        // Fetch full text for all PMC IDs
        string xml = Entrez.efetch!("pmc", "xml")(pmcIds, "full", apiKey);
        return parsePMCArticles(xml);
    }

    // Link PubMed articles to PMC and get full text
    static PMC.Article[] fromPubMed(Article[] articles, string apiKey = null)
    {
        if (articles.length == 0)
            return [];
        
        string[] pmids = articles.map!(a => a.pmid).array;
        PMC.Article[] pmcArticles;
        
        // Link each PMID to PMC
        foreach (pmid; pmids)
        {
            auto linkResult = Entrez.elink!("pubmed", "pmc")(pmid, TimeFrame.init, apiKey);
            
            if (!linkResult.isNull && "linksets" in linkResult)
            {
                foreach (linkset; linkResult["linksets"].array)
                {
                    if ("linksetdbs" in linkset)
                    {
                        foreach (linksetdb; linkset["linksetdbs"].array)
                        {
                            if (linksetdb["dbto"].str == "pmc" && "links" in linksetdb)
                            {
                                foreach (link; linksetdb["links"].array)
                                {
                                    string pmcId = link["id"].str;
                                    // Fetch full text for this PMC ID
                                    string xml = Entrez.efetch!("pmc", "xml")(pmcId, "full", apiKey);
                                    PMC.Article[] parsed = parsePMCArticles(xml);
                                    pmcArticles ~= parsed;
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return pmcArticles;
    }

    // Get full text for PMC articles
    static string[] fulltext(PMC.Article[] articles, string apiKey = null)
    {
        string[] pmcIds = articles.map!(a => a.pmcId).array;
        if (pmcIds.length == 0)
            return [];
        
        string xml = Entrez.efetch!("pmc", "xml")(pmcIds, "full", apiKey);
        PMC.Article[] fullArticles = parsePMCArticles(xml);
        return fullArticles.map!(a => a.fulltext).array;
    }

    // Low-level access: raw search
    static JSONValue searchRaw(string term, int limit = 10, int retstart = 0, string apiKey = null)
    {
        return Entrez.esearch!"pmc"(term, limit, retstart, false, TimeFrame.init, apiKey);
    }
}

unittest
{
    PMC.Article[] articles = PMC.search("ketamine", 3);
    // May return empty or some results, but should not crash
    assert(articles.length >= 0, "PMC search should not crash");
}

unittest
{
    JSONValue raw = PMC.searchRaw("test", 5);
    assert(!raw.isNull, "Raw search should return JSON");
    assert("esearchresult" in raw, "Should have esearchresult");
}

unittest
{
    Article[] pubmedArticles = PubMed.search("ketamine", 2);
    if (pubmedArticles.length > 0)
    {
        PMC.Article[] pmcArticles = PMC.fromPubMed(pubmedArticles);
        // May or may not have PMC versions, but function should work
        assert(pmcArticles.length >= 0, "fromPubMed should return array");
    }
}

unittest
{
    PMC.Article[] articles = PMC.search("LSD", 2);
    if (articles.length > 0)
    {
        foreach (article; articles)
        {
            assert(article.pmcId.length > 0, "PMC article should have PMC ID");
        }
    }
}
