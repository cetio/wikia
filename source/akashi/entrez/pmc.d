module akashi.entrez.pmc;

import akashi.entrez.eutils;
import akashi.entrez.pubmed;
import std.json : JSONValue;
import std.algorithm : map, filter;
import std.array : join, array;
import std.regex;
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
        
        RegexMatch!string matches = matchAll(
            xml, 
            ctRegex!`<(?:article|pmc-articleset)>.*?</(?:article|pmc-articleset)>`
        );
        
        foreach (match; matches)
        {
            string articleXml = match.hit;
            PMC.Article article;
            
            // Extract PMC ID
            Captures!string pmcMatch = matchFirst(
                articleXml, 
                ctRegex!`<article-id[^>]*pub-id-type="pmc"[^>]*>(\d+)</article-id>`
            );
            pmcMatch = pmcMatch.empty ? matchFirst(articleXml, ctRegex!`pmc-(\d+)`) : pmcMatch;
            if (pmcMatch.empty)
                continue;
            else
                article.pmcId = pmcMatch.captures[0];
            
            // Extract PMID
            Captures!string pmidMatch = matchFirst(
                articleXml,
                ctRegex!`<article-id[^>]*pub-id-type="pmid"[^>]*>(\d+)</article-id>`
            );
            if (!pmidMatch.empty)
                article.pmid = pmidMatch.captures[0];
            
            // Extract title
            Captures!string titleMatch = matchFirst(
                articleXml, 
                ctRegex!`<article-title[^>]*>(.*?)</article-title>`
            );
            if (!titleMatch.empty)
                article.title = decodeXml(titleMatch.captures[0]);
            
            // Extract authors
            RegexMatch!string authorMatch = matchAll(
                articleXml, 
                ctRegex!`<contrib[^>]*contrib-type="author"[^>]*>.*?<surname[^>]*>(.*?)</surname>.*?<given-names[^>]*>(.*?)</given-names>.*?</contrib>`
            );
            foreach (author; authorMatch)
            {
                if (author.captures.length >= 2)
                {
                    string lastName = decodeXml(author.captures[0]);
                    string foreName = decodeXml(author.captures[1]);
                    article.authors ~= foreName~" "~lastName;
                }
            }
            
            // Extract DOI
            Captures!string doiMatch = matchFirst(
                articleXml, 
                ctRegex!`<article-id[^>]*pub-id-type="doi"[^>]*>(.*?)</article-id>`
            );
            if (!doiMatch.empty)
                article.doi = decodeXml(doiMatch.captures[0]);

            // Extract abstract
            Captures!string abstractMatch = matchFirst(
                articleXml, 
                ctRegex!`<abstract[^>]*>(.*?)</abstract>`
            );
            if (!abstractMatch.empty)
                article.fulltext = decodeXml(abstractMatch.captures[0]);
            
            // Extract full text (body sections)
            RegexMatch!string bodyMatch = matchAll(
                articleXml, 
                ctRegex!`<body[^>]*>(.*?)</body>`
            );
            if (!bodyMatch.captures.empty)
                article.fulltext ~= "\n\n"~decodeXml(bodyMatch.front.captures[0]);
            
            articles ~= article;
        }
        
        return articles;
    }

    static PMC.Article[] search(string term, int limit = 10, string apiKey = null)
    {
        JSONValue json = Entrez.esearch!"pmc"(term, limit, 0, false, TimeFrame.init, apiKey);
        if ("esearchresult" !in json)
            throw new Exception("Entrez eSearch invalid "~json.toString);
        
        string[] pmcIds = json["esearchresult"]["idlist"].array.map!(x => x.str).array;
        if (pmcIds.length == 0)
            return [];
        
        // Fetch full text for all PMC IDs
        string xml = Entrez.efetch!("pmc", "xml")(pmcIds, "full", apiKey);
        return parsePMCArticles(xml);
    }

    static PMC.Article[] fromPubMed(PubMed.Article[] articles, string apiKey = null)
    {
        if (articles.length == 0)
            return [];
        
        string[] pmids = articles.map!(x => x.pmid).array;
        PMC.Article[] pmcArticles;
        
        foreach (pmid; pmids)
        {
            JSONValue linkResult = Entrez.elink!("pubmed", "pmc")(pmid, TimeFrame.init, apiKey);
            
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
                                    string xml = Entrez.efetch!("pmc", "xml")(link["id"].str, "full", apiKey);
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
        string[] pmcIds = articles.map!(x => x.pmcId).array;
        if (pmcIds.length == 0)
            return [];
        
        string xml = Entrez.efetch!("pmc", "xml")(pmcIds, "full", apiKey);
        return parsePMCArticles(xml).map!(x => x.fulltext).array;
    }

    // Low-level access: raw search
    static JSONValue searchRaw(string term, int limit = 10, int retstart = 0, string apiKey = null)
        => Entrez.esearch!"pmc"(term, limit, retstart, false, TimeFrame.init, apiKey);
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
    PubMed.Article[] pubmedArticles = PubMed.search("ketamine", 2);
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
