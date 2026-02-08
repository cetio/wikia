// module wikia.entrez.pubmed;

// import wikia.entrez.eutils;
// import std.json : JSONValue;
// import std.datetime : Date;
// import std.algorithm : map, filter;
// import std.array : join, array;
// import std.conv : to;
// import std.regex;
// import std.string : indexOf, strip, replace;

// class PubMed
// {
//     struct Article
//     {
//         string pmid;
//         string title;
//         string[] authors;
//         string abstractText;
//         string doi;
//         Date pubDate;
//         string journal;
//         string fulltext; // For full article text if available
//     }

//     // Decode XML entities
//     private static string decodeXml(string text)
//     {
//         string result = text;
//         result = replace(result, "&lt;", "<");
//         result = replace(result, "&gt;", ">");
//         result = replace(result, "&amp;", "&");
//         result = replace(result, "&quot;", "\"");
//         result = replace(result, "&apos;", "'");
//         result = replace(result, "&#39;", "'");
//         result = result.strip();
//         return result;
//     }

//     // Parse PubMed XML into PubMed.Article structs
//     static PubMed.Article[] parseArticles(string xml)
//     {
//         PubMed.Article[] articles;
        
//         if (xml.length == 0)
//             return articles;
        
//         RegexMatch!string matches = matchAll(
//             xml, 
//             ctRegex!`<PubmedArticle>.*?</PubmedArticle>`
//         );
        
//         foreach (match; matches)
//         {
//             string articleXml = match.hit;
//             PubMed.Article article;
            
//             // Extract PMID
//             Captures!string pmidMatch = matchFirst(
//                 articleXml, 
//                 ctRegex!`<PMID[^>]*>(\d+)</PMID>`
//             );
//             if (!pmidMatch.empty)
//                 article.pmid = pmidMatch.captures[1];
//             else
//                 continue;
            
//             // Extract title
//             Captures!string titleMatch = matchFirst(
//                 articleXml, 
//                 ctRegex!`<ArticleTitle[^>]*>(.*?)</ArticleTitle>`
//             );
//             if (!titleMatch.empty)
//                 article.title = decodeXml(titleMatch.captures[1]);
            
//             // Extract abstract
//             Captures!string abstractMatch = matchFirst(
//                 articleXml, 
//                 ctRegex!`<AbstractText[^>]*>(.*?)</AbstractText>`
//             );
//             if (abstractMatch.empty)
//                 abstractMatch = matchFirst(
//                     articleXml, 
//                     ctRegex!`<AbstractText[^>]*Label="([^"]*)"[^>]*>(.*?)</AbstractText>`
//                 );
//             if (!abstractMatch.empty)
//             {
//                 if (abstractMatch.captures.length > 1)
//                     article.abstractText = decodeXml(abstractMatch.captures[abstractMatch.captures.length - 1]);
//                 else
//                     article.abstractText = decodeXml(abstractMatch.captures[0]);
//             }
            
//             // Extract authors
//             RegexMatch!string authorMatches = matchAll(
//                 articleXml, 
//                 ctRegex!`<Author[^>]*>.*?<LastName[^>]*>(.*?)</LastName>.*?<ForeName[^>]*>(.*?)</ForeName>.*?</Author>`
//             );
//             foreach (authorMatch; authorMatches)
//             {
//                 if (authorMatch.captures.length >= 2)
//                 {
//                     string lastName = decodeXml(authorMatch.captures[0]);
//                     string foreName = decodeXml(authorMatch.captures[1]);
//                     article.authors ~= foreName~" "~lastName;
//                 }
//             }
            
//             // Extract DOI
//             Captures!string doiMatch = matchFirst(
//                 articleXml, 
//                 ctRegex!`<ELocationID[^>]*EIdType="doi"[^>]*>(.*?)</ELocationID>`
//             );
//             if (!doiMatch.empty)
//                 article.doi = decodeXml(doiMatch.captures[1]);
            
//             // Extract publication date
//             Captures!string dateMatch = matchFirst(
//                 articleXml, 
//                 ctRegex!`<PubDate>.*?<Year[^>]*>(\d+)</Year>.*?</PubDate>`
//             );
//             if (!dateMatch.empty && dateMatch.captures.length > 1)
//             {
//                 string yearStr = dateMatch.captures[1].strip();
//                 int year = yearStr.to!int;
//                 // Try to get month and day
//                 Captures!string monthMatch = matchFirst(
//                     articleXml, 
//                     ctRegex!`<Month[^>]*>(\d+)</Month>`
//                 );
//                 Captures!string dayMatch = matchFirst(
//                     articleXml, 
//                     ctRegex!`<Day[^>]*>(\d+)</Day>`
//                 );
//                 int month = (!monthMatch.empty && monthMatch.captures.length > 1) ? monthMatch.captures[1].strip().to!int : 1;
//                 int day = (!dayMatch.empty && dayMatch.captures.length > 1) ? dayMatch.captures[1].strip().to!int : 1;
//                 article.pubDate = Date(year, month, day);
//             }
            
//             // Extract journal
//             Captures!string journalMatch = matchFirst(
//                 articleXml, 
//                 ctRegex!`<Title[^>]*>(.*?)</Title>`
//             );
//             if (!journalMatch.empty)
//                 article.journal = decodeXml(journalMatch.captures[1]);
            
//             // Store full XML as fulltext for now (can be parsed more later)
//             article.fulltext = articleXml;
            
//             articles ~= article;
//         }
        
//         return articles;
//     }

//     // Search PubMed and return PubMed.Article structs
//     static PubMed.Article[] search(
//         string term, 
//         int limit = 10, 
//         string apiKey = null)
//     {
//         JSONValue result = Entrez.esearch!"pubmed"(term, limit, 0, false, TimeFrame.init, apiKey);
        
//         if ("esearchresult" !in result)
//             throw new Exception("Entrez eSearch invalid "~result.toString);
        
//         string[] pmids = result["esearchresult"]["idlist"].array.map!(x => x.str).array;
//         if (pmids.length == 0)
//             return [];
        
//         // Fetch abstracts for all PMIDs
//         string xml = Entrez.efetch!("pubmed", "xml")(pmids, "abstract", apiKey);
//         return parseArticles(xml);
//     }

//     // Get abstracts for specific PMIDs
//     static string[] abstracts(string[] pmids, string apiKey = null)
//     {
//         if (pmids.length == 0)
//             return [];
        
//         string xml = Entrez.efetch!("pubmed", "xml")(pmids, "abstract", apiKey);
//         PubMed.Article[] articles = parseArticles(xml);
//         return articles.map!(a => a.abstractText).array;
//     }

//     // Get full text for articles (requires PMC access for most)
//     static string[] fulltext(PubMed.Article[] articles, string apiKey = null)
//     {
//         string[] pmids = articles.map!(a => a.pmid).array;
//         if (pmids.length == 0)
//             return [];
        
//         // Try to get full text - may return abstracts if full text not available
//         string xml = Entrez.efetch!("pubmed", "xml")(pmids, "medline", apiKey);
//         PubMed.Article[] fullArticles = parseArticles(xml);
//         return fullArticles.map!(a => a.fulltext.length > 0 ? a.fulltext : a.abstractText).array;
//     }

//     // Low-level access: raw search
//     static JSONValue esearch(string term, int limit = 10, int retstart = 0, string apiKey = null)
//         => Entrez.esearch!"pubmed"(term, limit, retstart, false, TimeFrame.init, apiKey);
// }

// // unittest
// // {
// //     PubMed.Article[] articles = PubMed.search("ketamine", 5);
// //     assert(articles.length > 0, "PubMed search should return articles");
// //     foreach (article; articles)
// //     {
// //         assert(article.pmid.length > 0, "PubMed.Article should have PMID");
// //     }
// // }

// // unittest
// // {
// //     PubMed.Article[] articles = PubMed.search("LSD", 3);
// //     assert(articles.length > 0, "Should find LSD articles");
// //     foreach (article; articles)
// //     {
// //         assert(article.title.length > 0 || article.abstractText.length > 0, "PubMed.Article should have title or abstract");
// //     }
// // }

// // unittest
// // {
// //     JSONValue raw = PubMed.esearch("test", 5);
// //     assert(!raw.isNull, "Raw search should return JSON");
// //     assert("esearchresult" in raw, "Should have esearchresult");
// // }

// // unittest
// // {
// //     PubMed.Article[] articles = PubMed.search("nonexistenttermxyz123", 1);
// //     // May return empty or some results, but should not crash
// //     assert(articles.length >= 0, "Search should not crash");
// // }

// // unittest
// // {
// //     string[] pmids = ["12345678", "87654321"];
// //     string[] abstracts = PubMed.abstracts(pmids);
// //     // Abstracts may or may not be available, but function should work
// //     assert(abstracts.length >= 0, "Abstracts should return array");
// // }
