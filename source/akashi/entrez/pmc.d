module akashi.entrez.pmc;

import akashi.entrez.eutils;
import akashi.entrez.pubmed;
import std.json : JSONValue;
import std.algorithm : map, filter;
import std.array : join, array;
import std.regex : ctRegex, matchFirst, matchAll;
import std.string : indexOf, strip, replace;

struct PMCArticle
{
    string pmcId;
    string pmid;
    string fulltext;
    string title;
    string[] authors;
    string doi;
}

// Search PMC directly
PMCArticle[] search(string term, int limit = 10, string apiKey = null)
{
    auto result = esearch!"pmc"(term, limit, -1, false, TimeFrame.init, apiKey);
    
    if (result.isNull || !("esearchresult" in result))
        return [];
    
    string[] pmcIds = result["esearchresult"]["idlist"].array.map!(x => x.str).array;
    if (pmcIds.length == 0)
        return [];
    
    // Fetch full text for all PMC IDs
    string xml = efetch!("pmc", "xml")(pmcIds, "full", apiKey);
    return parsePMCArticles(xml);
}

// Link PubMed articles to PMC and get full text
PMCArticle[] fromPubMed(Article[] articles, string apiKey = null)
{
    if (articles.length == 0)
        return [];
    
    string[] pmids = articles.map!(a => a.pmid).array;
    PMCArticle[] pmcArticles;
    
    // Link each PMID to PMC
    foreach (pmid; pmids)
    {
        auto linkResult = elink!("pubmed", "pmc")(pmid, TimeFrame.init, apiKey);
        
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
                                string xml = efetch!("pmc", "xml")(pmcId, "full", apiKey);
                                PMCArticle[] parsed = parsePMCArticles(xml);
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
string[] fulltext(PMCArticle[] articles, string apiKey = null)
{
    string[] pmcIds = articles.map!(a => a.pmcId).array;
    if (pmcIds.length == 0)
        return [];
    
    string xml = efetch!("pmc", "xml")(pmcIds, "full", apiKey);
    PMCArticle[] fullArticles = parsePMCArticles(xml);
    return fullArticles.map!(a => a.fulltext).array;
}

// Parse PMC XML into PMCArticle structs
PMCArticle[] parsePMCArticles(string xml)
{
    PMCArticle[] articles;
    
    if (xml.length == 0)
        return articles;
    
    // PMC XML structure: <article>...</article> or <pmc-articleset>...</pmc-articleset>
    auto articleRegex = ctRegex!`<(?:article|pmc-articleset)>.*?</(?:article|pmc-articleset)>`;
    auto matches = matchAll(xml, articleRegex);
    
    foreach (match; matches)
    {
        string articleXml = match.hit;
        PMCArticle article;
        
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

// Decode XML entities
private string decodeXml(string text)
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