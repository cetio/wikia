// module wikia.entrez.pmc;

// import wikia.entrez.eutils;
// import wikia.page;
// import std.json : JSONValue, JSONType;
// import std.algorithm : map, filter;
// import std.array : join, array;
// import std.regex;
// import std.string : indexOf, strip, replace;

// class PMC
// {
//     private static string decodeXml(string str)
//     {
//         str = replace(str, "&lt;", "<");
//         str = replace(str, "&gt;", ">");
//         str = replace(str, "&quot;", "\"");
//         str = replace(str, "&apos;", "'");
//         str = replace(str, "&#39;", "'");
//         str = replace(str, "&amp;", "&");
//         return str.strip();
//     }

//     private static Page[] parseArticles(string xml)
//     {
//         Page[] ret;

//         if (xml.length == 0)
//             return ret;

//         RegexMatch!string matches = matchAll(
//             xml,
//             ctRegex!(`<(?:article|pmc-articleset)>.*?</(?:article|pmc-articleset)>`)
//         );

//         foreach (Captures!string match; matches)
//         {
//             string articleXml = match.hit;

//             Captures!string pmcMatch = matchFirst(
//                 articleXml,
//                 ctRegex!`<article-id[^>]*pub-id-type="pmc"[^>]*>(\d+)</article-id>`
//             );
//             pmcMatch = pmcMatch.empty ? matchFirst(articleXml, ctRegex!`pmc-(\d+)`) : pmcMatch;
//             if (pmcMatch.empty)
//                 continue;

//             string pmcId = pmcMatch.captures[0];
//             Page page = new Page(pmcId, "pmc");
//             page.metadata.fields["pmcId"] = pmcId;

//             Captures!string pmidMatch = matchFirst(
//                 articleXml,
//                 ctRegex!`<article-id[^>]*pub-id-type="pmid"[^>]*>(\d+)</article-id>`
//             );
//             if (!pmidMatch.empty)
//                 page.metadata.fields["pmid"] = pmidMatch.captures[0];

//             Captures!string titleMatch = matchFirst(
//                 articleXml,
//                 ctRegex!`<article-title[^>]*>(.*?)</article-title>`
//             );
//             if (!titleMatch.empty)
//                 page.title = decodeXml(titleMatch.captures[0]);

//             RegexMatch!string authorMatch = matchAll(
//                 articleXml,
//                 ctRegex!`<contrib[^>]*contrib-type="author"[^>]*>.*?<surname[^>]*>(.*?)</surname>.*?<given-names[^>]*>(.*?)</given-names>.*?</contrib>`
//             );
//             foreach (Captures!string author; authorMatch)
//             {
//                 if (author.captures.length >= 2)
//                 {
//                     string lastName = decodeXml(author.captures[0]);
//                     string foreName = decodeXml(author.captures[1]);
//                     page.authors ~= foreName~" "~lastName;
//                 }
//             }

//             Captures!string doiMatch = matchFirst(
//                 articleXml,
//                 ctRegex!`<article-id[^>]*pub-id-type="doi"[^>]*>(.*?)</article-id>`
//             );
//             if (!doiMatch.empty)
//                 page.metadata.fields["doi"] = decodeXml(doiMatch.captures[0]);

//             Section[] sections;
//             Captures!string abstractMatch = matchFirst(
//                 articleXml,
//                 ctRegex!`<abstract[^>]*>(.*?)</abstract>`
//             );
//             if (!abstractMatch.empty)
//                 sections ~= Section("Abstract", decodeXml(abstractMatch.captures[0]), 1);

//             RegexMatch!string bodyMatch = matchAll(
//                 articleXml,
//                 ctRegex!`<body[^>]*>(.*?)</body>`
//             );
//             if (!bodyMatch.captures.empty)
//                 sections ~= Section("Body", decodeXml(bodyMatch.front.captures[0]), 1);

//             page.sections = sections;

//             ret ~= page;
//         }

//         return ret;
//     }

//     static Page[] search(string term, int limit = 10, string apiKey = null)
//     {
//         JSONValue json = Entrez.esearch!"pmc"(term, limit, 0, false, TimeFrame.init, apiKey);
//         if (json.type == JSONType.null_ || "esearchresult" !in json)
//             return [];

//         string[] pmcIds = json["esearchresult"]["idlist"].array.map!(x => x.str).array;
//         if (pmcIds.length == 0)
//             return [];

//         string xml = Entrez.efetch!"pmc"(pmcIds, "full", apiKey);
//         return parseArticles(xml);
//     }

//     static string[] fulltext(Page[] pages, string apiKey = null)
//     {
//         string[] pmcIds = pages.map!(x => x.metadata.get("pmcId")).filter!(x => x !is null).array;
//         if (pmcIds.length == 0)
//             return [];

//         string xml = Entrez.efetch!"pmc"(pmcIds, "full", apiKey);
//         return parseArticles(xml).map!(x => x.fulltext()).array;
//     }

//     static JSONValue esearch(string term, int limit = 10, int retstart = 0, string apiKey = null)
//         => Entrez.esearch!"pmc"(term, limit, retstart, false, TimeFrame.init, apiKey);
// }
