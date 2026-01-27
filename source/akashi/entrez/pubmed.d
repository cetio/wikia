module akashi.entrez.pubmed;

import akashi.entrez.eutils;
import std.json : JSONValue;
import std.datetime : Date;
import std.algorithm : map, filter;
import std.array : join, array;
import std.conv : to;
import std.regex : regex, ctRegex, matchFirst, matchAll;
import std.string : indexOf, strip, replace;

static class PubMed
{
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

    // Parse PubMed XML into PubMed.Article structs
    static PubMed.Article[] parseArticles(string xml)
    {
        PubMed.Article[] articles;
        
        if (xml.length == 0)
            return articles;
        
        // Simple XML parsing using regex and string operations
        // PubMed XML structure: <PubmedArticle>...</PubmedArticle>
        auto articleRegex = ctRegex!`<PubmedArticle>.*?</PubmedArticle>`;
        auto matches = matchAll(xml, articleRegex);
        
        foreach (match; matches)
        {
            string articleXml = match.hit;
            PubMed.Article article;
            
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

    // Search PubMed and return PubMed.Article structs
    static PubMed.Article[] search(string term, int limit = 10, string apiKey = null)
    {
        auto result = Entrez.esearch!"pubmed"(term, limit, -1, false, TimeFrame.init, apiKey);
        
        if (result.isNull || !("esearchresult" in result))
            return [];
        
        string[] pmids = result["esearchresult"]["idlist"].array.map!(x => x.str).array;
        if (pmids.length == 0)
            return [];
        
        // Fetch abstracts for all PMIDs
        string xml = Entrez.efetch!("pubmed", "xml")(pmids, "abstract", apiKey);
        return parseArticles(xml);
    }

    // Get abstracts for specific PMIDs
    static string[] abstracts(string[] pmids, string apiKey = null)
    {
        if (pmids.length == 0)
            return [];
        
        string xml = Entrez.efetch!("pubmed", "xml")(pmids, "abstract", apiKey);
        PubMed.Article[] articles = parseArticles(xml);
        return articles.map!(a => a.abstractText).array;
    }

    // Get full text for articles (requires PMC access for most)
    static string[] fulltext(PubMed.Article[] articles, string apiKey = null)
    {
        string[] pmids = articles.map!(a => a.pmid).array;
        if (pmids.length == 0)
            return [];
        
        // Try to get full text - may return abstracts if full text not available
        string xml = Entrez.efetch!("pubmed", "xml")(pmids, "medline", apiKey);
        PubMed.Article[] fullArticles = parseArticles(xml);
        return fullArticles.map!(a => a.fulltext.length > 0 ? a.fulltext : a.abstractText).array;
    }

    // Low-level access: raw search
    static JSONValue searchRaw(string term, int limit = 10, int retstart = 0, string apiKey = null)
    {
        return Entrez.esearch!"pubmed"(term, limit, retstart, false, TimeFrame.init, apiKey);
    }
}

unittest
{
    PubMed.Article[] articles = PubMed.search("ketamine", 5);
    assert(articles.length > 0, "PubMed search should return articles");
    foreach (article; articles)
    {
        assert(article.pmid.length > 0, "PubMed.Article should have PMID");
    }
}

unittest
{
    PubMed.Article[] articles = PubMed.search("LSD", 3);
    assert(articles.length > 0, "Should find LSD articles");
    foreach (article; articles)
    {
        assert(article.title.length > 0 || article.abstractText.length > 0, "PubMed.Article should have title or abstract");
    }
}

unittest
{
    JSONValue raw = PubMed.searchRaw("test", 5);
    assert(!raw.isNull, "Raw search should return JSON");
    assert("esearchresult" in raw, "Should have esearchresult");
}

unittest
{
    PubMed.Article[] articles = PubMed.search("nonexistenttermxyz123", 1);
    // May return empty or some results, but should not crash
    assert(articles.length >= 0, "Search should not crash");
}

unittest
{
    string[] pmids = ["12345678", "87654321"];
    string[] abstracts = PubMed.abstracts(pmids);
    // Abstracts may or may not be available, but function should work
    assert(abstracts.length >= 0, "Abstracts should return array");
}
