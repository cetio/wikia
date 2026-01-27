module akashi.entrez.pubmed;

import akashi.entrez.eutils;
import std.json : JSONValue;
import std.datetime : Date;
import std.algorithm : map, filter;
import std.array : join, array;
import std.conv : to;
import std.regex : regex, ctRegex, matchFirst, matchAll;
import std.string : indexOf, strip, replace;

struct Article
{
    string pmid;
    string title;
    string[] authors;
    string abstractText;
    string doi;
    Date pubDate;
    string journal;
    string fulltext; // For full article text if available
}

// Search PubMed and return Article structs
Article[] search(string term, int limit = 10, string apiKey = null)
{
    auto result = esearch!"pubmed"(term, limit, -1, false, TimeFrame.init, apiKey);
    
    if (result.isNull || !("esearchresult" in result))
        return [];
    
    string[] pmids = result["esearchresult"]["idlist"].array.map!(x => x.str).array;
    if (pmids.length == 0)
        return [];
    
    // Fetch abstracts for all PMIDs
    string xml = efetch!("pubmed", "xml")(pmids, "abstract", apiKey);
    return parseArticles(xml);
}

// Get abstracts for specific PMIDs
string[] abstracts(string[] pmids, string apiKey = null)
{
    if (pmids.length == 0)
        return [];
    
    string xml = efetch!("pubmed", "xml")(pmids, "abstract", apiKey);
    Article[] articles = parseArticles(xml);
    return articles.map!(a => a.abstractText).array;
}

// Get full text for articles (requires PMC access for most)
string[] fulltext(Article[] articles, string apiKey = null)
{
    string[] pmids = articles.map!(a => a.pmid).array;
    if (pmids.length == 0)
        return [];
    
    // Try to get full text - may return abstracts if full text not available
    string xml = efetch!("pubmed", "xml")(pmids, "medline", apiKey);
    Article[] fullArticles = parseArticles(xml);
    return fullArticles.map!(a => a.fulltext.length > 0 ? a.fulltext : a.abstractText).array;
}

// Parse PubMed XML into Article structs
Article[] parseArticles(string xml)
{
    Article[] articles;
    
    if (xml.length == 0)
        return articles;
    
    // Simple XML parsing using regex and string operations
    // PubMed XML structure: <PubmedArticle>...</PubmedArticle>
    auto articleRegex = ctRegex!`<PubmedArticle>.*?</PubmedArticle>`;
    auto matches = matchAll(xml, articleRegex);
    
    foreach (match; matches)
    {
        string articleXml = match.hit;
        Article article;
        
        // Extract PMID
        auto pmidMatch = matchFirst(articleXml, ctRegex!`<PMID[^>]*>(\d+)</PMID>`);
        if (pmidMatch)
            article.pmid = pmidMatch.captures[1];
        
        // Extract title
        auto titleMatch = matchFirst(articleXml, ctRegex!`<ArticleTitle[^>]*>(.*?)</ArticleTitle>`);
        if (titleMatch)
            article.title = decodeXml(titleMatch.captures[1]);
        
        // Extract abstract
        auto abstractMatch = matchFirst(articleXml, ctRegex!`<AbstractText[^>]*>(.*?)</AbstractText>`);
        if (!abstractMatch)
            abstractMatch = matchFirst(articleXml, ctRegex!`<AbstractText[^>]*Label="([^"]*)"[^>]*>(.*?)</AbstractText>`);
        if (abstractMatch)
        {
            if (abstractMatch.captures.length > 1)
                article.abstractText = decodeXml(abstractMatch.captures[abstractMatch.captures.length - 1]);
            else
                article.abstractText = decodeXml(abstractMatch.captures[0]);
        }
        
        // Extract authors
        auto authorRegex = ctRegex!`<Author[^>]*>.*?<LastName[^>]*>(.*?)</LastName>.*?<ForeName[^>]*>(.*?)</ForeName>.*?</Author>`;
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
        auto doiMatch = matchFirst(articleXml, ctRegex!`<ELocationID[^>]*EIdType="doi"[^>]*>(.*?)</ELocationID>`);
        if (doiMatch)
            article.doi = decodeXml(doiMatch.captures[0]);
        
        // Extract publication date
        auto dateMatch = matchFirst(articleXml, ctRegex!`<PubDate>.*?<Year[^>]*>(\d+)</Year>.*?</PubDate>`);
        if (dateMatch && dateMatch.captures.length > 0)
        {
            try
            {
                string yearStr = dateMatch.captures[0].strip();
                int year = yearStr.to!int;
                // Try to get month and day
                auto monthMatch = matchFirst(articleXml, ctRegex!`<Month[^>]*>(\d+)</Month>`);
                auto dayMatch = matchFirst(articleXml, ctRegex!`<Day[^>]*>(\d+)</Day>`);
                int month = (monthMatch && monthMatch.captures.length > 0) ? monthMatch.captures[0].strip().to!int : 1;
                int day = (dayMatch && dayMatch.captures.length > 0) ? dayMatch.captures[0].strip().to!int : 1;
                article.pubDate = Date(year, month, day);
            }
            catch (Exception)
            {
                // Skip date parsing if conversion fails
            }
        }
        
        // Extract journal
        auto journalMatch = matchFirst(articleXml, ctRegex!`<Title[^>]*>(.*?)</Title>`);
        if (journalMatch)
            article.journal = decodeXml(journalMatch.captures[0]);
        
        // Store full XML as fulltext for now (can be parsed more later)
        article.fulltext = articleXml;
        
        if (article.pmid.length > 0)
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